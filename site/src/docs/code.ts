// A small highlighter for the docs' TOML, shell and JSON, as HTML with `tk-*` spans.
import type { Lang } from './content';

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const GRAMMARS: Record<Lang, RegExp | null> = {
  // comment, string, table header, key, number or boolean
  toml: /(#[^\n]*)|("(?:[^"\\\n]|\\.)*"|'[^'\n]*')|(^\s*\[\[?[^\]\n]+\]\]?)|([A-Za-z0-9_-]+(?=\s*=))|(\b\d+\b|\btrue\b|\bfalse\b)/gm,
  // comment, string, the command itself, a flag, a number
  sh: /(#[^\n]*)|("(?:[^"\\]|\\.)*"|'[^']*')|((?<=^|&& |\| )(?:shipyard|npx|herdr|git|make|curl|ntn|taplo|xattr|open|unzip|mv|rm|cd|brew|bash)\b)|((?<=\s)--?[\w-]+)|(\b\d+\b)/gm,
  // string key, string, number or literal
  json: /("(?:[^"\\]|\\.)*"(?=\s*:))|("(?:[^"\\]|\\.)*")|(\b-?\d+(?:\.\d+)?\b|\btrue\b|\bfalse\b|\bnull\b)/g,
  text: null,
};

const CLASSES: Record<Lang, string[]> = {
  toml: ['c', 's', 't', 'a', 'n'],
  sh: ['c', 's', 'k', 'a', 'n'],
  json: ['a', 's', 'n'],
  text: [],
};

export function highlight(code: string, lang: Lang): string {
  const re = GRAMMARS[lang];
  if (!re) return esc(code);
  let out = '';
  let last = 0;
  for (const m of code.matchAll(re)) {
    const [t] = m;
    if (!t) continue;
    out += esc(code.slice(last, m.index));
    const group = m.slice(1).findIndex((g) => g !== undefined && g !== '');
    const cls = CLASSES[lang][group] ?? '';
    out += cls ? `<span class="tk-${cls}">${esc(t)}</span>` : esc(t);
    last = (m.index ?? 0) + t.length;
  }
  return out + esc(code.slice(last));
}
