// The site's copy source: the one line, the category, the install lines and the links. Every page, the HTML heads,
// the social cards and the agent files read them here. It follows docs/messaging.md (the messaging kit, added in a
// separate pull request): when that file changes, change this one to match, and nothing else.

export const NAME = 'shipyard';

/** The category, as the messaging kit words it. */
export const CATEGORY = 'A macOS menu bar app.';

/** The one line, as the messaging kit words it. */
export const LINE = 'A macOS menu bar app for keeping up with your projects while your agents work.';

/** One proof point after the line, for meta descriptions (the kit's "one line, then one proof point"). */
export const PROOF = 'One number for what needs you, one file your agents edit, pings from any machine.';

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
