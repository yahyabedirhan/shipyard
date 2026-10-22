// The generated reference: the configuration's keys from schema/config.schema.json and cli.schema.json, and the
// `shipyard` command's groups from the Swift sources that define them. Everything here is pure: the site's integration
// reads the files (plugins/repo.ts) and hands their text in, so the page, its Markdown and the tests share one parse.

/* ---------------------------------------------------------------- the configuration */

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };
export interface SchemaNode {
  description?: string;
  type?: string;
  enum?: Json[];
  default?: Json;
  minimum?: number;
  maximum?: number;
  minItems?: number;
  pattern?: string;
  items?: SchemaNode;
  properties?: Record<string, SchemaNode>;
  definitions?: Record<string, SchemaNode>;
  required?: string[];
  anyOf?: SchemaNode[];
  $ref?: string;
}

/** One key of the configuration, as the reference lists it. */
export interface KeyRow {
  /** `<owner>.<key>`: the object the key belongs to, then its name. The tests check every one is on the page. */
  id: string;
  owner: string;
  key: string;
  type: string;
  allowed: string;
  default: string;
  description: string;
  required: boolean;
  /** When the key holds a table described elsewhere in the reference, that table's owner. */
  table?: string;
}

/** A block of the reference: one TOML table, or a table shape that several places share. */
export interface KeyGroup {
  owner: string;
  /** How the table is written in the file, such as `[menu]` or `[[projects]]`. */
  heading: string;
  /** Where else the same keys are written. */
  also?: string;
  description: string;
  rows: KeyRow[];
}

/** The tables of config.toml in reading order, each with the TOML it's written as. */
const OWNERS: { owner: string; heading: string; also?: string }[] = [
  { owner: 'root', heading: 'Top level' },
  { owner: 'menu-bar', heading: '[menu-bar]' },
  { owner: 'menu', heading: '[menu]' },
  { owner: 'rate-limit', heading: '[rate-limit]' },
  { owner: 'attention', heading: '[attention]' },
  { owner: 'banners', heading: '[banners]' },
  { owner: 'herdr', heading: '[herdr]' },
  { owner: 'remote', heading: '[remote]' },
  { owner: 'notices', heading: '[notices]' },
  { owner: 'defaults', heading: '[defaults]' },
  { owner: 'pull-requests', heading: '[defaults.pull-requests]', also: 'pull-requests = { … } in a project' },
  { owner: 'issues', heading: '[defaults.issues]', also: 'issues = { … } in a project' },
  { owner: 'workflow-runs', heading: '[defaults.workflow-runs]', also: 'workflow-runs = { … } in a project' },
  { owner: 'pings', heading: '[defaults.pings]', also: 'pings = { … } in a project' },
  { owner: 'notes', heading: '[defaults.notes]', also: 'notes = { … } in a project' },
  { owner: 'authors', heading: 'authors = { show, hide }', also: 'in each kind’s table' },
  { owner: 'notification-rule', heading: '[[defaults.notifications]]', also: 'notifications = [{ … }] in a project' },
  { owner: 'project', heading: '[[projects]]' },
];

const refName = (ref: string) => ref.replace('#/definitions/', '');

/** A JSON value as it would be written in TOML. */
export function toml(v: Json | undefined): string {
  if (v === undefined) return '';
  if (typeof v === 'string') return JSON.stringify(v);
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  if (v === null) return '';
  if (Array.isArray(v)) {
    if (v.length && v.every((x) => x && typeof x === 'object' && !Array.isArray(x) && 'event' in x)) {
      return `${v.length} rules: ${v.map((x) => (x as { event: string }).event).join(', ')}`;
    }
    return `[${v.map(toml).join(', ')}]`;
  }
  return `{ ${Object.entries(v).map(([k, x]) => `${k} = ${toml(x)}`).join(', ')} }`;
}

function describeType(n: SchemaNode, defs: Record<string, SchemaNode>): { type: string; allowed: string; table?: string } {
  if (n.$ref) {
    const name = refName(n.$ref);
    const d = defs[name];
    if (d?.type === 'object') return { type: 'table', allowed: '', table: name };
    if (name === 'notifications') return { type: 'list of rules', allowed: '', table: 'notification-rule' };
    return describeType(d ?? {}, defs);
  }
  if (n.anyOf) {
    return describeType(n.anyOf[0], defs);
  }
  if (n.type === 'array') {
    const items = n.items?.$ref ? defs[refName(n.items.$ref)] ?? {} : n.items ?? {};
    if (n.items?.$ref && items.type === 'object') return { type: 'list of tables', allowed: '', table: refName(n.items.$ref) };
    const allowed = items.enum ? items.enum.map((e) => toml(e)).join(', ') : n.items?.$ref === '#/definitions/author-selectors' ? 'author selectors' : '';
    const isSelectors = items.description?.startsWith('Author selectors');
    return { type: isSelectors ? 'author selectors' : 'list', allowed: allowed || (isSelectors ? '`me`, `others`, `bots`, `@login`' : '') };
  }
  const range = n.minimum !== undefined && n.maximum !== undefined ? `${n.minimum} to ${n.maximum}`
    : n.minimum !== undefined ? `${n.minimum} or more` : '';
  const allowed = n.enum ? n.enum.map((e) => toml(e)).join(', ') : range;
  return { type: n.type ?? '', allowed };
}

/** The default of a key, following its reference when the key itself has none. */
function defaultOf(n: SchemaNode, defs: Record<string, SchemaNode>): string {
  if (n.default !== undefined) return toml(n.default);
  if (n.$ref) {
    const d = defs[refName(n.$ref)];
    if (d && d.type !== 'object' && d.default !== undefined) return toml(d.default);
  }
  return '';
}

function rowsOf(owner: string, node: SchemaNode, defs: Record<string, SchemaNode>): KeyRow[] {
  return Object.entries(node.properties ?? {}).map(([key, n]) => {
    const target = n.$ref ? defs[refName(n.$ref)] : undefined;
    const t = describeType(n, defs);
    const description = n.description ?? target?.description ?? '';
    return {
      id: `${owner}.${key}`,
      owner,
      key,
      type: t.type,
      allowed: t.allowed,
      default: defaultOf(n, defs),
      description,
      required: Boolean(node.required?.includes(key)),
      ...(t.table ? { table: t.table } : {}),
    };
  });
}

/** The configuration's keys, one group per table, from the JSON schema. */
export function configReference(schema: SchemaNode): KeyGroup[] {
  const defs = schema.definitions ?? {};
  const props = schema.properties ?? {};
  const rootScalars: SchemaNode = { properties: Object.fromEntries(Object.entries(props).filter(([, n]) => n.type !== 'object' && n.type !== 'array' || (n.type === 'array' && !n.items?.$ref))) };
  const nodeOf = (owner: string): SchemaNode | undefined => (owner === 'root' ? rootScalars : props[owner]?.type === 'object' ? props[owner] : defs[owner]);
  return OWNERS.map(({ owner, heading, also }) => {
    const node = nodeOf(owner);
    if (!node) throw new Error(`config.schema.json has no table ${owner}`);
    return { owner, heading, also, description: owner === 'root' ? 'Keys above the first table header.' : node.description ?? '', rows: rowsOf(owner, node, defs) };
  });
}

/** Every key the schema defines, as `<owner>.<key>`, found by walking the schema itself. The tests compare it with the page. */
export function schemaKeyIds(schema: SchemaNode): string[] {
  const ids: string[] = [];
  for (const [k, n] of Object.entries(schema.properties ?? {})) {
    if (n.type === 'object') for (const sub of Object.keys(n.properties ?? {})) ids.push(`${k}.${sub}`);
    else if (k !== 'projects') ids.push(`root.${k}`);
  }
  for (const [name, d] of Object.entries(schema.definitions ?? {})) {
    if (d.type === 'object') for (const sub of Object.keys(d.properties ?? {})) ids.push(`${name}.${sub}`);
  }
  return ids;
}

/** The keys of cli.toml, the command's own settings file. */
export function cliReference(schema: SchemaNode): KeyGroup[] {
  const defs = schema.definitions ?? {};
  const props = schema.properties ?? {};
  const top: SchemaNode = { properties: Object.fromEntries(Object.entries(props).filter(([, n]) => n.type !== 'object')) };
  const groups: KeyGroup[] = [{ owner: 'cli-root', heading: 'Top level', description: 'Keys above the first table header.', rows: rowsOf('cli-root', top, defs) }];
  for (const [k, n] of Object.entries(props)) {
    if (n.type === 'object') groups.push({ owner: `cli-${k}`, heading: `[${k}]`, description: n.description ?? '', rows: rowsOf(`cli-${k}`, n, defs) });
  }
  return groups;
}

/* ---------------------------------------------------------------- the skill's tables */

/** Splits a Markdown table row into its cells, keeping `|` inside backticks. */
export function cells(line: string): string[] {
  const out: string[] = [];
  let cur = '';
  let tick = false;
  const body = line.trim().replace(/^\|/, '').replace(/\|$/, '');
  for (const ch of body) {
    if (ch === '`') tick = !tick;
    if (ch === '|' && !tick) { out.push(cur.trim()); cur = ''; continue; }
    cur += ch;
  }
  out.push(cur.trim());
  return out;
}

/** The Markdown tables in a document, each with the line of prose above it. */
export function tables(md: string): { intro: string; head: string[]; rows: string[][] }[] {
  const lines = md.split('\n');
  const out: { intro: string; head: string[]; rows: string[][] }[] = [];
  let intro = '';
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.startsWith('|') && lines[i + 1]?.startsWith('|') && /^\|[\s|:-]+\|$/.test(lines[i + 1].trim())) {
      const head = cells(line);
      const rows: string[][] = [];
      let j = i + 2;
      for (; j < lines.length && lines[j].startsWith('|'); j++) rows.push(cells(lines[j]));
      out.push({ intro, head, rows });
      i = j - 1;
    } else if (line.trim()) intro = line;
  }
  return out;
}

/**
 * The keys the skill's "Keys and defaults" tables name, as `<owner>.<key>` ids, with their Allowed text.
 * `[menu] layout` is `menu.layout`, `pull-requests.show` is `pull-requests.show`, and a bare key takes the owner of
 * its table's lead-in: top level, or a project.
 */
export function skillKeys(skill: string): { id: string; allowed: string }[] {
  const start = skill.indexOf('## Keys and defaults');
  const end = skill.indexOf('\n## ', start + 5);
  const out: { id: string; allowed: string }[] = [];
  for (const t of tables(skill.slice(start, end))) {
    if (t.head[0] !== 'Key') continue;
    const owner = /\[\[projects\]\]/.test(t.intro) ? 'project' : /^Top level/.test(t.intro) ? 'root' : '';
    for (const r of t.rows) {
      const m = r[0].match(/^`([^`]+)`$/);
      if (!m) continue; // a row naming several keys at once
      const k = m[1];
      const table = k.match(/^\[([\w.-]+)\] ([\w-]+)$/);
      const id = table ? `${table[1]}.${table[2]}` : k.includes('.') ? k : k === 'notifications' ? 'defaults.notifications' : `${owner}.${k}`;
      out.push({ id, allowed: r[r.length - 1] });
    }
  }
  return out;
}

/** The flags of a command, from the first `| Flag | What it does |` table in a document. */
export function flagTable(md: string): [string, string][] {
  const t = tables(md).find((x) => x.head[0] === 'Flag');
  return t ? t.rows.map((r) => [r[0], r[1]] as [string, string]) : [];
}

/* ---------------------------------------------------------------- the commands */

export interface CommandRow { group: string; section: string; usage: string; summary: string }
export interface CommandSection { id: string; heading: string; commands: CommandRow[] }
export interface CommandReference {
  sections: CommandSection[];
  options: [string, string][];
  environment: [string, string][];
  exitCodes: string;
  macOnly: string[];
}

const unescape = (s: string) => s.replace(/\\"/g, '"').replace(/\\\\/g, '\\');

/**
 * The command groups, read from the Swift sources. Swift can't run where the site builds (Linux CI, Cloudflare),
 * so this parses the source of the command table instead of running `shipyard help --json`: each group's
 * `CommandTable.Entry(name:section:commands:)`, the `static let` list of `CommandTable.Command(usage, summary)` it
 * names in the same file, and the section headings and top help in CommandTable.swift. A change to those shapes
 * fails the tests, which check the page against `shipyard help --json`'s shape.
 */
export function commandReference(files: Record<string, string>): CommandReference {
  const table = Object.entries(files).find(([p]) => p.endsWith('CommandTable.swift'))?.[1];
  if (!table) throw new Error('no CommandTable.swift among the sources');
  const order = [...table.matchAll(/^\s*case (\w+)$/gm)].map((m) => m[1]);
  const headings = Object.fromEntries([...table.matchAll(/case \.(\w+): "([^"]+)"/g)].map((m) => [m[1], m[2].replace(/:$/, '')]));
  const rows: CommandRow[] = [];
  for (const [, text] of Object.entries(files).sort(([a], [b]) => a.localeCompare(b))) {
    const lists: Record<string, [string, string][]> = {};
    for (const m of text.matchAll(/static let (\w+) = \[([\s\S]*?)\n\s*\]/g)) {
      lists[m[1]] = [...m[2].matchAll(/CommandTable\.Command\("((?:[^"\\]|\\.)*)", "((?:[^"\\]|\\.)*)"\)/g)].map((c) => [unescape(c[1]), unescape(c[2])]);
    }
    for (const m of text.matchAll(/CommandTable\.Entry\(name: "([\w-]+)", section: \.(\w+), commands: (\w+)\)/g)) {
      const list = lists[m[3]];
      if (!list) throw new Error(`no list ${m[3]} beside the ${m[1]} group`);
      for (const [usage, summary] of list) rows.push({ group: m[1], section: m[2], usage: `shipyard ${m[1]}${usage ? ` ${usage}` : ''}`, summary });
    }
  }
  const sections = order.filter((id) => headings[id]).map((id) => ({ id, heading: headings[id], commands: rows.filter((r) => r.section === id) }));
  const pairs = (re: RegExp) => [...table.matchAll(re)].map((m) => [unescape(m[1]), unescape(m[2])] as [string, string]);
  return {
    sections,
    options: pairs(/\("(-[^"]+)", "((?:[^"\\]|\\.)*)"\)/g),
    environment: pairs(/\("([A-Z_]+)", "((?:[^"\\]|\\.)*)"\)/g),
    exitCodes: table.match(/"(Exit codes: [^"]+)"/)?.[1] ?? '',
    macOnly: (table.match(/macOnly: Set<String> = \[([^\]]+)\]/)?.[1] ?? '').match(/[\w-]+/g) ?? [],
  };
}

/* ---------------------------------------------------------------- inline Markdown */

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** Inline Markdown from the repository's own files (code, bold, links) as HTML. Everything else is escaped. */
export function inlineMd(md: string): string {
  const parts = md.split(/(`[^`]*`)/);
  return parts.map((p) => {
    if (p.startsWith('`') && p.endsWith('`') && p.length > 1) return `<code>${esc(p.slice(1, -1))}</code>`;
    return esc(p)
      .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
      .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noreferrer">$1</a>')
      .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '$1');
  }).join('');
}
