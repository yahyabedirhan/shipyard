/**
 * Analytics for the shipyard site, after the topographic site's. It is built in only when `VITE_POSTHOG_KEY` is set.
 * Without a key, `track` does nothing and posthog-js is not part of the build.
 *
 * PostHog runs cookieless (`persistence: 'memory'`, `cookieless_mode: 'always'`), with no session recording and no
 * autocapture. Events carry only the small, fixed properties typed below, never free text. Each event says who it
 * comes from (`actor`, see `actor.ts`): a person with a `visitor_id`, or an agent with an `agent_id`.
 * This is the website's analytics only. The shipyard app sends nothing of the kind.
 */

import { superProperties } from './device';
import { consent, safeStore, setConsent, type Consent } from './consent';
import { visitorId } from './visitor';
import { loadAgent, readAgentParams, resolveActor, safeSession, saveAgent, type ActorProps } from './actor';

/** What a copy button copied, never the text itself. */
export type CopyTarget = 'download' | 'source' | 'skill' | 'plugin' | 'config' | 'command' | 'code';
export type OutboundTarget = 'github' | 'releases' | 'changelog' | 'herdr-plugin' | 'site';

/**
 * Every custom event the site sends, with its properties. Names are snake_case object_action.
 * Pageview and pageleave are PostHog's own `$pageview` and `$pageleave`.
 */
export interface AnalyticsEvents {
  code_copied: { target: CopyTarget };
  install_tab_changed: { to: string };
  explorer_snippet_picked: { snippet: string };
  outbound_clicked: { target: OutboundTarget };
  analytics_opted_out: { from: Exclude<Consent, 'none'> };
}

/** Properties registered once on every event after init. The actor properties are sent only while the visitor has not opted out. */
export interface SuperProperties extends Partial<ActorProps> {
  site: 'shipyard';
  app: 'shipyard-site';
  app_version: string;
  viewport_class: 'phone' | 'tablet' | 'desktop';
  is_mobile: boolean;
  platform: 'mobile' | 'desktop';
  os: string;
  page: 'home' | 'docs' | 'privacy' | 'other';
}

/** Event names, for tests and for the check that PRIVACY.md lists each one. */
export const EVENT_NAMES = [
  'code_copied', 'install_tab_changed', 'explorer_snippet_picked', 'outbound_clicked', 'analytics_opted_out',
] as const satisfies readonly (keyof AnalyticsEvents)[];

export type AnalyticsEvent = keyof AnalyticsEvents;
type Capture = (event: string, props: Record<string, unknown>) => void;
type Loader = (key: string, host: string) => Promise<Capture | null>;

export const DEFAULT_HOST = 'https://eu.i.posthog.com';

/** A tracker that queues events until the client loads. With no key it is a no-op and never loads. */
export function createTracker(key: string | undefined, host: string, load: Loader) {
  let capture: Capture | null = null;
  let queue: [string, Record<string, unknown>][] | null = key ? [] : null;
  let started = false;
  let stopped = false;
  return {
    enabled: Boolean(key),
    start(): void {
      if (!key || started) return;
      started = true;
      load(key, host).then((c) => {
        capture = c;
        const pending = queue ?? [];
        queue = null;
        if (c) for (const [e, p] of pending) c(e, p);
      }).catch(() => { queue = null; });
    },
    track<E extends AnalyticsEvent>(event: E, props: AnalyticsEvents[E]): void {
      if (!key || stopped) return;
      try {
        if (capture) capture(event, props as Record<string, unknown>);
        else if (queue && queue.length < 50) queue.push([event, props as Record<string, unknown>]);
      } catch { /* analytics never breaks the page */ }
    },
    /** Sends nothing more from this page. Events already queued still go out once the client loads. */
    stop(): void { stopped = true; },
  };
}

function doNotTrack(): boolean {
  const nav = navigator as Navigator & { msDoNotTrack?: string };
  const w = window as Window & { doNotTrack?: string };
  return [nav.doNotTrack, nav.msDoNotTrack, w.doNotTrack].some((v) => v === '1' || v === 'yes');
}

const KEY = import.meta.env.VITE_POSTHOG_KEY || undefined;
const HOST = import.meta.env.VITE_POSTHOG_HOST || DEFAULT_HOST;

let posthogLoaded = false;

// `?analytics_agent=<name>&analytics_purpose=<purpose>` on the first load: saved for this tab when valid, and always removed from the address bar.
if (typeof window !== 'undefined') {
  const { identity, handled } = readAgentParams(window.location.search);
  if (identity && consent() === 'all') saveAgent(safeSession(), identity);
  if (handled.length) {
    const url = new URL(window.location.href);
    for (const k of handled) url.searchParams.delete(k);
    try { window.history.replaceState(window.history.state, '', url.pathname + url.search + url.hash); } catch { /* ignore */ }
  }
}

/** This tab's actor properties: a person's visitor id, or an agent's id, name and purpose. */
function actorProps(): ActorProps {
  return resolveActor(
    { webdriver: Boolean(navigator.webdriver), userAgent: navigator.userAgent, agent: loadAgent(safeSession()) },
    { visitor: () => visitorId(safeStore()), agent: () => saveAgent(safeSession(), null).id },
  );
}

// With `?analytics_optout=all` saved, the client is never loaded.
const tracker = createTracker(consent() === 'none' ? undefined : KEY, HOST, async (key, host) => {
  if (doNotTrack()) return null;
  const { startPostHog } = await import('./posthog');
  posthogLoaded = true;
  const props: SuperProperties = superProperties();
  if (consent() === 'all') Object.assign(props, actorProps());
  return startPostHog(key, host, props);
});

/** Sends one event. Does nothing in a build without a key. */
export function track<E extends AnalyticsEvent>(event: E, props: AnalyticsEvents[E]): void {
  if (!KEY || consent() !== 'all') return;
  tracker.track(event, props);
}

/** True when this build can send analytics and the visitor has not opted out of everything. */
export function analyticsActive(): boolean {
  return Boolean(KEY) && consent() !== 'none';
}

/** Lowers the choice to `to`. From all, sends one final `analytics_opted_out` event first. Custom events stop at once. */
export function optOut(to: 'pageviews' | 'none' = 'none'): void {
  const from = consent();
  if (from === 'none' || from === to) return;
  if (KEY && from === 'all') {
    tracker.track('analytics_opted_out', { from });
    tracker.start();
    if (to === 'none') tracker.stop();
  } else if (KEY && to === 'none') tracker.stop();
  setConsent(to);
  if (posthogLoaded && to === 'pageviews') import('./posthog').then((m) => m.dropVisitorId()).catch(() => {});
}

/** Clears the saved choice. Analytics start again on the next page load. */
export function optIn(): void { setConsent('all'); }

/** Loads PostHog once the page is idle after the first paint. */
export function startAnalytics(): void {
  if (!KEY || consent() === 'none') return;
  const go = () => tracker.start();
  const idle = (window as Window & { requestIdleCallback?: (cb: () => void, o?: { timeout: number }) => number }).requestIdleCallback;
  const later = () => (idle ? idle(go, { timeout: 4000 }) : window.setTimeout(go, 1500));
  if (document.readyState === 'complete') later();
  else window.addEventListener('load', later, { once: true });
}
