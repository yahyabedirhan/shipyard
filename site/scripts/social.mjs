// Draws the social cards from the one line and the logo: a 1200x630 Open Graph image per page into site/public/og/,
// the 1280x640 GitHub social preview into assets/images/social/github-preview.png, and the favicons.
// Run from site/: `npm run social`. The words come from src/messaging.ts and src/pages.ts.
import { join } from 'node:path';
import { REPO, SITE, esc, fonts, logoDataUri, png, wrap, write } from './render.mjs';

const read = async (rel) => (await import('node:fs/promises')).readFile(join(SITE, rel), 'utf8');
const str = (src, name) => src.match(new RegExp(`export const ${name} = '([^']+)'`))?.[1] ?? src.match(new RegExp(`export const ${name} = "([^"]+)"`))?.[1];

const messaging = await read('src/messaging.ts');
const LINE = messaging.match(/A: '([^']+)'/)[1];
const SITE_URL = str(messaging, 'SITE_URL');
const pages = [...(await read('src/pages.ts')).matchAll(/id: '([\w-]+)'[\s\S]*?image: '([^']+)'[\s\S]*?card: '([^']*)'/g)]
  .map((m) => ({ id: m[1], image: m[2], card: m[3] }))
  .filter((p, i, all) => p.card && all.findIndex((q) => q.image === p.image) === i);

// The card's colours follow src/tokens.css.
const C = { bg: '#0b0b0d', fg: '#ecebe8', text: '#c9c8c3', mut: '#8b8a86', line: 'rgba(255,255,255,0.12)' };

function card({ w, h, logo, line, sub }) {
  const pad = Math.round(w * 0.075);
  const size = Math.round(h * 0.095);
  const lines = wrap(line, 31);
  const top = h * 0.5 - ((lines.length - 1) * size * 1.12) / 2;
  // three swells in the corner, the docs nav's mark drawn large
  const swell = (r, o) => `<path d="M${w - pad - r * 2} ${h - pad} c ${r * 0.28} ${-r * 0.76} ${r * 1.72} ${-r * 0.76} ${r * 2} 0" fill="none" stroke="${C.fg}" stroke-opacity="${o}" stroke-width="2"/>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <rect width="${w}" height="${h}" fill="${C.bg}"/>
  ${swell(h * 0.36, 0.1)}${swell(h * 0.26, 0.18)}${swell(h * 0.16, 0.3)}
  <image href="${logo}" x="${pad}" y="${pad}" width="${Math.round(h * 0.14)}" height="${Math.round(h * 0.14)}"/>
  <text x="${pad + h * 0.17}" y="${pad + h * 0.093}" font-family="Literata 72pt" font-weight="600" font-size="${Math.round(h * 0.06)}" fill="${C.fg}">shipyard</text>
  ${lines.map((l, i) => `<text x="${pad}" y="${top + i * size * 1.12}" font-family="Inter" font-weight="600" font-size="${size}" letter-spacing="-1" fill="${C.fg}">${esc(l)}</text>`).join('\n  ')}
  ${sub ? `<text x="${pad}" y="${top + lines.length * size * 1.12 + size * 0.35}" font-family="Inter" font-weight="400" font-size="${Math.round(size * 0.48)}" fill="${C.text}">${esc(sub)}</text>` : ''}
  <line x1="${pad}" y1="${h - pad - h * 0.06}" x2="${pad + h * 0.08}" y2="${h - pad - h * 0.06}" stroke="${C.line}" stroke-width="2"/>
  <text x="${pad}" y="${h - pad}" font-family="JetBrains Mono" font-size="${Math.round(h * 0.036)}" fill="${C.mut}">${esc(SITE_URL.replace('https://', ''))}</text>
</svg>`;
}

const fontFiles = await fonts();
const logo = await logoDataUri();
for (const p of pages) {
  await write(join(SITE, 'public', p.image), png(card({ w: 1200, h: 630, logo, line: LINE, sub: p.card }), fontFiles));
  console.log(`site/public/${p.image}`);
}
await write(join(REPO, 'assets/images/social/github-preview.png'), png(card({ w: 1280, h: 640, logo, line: LINE, sub: 'For macOS 14 and later. Open source.' }), fontFiles));
console.log('assets/images/social/github-preview.png');

// Favicons: the logo, drawn small.
const icon = (s) => `<svg xmlns="http://www.w3.org/2000/svg" width="${s}" height="${s}"><image href="${logo}" width="${s}" height="${s}"/></svg>`;
await write(join(SITE, 'public/favicon.png'), png(icon(64), fontFiles));
await write(join(SITE, 'public/apple-touch-icon.png'), png(icon(180), fontFiles));
console.log('site/public/favicon.png, site/public/apple-touch-icon.png');
