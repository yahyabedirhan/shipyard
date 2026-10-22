/**
 * The Sentry client, in its own chunk. Imported only by `errors.ts` in a build with a DSN.
 *
 * Copied: `yahyabedirhan/topographic` keeps the same module in `apps/playground/src`, and
 * `yahyabedirhan/personal-website` keeps an equivalent in `src/privacy.js`, `src/analytics.js` and `src/errors.js`.
 * Change all three together. `site/docs/low-level-design.md` > 'Copied modules' lists them.
 */
import * as Sentry from '@sentry/browser';
import type { Reporter } from './errors';

export function startSentry(dsn: string, maxEvents: number): Reporter {
  let sent = 0;
  Sentry.init({
    dsn,
    sampleRate: 1,
    // The v11 replacement for sendDefaultPii: false. The query string stays out too.
    dataCollection: { userInfo: false, cookies: false, httpHeaders: false, urlQueryParams: false, httpBodies: [] },
    // Errors only: no tracing and no replay integrations are added.
    tracesSampleRate: 0,
    integrations: (defaults) => defaults.filter((i) => i.name !== 'BrowserSession'),
    beforeSend(event) {
      // Window errors caught by Sentry itself also count against the per-page cap.
      sent += 1;
      if (sent > maxEvents) return null;
      if (event.request?.url) event.request.url = event.request.url.split(/[?#]/)[0];
      return event;
    },
  });
  return {
    report(r) {
      const scope = { tags: r.context };
      if (r.kind === 'error') Sentry.captureException(r.error, scope);
      else Sentry.captureMessage(r.message, { level: 'warning', ...scope });
    },
  };
}
