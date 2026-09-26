# GitHub workflow runs

Checked 2026-09-25 against [REST API endpoints for workflow runs](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-repository).

- The GraphQL API doesn't list workflow runs. Use REST: `GET /repos/{owner}/{repo}/actions/runs`.
- "Anyone with read access to the repository can use this endpoint. OAuth app tokens and personal access tokens (classic) need the `repo` scope to use this endpoint with a private repository."
- Filters:
  - `created`: runs created within a date-time range (search syntax, e.g. `>=2026-09-25T12:00:00Z`)
  - `status`: a status or conclusion: `completed`, `action_required`, `cancelled`, `failure`, `neutral`, `skipped`, `stale`, `success`, `timed_out`, `in_progress`, `queued`, `requested`, `waiting`, `pending`
  - `branch`: the branch of the push
  - `event`: the trigger, such as `push` or `pull_request`
  - `exclude_pull_requests`: "If true pull requests are omitted from the response (empty array)." Default `false`.
  - `per_page`: up to 100, default 30
- With `actor`, `branch`, `check_suite_id`, `created`, `event`, `head_sha` or `status`, the endpoint "will return up to 1,000 results for each search".
- The answer is `{ total_count, workflow_runs: [...] }`. The fields shipyard reads from a run: `name` (the workflow), `display_title`, `run_number`, `head_branch`, `status`, `conclusion` (string or null; `success`, `failure`, `neutral`, `cancelled`, `skipped`, `timed_out`, `action_required`), `html_url`, `created_at`, `updated_at`, `run_started_at`, and `actor` (a user: `login`, `type` among others). A run also has `id`, `run_attempt`, `event`, `triggering_actor` and `pull_requests`.
- The documentation doesn't say in what order runs are returned.
- Each call counts against the REST limit unless it's answered `304` (see [github-rate-limits.md](github-rate-limits.md)).
