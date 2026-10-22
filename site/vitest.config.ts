/// <reference types="vitest/config" />
// The tests run through Astro's Vite config, so they see the same virtual modules and JSX setup as the build.
import { getViteConfig } from 'astro/config';

export default getViteConfig({
  test: { environment: 'node', include: ['src/**/*.test.{ts,tsx}', 'plugins/**/*.test.ts', 'scripts/**/*.test.mjs', 'worker/**/*.test.mjs'] },
});
