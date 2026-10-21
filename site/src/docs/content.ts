// The docs page's words and data. Prose is small pieces of HTML; a `<sup class="fn"></sup>` in a body marks where the
// section's next note belongs, and the notes sit in the margin. The configuration and command references are not
// written here: they are generated from the schema and the Swift sources (src/reference/parse.ts).
// Say only what the app does today, describe behaviour, and leave how it looks to the screenshots.
import { ASK_AGENT, CHANGELOG, HERDR_PLUGIN, INSTALL, ISSUES, RELEASES, REPO, SCHEMA_URL } from '../messaging';

/** A link that opens in a new tab. */
export const ext = (href: string, text: string) => `<a href="${href}" target="_blank" rel="noreferrer">${text}</a>`;

export type Lang = 'toml' | 'sh' | 'json' | 'text';
export interface Snippet { label?: string; lang: Lang; code: string }

export interface DocSection {
  id: string;
  title: string;
  /** The name in the nav. */
  nav: string;
  lede: string;
  body: string;
  notes: string[];
  /** Code shown under the prose, one block or a tab per snippet. */
  code?: Snippet[];
  /** Screenshot ids from shots.json, shown under the code. */
  shots?: string[];
  extra?: 'install' | 'presets' | 'layouts' | 'explorer' | 'pings' | 'config' | 'commands' | 'limits' | 'troubleshooting' | 'changelog';
  /** Prose after the section's tables and figures. */
  after?: string;
  /** The code comes last, after `after`, instead of under the prose. */
  codeLast?: boolean;
}

export const GROUPS: { name: string; ids: string[] }[] = [
  { name: 'Start', ids: ['what', 'install', 'first-run'] },
  { name: 'Use', ids: ['presets', 'layouts', 'explorer', 'pings', 'notes'] },
  { name: 'Agents', ids: ['skill', 'machines'] },
  { name: 'Reference', ids: ['configuration', 'commands'] },
  { name: 'Last', ids: ['limits', 'troubleshooting', 'changelog'] },
];

export const SECTIONS: DocSection[] = [
  {
    id: 'what', title: 'What it is', nav: 'What it is',
    lede: 'Your pull requests, issues, workflow runs, pings and notes, grouped by project in the menu bar, with one number for what needs you.',
    body: '<p>Coding agents open pull requests and issues and start workflow runs, often several at once across several repositories. shipyard lists them in the menu bar, from anyone, grouped into projects you name. The number beside its icon counts the items that need attention: new, changed since you last opened them, waiting on your review, or failing their checks.<sup class="fn"></sup></p>\n<p>It can notify you when something happens, and your agents can ping you when they need you. What it shows lives in one TOML file that you, or your agents, edit.<sup class="fn"></sup></p>',
    notes: [
      'Clicking an item opens it on GitHub and clears its attention until it changes again. Closed items never need attention.',
      'There is no settings window. The file is the whole interface for settings, and each save applies at once.',
    ],
  },
  {
    id: 'install', title: 'Install', nav: 'Install',
    lede: 'Download the app, or build it from source. Then give your agents the skill.',
    body: '<p>You need macOS 14 or later and a GitHub account. Building from source also needs the Command Line Tools with Swift 6, from <code>xcode-select --install</code><sup class="fn"></sup></p>\n<p>The download is <code>Shipyard-&lt;version&gt;-macos.zip</code> on the ' + ext(RELEASES, 'latest release') + '. It isn\'t notarized yet, so clear the quarantine flag before the first launch, as below.<sup class="fn"></sup></p>',
    notes: [
      '<code>make install</code> builds, signs and copies <code>Shipyard.app</code> to <code>/Applications</code>, then opens it. To update, run <code>git pull &amp;&amp; make install</code> again.',
      'To update a download, replace the app with a newer zip. There is no automatic update yet.',
    ],
    extra: 'install',
    after: '<p>To uninstall, choose <b>Sign out</b> in the gear menu if you signed in with GitHub, quit shipyard, and delete the app and its files. Remove the agent skill with <code>npx skills remove shipyard -g</code> if you installed it.</p>',
    codeLast: true,
    code: [{ lang: 'sh', code: 'rm -rf /Applications/Shipyard.app ~/.config/shipyard ~/Library/Application\\ Support/Shipyard' }],
  },
  {
    id: 'first-run', title: 'First run', nav: 'First run',
    lede: 'Connect GitHub, choose a preset, and pick the repositories to watch.',
    body: '<p>shipyard lives in the menu bar, with no Dock icon. On first launch its panel asks you to connect GitHub: <b>Sign in with GitHub</b>, or use the ' + ext('https://cli.github.com', 'GitHub CLI') + ' if <code>gh</code> is signed in.<sup class="fn"></sup> It then offers three starting configurations, called presets, and asks which repositories to watch.</p>\n<p>Click an item to open it on GitHub and mark it seen; <b>⌥-click</b> marks it seen without opening it. <b>↑</b>, <b>↓</b> and <b>Return</b> move through the items and open one, and <b>⌘R</b> refreshes. shipyard starts at login unless <code>launch-at-login = false</code><sup class="fn"></sup></p>\n<p>The gear menu lists the parts shipyard uses: <b>Set up GitHub</b>, <b>Set up Notion</b>, <b>Set up /shipyard skill</b> and <b>Set up shipyard command</b>, with a check mark beside each one that is set up. Each opens a view of its status in the panel.</p>',
    notes: [
      'Sign in with GitHub uses GitHub\'s device flow: the panel shows a code to enter on github.com, and keeps the token in your Keychain.',
      'Every refresh spends a small share of your GitHub rate limit, 10% at most by default, since your agents share it.',
    ],
    shots: ['onboarding-presets-dark', 'view-github-dark'],
  },
  {
    id: 'presets', title: 'Presets', nav: 'Presets',
    lede: 'Three ready-made files for shipyard\'s main uses. Start from one, then change any key.',
    body: '<p>Onboarding writes the preset you choose into <code>config.toml</code>, with your repositories in place of the examples. It writes a preset only into a file that is missing or holds nothing but <code>version</code>, so it never replaces your settings.<sup class="fn"></sup></p>',
    notes: ['With the agent skill installed, an agent can start you from one too: "set shipyard up as a review queue".'],
    extra: 'presets',
  },
  {
    id: 'layouts', title: 'Layouts', nav: 'Layouts',
    lede: 'Every project in one list, or one project at a time in tabs.',
    body: '<p><code>layout = "list"</code> under <code>[menu]</code> shows every project in one scrolling list, one line per item under pinned project headers. <code>layout = "tabs"</code> shows one project at a time, with an All tab first. The layout button in the panel\'s header switches between them and writes the change to the file.<sup class="fn"></sup></p>\n<p>Within a project, <code>group-by</code> groups the items by kind, repository, date or author, or not at all; <code>sort-by</code> orders each group; <code>subsections</code> puts each group under a subheader; and <code>show-first</code> keeps each group to its first few rows, with a <b>Show N more</b> row for the rest.<sup class="fn"></sup></p>',
    notes: [
      'The layout button is one of only three ways the app writes the file. The others are onboarding\'s preset and the project picker, which appends projects.',
      'The All tab always groups by kind, newest first. Each project\'s own tab follows its configuration.',
    ],
    code: [
      { label: 'Tabs', lang: 'toml', code: '[menu]\nlayout = "tabs"' },
      { label: 'Grouped', lang: 'toml', code: '[defaults]\ngroup-by = "repository"\nsubsections = true\nshow-first = 4' },
    ],
    shots: ['panel-list-dark', 'panel-tabs-dark'],
  },
  {
    id: 'explorer', title: 'Config explorer', nav: 'Config explorer',
    lede: 'Pick a snippet and see what it changes, on a mock of the panel.',
    body: '<p>Each snippet below is a few lines of <code>config.toml</code>. The mock under it applies them to a small set of made-up items, so you can see what the keys do before you write them.<sup class="fn"></sup></p>',
    notes: ['The mock is drawn in HTML from these docs, not by the app. It follows the same rules for grouping, sorting and hiding, but it is not a screenshot.'],
    extra: 'explorer',
  },
  {
    id: 'pings', title: 'Pings and notices', nav: 'Pings and notices',
    lede: 'Your agents tell you when they need you, and when there\'s news.',
    body: '<p>A <b>ping</b> is a short message an agent sends with <code>shipyard ping send</code>: a title, an optional body and sender, and at most one action. It\'s listed under the projects that watch the repository of the agent\'s working folder, needs attention until you click it, and posts a notification. Clicking it opens a link, brings an app forward, or focuses the agent\'s Herdr tab.<sup class="fn"></sup></p>\n<p>A <b>notice</b>, from <code>shipyard notice send</code>, is a status update that needs nothing from you, such as "tests running": a notification only, never listed, counted or kept. When in doubt, agents send a notice.</p>',
    notes: [
      'A ping leaves a day after you\'ve seen it (<code>seen-window</code>), or when you dismiss it. Pings never reach GitHub.',
    ],
    code: [
      { lang: 'sh', code: 'shipyard ping send "PR #57 is ready for review" --from claude --open https://github.com/my-org/shop/pull/57\nshipyard ping send "Waiting for your input" --herdr --id shop-question\nshipyard ping withdraw shop-question\nshipyard notice send "Tests running" --from "claude · checkout" --id checkout-tests' },
    ],
    extra: 'pings',
    shots: ['panel-pings-dark', 'pings-tabs-light'],
    after: '<p>If your <code>config.toml</code> lists its own notification rules, add <code>{ event = "ping.sent" }</code> to hear about pings, and <code>{ event = "agent.notice" }</code> to let notices through: a project whose rules leave <code>agent.notice</code> out refuses notices, and the agent is told.</p>',
  },
  {
    id: 'notes', title: 'Notes in Notion', nav: 'Notes in Notion',
    lede: 'Your own notes, one Notion database per project, listed beside the pull requests.',
    body: '<p>Each project can list your open notes from Notion, newest first, with their numbers (<code>SHOP-7</code>) and labels. Each project has one database, titled with the project\'s title, under a "Projects" page inside a "Shipyard Notes" page. Clicking a note opens it in Notion, and the pencil icon on a project\'s header starts a new one there.<sup class="fn"></sup></p>\n<p>Notes are opt-in. shipyard reads and writes them through ' + ext('https://developers.notion.com/cli/get-started/overview', '<code>ntn</code>') + ', Notion\'s CLI, with ntn\'s own login, and keeps no Notion token of its own. Install ntn, run <code>ntn login</code> and choose your notes workspace, then press <b>Connect with ntn</b> in the gear menu\'s <b>Set up Notion</b> view.<sup class="fn"></sup></p>',
    notes: [
      'The pencil creates the project\'s database the first time, then an empty note, and opens it for you to type or dictate. Any agent with the skill can take a note you dictate.',
      'Once connected, notes are read every minute and when you open the menu. <code>shipyard notes check</code> reads the workspace the way the app does and says what\'s wrong.',
    ],
    code: [
      { label: 'ntn', lang: 'sh', code: 'curl -fsSL https://ntn.dev | bash\nntn login\nntn doctor' },
      { label: 'Hide one project\'s', lang: 'toml', code: '[[projects]]\nslug = "shop"\nrepositories = ["my-org/shop"]\nnotes = { show = false }' },
    ],
    shots: ['panel-notes-dark', 'view-notion-dark'],
  },
  {
    id: 'skill', title: 'The agent skill', nav: 'The agent skill',
    lede: 'Ask in your own words. Your agent edits the file and checks it.',
    body: '<p>shipyard ships an agent skill that teaches coding agents (Claude Code, Codex and others that read skills) to edit its configuration, ping you, post notices and take notes. Install it during onboarding, from <b>Set up /shipyard skill</b> in the gear menu, or from a terminal.<sup class="fn"></sup></p>\n<p>Then ask: "' + ASK_AGENT + '", "Hide dependabot\'s pull requests", "Tell me when CI fails on this project", "Switch shipyard to tabs". The agent edits the file, checks it with <code>shipyard config check</code> and the schema, and reads shipyard\'s verdict on the save.<sup class="fn"></sup></p>',
    notes: [
      'The Set up /shipyard skill view shows whether the skill is installed, and its <b>Update</b> runs the same command for the newest version.',
      'After each save the app writes its verdict to <code>~/Library/Application Support/Shipyard/config-status.json</code>, so the agent knows whether the app took the edit.',
    ],
    code: [
      { label: 'Install', lang: 'sh', code: INSTALL.skill },
      { label: 'Check an edit', lang: 'sh', code: 'shipyard config check\ntaplo check ~/.config/shipyard/config.toml' },
    ],
    shots: ['view-skill-dark', 'config-warning-dark'],
  },
  {
    id: 'machines', title: 'Other machines', nav: 'Other machines',
    lede: 'Agents on your other machines ping you too, through Herdr.',
    body: '<p>When your Mac\'s ' + ext('https://github.com/herdrdev/herdr', 'Herdr') + ' knows another machine as a saved machine, shipyard can list that machine\'s pings. Install the ' + ext(HERDR_PLUGIN, 'herdr-shipyard') + ' plugin on each machine, which puts the same <code>shipyard</code> command there, and name the machines in <code>[remote] machines</code> by their Herdr labels.<sup class="fn"></sup></p>\n<p>shipyard asks each machine for its pings about every 30 seconds and files them under the projects that watch their repositories, or under the machine\'s name. Clicking one sent from a Herdr pane takes you to that agent. On those machines the plugin also pings you by itself when Herdr marks an agent blocked, and takes the ping back when the agent goes on.<sup class="fn"></sup></p>\n<p>Notices travel the same way, or straight over your tailnet once <code>[notices] listen = true</code> and the machine\'s own <code>cli.toml</code> names your Mac.</p>',
    notes: [
      'shipyard reaches another machine only through Herdr\'s connection to it, never over SSH of its own, and the file names a label, never a host or an address.',
      'A machine that doesn\'t answer shows a quiet line in the menu and keeps its last pings until it answers again.',
    ],
    code: [
      { label: 'On the machine', lang: 'sh', code: INSTALL.plugin },
      { label: 'config.toml', lang: 'toml', code: '[remote]\nmachines = ["build-box"]' },
    ],
    shots: ['panel-remote-machine-dark', 'remote-machine-tabs-light'],
  },
  {
    id: 'configuration', title: 'Configuration reference', nav: 'Configuration',
    lede: 'Every key of config.toml, its default and what it takes.',
    body: '<p>The file is <code>~/.config/shipyard/config.toml</code>, or <code>$XDG_CONFIG_HOME/shipyard/config.toml</code> when that is set. <b>Open configuration file</b> in the gear menu opens it. Every key is optional and each save applies at once. A broken edit keeps the last good configuration and shows the error in the panel.<sup class="fn"></sup></p>\n<p>A project\'s tables merge key by key onto <code>[defaults]</code>, so <code>issues = { show = true }</code> keeps the default <code>closed-window</code>. A project\'s <code>notifications</code> replaces the default list instead. A <b>window</b> is a whole number and one unit, <code>s</code>, <code>m</code>, <code>h</code> or <code>d</code>, such as <code>"30m"</code> or <code>"7d"</code><sup class="fn"></sup></p>',
    notes: [
      `The file's first line, <code>#:schema</code>, names ${ext(SCHEMA_URL, 'the JSON schema')} this table is made from, so editors that read it complete and check every key.`,
      'Unknown keys are ignored with a warning, and deprecated keys still read, with a warning that names the new one.',
    ],
    code: [{ lang: 'toml', code: `#:schema ${SCHEMA_URL}\nversion = 1\n\n[[projects]]\nslug = "shipyard"\nrepositories = ["yahyabedirhan/shipyard"]` }],
    extra: 'config',
  },
  {
    id: 'commands', title: 'The shipyard command', nav: 'Command',
    lede: 'One command for agents and scripts: pings, notices, checks and the app.',
    body: '<p>The <code>shipyard</code> command comes inside the app. Link it onto your PATH from onboarding or <b>Set up shipyard command</b> in the gear menu, which puts it at <code>~/.local/bin/shipyard</code>. The herdr-shipyard plugin installs the same command on your Linux machines.<sup class="fn"></sup></p>\n<p>Every command is <code>shipyard &lt;group&gt; &lt;verb&gt;</code>. <code>shipyard --help</code> lists them all, <code>shipyard help &lt;group&gt;</code> prints one group\'s help, and <code>shipyard help --json</code> lists every command for agents.<sup class="fn"></sup></p>',
    notes: [
      'The app needn\'t be running for a ping: one sent meanwhile shows when it starts.',
      'The <code>app</code>, <code>panel</code> and <code>lease</code> groups drive the app on the Mac, one agent at a time. The holder shows as a yellow dot on the menu bar icon and a banner on the panel.',
    ],
    extra: 'commands',
    shots: ['view-cli-dark', 'cli-help-dark'],
  },
  {
    id: 'limits', title: 'Limits', nav: 'Limits',
    lede: 'What shipyard does not do yet.',
    body: '',
    notes: [],
    extra: 'limits',
  },
  {
    id: 'troubleshooting', title: 'Troubleshooting', nav: 'Troubleshooting',
    lede: 'Short answers to what goes wrong most.',
    body: '',
    notes: [],
    extra: 'troubleshooting',
  },
  {
    id: 'changelog', title: 'Changelog', nav: 'Changelog',
    lede: 'What changed in each version, with its pull requests.',
    body: `<p>Every release has an entry in ${ext(CHANGELOG, '<code>CHANGELOG.md</code>')}, newest first, and a download on ${ext(`${REPO}/releases`, 'GitHub releases')}. Ideas and bugs go to ${ext(ISSUES, 'the issues')}.</p>`,
    notes: [],
    extra: 'changelog',
  },
];

export const byId: Record<string, DocSection> = Object.fromEntries(SECTIONS.map((s) => [s.id, s]));

/** What shipyard does not do yet, each stated once. It follows the messaging kit's non-claims. */
export const LIMITS: [string, string][] = [
  ['macOS only', 'The app runs on macOS 14 or later. The <code>shipyard</code> command also runs on Linux, without the app.'],
  ['github.com only', 'It reads github.com. GitHub Enterprise Server is not supported.'],
  // PLACEHOLDER: notarized download. Remove this limit when the notarized build ships.
  ['Not notarized', 'macOS asks you to clear the quarantine flag before the first launch of the download.'],
  // PLACEHOLDER: Homebrew cask and automatic updates. Remove this limit when the cask ships.
  ['No Homebrew or updates', 'There is no Homebrew cask and no automatic update yet.'],
  ['Settings in a file', 'The gear menu shows the setup of GitHub, Notion, the skill and the command, and the layout button switches layouts. Everything else is edited in <code>config.toml</code>, by you or your agents.'],
  ['Herdr windows', 'With Herdr 0.9.3, clicking another machine\'s ping focuses its pane on that machine, but the Mac\'s Herdr window moves there only when it already shows that machine.'],
];

/** Questions and their answers, as HTML. */
export const QUESTIONS: [string, string][] = [
  ['macOS says the app can\'t be opened', 'The download isn\'t notarized. Run <code>xattr -dr com.apple.quarantine /Applications/Shipyard.app</code>, then open it again.'],
  ['The panel says the configuration has a problem', 'shipyard keeps running on the last valid configuration. Run <code>shipyard config check</code>: it names each problem with its line, and the nearest spelling when a key or value is misspelled.'],
  ['Pings don\'t notify me', 'Your file lists its own notification rules without <code>ping.sent</code>. Add <code>{ event = "ping.sent" }</code> beside the rules you have.'],
  ['<code>shipyard</code> isn\'t found', 'Link it from <b>Set up shipyard command</b> in the gear menu, which puts it at <code>~/.local/bin/shipyard</code>, and make sure that folder is on your PATH. The view says what is in the way when the link can\'t be made.'],
  ['A ping is refused', 'No project watches the repository of the folder it was sent from. Send it with <code>--project &lt;slug&gt;</code>, or watch the repository in a project.'],
  ['No notes are listed', 'Check that ntn is installed and logged in (<code>ntn doctor</code>), that its default workspace has a Shipyard Notes page, and that you pressed <b>Connect with ntn</b>. <code>shipyard notes check</code> says what\'s wrong.'],
  ['Another machine\'s pings don\'t show', 'Check that its label is in <code>[remote] machines</code> exactly as Herdr saves it, and that <code>herdr plugin list</code> on the machine shows herdr-shipyard.'],
  ['<code>anywhere</code> is rejected', '<code>anywhere</code> comes from one GitHub search, so its project must set <code>pull-requests = { review-requested = true }</code> and show no issues or runs.'],
  ['The rate limit runs low', 'shipyard spends at most <code>max-share-percent</code> of each hourly GitHub limit, 10% by default, and stretches <code>refresh-interval</code> to stay within it. Lower the share, or watch fewer repositories.'],
];

/** The ways to install, in the order the Install section shows them. */
export const INSTALL_WAYS = [
  { id: 'download', label: 'Download', lang: 'sh' as const, code: INSTALL.download, hint: `Get the zip from the ${ext(RELEASES, 'latest release')}.` },
  { id: 'source', label: 'From source', lang: 'sh' as const, code: INSTALL.source, hint: 'Builds, signs and installs the app, then opens it.' },
  // PLACEHOLDER: Homebrew. No cask exists yet, so the tab says so instead of showing a command that fails.
  { id: 'homebrew', label: 'Homebrew', lang: 'text' as const, code: 'Not available yet. Use the download or build from source.', hint: 'There is no cask yet.' },
];
