// Renders a page the way the build does, for the tests: Astro's container with the React renderer, so the HTML is the
// page's whole static markup, islands included as they render before they hydrate.
import { getContainerRenderer } from '@astrojs/react/container-renderer';
import { experimental_AstroContainer as AstroContainer } from 'astro/container';
import { loadRenderers } from 'astro:container';

type Page = Parameters<AstroContainer['renderToString']>[0];

export async function renderPage(page: Page): Promise<string> {
  const container = await AstroContainer.create({ renderers: await loadRenderers([getContainerRenderer()]) });
  return container.renderToString(page);
}
