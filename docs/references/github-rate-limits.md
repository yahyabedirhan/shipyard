# GitHub rate limits

Checked 2026-09-25 against:
- [Rate limits and query limits for the GraphQL API](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api)
- [Rate limits for the REST API](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
- [Best practices for using the REST API](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api)
- [GraphQL reference: RateLimit](https://docs.github.com/en/graphql/reference/objects#ratelimit)

## Two separate limits, both shared with the user's other tools

- **GraphQL:** 5,000 points per hour per user (10,000 for enterprise members). "This includes requests made with a personal access token as well as requests made by a GitHub App or OAuth app on behalf of a user."
- **REST:** 5,000 requests per hour per user. "All of these requests count towards your personal rate limit of 5,000 requests per hour", whether they come from personal access tokens, GitHub Apps or OAuth apps.

So shipyard shares both limits with `gh` and with every agent acting as the user. Its own usage has to stay a small share.

## What a GraphQL query costs

- Add up the requests needed to fulfil each connection in the query (a nested list counts once per parent node), divide by 100 and round. The minimum is 1 point.
- Nested per-item lists dominate. Fifty PRs, each asking for `reviewRequests(first: 10)` and `commits(last: 1)`, add about 100 requests on top of the PR list itself.
- `rateLimit(dryRun: true) { cost limit remaining resetAt }` returns a query's cost without spending it.
- **Measured 2026-09-25:** the shipyard query shape (open PRs first 50, closed PRs first 20, open issues first 50, closed issues first 20; per PR: comment and review counts, `reviewRequests(first: 10)`, last commit's `statusCheckRollup`) over 5 repositories costs **7 points**.

## Knowing where you stand

- REST responses carry `x-ratelimit-limit`, `x-ratelimit-remaining`, `x-ratelimit-used`, `x-ratelimit-reset` (UTC epoch seconds) and `x-ratelimit-resource`.
- GraphQL has the same headers, and a `rateLimit` object with `cost`, `limit`, `remaining`, `used` and `resetAt`. GitHub recommends reading the headers rather than querying the object where possible.

## Running out

- **GraphQL:** the status stays **200**. The body has a rate-limit error and `x-ratelimit-remaining` is `0`. A check on the status code alone misses it.
- **REST:** status 403 or 429.
- Either way: if `retry-after` is present, wait that many seconds. Otherwise wait until `x-ratelimit-reset`, or at least one minute.

## Secondary limits

- No more than 100 concurrent requests (REST and GraphQL).
- GraphQL: no more than 2,000 points per minute. REST: 900 points per minute across REST endpoints, and 90 seconds of CPU time per 60 seconds of real time.
- Send requests one after another, not in parallel: "To avoid exceeding secondary rate limits, you should make requests serially instead of concurrently."

## Polling cheaply over REST

- A conditional request (`If-None-Match` with the last `ETag`) that returns `304 Not Modified` "does not count against your primary rate limit".
- Stable, narrow requests return 304 more often: "A smaller, more specific response changes less often."
- Respect `x-poll-interval` when a response includes it.
- GitHub prefers webhooks to polling. Shipyard polls because it has no server.
