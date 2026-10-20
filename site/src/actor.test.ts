// @vitest-environment happy-dom
import { describe, expect, it } from 'vitest';
import { AGENT_KEY, durationBucket, loadAgent, readAgentParams, resolveActor, saveAgent } from './actor';
import { setConsent } from './consent';

function memory() {
  const m = new Map<string, string>();
  return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => { m.set(k, v); }, removeItem: (k: string) => { m.delete(k); }, m };
}

const ids = { visitor: () => 'v-1', agent: () => 'a-1' };
const CHROME = 'Mozilla/5.0 (Macintosh) AppleWebKit/537.36 Chrome/155.0.0.0 Safari/537.36';
const HEADLESS = 'Mozilla/5.0 (Macintosh) AppleWebKit/537.36 HeadlessChrome/155.0.0.0 Safari/537.36';

describe('?analytics_agent and ?analytics_purpose', () => {
  it('take a valid pair and list both keys to remove', () => {
    expect(readAgentParams('?analytics_agent=claude&analytics_purpose=testing&s=dunes')).toEqual({ identity: { name: 'claude', purpose: 'testing' }, handled: ['analytics_agent', 'analytics_purpose'] });
  });

  it('ignore an invalid or half pair, but still remove it', () => {
    expect(readAgentParams('?analytics_agent=acme&analytics_purpose=testing')).toEqual({ identity: null, handled: ['analytics_agent', 'analytics_purpose'] });
    expect(readAgentParams('?analytics_agent=claude')).toEqual({ identity: null, handled: ['analytics_agent'] });
    expect(readAgentParams('?agent=claude&purpose=testing')).toEqual({ identity: null, handled: [] });
    expect(readAgentParams('?s=dunes')).toEqual({ identity: null, handled: [] });
  });
});

describe('the actor', () => {
  it('is a person with a visitor id when no signal says otherwise', () => {
    expect(resolveActor({ webdriver: false, userAgent: CHROME, agent: null }, ids)).toEqual({ actor: 'human', visitor_id: 'v-1' });
  });

  it('is an identified agent with its id, name and purpose, and no visitor id', () => {
    const agent = { id: 'saved', name: 'claude' as const, purpose: 'demo' as const };
    expect(resolveActor({ webdriver: false, userAgent: CHROME, agent }, ids)).toEqual({ actor: 'agent', agent_id: 'saved', agent_name: 'claude', purpose: 'demo' });
  });

  it('is an agent in a WebDriver browser, headless or visible', () => {
    expect(resolveActor({ webdriver: true, userAgent: CHROME, agent: null }, ids)).toEqual({ actor: 'agent', agent_id: 'a-1', automation: 'visible' });
    expect(resolveActor({ webdriver: true, userAgent: HEADLESS, agent: null }, ids)).toEqual({ actor: 'agent', agent_id: 'a-1', automation: 'headless' });
  });

  it('keeps both the identity and the automation when an identified agent drives WebDriver', () => {
    const agent = { id: 'saved', name: 'other' as const, purpose: 'testing' as const };
    expect(resolveActor({ webdriver: true, userAgent: HEADLESS, agent }, ids)).toEqual({ actor: 'agent', agent_id: 'saved', agent_name: 'other', purpose: 'testing', automation: 'headless' });
  });
});

describe('the saved agent', () => {
  it('keeps one id for the tab across identities', () => {
    const s = memory();
    const first = saveAgent(s, null);
    const named = saveAgent(s, { name: 'gemini', purpose: 'exploring' });
    expect(named).toEqual({ id: first.id, name: 'gemini', purpose: 'exploring' });
    expect(loadAgent(s)).toEqual(named);
  });

  it('drops values that are not on the lists', () => {
    const s = memory();
    s.setItem(AGENT_KEY, JSON.stringify({ id: 'x', name: 'john', purpose: 'spying' }));
    expect(loadAgent(s)).toEqual({ id: 'x', name: undefined, purpose: undefined });
    s.setItem(AGENT_KEY, 'not json');
    expect(loadAgent(s)).toBeNull();
  });

  it('is deleted by any opt out', () => {
    const session = memory();
    Object.defineProperty(window, 'sessionStorage', { value: session, configurable: true });
    Object.defineProperty(window, 'localStorage', { value: memory(), configurable: true });
    saveAgent(session, { name: 'claude', purpose: 'testing' });
    setConsent('pageviews');
    expect(session.m.has(AGENT_KEY)).toBe(false);
    setConsent('all');
  });
});

describe('tool call durations', () => {
  it('fall into ranges, never exact times', () => {
    expect([10, 999, 1000, 4999, 5000, 29999, 30000].map(durationBucket)).toEqual(['under-1s', 'under-1s', '1-5s', '1-5s', '5-30s', '5-30s', 'over-30s']);
  });
});
