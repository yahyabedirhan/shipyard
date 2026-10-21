# GitHub repositories for the project picker and repository groups

How GitHub lists and checks repositories: the project picker's lists, a single repository's check, and the repositories behind a repository group (`owned`, `collaborator`, `organizations`) or an `owner/*`.
The project picker and the repository resolver (`GitHub/Repositories.swift`, `RepositoryListQuery`) depend on it.

## Sources

- The GraphQL schema, introspected with `__type(name: "User")`: checked 2026-09-25.
- [REST: get a repository](https://docs.github.com/en/rest/repos/repos#get-a-repository): checked 2026-09-25.
- The GraphQL schema, introspected with `__type(name: "User")`, `"Organization"` and `"RepositoryAffiliation"`, and small queries against the API: checked 2026-09-26, for [Group and owner listing](#group-and-owner-listing).

## Project picker lists

- `User.repositories` takes `first`, `orderBy` (`{field: PUSHED_AT, direction: DESC}` for latest push), `ownerAffiliations` (default `[OWNER, COLLABORATOR]`), `affiliations`, `privacy`, `visibility`, `isFork`, `isLocked`, `hasIssuesEnabled` and **`isArchived`**.
- `User.repositoriesContributedTo` takes `first`, `orderBy`, `contributionTypes` (all by default), `includeUserRepositories`, `privacy`, `isLocked` and `hasIssues`. It has **no `isArchived` argument**: archived ones are filtered from each node's `isArchived`.
- `Repository.pushedAt` is `null` for a repository nobody has pushed to.

## Checking one repository

- `GET /repos/{owner}/{repo}` answers with GitHub's spelling in `full_name` (case, and the new name after a rename, via a `301` the HTTP client follows), plus `private`, `archived`, `description` and `pushed_at`.
- Each call counts against the REST limit.
- A repository the token can't see answers `404 Not Found` over REST, the same as one that doesn't exist.

## Group and owner listing

The repository resolver (`GitHub/Repositories.swift`, `RepositoryListQuery`) relies on these.

### Affiliations

- `RepositoryAffiliation` has three values, and shipyard's groups `owned`, `collaborator` and `organizations` are these:
  - `OWNER`: "Repositories that are owned by the authenticated user."
  - `COLLABORATOR`: "Repositories that the user has been added to as a collaborator."
  - `ORGANIZATION_MEMBER`: "Repositories that the user has access to through being a member of an organization. This includes every repository on every team that the user is on."
- `User.repositories` and `Organization.repositories` take `affiliations` (no default: "Array of viewer's affiliation options…") and `ownerAffiliations` (default **`[OWNER, COLLABORATOR]`**: "Array of owner's affiliation options… For example, OWNER will include only repositories that the organization or user being viewed owns").
- For `viewer.repositories` both describe the same account, so a group sets both to its one value: with `ownerAffiliations` left at its default, `affiliations: [ORGANIZATION_MEMBER]` lists nothing.

### Owners

- `repositoryOwner(login:)` looks up a user or an organization by login.
- For a login that doesn't exist it answers `"repositoryOwner": null` with **no error** (and `rateLimit.cost` 1). Shipyard reads that as "doesn't exist, or can't be seen" and shows an error row for the `owner/*`.
- `repositoryOwner(login).repositories` with the default `ownerAffiliations` also lists repositories the owner is a collaborator on elsewhere, so `owner/*` asks for `ownerAffiliations: [OWNER]`.

### Archived repositories and forks

- Both connections take `isArchived` and `isFork` arguments (no default: both kinds listed), and each node has `isArchived` and `isFork` fields.
- Shipyard asks for everything and reads the fields, so one lookup serves projects whose `archived` and `forks` differ.

### Paging

- `first` is at most **100** (`first: 101` fails with `EXCESSIVE_PAGINATION`: "exceeds the `first` limit of 100 records").
- `pageInfo { hasNextPage endCursor }` gives the cursor for `after`.
- Each page is one request, costing 1 point at these sizes.
- `orderBy: {field: NAME, direction: ASC}` keeps the order stable between lookups.

## Gaps

- An organisation enforcing SAML SSO for the token answers `403` with a message saying so: not yet confirmed against the docs.
- The `301` that `GET /repos/{owner}/{repo}` follows after a rename: not yet confirmed against the docs.
