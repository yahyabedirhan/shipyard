# GitHub workflow runs

Checked 2026-09-25 against [REST API endpoints for workflow runs](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-repository).

- The GraphQL API doesn't list workflow runs. Use REST: `GET /repos/{owner}/{repo}/actions/runs`.
- Filters:
  - `created`: runs created within a date-time range (search syntax, e.g. `>=2026-09-25T12:00:00Z`)
  - `status`: a status or conclusion, such as `in_progress`, `completed`, `success` or `failure`
  - `branch`: the branch of the push
  - `event`: the trigger, such as `push` or `pull_request`
  - `per_page`: up to 100, default 30
- Each call counts against the REST limit unless it's answered `304` (see [github-rate-limits.md](github-rate-limits.md)).
