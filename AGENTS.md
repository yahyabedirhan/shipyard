# shipyard

A macOS menu bar app for seeing and reviewing the pull requests your agents open on your behalf.

## Changing The Maintainer's Shipyard

A request to change the maintainer's shipyard (its layout, projects, notifications, what it shows) means their `config.toml`: edit it through the **shipyard** skill, even from this repository. Change the app's code only when the request asks for code (a new setting, a bug fix, a feature). When no setting does what's asked, say so; the code change waits for the maintainer to ask for it.

The shipyard skill (`skills/shipyard/SKILL.md`), its description included, is for shipyard's users editing their `config.toml`. It never mentions this repository, its code, or how to maintain the project: guidance for agents working here goes in this file. Check skill diffs for maintainer-facing wording before committing.

## Git, Commits, And Pull Requests

- Opening a pull request, or changing an existing one's description, goes through the **to-pr** skill, which owns the description's shape and where it is saved. Invoke it as part of the work, without waiting to be asked.
- Issue and pull request numbers belong in commit messages, pull requests and docs. Code, comments and test names say what they mean in words, so they read without the tracker.

Use lowercase multi-line commit messages with a Conventional Commits type on the subject line:

```text
type(scope): what changed

- explanation 1
- explanation 2
- explanation 3
```

- Types: `feat` (new capability, MINOR bump) and `fix` (a patched bug, PATCH bump); `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, and `chore` for maintenance. Nothing else, and no bare subjects.
- Scope is optional and names the area: the app's (`menu`, `panel`, `sign-in`, `onboarding`, `config`, `arrangement`, `runs`, `icon`) or the repo's (`release`, `skill`, `agents`, `handoff`, `readme`, `design`, `adr`, `references`, `assets`). Moves and path rewrites are `refactor`, tickets and ledgers are `chore`, handoffs and reports are `docs`.
- Keep the whole message lowercase, including company and product names. The `Co-Authored-By` trailer keeps its standard spelling.
- Never add a `Claude-Session:` trailer or any other session link to a commit message. The `Co-Authored-By` line from the session's attribution rule is the only trailer.

## Releases

When the maintainer says "release", cut it end to end, in this order. Each step is done before the next starts.

1. **Version.** List the commits since the last tag (`git describe --tags --abbrev=0`, then `git log <tag>..origin/main`). Any `feat` raises the middle number and resets the patch; otherwise raise the patch. Tell the maintainer the version before anything else, so they can stop you.
2. **Bump, merged first.** One pull request changes `ShipyardVersion.current`, the version `VersionTests` pins and the README's "describes <version>" line together, and turns `CHANGELOG.md`'s Unreleased entries into the release's dated entry, in the shape of the entries below it. Once its checks are green, ask the maintainer to merge it: "release" starts the work, and merging still needs their yes. The `linux cli` workflow fails a release whose tag doesn't match `shipyard --version`, so nothing is tagged before this merge.
3. **Build and publish.** On `main` at the merged bump, `make release` runs the tests, bundles the app and zips it to `build/Shipyard-<version>-macos.zip`. Publish it with `gh release create v<version> <zip> --target <bump's merge commit> --title "shipyard <version>" --notes-file <notes>`, the notes source under `.scratch/`. Write the notes from the pull requests merged since the last tag, in the previous release's shape (`gh release view <previous tag>`): the logo line, the title, a summary paragraph, Highlights, Install with the Gatekeeper steps, Known limitations, and "Full change list:" with the pull request numbers.
4. **Linux build.** Publishing starts the `linux cli` run. Wait on it (`gh run list --workflow linux-cli.yml --event release`, then `gh run watch <id> --exit-status`) and check that the release now lists `shipyard-linux-x86_64`, `shipyard-linux-aarch64` and their `.sha256` files. The herdr-shipyard plugin downloads them from the latest release, so when the run fails, stop and report it with every machine left as it was.
5. **Machines.** Carry the release to the machines (below), the Mac's app included.
6. **Report.** Comment on the bump's pull request: the release's link, the Linux run, and each machine's checked versions or what failed there.

Efforts are named for what they do (`clean-slate`), never a version: a version belongs to a release, and an effort may ship in any of them.

### Carrying Changes To The Machines

After a release, and after any merge that changes `skills/shipyard/` without one, bring every machine it applies to up to date: the Mac, then each machine in the maintainer's `[remote] machines`. Read their labels from the maintainer's `config.toml` (the **shipyard** skill knows where it lives); machine labels and paths stay out of this repository. A skill-only change runs only the skill steps.

- **The Mac:** in a checkout at the tag `v<version>`, `make install` replaces the app. `/Applications/Shipyard.app/Contents/Helpers/shipyard --version` prints `shipyard <version>`. Then `npx skills update shipyard -g`.
- **Each remote machine,** through its saved Herdr machine (the **herdr** skill), never plain SSH:
  1. Open a workspace of its own with `herdr --machine <label> workspace create --no-focus`, and run the rest in its first pane.
  2. When `herdr plugin list` shows herdr-shipyard as a local link (`source: local`), `herdr plugin unlink <its id>` first, so GitHub's copy replaces it.
  3. `herdr plugin install yahyabedirhan/herdr-shipyard -y` reinstalls the plugin, which fetches the release's Linux `shipyard`.
  4. `npx skills update shipyard -g` updates the skill. A PromptScript failure it prints is harmless.
  5. Check: `shipyard --version` prints `shipyard <version>`, and the installed skill's `SKILL.md` matches `skills/shipyard/SKILL.md` on `main`.
  6. Close the workspace with `herdr --machine <label> workspace close <id>`.

A machine Herdr can't reach (`herdr machine status`) is reported with the rest and left for the maintainer; go on with the others.

## Folder Layout

```text
.handoff/<date>-<topic>.md     tracked   handoffs between sessions
assets/images/<topic>/         tracked   images the project uses, such as the logo and the app icon's drafts
assets/screenshots/<topic>/    tracked   screenshots worth keeping, linked from issues, pull requests and docs
.scratch/                      ignored   notes, logs, temp files, raw captures and pull request description sources
.claude/worktrees/             ignored   sub-agent worktrees
```

`.scratch/` is throwaway: anything that must outlive the session moves to a tracked home, or into the issue or pull request it belongs to.

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues in `yahyabedirhan/shipyard`, handled with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each named after its role (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## QA

When a ticket that changes what the maintainer sees or does is built, close it and open a separate QA ticket, linked to it both ways. Label it `ready-for-qa` and assign it to the maintainer. It holds the installed build, how to use the feature, numbered try-this steps with known risks marked, what to do when done, and the screenshots you took with `shipyard screenshot` of the installed build (see Testing), committed under `assets/screenshots/<topic>/`. QA doesn't hold the pull request. Only visual, interactive changes get a QA ticket; configuration, agent and skill changes close when built.

## Design

`docs/low-level-design.md` is the agreed module design: requirements, modules and their state, the folder tree, the refresh pipeline and traced flows. Read it before adding or moving a module, and update it in the same change when the design moves.

## Testing

Verify changes with automated tests (`make test`) that exercise the code and the menu model without driving the Mac.

Check a visual change, and take screenshots, with app control, the shipyard skill's "Driving the app": `make install` the build first, then `shipyard app`, `panel` and `screenshot` (the installed `/Applications/Shipyard.app/Contents/Helpers/shipyard`). Show example data with a demo run (`shipyard app open --demo <folder>`, public repositories only), and finish with plain `shipyard app open`, so the maintainer's normal app is running when you're done. The maintainer may be using the menu meanwhile: before every step that changes what the app shows (each `make install`, `app open` or `quit`, `panel` command and `screenshot`), send them a desktop notification, "Starting: <step>", and right after it "Done: <step> (<result>)", so they leave the panel alone. App control is the only way in: Accessibility is blocked for agents on purpose, so clicking, scripting System Events or any other Accessibility route fails; don't retry it or look for a way around it. When a check needs a click, a hover or the real menu bar strip, name it in the handoff or pull request and leave it to the maintainer.

Each contract has one owner test at the strongest boundary, usually a `Harness` scenario. A new or changed test passes this gate first, and a missing answer means it isn't added yet:

1. What behaviour does the test protect: observable behaviour, or an independent contract (configuration, storage, CLI output and exit codes, platform, defaults, notifications)?
2. What credible regression fails it?
3. Why doesn't existing coverage catch that regression? Extend the owner's table or scenario before writing a near-duplicate.
4. Does it need a seam (a `public` member, a hook, an overload) that no production caller needs? Then test through the real boundary instead.

## References

Facts from GitHub's documentation that shipyard depends on (rate limits, workflow runs, device flow) live in `docs/references/`. Read the one for an area before changing it, and update it when you learn something new from the source.
