/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** PostHog project key. Unset means no analytics and no PostHog code in the build. */
  readonly VITE_POSTHOG_KEY?: string;
  /** PostHog ingest host. Defaults to https://eu.i.posthog.com. */
  readonly VITE_POSTHOG_HOST?: string;
  /** Sentry DSN. Unset means no error reporting and no Sentry code in the build. */
  readonly VITE_SENTRY_DSN?: string;
}

/** The app version the docs describe, from Sources/ShipyardCommand/Version.swift, set at build time. */
declare const __APP_VERSION__: string;

declare module 'virtual:shipyard-reference' {
  /** The generated reference; src/reference/data.ts gives it its type. */
  const data: unknown;
  export default data;
}

declare module 'virtual:shipyard-privacy' {
  /** site/PRIVACY.md as HTML. */
  const html: string;
  export default html;
}
