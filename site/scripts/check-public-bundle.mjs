// A build without VITE_POSTHOG_KEY or VITE_SENTRY_DSN must not contain those clients, and a build with them must
// load each one lazily, in a chunk no page loads up front. Every page must be whole HTML, so it reads with JavaScript
// off. Run after `astro build`, from site/. It prints the JavaScript each page loads up front and in all.
import { readdir, readFile, stat } from 'node:fs/promises';
import { dirname, join, relative } from 'node:path';

const dist = new URL('../dist/', import.meta.url).pathname;
// Each vendor's words must appear only in that vendor's own code. posthog-js mentions Sentry, so the Sentry words
// are the SDK's package names and its global carrier object.
const vendors = { posthog: ['posthog', 'i.posthog.com'], sentry: ['@sentry/', '__SENTRY__'] };
// Words each page's HTML must hold without running any script.
const pages = {
  'index.html': ['A macOS menu bar app for keeping up with your projects while your agents work.', 'Read the docs'],
  'docs.html': ['What it is', 'data-key="menu.layout"'],
  'privacy.html': ['Privacy', 'Send nothing'],
  '404.html': ['No page here'],
};

async function files(dir) {
  const out = [];
  for (const name of await readdir(dir)) {
    const path = join(dir, name);
    if ((await stat(path)).isDirectory()) out.push(...await files(path));
    else out.push(path);
  }
  return out;
}

const all = await files(dist);
const scripts = all.filter((p) => p.endsWith('.js'));
const text = Object.fromEntries(await Promise.all(scripts.map(async (p) => [p, await readFile(p, 'utf8')])));

/** Every script reachable from `entries` through the imports `pattern` finds. */
function reach(entries, pattern) {
  const seen = new Set();
  const visit = (p) => {
    if (seen.has(p) || !text[p]) return;
    seen.add(p);
    for (const m of text[p].matchAll(pattern)) visit(join(dirname(p), m[1]));
  };
  entries.forEach(visit);
  return seen;
}
// Static imports load up front; any quoted relative script, dynamic imports included, may load later.
const STATIC = /(?:\bfrom|\bimport)\s*["'`](\.{1,2}\/[^"'`]+\.js)["'`]/g;
const ANY = /["'`](\.{1,2}\/[^"'`]+\.js)["'`]/g;

/** The scripts a page runs on load (`<script>` tags and their inline imports), and the ones its islands hydrate with. */
function pageEntries(html) {
  const abs = (refs) => [...new Set(refs)].map((r) => join(dist, r));
  const islands = [...html.matchAll(/(?:component-url|renderer-url|before-hydration-url)="(\/[^"]+\.js)"/g)].map((m) => m[1]);
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].flatMap((m) => [
    ...[...m[0].matchAll(/^<script\b[^>]*\bsrc="(\/[^"]+\.js)"/g)].map((x) => x[1]),
    ...[...m[1].matchAll(/["'`](\/_astro\/[^"'`]+\.js)["'`]/g)].map((x) => x[1]),
  ]);
  return { scripts: abs(scripts), islands: abs(islands) };
}

const leaks = [];
const eager = new Set();
const kb = (n) => `${(n / 1024).toFixed(1)} KB`;
const size = async (set) => (await Promise.all([...set].map(async (p) => (await stat(p)).size))).reduce((a, b) => a + b, 0);
for (const [page, words] of Object.entries(pages)) {
  const path = join(dist, page);
  if (!all.includes(path)) continue;
  const html = await readFile(path, 'utf8');
  for (const w of words) if (!html.includes(w)) leaks.push(`${page} has no "${w}" in its HTML`);
  const { scripts: run, islands } = pageEntries(html);
  const onLoad = reach(run, STATIC);
  const hydrate = new Set([...reach(islands, STATIC)].filter((p) => !onLoad.has(p)));
  const later = new Set([...reach([...run, ...islands], ANY)].filter((p) => !onLoad.has(p) && !hydrate.has(p)));
  [...onLoad, ...hydrate].forEach((p) => eager.add(p));
  console.log(`${page}: JavaScript ${kb(await size(onLoad))} on load, ${kb(await size(hydrate))} more for its islands, ${kb(await size(later))} more only when analytics load`);
}

const allowed = { posthog: Boolean(process.env.VITE_POSTHOG_KEY), sentry: Boolean(process.env.VITE_SENTRY_DSN) };
for (const path of scripts) {
  for (const [name, words] of Object.entries(vendors)) {
    if (!words.some((w) => text[path].includes(w))) continue;
    if (!allowed[name]) leaks.push(`${relative(dist, path)}: ${name} without its build key`);
    else if (eager.has(path) && text[path].includes(name === 'posthog' ? 'i.posthog.com/static' : 'sentry.io/api')) leaks.push(`${relative(dist, path)}: ${name} client loaded up front`);
  }
}
for (const need of ['index.html', 'docs.html', 'privacy.html', '404.html', 'llms.txt', 'llms-full.txt', 'sitemap.xml', 'robots.txt', 'docs/configuration.md', 'og/home.png', 'favicon.png']) {
  if (!all.includes(join(dist, need))) leaks.push(`dist has no ${need}`);
}
if (leaks.length) {
  console.error('the public build is not as it must be:');
  for (const line of leaks) console.error(`  ${line}`);
  process.exit(1);
}
console.log(`analytics clients: posthog ${allowed.posthog ? 'lazy' : 'off'}, sentry ${allowed.sentry ? 'lazy' : 'off'}`);
