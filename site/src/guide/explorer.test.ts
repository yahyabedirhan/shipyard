import { describe, expect, it } from 'vitest';
import { DEFAULT_CONFIG, ITEMS, SNIPPETS, configOf, groups, listed, mockPanel } from './explorer';

const snippet = (id: string) => configOf(SNIPPETS.find((s) => s.id === id)!);

describe('the config explorer\'s mock', () => {
  it('shows pull requests and pings only by default, grouped by kind', () => {
    const p = mockPanel(DEFAULT_CONFIG);
    expect(p.tabs).toBeNull();
    expect(p.projects[0].groups.map((g) => g.name)).toEqual(['Pull requests', 'Pings']);
  });

  it('adds issues and runs when they are shown, in the kind order', () => {
    expect(mockPanel(snippet('issues-runs')).projects[0].groups.map((g) => g.name)).toEqual(['Pull requests', 'Pings', 'Issues', 'Runs']);
  });

  it('puts open items first, then the newest', () => {
    const prs = groups(ITEMS.filter((i) => i.project === 'shop' && i.kind === 'pull-requests'), DEFAULT_CONFIG)[0].rows;
    expect(prs.map((r) => r.state)).toEqual(['open', 'draft', 'open', 'open', 'merged', 'closed']);
  });

  it('caps each group with show-first and counts what it hides', () => {
    const g = mockPanel(snippet('show-first')).projects[0].groups[0];
    expect(g.rows).toHaveLength(2);
    expect(g.more).toBe(g.count - 2);
  });

  it('hides bots and lowers the attention count', () => {
    expect(ITEMS.filter((i) => listed(i, snippet('hide-bots'))).some((i) => i.group === 'bots')).toBe(false);
    expect(mockPanel(snippet('hide-bots')).attention).toBeLessThan(mockPanel(DEFAULT_CONFIG).attention);
  });

  it('keeps drafts but drops merged and closed with states = ["open"]', () => {
    const states = ITEMS.filter((i) => i.kind === 'pull-requests' && listed(i, snippet('open-only'))).map((i) => i.state);
    expect(states).toContain('draft');
    expect(states).not.toContain('merged');
    expect(states).not.toContain('closed');
  });

  it('shows the All tab grouped by kind in the tabs layout', () => {
    const p = mockPanel(snippet('tabs'));
    expect(p.tabs).toEqual(['All', 'shop', 'docs']);
    expect(p.projects).toHaveLength(1);
  });

  it('groups by repository A to Z and by date in its fixed order', () => {
    expect(mockPanel(snippet('by-repository')).projects[0].groups.map((g) => g.name)).toEqual(['my-org/shop', 'my-org/shop-api']);
    expect(mockPanel(snippet('by-date')).projects[0].groups.map((g) => g.name)).toEqual(['Today', 'Yesterday', 'This week']);
  });
});
