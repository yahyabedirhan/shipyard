# GitHub repositories for the project picker

Checked 2026-09-25 by introspecting the GraphQL schema (`__type(name: "User")`) and against [REST: get a repository](https://docs.github.com/en/rest/repos/repos#get-a-repository).

- `User.repositories` takes `first`, `orderBy` (`{field: PUSHED_AT, direction: DESC}` for latest push), `ownerAffiliations` (default `[OWNER, COLLABORATOR]`), `affiliations`, `privacy`, `visibility`, `isFork`, `isLocked`, `hasIssuesEnabled` and **`isArchived`**.
- `User.repositoriesContributedTo` takes `first`, `orderBy`, `contributionTypes` (all by default), `includeUserRepositories`, `privacy`, `isLocked` and `hasIssues`. It has **no `isArchived` argument**: archived ones are filtered from each node's `isArchived`.
- `Repository.pushedAt` is `null` for a repository nobody has pushed to.
- A repository the token can't see answers `404 Not Found` over REST, the same as one that doesn't exist; an organisation enforcing SAML SSO for the token answers `403` with a message saying so (not yet confirmed against the docs).
- `GET /repos/{owner}/{repo}` answers with GitHub's spelling in `full_name` (case, and the new name after a rename, via a `301` the HTTP client follows; the redirect is not yet confirmed against the docs), plus `private`, `archived`, `description` and `pushed_at`. Each call counts against the REST limit.
