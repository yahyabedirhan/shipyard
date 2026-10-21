import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { openPlaceholders } from './placeholders.mjs';

function fixture() {
  const repo = mkdtempSync(join(tmpdir(), 'placeholders-'));
  const site = join(repo, 'site');
  mkdirSync(join(site, 'src'), { recursive: true });
  const shot = (id, status) => ({ id, shows: `the ${id} view`, path: `assets/${id}.png`, status });
  writeFileSync(join(site, 'shots.json'), JSON.stringify({ shots: [shot('open-shot', 'placeholder'), shot('done-shot', 'done')] }));
  writeFileSync(join(site, 'src', 'messaging.ts'), '// PLACEHOLDER: replace this line\n');
  writeFileSync(join(repo, 'README.md'), '<!-- SHOT:open-shot -->\n<!-- SHOT:done-shot -->\n<!-- SHOT:missing-shot -->\n');
  return { site, repo };
}

describe('npm run placeholders', () => {
  const open = openPlaceholders(fixture());

  it('lists the screenshots still marked placeholder', () => {
    expect(open.some((o) => o.kind === 'shot' && o.what.startsWith('open-shot:'))).toBe(true);
    expect(open.some((o) => o.kind === 'shot' && o.what.startsWith('done-shot:'))).toBe(false);
  });

  it('lists PLACEHOLDER: markers with their file and line', () => {
    expect(open.some((o) => o.kind === 'marker' && o.where === 'site/src/messaging.ts:1')).toBe(true);
  });

  it('lists SHOT: markers whose shot is not done or not in shots.json', () => {
    const what = open.filter((o) => o.kind === 'marker').map((o) => o.what);
    expect(what).toContain('SHOT:open-shot is still a placeholder');
    expect(what).toContain('SHOT:missing-shot is not in shots.json');
    expect(what.some((w) => w.includes('done-shot'))).toBe(false);
  });
});
