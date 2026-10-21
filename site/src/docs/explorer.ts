// The config explorer's model: a few made-up items and the handful of keys the snippets set, applied the way the
// skill describes them (grouping, sorting, show-first, states and authors). It draws a mock, not the app: keep it
// to the rules the docs state, and leave everything else out.

export type Kind = 'pull-requests' | 'pings' | 'issues' | 'workflow-runs';
export type State = 'open' | 'draft' | 'merged' | 'closed' | 'running' | 'failed' | 'succeeded';
export type AuthorGroup = 'me' | 'others' | 'bots';

export interface MockItem {
  kind: Kind;
  project: string;
  repo: string;
  number?: number;
  title: string;
  /** A login, or a ping's sender. */
  author: string;
  group: AuthorGroup | null;
  state: State;
  /** Hours since it was last updated. */
  age: number;
  attention: boolean;
}

export interface MockConfig {
  layout: 'list' | 'tabs';
  groupBy: 'kind' | 'repository' | 'date' | 'author' | 'none';
  /** Unset keeps each layout's own look: dividers in the list, subheaders in tabs. */
  subsections?: boolean;
  sortBy: 'updated' | 'title';
  showFirst: number;
  issues: boolean;
  runs: boolean;
  prStates: ('open' | 'merged' | 'closed')[];
  hide: AuthorGroup[];
}

export const DEFAULT_CONFIG: MockConfig = {
  layout: 'list', groupBy: 'kind', sortBy: 'updated', showFirst: 0, issues: false, runs: false, prStates: ['open', 'merged', 'closed'], hide: [],
};

export const PROJECTS = [
  { slug: 'shop', title: 'shop' },
  { slug: 'docs', title: 'docs' },
];

export const ITEMS: MockItem[] = [
  { kind: 'pull-requests', project: 'shop', repo: 'my-org/shop', number: 57, title: 'Add the order export', author: 'you', group: 'me', state: 'open', age: 1, attention: true },
  { kind: 'pull-requests', project: 'shop', repo: 'my-org/shop-api', number: 212, title: 'Cache the price lookups', author: 'you', group: 'me', state: 'draft', age: 3, attention: false },
  { kind: 'pull-requests', project: 'shop', repo: 'my-org/shop', number: 58, title: 'Bump vite from 5.4.0 to 5.4.21', author: 'dependabot[bot]', group: 'bots', state: 'open', age: 5, attention: true },
  { kind: 'pull-requests', project: 'shop', repo: 'my-org/shop-api', number: 209, title: 'Fix the refund rounding', author: 'ada', group: 'others', state: 'open', age: 20, attention: true },
  { kind: 'pull-requests', project: 'shop', repo: 'my-org/shop', number: 54, title: 'Split the checkout steps', author: 'you', group: 'me', state: 'merged', age: 30, attention: false },
  { kind: 'pull-requests', project: 'shop', repo: 'my-org/shop', number: 52, title: 'Try a second payment provider', author: 'lin', group: 'others', state: 'closed', age: 80, attention: false },
  { kind: 'pings', project: 'shop', repo: 'my-org/shop', title: 'PR #57 is ready for review', author: 'claude · orders', group: null, state: 'open', age: 0.5, attention: true },
  { kind: 'issues', project: 'shop', repo: 'my-org/shop', number: 61, title: 'Export misses the tax column', author: 'lin', group: 'others', state: 'open', age: 8, attention: true },
  { kind: 'issues', project: 'shop', repo: 'my-org/shop-api', number: 198, title: 'Document the webhook retries', author: 'you', group: 'me', state: 'closed', age: 50, attention: false },
  { kind: 'workflow-runs', project: 'shop', repo: 'my-org/shop', title: 'ci on add-order-export', author: 'you', group: 'me', state: 'failed', age: 1, attention: true },
  { kind: 'workflow-runs', project: 'shop', repo: 'my-org/shop-api', title: 'deploy on main', author: 'you', group: 'me', state: 'running', age: 0.2, attention: false },
  { kind: 'pull-requests', project: 'docs', repo: 'my-org/docs', number: 33, title: 'Rewrite the install page', author: 'you', group: 'me', state: 'open', age: 2, attention: true },
  { kind: 'pull-requests', project: 'docs', repo: 'my-org/docs', number: 34, title: 'Update renovate config', author: 'renovate[bot]', group: 'bots', state: 'open', age: 26, attention: false },
  { kind: 'issues', project: 'docs', repo: 'my-org/docs', number: 30, title: 'Broken link on the pricing page', author: 'ada', group: 'others', state: 'open', age: 100, attention: false },
  { kind: 'workflow-runs', project: 'docs', repo: 'my-org/docs', title: 'pages on main', author: 'you', group: 'me', state: 'succeeded', age: 2, attention: false },
];

export interface Snippet { id: string; label: string; toml: string; config: Partial<MockConfig>; what: string }

export const SNIPPETS: Snippet[] = [
  { id: 'defaults', label: 'Defaults', toml: 'version = 1', config: {}, what: 'Pull requests and pings only, grouped by kind, newest first.' },
  { id: 'issues-runs', label: 'Issues and runs', toml: '[defaults.issues]\nshow = true\n\n[defaults.workflow-runs]\nshow = true', config: { issues: true, runs: true }, what: 'Issues and workflow runs join the pull requests in every project.' },
  { id: 'by-repository', label: 'By repository', toml: '[defaults]\ngroup-by = "repository"\nsubsections = true', config: { groupBy: 'repository', subsections: true }, what: 'Each repository is a group under its own subheader, A to Z.' },
  { id: 'by-date', label: 'By date', toml: '[defaults]\ngroup-by = "date"', config: { groupBy: 'date' }, what: 'Today, Yesterday, This week and Older, by when each item was updated.' },
  { id: 'show-first', label: 'Show first', toml: '[defaults]\nshow-first = 2', config: { showFirst: 2 }, what: 'Each group shows two rows and a Show N more row for the rest.' },
  { id: 'hide-bots', label: 'Hide bots', toml: '[defaults.pull-requests]\nauthors = { hide = ["bots"] }', config: { hide: ['bots'] }, what: 'Bots\' pull requests are gone: not shown, counted or notified.' },
  { id: 'open-only', label: 'Open only', toml: '[defaults.pull-requests]\nstates = ["open"]', config: { prStates: ['open'] }, what: 'Merged and closed pull requests leave the list. Drafts count as open.' },
  { id: 'tabs', label: 'Tabs', toml: '[menu]\nlayout = "tabs"', config: { layout: 'tabs' }, what: 'One project at a time. The All tab lists every project, grouped by kind.' },
];

const KIND_ORDER: Kind[] = ['pull-requests', 'pings', 'issues', 'workflow-runs'];
export const KIND_NAMES: Record<Kind, string> = { 'pull-requests': 'Pull requests', pings: 'Pings', issues: 'Issues', 'workflow-runs': 'Runs' };
const DATE_GROUPS = ['Today', 'Yesterday', 'This week', 'Older'];

const isOpen = (s: State) => s === 'open' || s === 'draft' || s === 'running';
const dateGroup = (age: number) => (age < 24 ? 'Today' : age < 48 ? 'Yesterday' : age < 168 ? 'This week' : 'Older');

/** Whether a project's filters list an item. */
export function listed(item: MockItem, c: MockConfig): boolean {
  if (item.kind === 'issues' && !c.issues) return false;
  if (item.kind === 'workflow-runs' && !c.runs) return false;
  if (item.kind === 'pull-requests') {
    const state = item.state === 'draft' ? 'open' : item.state;
    if (!c.prStates.includes(state as 'open')) return false;
    if (item.group && c.hide.includes(item.group)) return false;
  }
  return true;
}

/** Open or running first, then newest first or A to Z. */
export function sorted(items: MockItem[], c: MockConfig): MockItem[] {
  return [...items].sort((a, b) => Number(isOpen(b.state)) - Number(isOpen(a.state)) || (c.sortBy === 'title' ? a.title.localeCompare(b.title) : a.age - b.age));
}

export interface Group { name: string; count: number; rows: MockItem[]; more: number }

export function groups(items: MockItem[], c: MockConfig, by = c.groupBy): Group[] {
  const keyOf = (i: MockItem): string => (by === 'kind' ? KIND_NAMES[i.kind] : by === 'repository' ? i.repo : by === 'date' ? dateGroup(i.age) : by === 'author' ? (i.kind === 'pings' ? 'Pings' : i.author) : '');
  const order = by === 'kind' ? KIND_ORDER.map((k) => KIND_NAMES[k]) : by === 'date' ? DATE_GROUPS : null;
  const names = [...new Set(items.map(keyOf))].sort((a, b) => (order ? order.indexOf(a) - order.indexOf(b) : a.localeCompare(b)));
  return names.map((name) => {
    const all = sorted(items.filter((i) => keyOf(i) === name), c);
    const rows = c.showFirst > 0 ? all.slice(0, c.showFirst) : all;
    return { name, count: all.length, rows, more: all.length - rows.length };
  });
}

/** The attention count in the menu bar: listed items that need attention. */
export function attentionCount(c: MockConfig): number {
  return ITEMS.filter((i) => listed(i, c) && i.attention && isOpen(i.state)).length;
}

export interface MockProject { slug: string; title: string; groups: Group[]; count: number }

/** What the mock panel shows for a configuration. In tabs it shows the All tab, grouped by kind across projects. */
export function mockPanel(c: MockConfig): { tabs: string[] | null; projects: MockProject[]; attention: number } {
  const shown = ITEMS.filter((i) => listed(i, c));
  if (c.layout === 'tabs') {
    return { tabs: ['All', ...PROJECTS.map((p) => p.title)], projects: [{ slug: 'all', title: 'All', groups: groups(shown, { ...c, sortBy: 'updated' }, 'kind'), count: shown.length }], attention: attentionCount(c) };
  }
  return {
    tabs: null,
    projects: PROJECTS.map((p) => {
      const mine = shown.filter((i) => i.project === p.slug);
      return { ...p, groups: groups(mine, c), count: mine.length };
    }),
    attention: attentionCount(c),
  };
}

export const configOf = (s: Snippet): MockConfig => ({ ...DEFAULT_CONFIG, ...s.config });

/** A row's age as the panel writes it. */
export const ageLabel = (h: number) => (h < 1 ? `${Math.round(h * 60)}m` : h < 24 ? `${Math.round(h)}h` : `${Math.round(h / 24)}d`);
