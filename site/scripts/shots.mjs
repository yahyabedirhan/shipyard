// Writes a placeholder PNG at the final path of every screenshot in shots.json still marked placeholder, with its id
// and what it must show drawn on it, so the README and the site have a file at each path until the real capture
// replaces it. A shot marked done is never touched. Run from site/: `npm run shots`.
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { REPO, SITE, esc, fonts, png, wrap, write } from './render.mjs';

const { shots } = JSON.parse(await readFile(join(SITE, 'shots.json'), 'utf8'));

/** The placeholder's size: about what the capture will be, so layouts that use it keep their shape. */
const sizeOf = (s) => (s.id.startsWith('readme-hero') ? [1600, 1040] : s.id === 'menu-bar-icon-dark' ? [480, 120] : [840, 1120]);

function placeholder(s, [w, h]) {
  const light = s.appearance === 'light';
  const bg = light ? '#f4f3ef' : '#131316';
  const fg = light ? '#1c1c1f' : '#ecebe8';
  const mut = light ? '#6b6a66' : '#8b8a86';
  const stripe = light ? 'rgba(0,0,0,0.035)' : 'rgba(255,255,255,0.03)';
  if (h < 200) {
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><rect width="${w}" height="${h}" rx="16" fill="${bg}"/><text x="24" y="${h / 2 + 8}" font-family="JetBrains Mono" font-size="22" fill="${fg}">SHOT:${esc(s.id)}</text></svg>`;
  }
  const pad = Math.round(w * 0.08);
  const size = Math.round(w * 0.034);
  const lines = wrap(s.shows, Math.floor((w - pad * 2) / (size * 0.52)));
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <defs><pattern id="p" width="16" height="16" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="2" height="16" fill="${stripe}"/></pattern></defs>
  <rect width="${w}" height="${h}" rx="28" fill="${bg}"/><rect width="${w}" height="${h}" rx="28" fill="url(#p)"/>
  <rect x="1" y="1" width="${w - 2}" height="${h - 2}" rx="27" fill="none" stroke="${mut}" stroke-opacity="0.4" stroke-width="2" stroke-dasharray="10 8"/>
  <text x="${pad}" y="${h * 0.38}" font-family="Geist" font-weight="600" font-size="${Math.round(size * 0.62)}" letter-spacing="2" fill="${mut}">SCREENSHOT TO COME · ${esc(s.appearance.toUpperCase())} · ${esc(s.layout.toUpperCase())}</text>
  ${lines.map((l, i) => `<text x="${pad}" y="${h * 0.38 + size * 1.9 + i * size * 1.35}" font-family="Geist" font-weight="500" font-size="${size}" fill="${fg}">${esc(l)}</text>`).join('\n  ')}
  <text x="${pad}" y="${h * 0.38 + size * 2.6 + lines.length * size * 1.35}" font-family="JetBrains Mono" font-size="${Math.round(size * 0.7)}" fill="${mut}">SHOT:${esc(s.id)}</text>
</svg>`;
}

const fontFiles = await fonts();
let n = 0;
for (const s of shots) {
  if (s.status !== 'placeholder') continue;
  await write(join(REPO, s.path), png(placeholder(s, sizeOf(s)), fontFiles));
  n++;
}
console.log(`${n} placeholder screenshots written under assets/screenshots/launch/`);
