// Draws `shipyard --help` as a dark terminal window for the docs' Command section, at
// assets/screenshots/launch/cli-help-dark.png. It runs the installed command, so retake it after a release.
// Run from site/: `npm run terminal`.
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
import { REPO, esc, fonts, png, write } from './render.mjs';

const BIN = process.env.SHIPYARD_BIN ?? '/Applications/Shipyard.app/Contents/Helpers/shipyard';
const lines = ['$ shipyard --help', ...execFileSync(BIN, ['--help'], { encoding: 'utf8' }).trimEnd().split('\n')];

// The window's colours follow src/tokens.css.
const C = { bg: '#131316', bar: '#1c1c20', fg: '#ecebe8', mut: '#8b8a86', line: 'rgba(255,255,255,0.08)' };
const size = 13, lead = 20, pad = 24, bar = 36;
const w = 860, h = bar + pad * 2 + lines.length * lead;
const dot = (x, c) => `<circle cx="${x}" cy="${bar / 2}" r="6" fill="${c}"/>`;
const text = lines.map((l, i) => {
  const fill = i === 0 ? C.mut : /^\S.*:$/.test(l) ? C.fg : C.fg;
  return `<text x="${pad}" y="${bar + pad + (i + 0.75) * lead}" font-family="JetBrains Mono" font-size="${size}" fill="${fill}" xml:space="preserve">${esc(l)}</text>`;
}).join('\n  ');
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <rect width="${w}" height="${h}" rx="12" fill="${C.bg}"/>
  <path d="M0 12a12 12 0 0 1 12-12h${w - 24}a12 12 0 0 1 12 12v${bar - 12}h-${w}z" fill="${C.bar}"/>
  <line x1="0" y1="${bar}" x2="${w}" y2="${bar}" stroke="${C.line}"/>
  ${dot(20, '#ff5f57')}${dot(40, '#febc2e')}${dot(60, '#28c840')}
  ${text}
</svg>`;

const out = join(REPO, 'assets/screenshots/launch/cli-help-dark.png');
await write(out, png(svg, await fonts(), w * 2));
console.log(out.replace(REPO + '/', ''));
