# GitHub Actions cache

Checked 2026-10-02 against [Dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching), [Workflow syntax: `on.push`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onpushbranchestagsbranches-ignoretags-ignore) and the [`actions/cache` README at v6.1.0](https://github.com/actions/cache/blob/v6.1.0/README.md).

The `ci` workflow (`.github/workflows/ci.yml`) caches `.build` in both jobs with `actions/cache/restore@v6` and `actions/cache/save@v6`. Its key is `<runner.os>-<runner.arch>-swift-<hash of swift --version>-<hash of Package.resolved>-<commit>`, and its one restore key is the same without the commit.

## Matching a key

- The action "first searches for cache hits for `key` and the cache version in the branch containing the workflow run. If there is no hit, it searches for prefix-matches for `key`, and if there is still no hit, it searches for `restore-keys` and the version. If there are still no hits in the current branch, the `cache` action retries the same steps on the default branch."
- `restore-keys` are tried in order; "if there are multiple partial matches for a restore key, the action returns the most recently created cache."
- `cache-hit` is `'true'` only for an exact match of `key`; a restore through `restore-keys` gives `'false'`. That is why the workflow saves when `cache-hit` isn't `'true'`: a rerun of the same commit restores its own cache and saves nothing.
- The cache "version" is a hash of the `path` and the compression tool. A cache made with zstd (the macOS runner) and one made with gzip (the `swift:6.2-noble` container, which has no `zstd`) never match each other, whatever the key.
- Keys are at most 512 characters.

## Immutability

- "You cannot change the contents of an existing cache. Instead, you can create a new cache with a new key." A key that names only the dependencies would keep restoring the first build forever; the commit in the key makes every push's build a new cache, and the restore key finds the newest one.

## Which runs can restore which caches

- "Workflow runs can restore caches created in either the current branch or the default branch (usually `main`)." A pull request run can also restore caches of its base branch.
- "Workflow runs cannot restore caches created for child branches or sibling branches", nor caches of a different tag name.
- A cache saved by a `pull_request` run "is created for the merge ref (`refs/pull/.../merge`)" and "can only be restored by re-runs of the pull request". The workflow therefore saves only from `push` runs.
- Only `push`, `workflow_dispatch`, `repository_dispatch`, `delete`, `registry_package`, `page_build` and `schedule` runs can write caches in the default branch's scope; others resolving to it get read-only access, where a save logs a warning and the job goes on.
- So a branch's first run finds a cache only if `main` has one with the same OS, toolchain and `Package.resolved`; after that it restores its own newest one.

## Size and eviction

- Entries "not accessed in over 7 days" are removed.
- Measured on shipyard's probe runs (2026-10-02): a macOS `.build` is about 151 MB, a Linux one about 88 MB, so each push saves about 240 MB.
- A repository holds 10 GB of caches by default (raisable, with billing). Past the limit "GitHub will save the new cache but will begin evicting caches" in order of last access, oldest first, which can thrash.
- At most 200 uploads per minute and 1500 downloads per minute per repository.

## Containers

- Inside a container job, "a POSIX-compliant `tar` needs to be included and accessible from the execution path." `swift:6.2-noble` has GNU tar but no `zstd`, so the action packs with gzip there (seen in the save step's `tar ... -z`); saving the Linux cache takes about 10–15 s.
- `actions/cache` v5 and later run on Node.js 24 and need runner version 2.327.1 or newer (GitHub-hosted runners have it).

## Triggers

- "If you define neither `tags`/`tags-ignore` or `branches`/`branches-ignore`, the workflow will run for events affecting either branches or tags." Defining only `branches` stops tag pushes, which is why `ci.yml` lists both `branches: ['**']` and `tags: ['**']`.

## Security

- "Anyone who can open a pull request against your repository can read the contents of caches in the base branch." Never put secrets in a cached path; `.build` holds only build products and the Linux job's list of source hashes.
