# shipyard

A macOS menu bar app for seeing and reviewing the pull requests your agents open on your behalf.

Shipyard shows the pull requests (and, if you turn them on, issues and workflow runs) on the projects you choose, from anyone, you and your agents included. The menu bar shows one number: how many items still need your attention. Clicking an item opens it on GitHub and marks it seen. Everything it shows, and when it notifies you, lives in one commented TOML file under `~/.config/shipyard/` that you or your agents edit.

**Status:** under construction, version 0.0.1. Versions stay at 0.0.x until the public launch.

## Install

### Requirements

- **macOS 14** or later. Shipyard ships for macOS only.
- **To build from source: the Command Line Tools with Swift 6 or later** (`swift --version` says which you have). The package uses Swift tools version 6.0; Xcode isn't needed.
- **A GitHub account.** Either **Sign in with GitHub** from the panel (GitHub's device flow: you enter a code on github.com, and the token is kept in your login Keychain), or have the [GitHub CLI](https://cli.github.com) signed in, and shipyard picks up its token silently:

  ```sh
  brew install gh
  gh auth login
  ```

### From source

You need the Command Line Tools (`xcode-select --install`) with Swift 6 or later; check with `swift --version`. Xcode isn't needed.

```sh
git clone https://github.com/yahyabedirhan/shipyard.git
cd shipyard
make install    # builds, ad-hoc signs, copies Shipyard.app to /Applications and opens it
```

### From a release zip

There's no GitHub release yet, so build the zip yourself with `make release` in a clone (it runs the tests and writes `build/Shipyard-<version>-macos.zip`). The zip is ad-hoc signed, not notarized, so macOS blocks the first launch of a copy that was downloaded. Unzip it, move `Shipyard.app` to `/Applications`, clear the quarantine flag and open it:

```sh
unzip Shipyard-<version>-macos.zip
mv Shipyard.app /Applications/
xattr -dr com.apple.quarantine /Applications/Shipyard.app
open /Applications/Shipyard.app
```

Or, on macOS 15 and later, open it once, dismiss the warning, then choose **Open Anyway** in System Settings > Privacy & Security.

### First launch

Shipyard has no Dock icon: it lives in the menu bar. Click its icon to open the panel.

1. Until it's connected, the panel offers **Sign in with GitHub**: it shows a code, **Copy code and open GitHub** puts it on the clipboard and opens github.com/login/device, and shipyard connects once you approve. Beside it are the `gh` command to run instead and a **Try again** button.
2. Then it offers your repositories to pick from (or type `owner/name`). Name each project, or give several repositories the same name to group them, and **Add** them. The panel also offers to install the agent skill (see [Configuration](#configuration)).
3. The first time something is worth notifying, macOS asks whether shipyard may send notifications. If you decline, the panel says notifications are off, with a button to System Settings.

Shipyard starts at login: it registers itself as a login item when it launches. Set `launch-at-login = false` in the configuration to remove it; switching it off in System Settings > General > Login Items also sticks.

### Everyday use

- The number in the menu bar counts the items that still need your attention.
- Click an item to open it on GitHub and mark it seen; **⌥-click** marks it seen without opening it.
- **↑** and **↓** move through the projects and items, wrapping at the ends; **Return** opens the highlighted item and **⌥Return** marks it seen. In the list, **←** goes to the item's project and collapses it, **→** expands it and goes to its first item, and **Return** on a project opens its (first) repository on GitHub. In tabs, **←** and **→** switch tabs.
- **⌘R** refreshes now; otherwise shipyard refreshes on its own, within GitHub's rate limit.
- Choose the layout in the configuration: `[menu] layout = "list"` (the default) puts every project in one scrolling list; `"tabs"` shows one project at a time.
- Projects, what's shown and when you're notified live in `~/.config/shipyard/config.toml`; see [Configuration](#configuration). What you've seen lives in `~/Library/Application Support/Shipyard/`.

### Update

From source, pull and install again (it quits the running copy first):

```sh
git pull
make install
```

From a zip, quit shipyard, delete the old copy (`rm -rf /Applications/Shipyard.app`), then install the newer zip as [above](#from-a-release-zip).

If you signed in with GitHub, macOS may ask once whether the new copy may use shipyard's Keychain item (each build is signed afresh); choose **Always Allow**.

### Uninstall

1. Quit shipyard (**Quit** in its panel, or ⌘Q while it's open).
2. Delete the app: `rm -rf /Applications/Shipyard.app`.
3. If it's still listed in System Settings > General > Login Items, remove it there.
4. Delete its configuration and state:

   ```sh
   rm -rf ~/.config/shipyard ~/Library/Application\ Support/Shipyard
   ```

5. If you installed the agent skill, remove it:

   ```sh
   npx skills remove shipyard -g
   ```

6. macOS may keep a Shipyard entry under System Settings > Notifications after the app is gone. It's harmless, and System Settings has no button to remove it; leave it, or turn its notifications off there.

If you signed in with GitHub, **Sign out** in the gear menu deletes the token from the Keychain; to do it after the app is gone, run `security delete-generic-password -s com.yahyabedirhan.shipyard -a github-token`. `gh` stays signed in; run `gh auth logout` if you want that too.

## Configuration

Everything shipyard shows and when it notifies lives in `~/.config/shipyard/config.toml` (`$XDG_CONFIG_HOME/shipyard/` when that's set). Every key is optional, edits apply live, and a broken edit keeps the last valid configuration and shows the error in the panel. **Open configuration file**, in the panel's gear menu, opens it.

The menu comes in two layouts, chosen with `[menu] layout`: `"list"` (the default) puts every project in one scrolling list, one line per item under pinned project headers; `"tabs"` shows one project at a time.

Each kind of item (`pull-requests`, `issues`, `workflow-runs`) can list only some authors, for every project or for one: `authors = { hide = ["me", "bots"] }` lists what other people open, and `authors = { show = ["@dependabot[bot]"] }` only that account's. A bare word is a group (`me`, `others`, `bots`) and `@` marks a login. What a project's filters leave out isn't shown, counted or notified.

- The schema, [`schema/config.schema.json`](schema/config.schema.json), documents every key and default; name it on the file's first line (`#:schema https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json`) for editor completion and `taplo check`.
- The agent skill, [`skills/shipyard/SKILL.md`](skills/shipyard/SKILL.md), teaches your agents to edit the file. Install it with `npx skills add yahyabedirhan/shipyard -g -y`.
- For maintainers, [`docs/configuration.md`](docs/configuration.md) explains how configuration works in the code and lists every place to touch when adding a setting.

## Development

The package has two targets:

- `ShipyardCore`: every rule (configuration, the GitHub client, attention, events, notification rules, the rate budget, the menu model). It depends only on Foundation, FoundationNetworking, Observation and TOMLDecoder, so it also **builds and tests on Linux, for development**. Linux isn't a supported platform for running shipyard.
- `ShipyardApp`: the macOS app (the `Shipyard` executable), a thin layer of Apple frameworks over the core. It's only part of the package on macOS.

```sh
make test                            # the tests (plain `swift test` needs Xcode or Linux; the Makefile finds the Testing framework the Command Line Tools ship)
make install                         # bundle, ad-hoc sign and install /Applications/Shipyard.app, then open it
make release                         # test, bundle and zip build/Shipyard-<version>-macos.zip
swift build --target ShipyardCore    # the core alone, on macOS or Linux
```

CI runs the core's tests on Ubuntu for every push and pull request.

### Forks: your own OAuth App

Sign in with GitHub uses the OAuth App client ID compiled into the build. A fork sets its own rather than borrowing the maintainer's:

1. On GitHub, **Settings > Developer settings > OAuth Apps > New OAuth App**. Any homepage and callback URL will do (the device flow doesn't use the callback). Tick **Enable Device Flow** in its settings.
2. Copy its **Client ID** (not a secret; there's no client secret to add) into `OAuthApp.clientID` in `Sources/ShipyardCore/GitHub/Auth/DeviceFlow.swift`.

A build without a client ID shows Sign in with GitHub as unavailable and connects through `gh`. GitHub limits each OAuth App to 50 device-code submissions an hour, and keeps at most 10 tokens per user and scope, revoking older ones; see [`docs/references/github-device-flow.md`](docs/references/github-device-flow.md).

The design is in `docs/low-level-design.md`, and the glossary in `CONTEXT.md`.
