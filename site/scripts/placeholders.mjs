// Lists every open placeholder before a launch: screenshots in shots.json still marked placeholder, analytics keys
// not set for the build, and every PLACEHOLDER: or SHOT:<id> marker in the site's sources, README.md and docs/.
// `npm run placeholders` prints the list; `npm run placeholders -- --check` also exits 1 while any is open.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const SITE = fileURLToPath(new URL('..', import.meta.url));
const REPO = join(SITE, '..');

/** The analytics keys a production build reads. Unset, the build sends nothing. */
export const KEYS = ['VITE_POSTHOG_KEY', 'VITE_SENTRY_DSN'];

function walk(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).flatMap((name) => {
    if (name === 'node_modules' || name === 'dist' || name.startsWith('.')) return [];
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
}

/** The files the markers are looked for in. The scripts themselves name the markers, so they're left out. */
export function sources(site = SITE, repo = REPO) {
  return [
    ...walk(join(site, 'src')),
    ...['index.html', 'PRIVACY.md', 'wrangler.jsonc', '.env.example'].map((f) => join(site, f)).filter(existsSync),
    join(repo, 'README.md'),
    ...walk(join(repo, 'docs')).filter((p) => p.endsWith('.md')),
  ].filter((p) => /\.(tsx?|css|html|md|jsonc|example)$/.test(p) && !/\.test\.tsx?$/.test(p));
}

/** Keys set in the environment or in one of the site's env files. */
function setKeys(site = SITE) {
  const set = new Set(KEYS.filter((k) => process.env[k]));
  for (const f of ['.env', '.env.local', '.env.production', '.env.production.local']) {
    const p = join(site, f);
    if (!existsSync(p)) continue;
    for (const m of readFileSync(p, 'utf8').matchAll(/^(VITE_[A-Z_]+)=(.+)$/gm)) if (m[2].trim()) set.add(m[1]);
  }
  return set;
}

/** Every open placeholder, each as { kind, where, what }. */
export function openPlaceholders({ site = SITE, repo = REPO } = {}) {
  const { shots } = JSON.parse(readFileSync(join(site, 'shots.json'), 'utf8'));
  const status = Object.fromEntries(shots.map((s) => [s.id, s.status]));
  const out = shots.filter((s) => s.status !== 'done').map((s) => ({ kind: 'shot', where: s.path, what: `${s.id}: ${s.shows}` }));
  const keys = setKeys(site);
  for (const k of KEYS) if (!keys.has(k)) out.push({ kind: 'key', where: 'build environment', what: `${k} is not set` });
  for (const file of sources(site, repo)) {
    const lines = readFileSync(file, 'utf8').split('\n');
    lines.forEach((line, i) => {
      const where = `${relative(repo, file)}:${i + 1}`;
      const p = line.match(/PLACEHOLDER:\s*(.*?)(?:\s*-->|\s*\*\/)?\s*$/);
      if (p) out.push({ kind: 'marker', where, what: p[1] || 'PLACEHOLDER' });
      for (const m of line.matchAll(/SHOT:([a-z0-9-]+)/g)) {
        if (status[m[1]] === 'done') continue;
        out.push({ kind: 'marker', where, what: status[m[1]] ? `SHOT:${m[1]} is still a placeholder` : `SHOT:${m[1]} is not in shots.json` });
      }
    });
  }
  return out;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const open = openPlaceholders();
  const titles = { shot: 'Screenshots still to capture', key: 'Analytics keys not set', marker: 'Markers in the sources' };
  for (const kind of ['shot', 'key', 'marker']) {
    const rows = open.filter((o) => o.kind === kind);
    if (!rows.length) continue;
    console.log(`${titles[kind]} (${rows.length}):`);
    for (const r of rows) console.log(`  ${r.where}  ${r.what}`);
    console.log('');
  }
  console.log(open.length ? `${open.length} open placeholders.` : 'No open placeholders.');
  if (process.argv.includes('--check') && open.length) process.exit(1);
}
