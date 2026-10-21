// Reads the repository files the site is made from. The site lives in site/, so the rest of the repository is one
// folder up. Only this file and the scripts touch the disk; src/reference/parse.ts turns the text into data.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { cliReference, commandReference, configReference, flagTable, skillKeys, tables, type SchemaNode } from '../src/reference/parse';

export const SITE_DIR = fileURLToPath(new URL('..', import.meta.url));
export const REPO_DIR = join(SITE_DIR, '..');

export const repoPath = (...parts: string[]) => join(REPO_DIR, ...parts);
export const readRepo = (...parts: string[]) => readFileSync(repoPath(...parts), 'utf8');

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
}

/** The Swift files that define the command table and its groups: CommandTable.swift and each `*Command*.swift`. */
export function commandSources(): Record<string, string> {
  const files = walk(repoPath('Sources')).filter((p) => /Command[^/]*\.swift$/.test(p));
  return Object.fromEntries(files.map((p) => [relative(REPO_DIR, p), readFileSync(p, 'utf8')]));
}

/** The app's version, from Version.swift. */
export function appVersion(): string {
  return readRepo('Sources/ShipyardCommand/Version.swift').match(/current\s*=\s*"([^"]+)"/)?.[1] ?? '';
}

/** The three presets from skills/shipyard/presets.md: each one's use, what it asks for, its lead paragraph and its whole file. */
export function presets(md = readRepo('skills/shipyard/presets.md')) {
  const table = tables(md).find((t) => t.head[0] === 'Preset');
  return (table?.rows ?? []).map(([id, forWhat, asks]) => {
    const name = id.replace(/`/g, '');
    const start = md.indexOf(`## \`${name}\``);
    const part = md.slice(start, md.indexOf('\n## ', start + 4) === -1 ? undefined : md.indexOf('\n## ', start + 4));
    const about = part.split('\n').find((l, i) => i > 0 && l.trim() && !l.startsWith('```')) ?? '';
    const file = part.match(/```toml\n([\s\S]*?)```/)?.[1].trim() ?? '';
    return { id: name, for: forWhat, asks, about, file };
  });
}

/** The newest released version in CHANGELOG.md and its date, and the first paragraph of its entry. */
export function latestRelease(md = readRepo('CHANGELOG.md')) {
  const m = md.match(/^## (\d+\.\d+\.\d+) \((\d{4}-\d{2}-\d{2})\)\n\n([^\n]+)/m);
  return m ? { version: m[1], date: m[2], summary: m[3] } : null;
}

/** Everything the reference sections show, as one JSON-ready object. */
export function referenceData() {
  const schema = JSON.parse(readRepo('schema/config.schema.json')) as SchemaNode;
  const cli = JSON.parse(readRepo('schema/cli.schema.json')) as SchemaNode;
  const skill = readRepo('skills/shipyard/SKILL.md');
  const notices = readRepo('skills/shipyard/references/notices.md');
  const allowed = Object.fromEntries(skillKeys(skill).map((k) => [k.id, k.allowed]));
  const config = configReference(schema).map((g) => ({
    ...g,
    rows: g.rows.map((r) => (r.description ? r : { ...r, description: allowed[r.id] ?? '' })),
  }));
  return {
    version: appVersion(),
    config,
    cli: cliReference(cli),
    commands: commandReference(commandSources()),
    presets: presets(),
    changelog: latestRelease(),
    flags: { ping: flagTable(skill.slice(skill.indexOf('### The command'))), notice: flagTable(notices) },
  };
}

export type ReferenceData = ReturnType<typeof referenceData>;
