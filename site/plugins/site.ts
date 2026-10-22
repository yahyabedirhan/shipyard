// The site's Astro integration. It serves the generated reference to the pages as a virtual module, and emits what a
// static host needs beside the pages: the agent files, the sitemap and the finished screenshots. In development it
// serves the same files from memory. The pages themselves, and each page's head, are src/pages/ and src/layouts/.
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { AstroIntegration } from 'astro';
import type { Plugin } from 'vite';
import { PAGES, absolute } from '../src/meta';
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

export function sitemap(): string {
  const urls = PAGES.filter((p) => p.listed).map((p) => absolute(p.path));
  const extra = ['/llms.txt', '/llms-full.txt'].map(absolute);
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${[...urls, ...extra].map((u) => `  <url><loc>${u}</loc></url>`).join('\n')}\n</urlset>\n`;
}

/** Every generated text file, by its path in the build. */
export function generatedFiles(): Record<string, string> {
  return { ...buildAgentFiles(referenceData()), 'sitemap.xml': sitemap() };
}

/** The screenshots listed in shots.json, by file name. */
function shotFiles(): string[] {
  const listed = new Set((JSON.parse(readFileSync(`${SITE_DIR}shots.json`, 'utf8')).shots as { id: string }[]).map((s) => `${s.id}.png`));
  return existsSync(SHOTS_DIR) ? readdirSync(SHOTS_DIR).filter((f) => listed.has(f)) : [];
}

/** The virtual modules: the generated reference and site/PRIVACY.md as HTML. */
export function referenceModules(): Plugin {
  return {
    name: 'shipyard-reference',
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
  };
}

export function siteIntegration(): AstroIntegration {
  return {
    name: 'shipyard-site',
    hooks: {
      'astro:config:setup': ({ updateConfig }) => {
        updateConfig({ vite: { plugins: [referenceModules()] } });
      },
      'astro:server:setup': ({ server }) => {
        server.watcher.add(SOURCES);
        server.watcher.on('change', (file) => {
          if (!SOURCES.some((s) => file.startsWith(s))) return;
          for (const env of Object.values(server.environments)) {
            for (const id of [`\0${REFERENCE}`, `\0${PRIVACY}`]) {
              const mod = env.moduleGraph.getModuleById(id);
              if (mod) env.moduleGraph.invalidateModule(mod);
            }
          }
          server.ws.send({ type: 'full-reload' });
        });
        server.middlewares.use((req, res, next) => {
          const path = (req.url ?? '').split('?')[0].replace(/^\//, '');
          if (path.startsWith('shots/') && existsSync(`${SHOTS_DIR}/${path.slice(6)}`)) {
            res.setHeader('content-type', 'image/png');
            res.end(readFileSync(`${SHOTS_DIR}/${path.slice(6)}`));
            return;
          }
          const body = generatedFiles()[path];
          if (body === undefined) { next(); return; }
          res.setHeader('content-type', `${path.endsWith('.md') ? 'text/markdown' : path.endsWith('.xml') ? 'application/xml' : 'text/plain'}; charset=utf-8`);
          res.end(body);
        });
      },
      'astro:build:done': ({ dir }) => {
        const out = fileURLToPath(dir);
        const write = (name: string, body: string | Buffer) => {
          mkdirSync(dirname(join(out, name)), { recursive: true });
          writeFileSync(join(out, name), body);
        };
        for (const [name, body] of Object.entries(generatedFiles())) write(name, body);
        for (const f of shotFiles()) write(`shots/${f}`, readFileSync(`${SHOTS_DIR}/${f}`));
      },
    },
  };
}
