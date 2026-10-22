import { describe, expect, it } from 'vitest';
import { ASK_AGENT, INSTALL, LINE } from '../messaging';
import { renderPage } from '../test/render';
import { FACTS, HOW, WHAT, WHO } from './copy';
import Landing from './Landing.astro';

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

describe('the landing page', async () => {
  const html = await renderPage(Landing);
  // The text a reader sees: no tags, and no island props, which repeat the code blocks' text.
  const text = html.replace(/<astro-island\b[^>]*>/g, '').replace(/<[^>]+>/g, '');

  it('tells the whole story: the line, what, who and how, the panel, the install, the agent line and the way to the docs', () => {
    expect(html).toContain(esc(LINE));
    for (const s of [WHAT, WHO, HOW.replaceAll('`', '')]) expect(text).toContain(esc(s));
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

  it('has no prototype switcher and ignores ?variant=', async () => {
    expect(html).not.toContain('switcher');
    expect(await renderPage(Landing)).toBe(html);
  });
});
