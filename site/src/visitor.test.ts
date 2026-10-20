// @vitest-environment happy-dom
import { describe, expect, it } from 'vitest';
import { VISITOR_KEY, forgetVisitor, visitorId } from './visitor';
import { setConsent } from './consent';

function memory() {
  const m = new Map<string, string>();
  return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => { m.set(k, v); }, removeItem: (k: string) => { m.delete(k); }, m };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

describe('visitor id', () => {
  it('makes a UUID once and keeps it', () => {
    const s = memory();
    const id = visitorId(s);
    expect(id).toMatch(UUID);
    expect(s.m.get(VISITOR_KEY)).toBe(id);
    expect(visitorId(s)).toBe(id);
  });

  it('replaces a saved value that is not a UUID', () => {
    const s = memory();
    s.setItem(VISITOR_KEY, 'cookieless_abc');
    expect(visitorId(s)).toMatch(UUID);
  });

  it('works with blocked storage, for this page only', () => {
    const blocked = { getItem: () => { throw new Error('x'); }, setItem: () => { throw new Error('x'); }, removeItem: () => { throw new Error('x'); } };
    expect(visitorId(blocked)).toMatch(UUID);
    expect(visitorId(null)).toMatch(UUID);
    expect(() => forgetVisitor(blocked)).not.toThrow();
  });

  it('any opt out deletes the id, and opting in does not make one', () => {
    Object.defineProperty(window, 'localStorage', { value: memory(), configurable: true });
    window.localStorage.setItem(VISITOR_KEY, visitorId(null));
    setConsent('pageviews');
    expect(window.localStorage.getItem(VISITOR_KEY)).toBeNull();
    window.localStorage.setItem(VISITOR_KEY, visitorId(null));
    setConsent('none');
    expect(window.localStorage.getItem(VISITOR_KEY)).toBeNull();
    setConsent('all');
    expect(window.localStorage.getItem(VISITOR_KEY)).toBeNull();
  });
});
