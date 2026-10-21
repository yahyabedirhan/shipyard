/** The PostHog client, in its own chunk. Imported only by `analytics.ts` in a build with a key. */
// The slim build has capture, pageview and pageleave, without replay, surveys or the toolbar.
import posthog from 'posthog-js/dist/module.slim';
import type { SuperProperties } from './analytics';

export function startPostHog(key: string, host: string, props: SuperProperties): (event: string, props: Record<string, unknown>) => void {
  posthog.init(key, {
    api_host: host,
    persistence: 'memory',
    // No cookies or stored ids: the server counts daily unique visitors from a salted hash that rotates each day.
    // This needs the project's cookieless server hash setting on.
    cookieless_mode: 'always',
    disable_session_recording: true,
    autocapture: false,
    capture_pageview: true,
    capture_pageleave: true,
    respect_dnt: true,
    // Nothing that loads remote code or adds events of its own.
    advanced_disable_flags: true,
    disable_external_dependency_loading: true,
    disable_surveys: true,
    disable_web_experiments: true,
    disable_product_tours: true,
    rageclick: false,
    capture_dead_clicks: false,
    enable_heatmaps: false,
    capture_heatmaps: false,
    capture_performance: false,
    capture_exceptions: false,
    // WebDriver browsers (Playwright, Selenium, Puppeteer) are sent, not dropped: pageviews arrive as $bot_pageview,
    // and `actor.ts` marks every event of theirs `actor: agent`. A preview option of posthog-js, which may change.
    __preview_capture_bot_pageviews: true,
  } as Parameters<typeof posthog.init>[1]);
  posthog.register(props as unknown as Record<string, unknown>);
  return (event, p) => { posthog.capture(event, p); };
}

const ACTOR_KEYS = ['actor', 'visitor_id', 'agent_id', 'agent_name', 'purpose', 'automation'];

/** Stops sending the visitor id and the actor properties from this page, after an opt out. */
export function dropVisitorId(): void {
  for (const k of ACTOR_KEYS) posthog.unregister(k);
}

/** Replaces the actor properties, after an agent identifies itself. */
export function setActor(props: object): void {
  for (const k of ACTOR_KEYS) posthog.unregister(k);
  posthog.register(props as Record<string, unknown>);
}
