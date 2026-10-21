// @vitest-environment happy-dom
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { ASK_AGENT, INSTALL, LINE } from '../messaging';
import { FACTS, HOW, WHAT, WHO } from './copy';
import { Landing } from './Landing';

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

describe('the landing page', () => {
  const html = renderToStaticMarkup(<Landing />);
  const text = html.replace(/<[^>]+>/g, '');

  it('tells the whole story: the line, what, who and how, the panel, the install, the agent line and the way to the docs', () => {
    expect(html).toContain(esc(LINE));
    for (const s of [WHAT, WHO, HOW]) expect(text).toContain(esc(s));
    expect(html).toContain('data-shot="landing-tabs-dark"');
    expect(html).toContain('data-shot="landing-list-light"');
    expect(html).not.toContain('<figcaption');
    expect(text).toContain('make install');
    expect(text).toContain(INSTALL.skill);
    expect(text).toContain(ASK_AGENT);
    expect(html).toContain('href="/docs"');
    expect(html).toContain('href="/docs#install"');
  });

  it('shows every fact and has one heading level one', () => {
    for (const [k] of FACTS) expect(text).toContain(k);
    expect(html.match(/<h1[ >]/g)).toHaveLength(1);
  });

  it('has no prototype switcher and ignores ?variant=', () => {
    expect(html).not.toContain('switcher');
    expect(renderToStaticMarkup(<Landing />)).toBe(html);
  });
});
