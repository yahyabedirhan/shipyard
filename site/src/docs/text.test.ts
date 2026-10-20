import { describe, expect, it } from 'vitest';
import { tidy, withMarkers } from './text';

const NB = ' ';

describe('tidy', () => {
  it('joins the last words of a block with no-break spaces', () => {
    expect(tidy('Each save applies at once, and a broken edit keeps the last good one.')).toBe(`Each save applies at once, and a broken edit keeps the${NB}last${NB}good${NB}one.`);
  });

  it('leaves tags and their attributes alone', () => {
    const out = tidy('Watch <a href="https://example.com/a b">every repository</a> you own.');
    expect(out).toContain('<a href="https://example.com/a b">');
    expect(out.endsWith(`repository</a>${NB}you${NB}own.`)).toBe(true);
  });

  it('counts an entity as one character', () => {
    expect(tidy('Run <code>&lt;shipyard&gt;</code> anywhere')).toBe(`Run <code>&lt;shipyard&gt;</code>${NB}anywhere`);
  });
});

describe('withMarkers', () => {
  it('glues a marker to inline code before it', () => {
    expect(withMarkers('with <code>shipyard config check</code><sup class="fn"></sup>', [5]))
      .toBe('with <span class="nw"><code>shipyard config check</code><sup class="fn" id="fnref-5"><a href="#fn-5">5</a></sup></span>');
  });

  it('numbers and links each marker, glued to the word before it', () => {
    expect(withMarkers('A word.<sup class="fn"></sup> Another.<sup class="fn"></sup>', [3, 4])).toBe(
      'A <span class="nw">word.<sup class="fn" id="fnref-3"><a href="#fn-3">3</a></sup></span> '
      + '<span class="nw">Another.<sup class="fn" id="fnref-4"><a href="#fn-4">4</a></sup></span>',
    );
  });
});
