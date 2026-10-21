// Small converters between the site's two text forms: the repository's Markdown (PRIVACY.md) shown as HTML, and the
// docs' HTML prose written out as Markdown for llms.txt and /docs/*.md. Both cover only what these files use.
import { cells, inlineMd } from './parse';

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** Block Markdown (headings, paragraphs, lists, tables, fenced code) as HTML. */
export function blockMd(md: string): string {
  const lines = md.split('\n');
  const out: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line.trim()) continue;
    const h = line.match(/^(#{1,3}) (.*)$/);
    if (h) { out.push(`<h${h[1].length}>${inlineMd(h[2])}</h${h[1].length}>`); continue; }
    if (line.startsWith('```')) {
      const body: string[] = [];
      for (i++; i < lines.length && !lines[i].startsWith('```'); i++) body.push(lines[i]);
      out.push(`<pre><code>${esc(body.join('\n'))}</code></pre>`);
      continue;
    }
    if (line.startsWith('|')) {
      const rows: string[][] = [];
      for (; i < lines.length && lines[i].startsWith('|'); i++) if (!/^\|[\s|:-]+\|$/.test(lines[i].trim())) rows.push(cells(lines[i]));
      i--;
      const [head, ...body] = rows;
      out.push(`<div class="tbl-wrap"><table class="tbl"><thead><tr>${head.map((c) => `<th>${inlineMd(c)}</th>`).join('')}</tr></thead><tbody>${body.map((r) => `<tr>${r.map((c) => `<td>${inlineMd(c)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`);
      continue;
    }
    if (/^- /.test(line)) {
      const items: string[] = [];
      for (; i < lines.length && /^- /.test(lines[i]); i++) items.push(`<li>${inlineMd(lines[i].slice(2))}</li>`);
      i--;
      out.push(`<ul>${items.join('')}</ul>`);
      continue;
    }
    const para: string[] = [line];
    while (i + 1 < lines.length && lines[i + 1].trim() && !/^(#|- |\||```)/.test(lines[i + 1])) para.push(lines[++i]);
    out.push(`<p>${inlineMd(para.join(' '))}</p>`);
  }
  return out.join('\n');
}

const ENTITIES: Record<string, string> = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&nbsp;': ' ' };

/** The docs' inline HTML as Markdown: code, bold, links and paragraphs; note markers are dropped. */
export function htmlToMd(html: string, site = ''): string {
  return html
    .replace(/<sup class="fn"><\/sup>/g, '')
    .replace(/<code>([\s\S]*?)<\/code>/g, (_, c: string) => `\`${c}\``)
    .replace(/<b>([\s\S]*?)<\/b>/g, '**$1**')
    .replace(/<a href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g, (_, href: string, text: string) => `[${text}](${href.startsWith('#') ? `${site}/docs${href}` : href.startsWith('/') ? `${site}${href}` : href})`)
    .replace(/<span class="wm-inline">([\s\S]*?)<\/span>/g, '$1')
    .replace(/<\/p>\s*<p>/g, '\n\n')
    .replace(/<\/?p>/g, '')
    .replace(/<[^>]+>/g, '')
    .replace(/&[#\w]+;/g, (e) => ENTITIES[e] ?? e)
    .replace(/ /g, ' ')
    .trim();
}
