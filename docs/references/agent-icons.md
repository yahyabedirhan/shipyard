# Agent icons

> **Decision (#137, 2026-10-03): shipyard bundles each known agent's real logo.** After the licence check below, the maintainer chose to bundle each agent's real logo for nominative identification of the sender (which agent sent a ping), accepting that Anthropic's, OpenAI's and Google's brand terms ask for approval. The earlier choice, a monogram on a coloured circle of shipyard's own, didn't let them recognise the agents. Each SVG is kept as published in `assets/images/agent-logos/` and converted, unaltered, to the PDF the app bundles (`make agent-logos`); the view fits it to a square with app-icon corners, tints Copilot's one-colour glyph like text, and switches OpenCode to its maker's dark-mode file. Shipyard still has no `LICENSE` file, so the MIT notices below have nowhere to go yet: add them when it gets one.

## Bundled logos

| Agent | Bundled file (`assets/images/agent-logos/`, PDF in `Sources/ShipyardApp/Resources/AgentLogos/`) | Source | Licence or terms |
|---|---|---|---|
| Claude | `claude.svg` | Anthropic's own: `https://claude.ai/favicon.svg` (the orange `#D97757` starburst), fetched 2026-10-03 | Anthropic Trademark Guidelines: prior approval, their files, no alterations |
| Codex | `codex.svg` | no first-party SVG found; [lobehub/lobe-icons](https://github.com/lobehub/lobe-icons) at `79b551cf26aab9ea4ac701fb807160950a5b860f`, `packages/static-svg/icons/codex-color.svg` | MIT (LobeHub's drawing); OpenAI's Marks terms: unaltered official files, revocable |
| OpenCode | `opencode.svg` (light), `opencode-dark.svg` (dark) | [anomalyco/opencode](https://github.com/anomalyco/opencode) at `108b988a08227df45417f27905a4d6b27ad49b6d`, `packages/identity/mark-light.svg` and `mark.svg` | MIT ("Copyright (c) 2025 opencode"); no brand terms |
| Cursor | `cursor.svg` | Cursor's own: `https://cursor.com/favicon.svg` (the 2.5D cube app icon), fetched 2026-10-03 | not stated; cursor.com/brand asks only for the name "Cursor" |
| Pi | `pi.svg` | Pi's own: `https://pi.dev/logo-auto.svg`, fetched 2026-10-03 | not stated (not in the MIT repo) |
| Gemini | `gemini.svg` | no first-party SVG (the Apache repo has a PNG only); lobe-icons at `79b551cf26aab9ea4ac701fb807160950a5b860f`, `packages/static-svg/icons/gemini-color.svg` | MIT (LobeHub's drawing); Google: product icons need a permission request |
| GitHub Copilot | `copilot.svg` | [primer/octicons](https://github.com/primer/octicons) at `923a31b34542702800cb90a0fd390e2e60dd92ac`, `icons/copilot-24.svg` | MIT ("Copyright (c) 2026 GitHub Inc."); GitHub logo terms allow showing an integration |
| Amp | `amp.svg` | Amp's press kit: `https://ampcode.com/app-icon.svg`, fetched 2026-10-03 | not stated |
| Droid (Factory) | `droid.svg` | Factory's own: `https://factory.com/icon.svg` (the site's schema.org logo), fetched 2026-10-03 | not stated; all rights reserved |

The conversion needs librsvg (`brew install librsvg`): macOS's own SVG renderer drops lobe-icons' compact arc flags and gradients, so its Gemini and Codex come out wrong. Amp's drop shadow is a filter, which rsvg-convert keeps as a small embedded bitmap; the rest stay vector.

[pingdotgg/t3code](https://github.com/pingdotgg/t3code) at `b4d3d51ac99d4306d754afb5c78c49845bfac3c1` (MIT) shows agents the same way: real marks inlined as SVG in `apps/web/src/components/Icons.tsx` (Claude's starburst in `#d97757`, OpenAI's Blossom for Codex, Cursor's cube, Pi, OpenCode), each one-colour glyph given a light and a dark fill (`chat/ProviderInstanceIcon.tsx`).

Checked 2026-10-03. Where each coding agent's icon is published, under what terms, and whether shipyard can bundle a small copy to show next to a ping from that agent.

Two rights apply to every icon, and a code licence only answers the first:

- **Copyright** in the drawing. An MIT or Apache-2.0 repository that contains the file licenses the file.
- **Trademark** in the mark. Apache-2.0 says so outright (§6: "This License does not grant permission to use the trade names, trademarks, service marks, or product names of the Licensor"); MIT is silent, so it grants none either. Showing a mark only to say which agent sent a ping is nominative use, which trademark law allows without a licence when the mark isn't altered and doesn't imply endorsement. Some brand owners' published terms ask for more than that.

Shipyard itself has **no `LICENSE` file** (checked at `f167e7b`), so any bundled icon's notice has nowhere to go yet. Add the licence before bundling third-party files.

## Verdicts

| Agent | Best file | Copyright | Trademark terms | Verdict |
|---|---|---|---|---|
| Claude Code | none first-party; simple-icons `claudecode.svg` | unknown (no licence data) | Anthropic requires prior approval and its own image files | not allowed without Anthropic's permission |
| Codex | none first-party; lobe-icons `codex.svg` (redraw) | MIT (lobe-icons' drawing) | OpenAI Marks terms: unaltered official files, revocable | brand guidelines restrict (nominative use only, official file) |
| OpenCode | `packages/identity/mark.svg` in the repo | MIT | none published | bundle with attribution |
| Cursor | brand kit SVGs on cursor.com/brand | not stated | none published beyond naming | unknown terms; nominative use only, unaltered kit file |
| Pi | `https://pi.dev/logo-auto.svg` (not in the repo) | not stated | none published | unknown; ask the maintainer |
| Gemini CLI | Apache repo has only a PNG; lobe-icons `geminicli.svg` | Apache-2.0 (repo PNG) | Google: product icons need a permission request | not allowed without Google's permission |
| GitHub Copilot CLI | primer/octicons `copilot-16.svg` | MIT | GitHub: written permission, but showing integration is a listed "do" | bundle with attribution (octicon), nominative use only |
| Amp | `https://ampcode.com/app-icon.svg` (press kit) | not stated | none published | unknown terms; nominative use only, unaltered kit file |
| Droid (Factory) | `https://factory.com/icon.svg`; `docs/favicon.svg` in an unlicensed repo | all rights reserved (no licence) | none published | unknown; ask Factory |

Practical upshot: OpenCode and Copilot are the only two with a first-party SVG under an open licence. Everything else is either restricted (Claude, Gemini, Codex) or published with no terms (Cursor, Amp, Pi, Droid). A text label, or a neutral shipyard-drawn glyph per agent, avoids the question entirely.

## Aggregator icon sets

These hold redrawn icons for almost every agent, but their licence covers only their own drawings, never the marks.

- **simple-icons** ([simple-icons/simple-icons](https://github.com/simple-icons/simple-icons) at `1089fb7d2bf0e323f834c205ab76265005a6d5e8`): the project is CC0, but `DISCLAIMER.md` says "Simple Icons is released under CC0 - though that doesn't mean to imply that all icons within the project are also CC0. Please see individual licenses where available" and "We ask that our users seek the correct permissions to use the icons relevant to their project." In `data/simple-icons.json`, Claude, Claude Code, Cursor, OpenCode, Google Gemini, Qwen, Kimi and Cline have no `license` field; GitHub Copilot has `"license": {"type": "MIT"}` (sourced from Primer). OpenAI has no entry.
- **lobe-icons** ([lobehub/lobe-icons](https://github.com/lobehub/lobe-icons) at `79b551cf26aab9ea4ac701fb807160950a5b860f`): MIT (`LICENSE`, "Copyright (c) 2023 LobeHub"), no trademark disclaimer. Static SVGs in `packages/static-svg/icons/` (published as `@lobehub/icons-static-svg`, MIT), mono and `-color` variants: `claude`, `claudecode`, `codex`, `openai`, `opencode`, `cursor`, `pi` (titled "Pi Agent", description `https://pi.dev`), `gemini`, `geminicli`, `githubcopilot`, `copilot`, `amp`, `devin`, `kimi`, `kilocode`, `hermesagent`, `qoder`, `qwen`, `mastra`, `grok`, `antigravity`, `kiro`, `cline`. No Factory/Droid or Letta icon.

Bundling an aggregator SVG is fine for copyright (attribute LobeHub's MIT notice, or nothing for simple-icons' CC0 data), but where a brand owner requires its own unaltered files (Anthropic, OpenAI, Google), a redraw is the thing those terms forbid.

## Herdr

[herdrdev/herdr](https://github.com/herdrdev/herdr) at tag `v0.9.3` (`7b116c05bfda646af39d2524c54e70c751f57ee8`), Apache-2.0. It **bundles no agent icons**: the only tracked images are its own `assets/logo.svg`/`logo.png`, a screenshot, an OG card and a sponsor logo. Its sidebar shows a per-state `state_icon` and the agent as text (`src/ui/sidebar/tokens.rs`). No lead there.

Herdr's agent list (`docs/next/website/src/content/docs/agents.mdx`, `integrations.mdx`): Claude Code, Codex, GitHub Copilot CLI, Cursor Agent CLI, OpenCode, Pi, OMP, Droid, Devin CLI, Kimi Code CLI, Kilo Code CLI, Hermes Agent, Qoder CLI, Qwen Code, Letta Code, MastraCode, Grok CLI, Antigravity CLI; state-only: Amp, Kiro CLI, Maki, Gemini CLI, Cline.

## Per agent

### Claude Code (Anthropic)

- Repo [anthropics/claude-code](https://github.com/anthropics/claude-code) at `1c229fcd1e1e4e452e29a8f116b45fe4cfe2c528` has no logo file. `LICENSE.md`: "© Anthropic PBC. All rights reserved. Use is subject to Anthropic's Commercial Terms of Service."
- Official assets: the press kit linked as "Media assets — Download press kit" on [anthropic.com/news](https://www.anthropic.com/news).
- [Anthropic Trademark Guidelines](https://www.anthropic.com/legal/trademark-guidelines) (effective 2024-08-01): "You may only use our trademarks as specifically permitted by us and only in materials we approve beforehand." "We will supply an image (or images) of the trademark(s) for your use … No alterations of our trademarks (changes to color, font, proportion, or otherwise) are permitted." "You may not use our trademarks in a manner that implies Anthropic's sponsorship or endorsement…". Permission requests: marketing@anthropic.com.
- Verdict: **not allowed without permission.** The guidelines name no nominative-use carve-out, and a recoloured monochrome glyph is an alteration.

### Codex (OpenAI)

- Repo [openai/codex](https://github.com/openai/codex) at `bee28e8a061c38c781c74299f2c1d90e3732da18`, Apache-2.0 (§6 excludes trademarks). Only image: `.github/codex-cli-splash.png`; no Codex mark as SVG.
- [OpenAI brand guidelines](https://openai.com/brand/) cover the OpenAI wordmark and Blossom; no Codex-specific mark found there. Usage terms: "The term 'Marks' includes anything we use to identify our goods or services, including our names, logos, icons, and design elements." Do: "Use the logo only when it directly relates to OpenAI services", "Use the logo exactly as provided and acknowledge that it belongs to OpenAI." Don't: "Use the logo without permission or outside OpenAI's terms", "modify it in any way". "We may terminate permission to use our Marks at any time."
- Verdict: **brand guidelines restrict.** Nominative use of the unaltered Blossom to mean "Codex" is arguably inside the terms; a Codex-specific icon has no official file to use unaltered.

### OpenCode (anomalyco/opencode, formerly sst/opencode)

- Repo [anomalyco/opencode](https://github.com/anomalyco/opencode) at `108b988a08227df45417f27905a4d6b27ad49b6d`, MIT ("Copyright (c) 2025 opencode").
- Files: `packages/identity/mark.svg` and `mark-light.svg` (512×512 SVG, square mark on dark tile; also PNGs at 96/192/512); full kit in `packages/console/app/src/asset/brand/` (`opencode-logo-{dark,light}[-square].svg`, wordmarks, `opencode-brand-assets.zip`), served at opencode.ai/brand. simple-icons' OpenCode entry cites `packages/identity/mark.svg` as its source.
- The brand page (`packages/console/app/src/routes/brand/index.tsx`, strings in `packages/console/app/src/i18n/en.ts`) says only "Resources and assets to help you work with the OpenCode brand." No usage restrictions published.
- Verdict: **bundle with attribution** (MIT notice for the file); nominative use for the mark.

### Cursor (Anysphere)

- No public repo for the agent CLI.
- [cursor.com/brand](https://cursor.com/brand): "Resources to represent Cursor consistently and accurately." Logos, app icons and avatars, 2D/2.5D/3D, light and dark, as SVGs (`…/assets/brand/brand-logo-*.svg`) and `cursor-brand-assets.zip`. Only stated rule: "Refer to us as Cursor. Not Cursor AI or Cursor Code." No licence or trademark terms found on the page or in the terms of service.
- Verdict: **unknown terms; nominative use only**, with an unaltered kit file (the 2D cube avatar is the closest to a small icon).

### Pi (earendil-works/pi, formerly badlogic/pi-mono)

- Repo [earendil-works/pi](https://github.com/earendil-works/pi) (badlogic/pi-mono redirects there) at `69f0be6f0a6ca1bf66a2a9cf59c821b632e6bca1`, MIT ("Copyright (c) 2025 Mario Zechner"). The logo is **not in the repo**: `README.md` loads `https://pi.dev/logo-auto.svg` (three-colour block mark, 800×800 SVG, `#F09082` `#4D9ABF` `#F1BE58`).
- No brand page or terms on [pi.dev](https://pi.dev). The repo's package-report template lists "Trademark / TOS Violations" as a report reason, so the project treats its name as a mark.
- Verdict: **unknown; ask the maintainer.** The MIT licence doesn't cover a file served only from the website.

### Gemini CLI (Google)

- Repo [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) at `fb972b2f87fe7d5b06d37eac711490162d98de2c`, Apache-2.0. Only icon: `packages/vscode-ide-companion/assets/icon.png`. No SVG.
- Google [brand guidance](https://about.google/brand-resource-center/guidance/) puts product icons under "Ask first": "Refer to our icon usage guidelines to see whether you can use certain product icons in association with your business." [How to show Google's brand](https://about.google/brand-resource-center/brand-elements/): "To use a Google product icon in your work, create a Partner Marketing Hub account to find assets and request permission through our approval form." [Product co-branding](https://about.google/brand-resource-center/guidance/apis/): "Use plain text. For example, you could say your product or service 'works with,' … a Google product." The [trademarks list](https://about.google/brand-resource-center/logos-list/) includes "Gemini™".
- Verdict: **not allowed without permission.** The Apache licence covers the PNG's copyright only.

### GitHub Copilot CLI

- Repo [github/copilot-cli](https://github.com/github/copilot-cli) at `a9ba11a191255b3f7b323b425b717f7db14b6c74`: proprietary licence; §3 "This License does not grant you the right to … Use GitHub trademarks, logos, or branding except as necessary to identify the Software."
- Icon: [primer/octicons](https://github.com/primer/octicons) at `923a31b34542702800cb90a0fd390e2e60dd92ac`, MIT ("Copyright (c) 2026 GitHub Inc."): `icons/copilot-16.svg`, `copilot-24.svg`, `-48`, `-96`, monochrome, designed for UI. Octicons' README: "When using the GitHub logos, be sure to follow the GitHub logo guidelines."
- [GitHub logos](https://github.com/logos) Legal: "No adaptation or use of any kind of any of our registered trademarks or copyrights … is allowed without the express written permission of GitHub, Inc." Its "Do these things" list includes "Show integration: Use a permitted GitHub logo to inform others that your project integrates with GitHub." [Copilot brand page](https://brand.github.com/brand-identity/copilot): "Beginning in 2025, GitHub Copilot no longer has a standalone logo that heros the Copilot icon."
- Verdict: **bundle with attribution** (MIT for the octicon), **nominative use only**: the Copilot icon is a UI octicon, not one of the listed registered marks, and showing which integration sent a ping is the listed allowed case.

### Amp

- Closed source. [ampcode.com/press-kit](https://ampcode.com/press-kit) "Brand Assets": `/app-icon.svg`, `/logo-dark.svg`, `/logo-light.svg`. Contact amp-devs@ampcode.com. No licence or usage terms on the page.
- Verdict: **unknown terms; nominative use only**, unaltered `app-icon.svg`.

### Droid (Factory)

- No brand or press page (factory.ai and factory.com `/brand`, `/press`, `/press-kit` return 404). The site's schema.org data names `https://factory.com/icon.svg` as the logo. Repo [Factory-AI/factory](https://github.com/Factory-AI/factory) at `485a0c3b5d3d11c52d50cd2a8889e1a71e86905a` (docs) has `docs/favicon.svg` and `docs/images/droid_logo_cli.png`, and **no licence**, so all rights are reserved.
- Verdict: **unknown; ask Factory** (contact@factory.ai). Not in simple-icons or lobe-icons.

### Other herdr agents

Not checked as deeply: source of a usable icon and the repository licence (code licence only; none of these publish trademark terms found here).

| Agent | Owner | Repo licence | Icon source |
|---|---|---|---|
| OMP | can1357/oh-my-pi | MIT | none found |
| Devin CLI | Cognition | closed | lobe-icons `devin.svg` |
| Kimi Code CLI | Moonshot AI | MoonshotAI/kimi-cli, Apache-2.0 | official [Kimi brand guide](https://moonshotai.github.io/Branding-Guide) (SVG/PNG downloads, no terms; questions to team@moonshot.ai); simple-icons, lobe-icons |
| Kilo Code CLI | Kilo-Org/kilocode | MIT | lobe-icons `kilocode.svg` |
| Hermes Agent | NousResearch/hermes-agent | MIT | lobe-icons `hermesagent.svg` (simple-icons "Hermes" is the parcel company) |
| Qoder CLI | Alibaba | closed | lobe-icons `qoder.svg` |
| Qwen Code | QwenLM/qwen-code | Apache-2.0 | simple-icons, lobe-icons `qwen.svg` |
| Letta Code | letta-ai/letta-code | Apache-2.0 | none in either set |
| MastraCode | mastra-ai/mastra | NOASSERTION (mixed) | lobe-icons `mastra.svg` |
| Grok CLI | xAI | — | lobe-icons `grok.svg` |
| Antigravity CLI | Google | closed | lobe-icons `antigravity.svg`; Google's product-icon permission rule applies |
| Kiro CLI | Amazon | closed | lobe-icons `kiro.svg` |
| Cline | cline/cline | Apache-2.0 | simple-icons `cline.svg` (source: cline.bot branding assets), lobe-icons |
| Maki | — | — | none found |

Default verdict for these: **nominative use only**, unknown brand terms; Antigravity follows Google's rule (permission required).
