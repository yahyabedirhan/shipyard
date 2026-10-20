/// <reference types="vitest" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { appVersion } from './plugins/repo';
import { sitePlugin } from './plugins/site';

// The site is a self-contained folder: its own package.json, this config and its own build. It reads the repository
// one folder up (the schema, the skill, the Swift command table) only through plugins/repo.ts.
export default defineConfig({
  plugins: [react(), sitePlugin()],
  define: { __APP_VERSION__: JSON.stringify(appVersion()) },
  server: { fs: { allow: ['..'] } },
  build: { rollupOptions: { input: 'index.html' } },
  test: { environment: 'node', include: ['src/**/*.test.{ts,tsx}', 'plugins/**/*.test.ts', 'scripts/**/*.test.mjs'] },
});
