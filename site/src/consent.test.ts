// @vitest-environment happy-dom
import { describe, expect, it, vi } from 'vitest';
import { CONSENT_KEY, resolveConsent } from './consent';
import { createTracker } from './analytics';

function memory() {
  const m = new Map<string, string>();
  return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => { m.set(k, v); }, removeItem: (k: string) => { m.delete(k); }, m };
}

describe('consent', () => {
  it('defaults to all with nothing saved', () => {
    expect(resolveConsent('', memory()).consent).toBe('all');
  });

  it('?analytics_optout keeps pageviews only and is saved', () => {
    const s = memory();
    expect(resolveConsent('?analytics_optout', s)).toEqual({ consent: 'pageviews', handled: 'analytics_optout' });
    expect(s.m.get(CONSENT_KEY)).toBe('pageviews');
    expect(resolveConsent('?seed=3', s).consent).toBe('pageviews');
  });

  it('?analytics_optout=all sends nothing and ?analytics_optin clears it', () => {
    const s = memory();
    expect(resolveConsent('?analytics_optout=all', s).consent).toBe('none');
    expect(resolveConsent('', s).consent).toBe('none');
    expect(resolveConsent('?analytics_optin', s).consent).toBe('all');
    expect(s.m.has(CONSENT_KEY)).toBe(false);
  });

  it('ignores unknown saved values and blocked storage', () => {
    const s = memory();
    s.setItem(CONSENT_KEY, 'weird');
    expect(resolveConsent('', s).consent).toBe('all');
    const blocked = { getItem: () => { throw new Error('x'); }, setItem: () => { throw new Error('x'); }, removeItem: () => { throw new Error('x'); } };
    expect(resolveConsent('?analytics_optout=all', blocked).consent).toBe('none');
    expect(resolveConsent('', blocked).consent).toBe('all');
  });

  it('a stopped tracker still delivers the queued final event, then nothing', async () => {
    const sent: string[] = [];
    const t = createTracker('phc_test', 'h', async () => (e) => { sent.push(e); });
    t.track('analytics_opted_out', { from: 'all' });
    t.start();
    t.stop();
    t.track('code_copied', { target: 'code' });
    await new Promise((r) => setTimeout(r, 0));
    expect(sent).toEqual(['analytics_opted_out']);
  });

  it('a tracker without a key never loads', () => {
    const load = vi.fn();
    createTracker(undefined, 'h', load).start();
    expect(load).not.toHaveBeenCalled();
  });
});

describe('privacy docs', () => {
  it('PRIVACY.md lists every event', async () => {
    const { readFileSync } = await import('node:fs');
    const { EVENT_NAMES } = await import('./analytics');
    const md = readFileSync(`${process.cwd()}/PRIVACY.md`, 'utf8');
    for (const name of EVENT_NAMES) expect(md).toContain(`\`${name}\``);
  });
});
