import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import SHOTS from '../shots.json';
import { buildAgentFiles, pagePath } from '../plugins/agents';
import { REPO_DIR, SITE_DIR, referenceData } from '../plugins/repo';
import { headFor, pageForPath, sitemap } from '../plugins/site';
import { SECTIONS } from './docs/content';
import { LINE } from './messaging';
import { PAGES } from './pages';
import { routeOf } from './route';

const site = (...p: string[]) => join(SITE_DIR, ...p);

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((n) => (n === 'node_modules' || n === 'dist' || n.startsWith('.') ? [] : statSync(join(dir, n)).isDirectory() ? walk(join(dir, n)) : [join(dir, n)]));
}

describe('page heads', () => {
  const html = readFileSync(site('index.html'), 'utf8');

  it('keep titles near 60 characters and descriptions near 155', () => {
    for (const p of PAGES) {
      expect(p.title.length, p.title).toBeGreaterThanOrEqual(50);
      expect(p.title.length, p.title).toBeLessThanOrEqual(65);
      expect(p.description.length, p.description).toBeGreaterThanOrEqual(110);
      expect(p.description.length, p.description).toBeLessThanOrEqual(160);
    }
  });

  it('fill every meta tag, with a social card of 1200 by 630 that exists', () => {
    for (const p of PAGES) {
      const head = headFor(html, p);
      expect(head, p.id).not.toMatch(/content=""|href=""/);
      expect(head).toContain(`<title>${p.title.replace(/'/g, "'")}</title>`);
      const png = readFileSync(site('public', p.image));
      expect(png.readUInt32BE(16), p.image).toBe(1200);
      expect(png.readUInt32BE(20), p.image).toBe(630);
    }
  });

  it('keep the 404 page out of search', () => {
    expect(headFor(html, pageForPath('/nope'))).toContain('content="noindex"');
    expect(sitemap()).not.toContain('/404');
    expect(sitemap()).toContain('https://shipyard.yahyapak.dev/docs');
  });

  it('route each path to its page', () => {
    expect(routeOf('/')).toBe('home');
    expect(routeOf('/docs/')).toBe('docs');
    expect(routeOf('/privacy')).toBe('privacy');
    expect(routeOf('/elsewhere')).toBe('not-found');
  });

  it('use the one line from the messaging kit', () => {
    expect(LINE).toBe('A macOS menu bar app for keeping up with your projects while your agents work.');
    expect(LINE.length).toBeLessThan(80);
  });
});

describe('the GitHub social preview', () => {
  it('is 1280 by 640', () => {
    const png = readFileSync(join(REPO_DIR, 'assets/images/social/github-preview.png'));
    expect([png.readUInt32BE(16), png.readUInt32BE(20)]).toEqual([1280, 640]);
  });
});

describe('agent files', () => {
  const files = buildAgentFiles(referenceData());

  it('give every docs section its own Markdown page, listed in llms.txt', () => {
    for (const s of SECTIONS) {
      expect(files[pagePath(s)], s.id).toMatch(new RegExp(`^# ${s.title}`));
      expect(files['llms.txt']).toContain(`https://shipyard.yahyapak.dev/${pagePath(s)}`);
    }
  });

  it('hold Markdown, not the page\'s HTML', () => {
    for (const [path, body] of Object.entries(files)) expect(body, path).not.toMatch(/<(code|a |b>|p>|sup|span)/);
  });

  it('put everything in llms-full.txt', () => {
    for (const s of SECTIONS) expect(files['llms-full.txt']).toContain(`# ${s.title}`);
  });
});

describe('screenshots', () => {
  const shots = SHOTS.shots;
  const ids = new Set(shots.map((s) => s.id));

  it('each say what they show, how to capture them, and where they go', () => {
    for (const s of shots) {
      expect(s.id).toMatch(/^[a-z0-9]+(-[a-z0-9]+)*-(light|dark)$/);
      expect(['placeholder', 'done']).toContain(s.status);
      expect(['light', 'dark']).toContain(s.appearance);
      expect(s.path).toBe(`assets/screenshots/launch/${s.id}.png`);
      expect(existsSync(join(REPO_DIR, s.path)), s.path).toBe(true);
      expect(s.capture.join('\n')).toContain('shipyard app capture');
      expect(s.capture.at(-1)).toBe('shipyard lease release');
      for (const k of ['shows', 'state', 'demo', 'layout', 'size'] as const) expect(s[k], `${s.id} ${k}`).toBeTruthy();
      expect(s.usedIn.length).toBeGreaterThan(0);
    }
  });

  it('include the README hero in both appearances', () => {
    for (const ap of ['light', 'dark']) {
      const s = shots.find((x) => x.id === `readme-hero-${ap}`);
      expect(s?.usedIn).toContain('README.md');
      expect(s?.layout).toBe('tabs');
    }
  });

  it('cover every id the pages use', () => {
    const used = [
      ...SECTIONS.flatMap((s) => s.shots ?? []),
      ...referenceData().presets.map((p) => `preset-${p.id}-dark`),
      ...walk(site('src')).flatMap((f) => [...readFileSync(f, 'utf8').matchAll(/SHOT:([a-z0-9-]+)|<Shot id="([a-z0-9-]+)"/g)].map((m) => m[1] ?? m[2])),
    ];
    expect(used.length).toBeGreaterThan(10);
    for (const id of used) expect(ids, id).toContain(id);
  });
});

describe('what the site never holds', () => {
  const files = [...walk(site('src')), ...walk(site('plugins')), ...walk(site('scripts')), ...walk(site('public')).filter((f) => !f.endsWith('.png')), site('shots.json'), site('PRIVACY.md'), site('index.html'), site('wrangler.jsonc'), site('worker/index.js')];

  it('has no private paths, machine labels or the lab', () => {
    const banned = [/\/Users\/[a-z]/i, /\/home\/user/, /hetzner/i, /netcup/i, /\blab\//, /LAB_CLI/, /Swift Lab/i, /Developer\/open-source/];
    for (const f of files) {
      if (f.endsWith('site.test.ts')) continue;
      const text = readFileSync(f, 'utf8');
      for (const b of banned) expect(text.match(b)?.[0], `${f} ${b}`).toBeUndefined();
    }
  });

  it('has no em dashes in its prose', () => {
    for (const f of [site('src/docs/content.ts'), site('src/messaging.ts'), site('src/pages.ts'), site('PRIVACY.md'), site('shots.json')]) {
      expect(readFileSync(f, 'utf8').includes('—'), f).toBe(false);
    }
  });

  it('keeps every colour and size in tokens.css', () => {
    for (const f of walk(site('src')).filter((p) => p.endsWith('.css') && !p.endsWith('tokens.css'))) {
      const css = readFileSync(f, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/@media[^{]*\{/g, '{');
      expect(css.match(/#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(|\d*\.?\d+px/g), f).toBeNull();
    }
  });
});
