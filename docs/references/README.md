# References

Facts from outside documentation that shipyard depends on, with their sources. Read the file for an area before working in it. When a fact changes, update it here with the new check date.

| File | Covers |
|---|---|
| [github-rate-limits.md](github-rate-limits.md) | GraphQL and REST rate limits, query cost, running out, secondary limits, resource limits (`RESOURCE_LIMITS_EXCEEDED`, an answer cut short), conditional requests |
| [github-workflow-runs.md](github-workflow-runs.md) | Listing workflow runs over REST |
| [github-actions-cache.md](github-actions-cache.md) | The `ci` workflow's `.build` cache: key and restore-key matching, which branches can restore which caches, immutability, size and eviction, container jobs, tag triggers |
| [github-device-flow.md](github-device-flow.md) | Signing in with GitHub's OAuth device flow |
| [github-search.md](github-search.md) | The review search: `review-requested` and team requests, its 100-result page |
| [github-repositories.md](github-repositories.md) | Listing and checking repositories for the project picker; listing a repository group's or an owner's repositories (affiliations, `isArchived`, `isFork`, paging) |
| [notion-api.md](notion-api.md) | Notion's API for notes: versions (`2025-09-03` and data sources), internal connections (the route before ADR 0012), unique IDs, data-source queries and filters, Markdown page content, child pages and tables, rate limits, and `ntn`, the route the app reads notes through: its exit codes, error line and standard input |
| [tailscale-serve.md](tailscale-serve.md) | Notices over the tailnet: `tailscale serve` exposing a loopback port, `--bg`, the identity headers it adds and strips, tagged devices, and the Mac's own login in `tailscale status --json` |
| [herdr-terminal.md](herdr-terminal.md) | What Herdr's panes expose about the outer terminal app and their named session, and how `shipyard ping --herdr` uses them |
| [macos-end-to-end-testing.md](macos-end-to-end-testing.md) | End-to-end testing options for a SwiftUI menu bar app without Xcode, and what shipyard adopts |
| [macos-hover-help.md](macos-hover-help.md) | Hover help in the panel instead of native tooltips: packages, native options (popover, a drawn card, inline text), what menu bar apps do, and each call site |
| [screencapturekit-own-windows.md](screencapturekit-own-windows.md) | Capturing shipyard's own panel window with ScreenCaptureKit (`SCShareableContent.currentProcess`, macOS 14.4) without the Screen Recording permission, and the first real capture's outcome |
| [agent-icons.md](agent-icons.md) | Where each coding agent's icon is published and under what terms; why shipyard draws its own marks instead of bundling them |
| [service-icons.md](service-icons.md) | Where GitHub's and Notion's marks for their status views come from, under what licence and brand terms, and the look the maintainer chose |
