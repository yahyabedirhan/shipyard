import { readFileSync } from 'node:fs';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { referenceData, readRepo } from '../../plugins/repo';
import { buildAgentFiles } from '../../plugins/agents';
import { Docs } from '../docs/Docs';
import { schemaKeyIds, skillKeys, type SchemaNode } from './parse';

const ref = referenceData();
const page = renderToStaticMarkup(<Docs />);
const files = buildAgentFiles(ref);
const schema = JSON.parse(readRepo('schema/config.schema.json')) as SchemaNode;

describe('the configuration reference', () => {
  const ids = schemaKeyIds(schema);

  it('finds the schema\'s keys', () => {
    expect(ids.length).toBeGreaterThan(60);
    expect(ids).toContain('menu.layout');
    expect(ids).toContain('notification-rule.event');
  });

  it('lists every key of config.schema.json on the page', () => {
    const missing = ids.filter((id) => !page.includes(`data-key="${id}"`));
    expect(missing).toEqual([]);
  });

  it('lists every key in configuration.md, under its table', () => {
    const md = files['docs/configuration.md'];
    for (const g of ref.config) {
      expect(md).toContain(`### \`${g.heading}\``);
      for (const r of g.rows) expect(md, r.id).toContain(`| \`${r.key}\``);
    }
  });

  it('lists every key of cli.schema.json', () => {
    const cli = JSON.parse(readRepo('schema/cli.schema.json')) as SchemaNode;
    for (const [k, n] of Object.entries(cli.properties ?? {})) {
      const subs = n.type === 'object' ? Object.keys(n.properties ?? {}).map((s) => `cli-${k}.${s}`) : [`cli-root.${k}`];
      for (const id of subs) expect(page, id).toContain(`data-key="${id}"`);
    }
  });

  it('names in the skill only keys the schema has, so the two cannot drift apart', () => {
    const known = new Set(ids);
    const keys = skillKeys(readRepo('skills/shipyard/SKILL.md'));
    expect(keys.length).toBeGreaterThan(30);
    expect(keys.filter((k) => !known.has(k.id)).map((k) => k.id)).toEqual([]);
  });

  it('gives each row a description', () => {
    expect(ref.config.flatMap((g) => g.rows).filter((r) => !r.description).map((r) => r.id)).toEqual([]);
  });
});

describe('the command reference', () => {
  const rows = ref.commands.sections.flatMap((s) => s.commands);

  it('reads every group from the Swift sources, in the help\'s sections', () => {
    expect(ref.commands.sections.map((s) => s.id)).toEqual(['messages', 'app', 'checks', 'plumbing']);
    const groups = new Set(rows.map((r) => r.group));
    for (const g of ['ping', 'notice', 'app', 'panel', 'lease', 'config', 'notes', 'herdr-event']) expect(groups, g).toContain(g);
    for (const g of ref.commands.macOnly) expect(groups, g).toContain(g);
  });

  it('lists every command on the page and in commands.md', () => {
    expect(rows.length).toBeGreaterThan(15);
    for (const r of rows) {
      expect(page, r.usage).toContain(`data-command="${r.usage.replace(/</g, '&lt;').replace(/>/g, '&gt;')}"`);
      expect(files['docs/commands.md'], r.usage).toContain(r.usage);
    }
  });

  it('matches every usage the Swift sources declare', () => {
    const declared = Object.values(import.meta.glob('../../../Sources/**/*Command*.swift', { query: '?raw', import: 'default', eager: true }) as Record<string, string>)
      .flatMap((text) => [...text.matchAll(/CommandTable\.Command\("((?:[^"\\]|\\.)*)"/g)].map((m) => m[1]));
    expect(rows.length).toBe(declared.length);
  });

  it('reads the top help\'s options and exit codes', () => {
    expect(ref.commands.options.map(([k]) => k)).toEqual(['-h, --help', '--version']);
    expect(ref.commands.environment.map(([k]) => k)).toEqual(['SHIPYARD_CONTROL_KEY']);
    expect(ref.commands.exitCodes).toMatch(/^Exit codes: 0 success/);
  });

  it('reads the flags of ping send and notice send from the skill', () => {
    expect(ref.flags.ping.map(([f]) => f)).toContain('`--open <url>`');
    expect(ref.flags.notice.map(([f]) => f)).toContain('`--level <level>`');
  });
});

describe('the presets', () => {
  it('reads all three, each with its whole file', () => {
    expect(ref.presets.map((p) => p.id)).toEqual(['my-agents', 'incoming-contributions', 'review-queue']);
    for (const p of ref.presets) expect(p.file, p.id).toMatch(/^#:schema https:\/\/.*\n[\s\S]*version = 1/);
  });
});

describe('the version', () => {
  it('is the app\'s, and the changelog has a release', () => {
    expect(ref.version).toMatch(/^\d+\.\d+\.\d+$/);
    expect(readFileSync(new URL('../../../CHANGELOG.md', import.meta.url), 'utf8')).toContain(`## ${ref.changelog!.version} (`);
  });
});
