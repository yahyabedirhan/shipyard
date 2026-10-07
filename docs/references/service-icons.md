# Service icons

> **Decision (#249, 2026-10-07): the GitHub and Notion status views show their makers' marks, in look A.** The maintainer picked look A of three prototyped looks: each mark on a tile of `LogoBadge`'s squircle in its maker's colours, GitHub's white Invertocat on `#24292F` and Notion's black cube on white (as Notion's own app icon), both fixed in light and dark mode. The Shipyard Skill and Shipyard CLI views keep the sailboat (`LogoBadge`), and the signed-out GitHub view (`ConnectView`) keeps its logo. Each SVG is kept as published in `assets/images/service-logos/` and converted, unaltered, to the PDF the app bundles (`make service-logos`); `SetupBadge` draws it. The bundled files' sources and notices are in `THIRD-PARTY-NOTICES.md`.

Checked 2026-10-07, with the method of [agent-icons.md](agent-icons.md): copyright in the drawing and trademark in the mark are separate questions, and showing a mark only to say which service a view sets up is nominative use, when the mark isn't altered and implies no endorsement.

## Bundled logos

| Service | Bundled file (`assets/images/service-logos/`, PDF in `Sources/ShipyardApp/Resources/ServiceLogos/`) | Source | Licence and terms |
|---|---|---|---|
| GitHub | `github.svg` | [primer/octicons](https://github.com/primer/octicons) at `923a31b34542702800cb90a0fd390e2e60dd92ac` (the last commit touching it; HEAD `f04253eb4088fb9869418771effb391fa13a2744` has it unchanged), `icons/mark-github-24.svg` | MIT, "Copyright (c) 2026 GitHub Inc."; GitHub's logo terms allow showing an integration, white or black only |
| Notion | `notion.svg` | [simple-icons/simple-icons](https://github.com/simple-icons/simple-icons) at `1089fb7d2bf0e323f834c205ab76265005a6d5e8` (the last commit touching it), `icons/notion.svg` | project CC0, the Notion entry has no licence field; Notion's trademark terms allow describing an integration |

Both are one path on a 24-unit box with no fill, so the view draws them as template images in the tile's mark colour: GitHub's white, Notion's black. The mark's box takes 66 % (GitHub) and 64 % (Notion) of the tile's side, centred, so each mark looks the size of the sailboat. A 0.5 pt hairline inside the edge (white at 10 % on GitHub's tile, black at 12 % on Notion's) keeps each tile's shape against the panel in both modes.

Notion's file comes from simple-icons because Notion publishes no clean vector file: its brand page (`notion.com/brand`) answers 401, its media kit's "SVG" wraps a 2019 PNG, and the only first-party vector, the cube inline in notion.com's header, takes its black fill from a CSS variable, which the conversion drops unless that fill is edited. The simple-icons path is the same cube, converts cleanly, and on a white tile matches Notion's own app icon (`https://www.notion.com/front-static/logo-ios.png`).

## Sources checked

| Candidate | Source | Copyright | Verdict |
|---|---|---|---|
| GitHub octicon `mark-github-24.svg` | primer/octicons, as above | MIT | **Bundled.** Vector, one path, the current Invertocat: the same outline as the brand kit's file, scaled. Octicons' README: "When using the GitHub logos, be sure to follow the [GitHub logo guidelines](https://github.com/logos)." |
| GitHub brand kit (Invertocat black and white, SVG and PDF) | `https://brand.github.com/GitHub_Logos.zip`, the "Download the logo files" link on github.com/logos, fetched 2026-10-07 (files dated 2026-01-09) | none; "All rights reserved" | The same mark, but under no open licence, so the octicon is the better file to bundle. The kit has no app-icon file (no mark on a tile). |
| github.com's favicon | `https://github.githubassets.com/favicons/favicon.svg`, fetched 2026-10-07 | not stated | Not used: the old Invertocat outline, filled `#24292E`. |
| github.com's apple-touch-icon | `https://github.githubassets.com/apple-touch-icon-180x180.png`, fetched 2026-10-07 | not stated | Not used: a 180 × 180 raster of the old mark on a near-black tile, the only first-party GitHub file in an app icon's shape. |
| notion.com's header cube | the inline SVG of the "Notion – Home" link on `https://www.notion.com/`, extracted 2026-10-07 | not stated | Not used: Notion's own vector cube, but its black path's fill is `var(--notion-logo-fill, var(--tatami-color-black))`, which rsvg-convert drops. |
| Notion's media kit | [Media kit](https://notion.notion.site/Media-kit-4bd09326fb6a45b680aac5e639757372), "Logos" download, fetched 2026-10-07 (entries dated 2019-03-20) | not stated | Not used: the "SVG" is a 512 × 512 PNG inside an SVG; the PNGs are raster. `notion-logo.png`, the black cube on a white square, confirms the white-tile look is Notion's own. |
| notion.com's app icon | `https://www.notion.com/front-static/logo-ios.png`, fetched 2026-10-07 | not stated | Reference only: the same white-square artwork, raster. notion.com has no `favicon.svg`. |
| simple-icons `notion.svg` | simple-icons, as above | CC0 project; `data/simple-icons.json` entry `{"title": "Notion", "hex": "000000", "source": "https://www.notion.so"}`, no `license` or `guidelines` field. `DISCLAIMER.md`: "Simple Icons is released under CC0 - though that doesn't mean to imply that all icons within the project are also CC0." "We ask that our users seek the correct permissions to use the icons relevant to their project." | **Bundled**, for the reasons above. |

## Brand terms

### GitHub

[github.com/logos](https://github.com/logos), checked 2026-10-07:

- Do: "Show integration: Use a permitted GitHub logo to inform others that your project integrates with GitHub." "Secondary placement: Use the permitted GitHub logos less prominently than your own company or product name or logo."
- Don't: "Modify the logo: Do not modify the permitted GitHub logos, including changing the color, dimensions, or combining with other words or design elements."
- Colour: "The Invertocat and our wordmark should only appear in white, black, or in few cases grey or green."
- Legal: "No adaptation or use of any kind … is allowed without the express written permission of GitHub, Inc." The "Show integration" Do is the carve-out that covers a view that sets up shipyard's GitHub connection.

Verdict: bundled with the MIT notice, drawn white, unaltered, as the integration case GitHub lists.

### Notion

[Notion Trademark Usage Guidelines](https://notion.notion.site/Notion-Trademark-Usage-Guidelines-9826313c686a4f6e9d8a48347162714b) and [Notion's brand usage guidelines](https://notion.notion.site/Notion-s-brand-usage-guidelines-How-to-use-Notion-s-brand-in-your-marketing-30a5510bc5644475a28844e427008bee), checked 2026-10-07 (`notion.com/brand` answers 401; `/press` and `/media-kit` 404):

- "The 'Notion Marks' are … the name and wordmark 'Notion', and our black and white cube logo."
- Permitted: "You may refer to the Notion Marks to accurately describe how your products or services relate to our products or services. For example, if you have built an integration to Notion you can say that your integration works with, works for, uses, or was built with Notion's product or service."
- "Please only use the Notion Marks for which you are approved for use in the Brand Guidelines or other written agreement with Notion."
- Prohibited: "Use the Notion Marks in a way that suggests or implies an endorsement, sponsorship, partnership, or affiliation where such a relationship does not exist."
- Attribution, where permission is granted: "Notion and the Notion logo are trademarks of Notion Labs, Inc., and are used here with permission."
- "Notion can modify or revoke at any time … any permission or license we grant you to use our trademarks." Questions: team@makenotion.com.

Verdict: the same standing as the agents' logos in #137. The terms name describing an integration as permitted, in words; the cube is shown unaltered only to identify the view that connects shipyard's notes to Notion, with no endorsement implied, and `THIRD-PARTY-NOTICES.md` carries the trademark line. Notion may revoke the permission, so the cube may have to go back to the sailboat.

## Surprises

- The tile colour `#24292F` is the old Primer dark. GitHub's current brand palette lists Gray 6 `#101411` ("Process Black") and Gray 5 `#232925`; the site favicon uses `#24292E`. GitHub publishes no app-icon tile colour, and the maintainer kept `#24292F`.
- GitHub's brand guidelines prefer the Invertocat "in GitHub-owned environments or where the brand is already clearly established", and ask for written permission for any use; "Show integration" is the exception that applies.
- The octicon and simple-icons commits are the ones [agent-icons.md](agent-icons.md) already cites.
