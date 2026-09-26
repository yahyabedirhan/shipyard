# GitHub repositories for the project picker and repository groups

Checked 2026-09-25 by introspecting the GraphQL schema (`__type(name: "User")`) and against [REST: get a repository](https://docs.github.com/en/rest/repos/repos#get-a-repository).

- `User.repositories` takes `first`, `orderBy` (`{field: PUSHED_AT, direction: DESC}` for latest push), `ownerAffiliations` (default `[OWNER, COLLABORATOR]`), `affiliations`, `privacy`, `visibility`, `isFork`, `isLocked`, `hasIssuesEnabled` and **`isArchived`**.
- `User.repositoriesContributedTo` takes `first`, `orderBy`, `contributionTypes` (all by default), `includeUserRepositories`, `privacy`, `isLocked` and `hasIssues`. It has **no `isArchived` argument**: archived ones are filtered from each node's `isArchived`.
- `Repository.pushedAt` is `null` for a repository nobody has pushed to.
- A repository the token can't see answers `404 Not Found` over REST, the same as one that doesn't exist; an organisation enforcing SAML SSO for the token answers `403` with a message saying so (not yet confirmed against the docs).
- `GET /repos/{owner}/{repo}` answers with GitHub's spelling in `full_name` (case, and the new name after a rename, via a `301` the HTTP client follows; the redirect is not yet confirmed against the docs), plus `private`, `archived`, `description` and `pushed_at`. Each call counts against the REST limit.

## Listing a group's or an owner's repositories

Checked 2026-09-26 by introspecting the GraphQL schema (`__type(name: "User")`, `"Organization"`, `"RepositoryAffiliation"`) and with small queries against the API. The repository resolver (`GitHub/Repositories.swift`, `RepositoryListQuery`) relies on these:

- `RepositoryAffiliation` has three values. `OWNER`: "Repositories that are owned by the authenticated user." `COLLABORATOR`: "Repositories that the user has been added to as a collaborator." `ORGANIZATION_MEMBER`: "Repositories that the user has access to through being a member of an organization. This includes every repository on every team that the user is on." Shipyard's groups `owned`, `collaborator` and `organizations` are these.
- `User.repositories` and `Organization.repositories` take `affiliations` (no default: "Array of viewer's affiliation options…") and `ownerAffiliations` (default **`[OWNER, COLLABORATOR]`**: "Array of owner's affiliation options… For example, OWNER will include only repositories that the organization or user being viewed owns"). For `viewer.repositories` both describe the same account, so a group sets both to its one value: with `ownerAffiliations` left at its default, `affiliations: [ORGANIZATION_MEMBER]` lists nothing.
- `repositoryOwner(login:)` looks up a user or an organization by login. For a login that doesn't exist it answers `"repositoryOwner": null` with **no error** (and `rateLimit.cost` 1). Shipyard reads that as "doesn't exist, or can't be seen" and shows an error row for the `owner/*`.
- `repositoryOwner(login).repositories` with the default `ownerAffiliations` also lists repositories the owner is a collaborator on elsewhere, so `owner/*` asks for `ownerAffiliations: [OWNER]`.
- Both connections take `isArchived` and `isFork` arguments (no default: both kinds listed), and each node has `isArchived` and `isFork` fields. Shipyard asks for everything and reads the fields, so one lookup serves projects whose `archived` and `forks` differ.
- Paging: `first` is at most **100** (`first: 101` fails with `EXCESSIVE_PAGINATION`: "exceeds the `first` limit of 100 records"). `pageInfo { hasNextPage endCursor }` gives the cursor for `after`. Each page is one request, costing 1 point at these sizes. `orderBy: {field: NAME, direction: ASC}` keeps the order stable between lookups.
