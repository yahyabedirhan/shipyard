// The site is a self-contained folder: its own package.json, this config and its own build. It reads the repository
// one folder up (the schema, the skill, the Swift command table) only through plugins/repo.ts.
// Astro renders every page to HTML at build time; only the parts that move hydrate in the browser, as React islands.
import react from '@astrojs/react';
import { defineConfig } from 'astro/config';
import { SITE_URL } from './src/messaging';
import { appVersion } from './plugins/repo';
import { siteIntegration } from './plugins/site';

export default defineConfig({
  site: SITE_URL,
  output: 'static',
  // docs.html, privacy.html and 404.html beside index.html, as the Worker's assets serve them at /docs and /privacy.
  build: { format: 'file' },
  // The landing page and the docs mark their links to each other with data-astro-prefetch.
  prefetch: { prefetchAll: false, defaultStrategy: 'hover' },
  integrations: [react(), siteIntegration()],
  devToolbar: { enabled: false },
  vite: {
    // The analytics keys keep the names VITE_POSTHOG_KEY, VITE_POSTHOG_HOST and VITE_SENTRY_DSN.
    envPrefix: ['VITE_', 'PUBLIC_'],
    define: { __APP_VERSION__: JSON.stringify(appVersion()) },
    server: { fs: { allow: ['..'] } },
  },
});
