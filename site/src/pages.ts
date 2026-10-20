// Each page's head: its title, description, address and social card. The Vite plugin writes them into each page's
// HTML, scripts/social.mjs draws each card, and the sitemap lists the pages. Titles stay near 60 characters and
// descriptions near 155, as the messaging kit's channel lengths ask.
import { LINE, NAME, PROOF, SITE_URL } from './messaging';

export interface PageMeta {
  id: 'home' | 'docs' | 'privacy' | 'not-found';
  /** The path the page is served at. */
  path: string;
  /** The built HTML file that serves it. */
  file: string;
  title: string;
  description: string;
  /** The social card, under /og/. */
  image: string;
  imageAlt: string;
  /** The words drawn on the card under the one line. */
  card: string;
  /** Listed in the sitemap. */
  listed: boolean;
}

export const PAGES: PageMeta[] = [
  {
    id: 'home', path: '/', file: 'index.html',
    title: `${NAME}: a menu bar app for the pull requests your agents open`,
    description: `${LINE} ${PROOF}`,
    image: 'og/home.png', imageAlt: `${NAME}: ${LINE}`, card: 'For macOS 14 and later. Open source.', listed: true,
  },
  {
    id: 'docs', path: '/docs', file: 'docs.html',
    title: `${NAME} docs: install, configure and use it with your agents`,
    description: `Install ${NAME}, choose a preset, and configure every key of config.toml. Pings, notices, notes, the agent skill and the shipyard command.`,
    image: 'og/docs.png', imageAlt: `The ${NAME} docs: install, configuration reference and the shipyard command.`, card: 'Docs: install, configuration and the command.', listed: true,
  },
  {
    id: 'privacy', path: '/privacy', file: 'privacy.html',
    title: `${NAME} privacy: what this site collects, and what it never does`,
    description: `What the ${NAME} website collects without cookies, what it never collects, where it goes and how to opt out. The app has no analytics.`,
    image: 'og/privacy.png', imageAlt: `The ${NAME} privacy page.`, card: 'Privacy: what this website collects.', listed: true,
  },
  {
    id: 'not-found', path: '/404', file: '404.html',
    title: `${NAME}: this page doesn't exist, try the docs or the home page`,
    description: `This address has no page. The ${NAME} docs cover install, configuration and the shipyard command, and llms.txt has them all as plain text.`,
    image: 'og/home.png', imageAlt: `${NAME}: ${LINE}`, card: '', listed: false,
  },
];

export const pageById = (id: PageMeta['id']) => PAGES.find((p) => p.id === id)!;
export const absolute = (path: string) => `${SITE_URL}${path.startsWith('/') ? '' : '/'}${path}`;
