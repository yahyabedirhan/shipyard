// A build without VITE_POSTHOG_KEY or VITE_SENTRY_DSN must not contain those clients, and a build with them must
// load each one lazily, in its own chunk. Run after `vite build`, from site/.
import { readdir, readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';

const dist = new URL('../dist/', import.meta.url).pathname;
// Each vendor's words must appear only in that vendor's own code. posthog-js mentions Sentry, so the Sentry words
// are the SDK's package names and its global carrier object.
const vendors = { posthog: ['posthog', 'i.posthog.com'], sentry: ['@sentry/', '__SENTRY__'] };

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
const main = all.find((p) => /\/assets\/index-.*\.js$/.test(p));
if (!main) { console.error('no index bundle in dist'); process.exit(1); }
console.log(`main bundle ${main.split('/').pop()} ${(await stat(main)).size} bytes`);

const allowed = { posthog: Boolean(process.env.VITE_POSTHOG_KEY), sentry: Boolean(process.env.VITE_SENTRY_DSN) };
const leaks = [];
for (const path of all.filter((p) => p.endsWith('.js'))) {
  const text = await readFile(path, 'utf8');
  for (const [name, words] of Object.entries(vendors)) {
    if (!words.some((w) => text.includes(w))) continue;
    if (!allowed[name]) leaks.push(`${path}: ${name} without its build key`);
    else if (path === main && text.includes(name === 'posthog' ? 'i.posthog.com/static' : 'sentry.io/api')) leaks.push(`${path}: ${name} client in the main bundle`);
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
