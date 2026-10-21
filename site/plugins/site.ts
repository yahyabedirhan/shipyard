// The site's Vite plugin. It serves the generated reference to the page as a virtual module, writes each page's HTML
// head, and emits what a static host needs beside the bundle: docs.html, privacy.html and 404.html, the agent files,
// the sitemap and the finished screenshots. In development it serves the same files from memory.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import type { Plugin, ViteDevServer } from 'vite';
import { PAGES, absolute, type PageMeta } from '../src/pages';
import { blockMd } from '../src/reference/markdown';
import { buildAgentFiles } from './agents';
import { SITE_DIR, referenceData, repoPath } from './repo';

const REFERENCE = 'virtual:shipyard-reference';
const PRIVACY = 'virtual:shipyard-privacy';
const SHOTS_DIR = repoPath('assets/screenshots/launch');

/** The repository files the generated parts read; a change to one reloads the page in development. */
export const SOURCES = [
  repoPath('schema/config.schema.json'), repoPath('schema/cli.schema.json'), repoPath('skills/shipyard/SKILL.md'),
  repoPath('skills/shipyard/presets.md'), repoPath('skills/shipyard/references/notices.md'), repoPath('CHANGELOG.md'),
  repoPath('Sources'), `${SITE_DIR}PRIVACY.md`,
];

const attr = (text: string) => text.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');

/** The site's index.html with the head of `page`: title, description, canonical address and social card. */
export function headFor(html: string, page: PageMeta): string {
  const url = absolute(page.path === '/' ? '/' : page.path);
  const image = absolute(page.image);
  const meta = (key: 'name' | 'property', name: string, content: string) => (h: string) =>
    h.replace(new RegExp(`(<meta ${key}="${name}" content=")[^"]*(")`), `$1${attr(content)}$2`);
  const steps = [
    (h: string) => h.replace(/<title>[^<]*<\/title>/, `<title>${attr(page.title)}</title>`),
    meta('name', 'description', page.description),
    meta('property', 'og:title', page.title),
    meta('property', 'og:description', page.description),
    meta('property', 'og:url', url),
    meta('property', 'og:image', image),
    meta('property', 'og:image:alt', page.imageAlt),
    meta('name', 'twitter:title', page.title),
    meta('name', 'twitter:description', page.description),
    meta('name', 'twitter:image', image),
    meta('name', 'twitter:image:alt', page.imageAlt),
    (h: string) => h.replace(/(<link rel="canonical" href=")[^"]*(")/, `$1${url}$2`),
    (h: string) => (page.listed ? h : h.replace('<meta name="robots" content="index, follow" />', '<meta name="robots" content="noindex" />')),
  ];
  return steps.reduce((h, step) => step(h), html);
}

/** The page a request path is, for the head in development. */
export function pageForPath(path: string): PageMeta {
  const p = path.replace(/\/+$/, '') || '/';
  return PAGES.find((x) => x.path === p) ?? PAGES.find((x) => x.id === 'not-found')!;
}

export function sitemap(): string {
  const urls = PAGES.filter((p) => p.listed).map((p) => absolute(p.path));
  const extra = ['/llms.txt', '/llms-full.txt'].map(absolute);
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${[...urls, ...extra].map((u) => `  <url><loc>${u}</loc></url>`).join('\n')}\n</urlset>\n`;
}

/** Every generated text file, by its path in the build. */
export function generatedFiles(): Record<string, string> {
  return { ...buildAgentFiles(referenceData()), 'sitemap.xml': sitemap() };
}

/** The finished screenshots: a shot still marked placeholder shows its frame on the page, not its PNG. */
function shotFiles(): string[] {
  const done = new Set((JSON.parse(readFileSync(`${SITE_DIR}shots.json`, 'utf8')).shots as { id: string; status: string }[]).filter((s) => s.status === 'done').map((s) => `${s.id}.png`));
  return existsSync(SHOTS_DIR) ? readdirSync(SHOTS_DIR).filter((f) => done.has(f)) : [];
}

export function sitePlugin(): Plugin {
  let server: ViteDevServer | undefined;
  return {
    name: 'shipyard-site',
    enforce: 'post',
    resolveId(id) {
      if (id === REFERENCE || id === PRIVACY) return `\0${id}`;
      return null;
    },
    load(id) {
      if (id === `\0${REFERENCE}`) return `export default ${JSON.stringify(referenceData())};`;
      if (id === `\0${PRIVACY}`) {
        const md = readFileSync(`${SITE_DIR}PRIVACY.md`, 'utf8').replace(/^# .*\n/, '');
        return `export default ${JSON.stringify(blockMd(md))};`;
      }
      return null;
    },
    transformIndexHtml: {
      order: 'post',
      handler(html, ctx) {
        if (!server) return html;
        return headFor(html, pageForPath((ctx.originalUrl ?? ctx.path).split(/[?#]/)[0]));
      },
    },
    configureServer(dev) {
      server = dev;
      dev.watcher.add(SOURCES);
      dev.watcher.on('change', (file) => {
        if (!SOURCES.some((s) => file.startsWith(s))) return;
        for (const id of [`\0${REFERENCE}`, `\0${PRIVACY}`]) {
          const mod = dev.moduleGraph.getModuleById(id);
          if (mod) dev.moduleGraph.invalidateModule(mod);
        }
        dev.ws.send({ type: 'full-reload' });
      });
      dev.middlewares.use((req, res, next) => {
        const path = (req.url ?? '').split('?')[0].replace(/^\//, '');
        if (path.startsWith('shots/') && existsSync(`${SHOTS_DIR}/${path.slice(6)}`)) {
          res.setHeader('content-type', 'image/png');
          res.end(readFileSync(`${SHOTS_DIR}/${path.slice(6)}`));
          return;
        }
        // Without this, Vite would answer /docs with nothing and /privacy with a 404.
        if (path === 'docs' || path === 'docs/' || path === 'privacy' || path === 'privacy/') { req.url = '/index.html'; next(); return; }
        const body = generatedFiles()[path];
        if (body === undefined) { next(); return; }
        res.setHeader('content-type', `${path.endsWith('.md') ? 'text/markdown' : path.endsWith('.xml') ? 'application/xml' : 'text/plain'}; charset=utf-8`);
        res.end(body);
      });
    },
    generateBundle(_options, bundle) {
      for (const [fileName, source] of Object.entries(generatedFiles())) this.emitFile({ type: 'asset', fileName, source });
      const index = bundle['index.html'];
      if (index?.type !== 'asset') throw new Error('shipyard-site: no index.html in the bundle to make the pages from');
      const html = String(index.source);
      for (const page of PAGES) {
        const source = headFor(html, page);
        if (page.file === 'index.html') index.source = source;
        else this.emitFile({ type: 'asset', fileName: page.file, source });
      }
      for (const f of shotFiles()) this.emitFile({ type: 'asset', fileName: `shots/${f}`, source: readFileSync(`${SHOTS_DIR}/${f}`) });
    },
  };
}
