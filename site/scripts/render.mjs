// Shared by the image scripts: the fonts, SVG to PNG with resvg, and plain word wrapping (resvg doesn't wrap text).
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';

export const SITE = fileURLToPath(new URL('..', import.meta.url));
export const REPO = join(SITE, '..');
const CACHE = join(SITE, '.cache/fonts');

// The site's three faces, as TrueType from Google Fonts (an old user agent gets .ttf links). Cached in site/.cache.
const FONTS = 'https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&family=IBM+Plex+Serif:wght@600&family=JetBrains+Mono:wght@400';

export async function fonts() {
  await mkdir(CACHE, { recursive: true });
  const index = join(CACHE, 'fonts.css');
  if (!existsSync(index)) {
    const res = await fetch(FONTS, { headers: { 'user-agent': 'Mozilla/4.0' } });
    if (!res.ok) throw new Error(`fonts: ${res.status} from Google Fonts`);
    await writeFile(index, await res.text());
  }
  const css = await readFile(index, 'utf8');
  const files = [];
  for (const m of css.matchAll(/font-family: '([^']+)';[\s\S]*?font-weight: (\d+);[\s\S]*?url\(([^)]+\.ttf)\)/g)) {
    const file = join(CACHE, `${m[1].replace(/\s/g, '')}-${m[2]}.ttf`);
    if (!existsSync(file)) {
      const res = await fetch(m[3]);
      if (!res.ok) throw new Error(`fonts: ${res.status} for ${m[3]}`);
      await writeFile(file, Buffer.from(await res.arrayBuffer()));
    }
    files.push(file);
  }
  return files;
}

export function png(svg, fontFiles, width) {
  const r = new Resvg(svg, { font: { fontFiles, loadSystemFonts: false, defaultFontFamily: 'Geist' }, fitTo: width ? { mode: 'width', value: width } : { mode: 'original' } });
  return r.render().asPng();
}

export async function write(path, data) {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, data);
}

export const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** Splits text into lines of at most `max` characters, at spaces. */
export function wrap(text, max) {
  const lines = [];
  let cur = '';
  for (const word of text.split(/\s+/)) {
    if (cur && (cur + ' ' + word).length > max) { lines.push(cur); cur = word; } else cur = cur ? `${cur} ${word}` : word;
  }
  if (cur) lines.push(cur);
  return lines;
}

export async function logoDataUri() {
  return `data:image/png;base64,${(await readFile(join(REPO, 'assets/images/logo/shipyard.png'))).toString('base64')}`;
}
