// @vitest-environment happy-dom
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { ASK_AGENT, INSTALL, LINES } from '../messaging';
import { Switcher, cycle, variantFrom } from '../prototype/Switcher';
import { lineFrom } from './copy';
import { VARIANTS } from './variants';
import { Landing } from './Landing';

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

describe('the landing variants', () => {
  it('are three to five, each with a name', () => {
    expect(VARIANTS.length).toBeGreaterThanOrEqual(3);
    expect(VARIANTS.length).toBeLessThanOrEqual(5);
    for (const v of VARIANTS) expect(v.name).toBeTruthy();
  });

  it('each tell the whole story: the line, the panel, the install, the agent line and the way to the docs', () => {
    for (const v of VARIANTS) {
      const html = renderToStaticMarkup(<v.Component line={LINES.A} />);
      const text = html.replace(/<[^>]+>/g, '');
      expect(html, v.id).toContain(esc(LINES.A));
      expect(html, v.id).toContain('data-shot="readme-hero-dark"');
      expect(text, v.id).toContain('make install');
      expect(text, v.id).toContain(INSTALL.skill);
      expect(text, v.id).toContain(ASK_AGENT);
      expect(html, v.id).toContain('href="/docs"');
      expect(html, v.id).toContain('href="/docs#install"');
    }
  });

  it('differ in structure, not only in words', () => {
    const roots = VARIANTS.map((v) => renderToStaticMarkup(<v.Component line="x" />).match(/^<div class="land (\w+)"/)?.[1]);
    expect(new Set(roots).size).toBe(VARIANTS.length);
  });

  it('open the variant the address names, and the first otherwise', () => {
    expect(renderToStaticMarkup(<Landing search="?variant=c" />)).toContain('class="land vc"');
    expect(renderToStaticMarkup(<Landing search="?variant=Z" />)).toContain('class="land va"');
  });
});

describe('the switcher', () => {
  const ids = VARIANTS.map((v) => v.id);

  it('cycles both ways and wraps around', () => {
    expect(cycle(ids, 'A', 1)).toBe('B');
    expect(cycle(ids, 'A', -1)).toBe(ids.at(-1));
    expect(cycle(ids, ids.at(-1)!, 1)).toBe('A');
    expect(variantFrom('?variant=b', ids)).toBe('B');
  });

  it('shows the variant and its name in development, and nothing in production', () => {
    const dev = renderToStaticMarkup(<Switcher variants={VARIANTS} current="B" onChange={() => {}} production={false} />);
    expect(dev).toContain('Menu bar');
    expect(renderToStaticMarkup(<Switcher variants={VARIANTS} current="B" onChange={() => {}} production />)).toBe('');
  });

  it('lets ?line= pick a candidate one line only in development', () => {
    expect(lineFrom('?line=b', true)).toBe(LINES.B);
    expect(lineFrom('?line=b', false)).toBe(LINES.A);
  });
});
