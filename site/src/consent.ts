/**
 * The visitor's analytics choice, kept in this browser's local storage.
 *
 * - `?analytics_optout` keeps pageviews and pageleaves only: no custom events and no error reports.
 * - `?analytics_optout=all` sends nothing: the analytics and error clients are not loaded.
 * - `?analytics_optin` clears the choice.
 *
 * The parameter is removed from the address bar once it is read, so it does not end up in shared links.
 * Any choice other than `all` also deletes the visitor id and this tab's agent identity.
 *
 * Copied: yahyabedirhan/topographic keeps the same module in apps/playground/src, and yahyabedirhan/personal-website
 * keeps the same behaviour in src/privacy.js, src/analytics.js and src/errors.js. Change all three together;
 * docs/low-level-design.md > 'Copied modules' lists them.
 */

import { forgetVisitor } from './visitor';
import { forgetAgent, safeSession } from './actor';

export type Consent = 'all' | 'pageviews' | 'none';
export const CONSENT_KEY = 'shipyard:analytics';

type Store = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;

export function safeStore(): Store | null {
  try { return window.localStorage; } catch { return null; }
}

/** The opt-in and opt-out parameters. */
export const OPT_IN = ['analytics_optin'];
export const OPT_OUT = ['analytics_optout'];

/** Reads the choice from the query string, saves it, and falls back to the saved value. */
export function resolveConsent(search: string, store: Store | null): { consent: Consent; handled: string | null } {
  const q = new URLSearchParams(search);
  const optIn = OPT_IN.find((k) => q.has(k));
  const optOut = OPT_OUT.find((k) => q.has(k));
  const handled = optIn ?? optOut ?? null;
  const level: Consent = optIn ? 'all' : optOut && q.get(optOut) === 'all' ? 'none' : 'pageviews';
  try {
    if (optIn) store?.removeItem(CONSENT_KEY);
    else if (optOut) store?.setItem(CONSENT_KEY, level);
  } catch { /* storage can be blocked; the choice then lasts for this page only */ }
  if (handled) return { consent: level, handled };
  let saved: string | null = null;
  try { saved = store?.getItem(CONSENT_KEY) ?? null; } catch { /* ignore */ }
  return { consent: saved === 'none' || saved === 'pageviews' ? saved : 'all', handled };
}

function initial(): Consent {
  if (typeof window === 'undefined') return 'all';
  const { consent, handled } = resolveConsent(window.location.search, safeStore());
  if (handled) {
    const url = new URL(window.location.href);
    url.searchParams.delete(handled);
    try { window.history.replaceState(window.history.state, '', url.pathname + url.search + url.hash); } catch { /* ignore */ }
  }
  if (consent !== 'all') { forgetVisitor(safeStore()); forgetAgent(safeSession()); }
  return consent;
}

let current: Consent = initial();

export function consent(): Consent { return current; }

/** Saves a new choice for this browser. Takes effect for analytics now; a reload applies it fully. */
export function setConsent(next: Consent): void {
  current = next;
  const store = safeStore();
  try {
    if (next === 'all') store?.removeItem(CONSENT_KEY);
    else store?.setItem(CONSENT_KEY, next);
  } catch { /* ignore */ }
  if (next !== 'all') { forgetVisitor(store); forgetAgent(safeSession()); }
}
