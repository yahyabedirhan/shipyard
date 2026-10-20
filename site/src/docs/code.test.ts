import { describe, expect, it } from 'vitest';
import { highlight } from './code';

describe('highlight', () => {
  it('escapes HTML in every language', () => {
    expect(highlight('<b>', 'text')).toBe('&lt;b&gt;');
    expect(highlight('shipyard ping send "<title>"', 'sh')).toContain('&lt;title&gt;');
  });

  it('marks TOML tables, keys, strings and comments', () => {
    const out = highlight('# a comment\n[menu]\nlayout = "tabs"', 'toml');
    expect(out).toContain('<span class="tk-c"># a comment</span>');
    expect(out).toContain('<span class="tk-t">[menu]</span>');
    expect(out).toContain('<span class="tk-a">layout</span>');
    expect(out).toContain('<span class="tk-s">&quot;tabs&quot;</span>'.replace(/&quot;/g, '"'));
  });

  it('keeps a # inside a shell string out of the comment', () => {
    expect(highlight('shipyard ping send "PR #57 is ready"', 'sh')).not.toContain('tk-c');
  });
});
