// The landing page's words. The one line, install lines and links come from messaging.ts; this adds the first
// screen's few sentences: what it is, who it's for, how it's used, and the basic facts.

export const WHAT = 'Your pull requests, issues, workflow runs, pings from your agents and notes, grouped by project, in one list in the menu bar.';

/** The two uses, as equals, as the messaging kit asks. */
export const WHO = 'For people whose coding agents work on their projects, and for maintainers who review what other people open.';

export const HOW = 'Click any item to open it. To change what you see, just ask your agent. Your agents can also message you when they need your input.';

export const FACTS: [string, string][] = [
  ['Runs on', 'macOS 14 or later'],
  ['Works with', 'GitHub, Notion'],
  ['Configuration', 'Agent-first customization'],
  ['Command', '`shipyard`, also on Linux'],
  ['License', 'Apache 2.0'],
];
