# GitHub search for review requests

Checked 2026-09-26 against [Searching issues and pull requests](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests), [GraphQL: search](https://docs.github.com/en/graphql/reference/search) and [GraphQL rate and query limits](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api).

Shipyard asks once per refresh, in the first GraphQL batch: `search(type: ISSUE, query: "is:pr is:open archived:false review-requested:@me", first: 100)`.

## Qualifiers

- `review-requested:<user>` matches pull requests where that user is asked for a review. "If the requested person is on a team that is requested for review, then review requests for that team will also appear in the search results." So a team request counts, which is why shipyard uses it.
- `user-review-requested:@me` "matches pull requests that you have directly been asked to review": no teams. Shipyard doesn't use it.
- `team-review-requested:<org/team>` matches one team's requests.
- "Requested reviewers are no longer listed in the search results after they review a pull request." Once the user reviews, the pull request leaves the search, and shipyard stops counting it as waiting on them.
- `is:pr is:open` narrows to open pull requests; `archived:false` leaves out archived repositories' pull requests.
- The search sees only open pull requests, so a closed one never has a review request in shipyard's eyes. The event detector keeps the request a pull request had when it was closed, so reopening it isn't announced as a new request.

## Limits

- `first` (and `last`) "must be within 1-100", so one page holds at most 100 pull requests. Shipyard reads that one page; `issueCount` is "the total number of issues that matched the search query", which says when there are more.
- A search returns "a maximum of 1,000 results" across all pages, whatever the number of matches.
- The search is part of a GraphQL request, so its cost is part of that request's `rateLimit.cost`, which the rate budget records (see [github-rate-limits.md](github-rate-limits.md)).

## Not confirmed against the docs

- A search that fails on its own comes back as `"reviewSearch": null` with an error whose `path` is `["reviewSearch"]`, while the repositories in the same request still answer. This is how GraphQL reports a field that failed; shipyard then keeps the last pull requests the search found and shows an error row where review requests were needed.
- GitHub's search index can lag a pull request's latest change by a short while.
