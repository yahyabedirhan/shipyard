# Screenshots

Every public screenshot of the app: where it shows, what it is for, which account it signs in as, and how to take it again.
Use this page as the to-do list when the panel's look changes and the screenshots must follow.

This page has four sections:

1. Files
2. Screenshots
3. Retake
4. Notes

## Files

| File | What it is |
|---|---|
| `site/shots.json` | the source of truth: each screenshot's id, what it shows, its demo configuration, its capture steps and its path |
| `assets/screenshots/launch/<id>.png` | each screenshot, at the path its `shots.json` entry names |
| `assets/demo/` | the demo folder that demo-items shots copy: `demo-items.json`, its account's avatar `orangecat.png`, and `yahyabedirhan.png` for the shots that sign in as the maintainer |
| `docs/screenshots/retake.py` | retakes one, several or every screenshot from its `shots.json` entry |

## Screenshots

The **Account** column says who the panel's header shows and where the rows come from:

- **`@orangecat`, demo items**: the made-up rows of `assets/demo/demo-items.json`, signed in as orangecat, whose avatar is Havooch's paper cat (`yahyabedirhan/havooch` > `assets/images/logo/v3-paper-cat/havooch-mark-small.svg`, on the app icon's graphite tile).
- **`@yahyabedirhan`, demo items**: the same rows, with a capture step that renames the account to yahyabedirhan.
- **`@yahyabedirhan`, live GitHub**: no `demo-items.json`, so the demo run asks GitHub as the signed-in maintainer and lists public repositories' real items.

Where a pair of screenshots shows side by side, one is `@yahyabedirhan` and the other `@orangecat`: `landing-tabs-dark` and `landing-list-light` on the landing page, at the top of the README and in the personal website's hero.

| Screenshot | Used in | Shows | Account |
|---|---|---|---|
| `landing-tabs-dark` | README top; site landing first screen; site docs opening; personal website hero | the tabs layout on the shipyard tab, Shipyard Dark | `@yahyabedirhan`, demo items |
| `landing-list-light` | README top; site landing first screen; site docs opening; personal website hero | the list layout, Paper Light | `@orangecat`, demo items |
| `onboarding-presets-dark` | README > 'Setup' and 'Examples'; site docs #first-run | onboarding's three presets and the agent skill card | `@yahyabedirhan`, live GitHub |
| `view-github-dark` | site docs #first-run | the Set up GitHub view | `@yahyabedirhan`, live GitHub |
| `config-warning-dark` | README > 'Configuration'; site docs #skill | the quiet banner for a misspelled key | `@orangecat`, demo items |
| `panel-pings-dark` | README > 'Pings'; site docs #pings | two pings from agents above the pull requests | `@orangecat`, demo items |
| `pings-tabs-light` | site docs #pings | the tabs layout's Pings group, light | `@orangecat`, demo items |
| `notes-tabs-light` | README > 'Notion notes'; site docs #notes | the Notes group on the shipyard tab, light | `@orangecat`, demo items |
| `panel-notes-dark` | site docs #notes | a project's Notes group | `@orangecat`, demo items |
| `panel-list-dark` | site docs #layouts; personal website > 'Layouts' | the list layout, grouped by repository | `@orangecat`, demo items |
| `panel-tabs-dark` | site docs #layouts; personal website > 'Layouts' | the tabs layout on one project's tab | `@orangecat`, demo items |
| `preset-my-agents-dark` | site docs #presets | the my-agents preset | `@orangecat`, demo items |
| `preset-incoming-contributions-dark` | site docs #presets | the incoming-contributions preset | `@orangecat`, demo items |
| `preset-review-queue-dark` | site docs #presets; personal website > 'Review queue' | the review-queue preset | `@orangecat`, demo items |
| `preset-my-agents-light` | site docs #preset-my-agents | the my-agents preset, Paper Light | `@orangecat`, demo items |
| `preset-incoming-contributions-light` | site docs #preset-incoming-contributions | the incoming-contributions preset, Paper Light | `@orangecat`, demo items |
| `preset-review-queue-light` | site docs #preset-review-queue | the review-queue preset, Paper Light | `@orangecat`, demo items |
| `view-skill-dark` | site docs #skill | the Set up /shipyard skill view | `@orangecat`, demo items |
| `view-cli-dark` | site docs #commands | the Set up shipyard command view | `@orangecat`, demo items |
| `menu-bar-icon-dark` | site landing | the menu bar icon with its count | `@yahyabedirhan`, live GitHub |
| `readme-subsections-dark` | README > 'Examples', the list layout | grouped by repository under subheaders | `@yahyabedirhan`, live GitHub |
| `readme-tabs-dark` | README > 'Examples', the tabs layout | the same file in the tabs layout | `@yahyabedirhan`, live GitHub |
| `readme-date-dark` | README > 'Examples', grouped by date | grouped by date | `@yahyabedirhan`, live GitHub |
| `readme-hero-light`, `readme-hero-dark` | nowhere today: `shots.json` and `site/src/site.test.ts` list them for the README, which no longer shows them | the tabs layout's All tab on live data | `@yahyabedirhan`, live GitHub |
| `cli-help-dark` | site docs #command | `shipyard --help` in a terminal | none: drawn by `site/scripts/terminal.mjs` |

The README's Examples show the configuration that made each screenshot beside it.
Keep each of those `shots.json` demo configurations equal to the README's, apart from the `theme` line.

## Retake

1. Find the screenshots the change touches in the table above. Retake all of them when the header, the theme or the type changes.
2. Take the lease and install the build from `main`.

   ```sh
   shipyard lease take --wait 120 --for "retake site screenshots"
   make install
   ```

   - Result: the installed app is the build the screenshots must show. The reinstall frees the lease; the script takes it again.
3. Run the script from the repository root, with ids or without.

   ```sh
   python3 docs/screenshots/retake.py
   python3 docs/screenshots/retake.py panel-list-dark view-cli-dark
   ```

   - Result: each id prints `ok`, or `FAILED` with the steps that failed. The exit status is 1 when one failed. The maintainer's own app runs again at the end, and the lease is released.
4. Look at every new picture before you commit it.
   - Result: the panel holds data, the header shows the account the table names, and nothing private shows.
5. Update the personal website (`yahyabedirhan/personal-website`) when one of its screenshots changed.
   1. Copy `panel-list-dark`, `panel-tabs-dark` and `preset-review-queue-dark` to `public/shipyard/`.
   2. Compose `public/shipyard/hero.webp`, 2400 × 1500: `landing-tabs-dark` and `landing-list-light` side by side on the dark backdrop.
   3. Change the commit named in `src/data.js`'s comment.
6. Commit the pictures with `site/shots.json` in one pull request.

## Notes

NOTE: The script uses `.scratch/shots-demo` in place of `~/shipyard-demo`. A demo folder whose socket path passes 103 bytes fails to launch.

NOTE: A refresh of large public repositories sometimes answers HTTP 502 or 504, and a live-GitHub shot then shows Not loaded yet. Run its id again.

NOTE: The System theme follows the Mac's accent colour. A shot without a `theme` line, such as onboarding, takes the accent of the Mac it is taken on.
