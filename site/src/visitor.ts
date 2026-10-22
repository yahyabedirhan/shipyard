/**
 * A random visitor id for this browser, kept in local storage under `shipyard:visitor`.
 * It is sent as the `visitor_id` event property, so one browser's visits can be followed across days.
 * PostHog stays cookieless: its own distinct id is still the server's daily hash.
 * Any opt out deletes the id.
 *
 * Copied: `yahyabedirhan/topographic` keeps the same module in `apps/playground/src`, and
 * `yahyabedirhan/personal-website` keeps an equivalent in `src/privacy.js`, `src/analytics.js` and `src/errors.js`.
 * Change all three together. `site/docs/low-level-design.md` > 'Copied modules' lists them.
 */

export const VISITOR_KEY = 'shipyard:visitor';

type Store = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function randomUuid(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  // randomUUID needs a secure context; build a version 4 UUID by hand otherwise.
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

/** Returns the saved id, or makes and saves a new one. With storage blocked, the id lasts for this page only. */
export function visitorId(store: Store | null): string {
  try {
    const saved = store?.getItem(VISITOR_KEY);
    if (saved && UUID.test(saved)) return saved;
  } catch { /* storage can be blocked */ }
  const id = randomUuid();
  try { store?.setItem(VISITOR_KEY, id); } catch { /* ignore */ }
  return id;
}

/** Deletes the saved id. */
export function forgetVisitor(store: Store | null): void {
  try { store?.removeItem(VISITOR_KEY); } catch { /* ignore */ }
}
