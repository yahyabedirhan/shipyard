// Text helpers for the docs page's prose, which is written as small pieces of HTML.

const NBSP = ' ';

/**
 * Keeps a block of text from ending on a lone word or a tiny line: the spaces in its last 16 or so visible
 * characters become no-break spaces. Tags and entities are left alone, and an entity counts as one character.
 * `text-wrap: pretty` does the rest where the browser has it.
 */
export function tidy(html: string): string {
  const parts = html.split(/(<[^>]*>)/);
  let tail = 0;
  let joined = 0;
  for (let i = parts.length - 1; i >= 0 && tail < 18; i--) {
    if (parts[i].startsWith('<')) continue;
    const chars = parts[i].match(/&[#\w]+;|[\s\S]/g) ?? [];
    let stop = false;
    for (let j = chars.length - 1; j >= 0 && tail < 18; j--) {
      if (chars[j] === ' ' && tail > 0) {
        if (tail >= 16 && joined) { stop = true; break; }
        chars[j] = NBSP;
        joined++;
      }
      tail++;
    }
    parts[i] = chars.join('');
    if (stop) break;
  }
  return parts.join('');
}

/** `tidy` for each paragraph of a body, and for the whole when it has no paragraphs. */
export function tidyParagraphs(html: string): string {
  return /<p>/.test(html) ? html.replace(/<p>([\s\S]*?)<\/p>/g, (_, inner: string) => `<p>${tidy(inner)}</p>`) : tidy(html);
}

/**
 * Numbers a section's note markers, `<sup class="fn"></sup>`, with the page-wide numbers given, and links each to
 * its note. The marker stays glued to the word before it, so it never wraps onto a line of its own.
 */
export function withMarkers(body: string, numbers: number[]): string {
  let i = 0;
  return body.replace(/(<code>[^<]*<\/code>|[^\s<>]*)<sup class="fn"><\/sup>/g, (_, word: string) => {
    const n = numbers[i++];
    return n ? `<span class="nw">${word}<sup class="fn" id="fnref-${n}"><a href="#fn-${n}">${n}</a></sup></span>` : word;
  });
}
