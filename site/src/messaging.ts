// The site's copy source: the one line, the category, the install lines and the links. Every page, the HTML heads,
// the social cards and the agent files read them here. It follows docs/messaging.md (the messaging kit, added in a
// separate pull request): when that file changes, change this one to match, and nothing else.

export const NAME = 'shipyard';

/** The category, as the messaging kit words it. */
export const CATEGORY = 'A macOS menu bar app for pull requests.';

/**
 * The one line. The positioning isn't chosen yet, so the three candidates are here by their kit ids, and every
 * surface uses A until one is picked.
 */
export const LINES = {
  A: 'A macOS menu bar app for the pull requests your agents open.',
  B: 'See, review and triage what your coding agents ship, from the menu bar.',
  C: "Your agents' pull requests, issues and runs, one click away in the menu bar.",
} as const;
export type LineId = keyof typeof LINES;
export const LINE_ID: LineId = 'A';
export const LINE = LINES[LINE_ID];

/** One proof point after the line, for meta descriptions (the kit's "one line, then one proof point"). */
export const PROOF = 'One number for what needs you, one file your agents edit, and pings from any machine.';

export const SITE_URL = 'https://shipyard.yahyapak.dev';
export const REPO = 'https://github.com/yahyabedirhan/shipyard';
export const RELEASES = `${REPO}/releases/latest`;
export const CHANGELOG = `${REPO}/blob/main/CHANGELOG.md`;
export const LICENSE = `${REPO}/blob/main/LICENSE`;
export const ISSUES = `${REPO}/issues`;
export const HERDR_PLUGIN = 'https://github.com/yahyabedirhan/herdr-shipyard';
export const PERSONAL_SITE = 'https://yahyapak.dev';
export const SCHEMA_URL = 'https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json';

/** The install lines every first screen carries. */
export const INSTALL = {
  source: ['git clone https://github.com/yahyabedirhan/shipyard.git', 'cd shipyard', 'make install'].join('\n'),
  download: [
    'unzip Shipyard-<version>-macos.zip',
    'mv Shipyard.app /Applications/',
    'xattr -dr com.apple.quarantine /Applications/Shipyard.app',
    'open /Applications/Shipyard.app',
  ].join('\n'),
  // PLACEHOLDER: Homebrew cask. There is no cask yet; replace this line when `brew install --cask shipyard` works.
  homebrew: 'brew install --cask shipyard',
  skill: 'npx skills add yahyabedirhan/shipyard -g -y',
  plugin: 'herdr plugin install yahyabedirhan/herdr-shipyard',
} as const;

/** What to tell an agent once the skill is installed. */
export const ASK_AGENT = 'Watch this repo in shipyard';
