/** Which page a path shows. The host serves /, /docs and /privacy from their own HTML files, and every page runs this bundle. */
export type Route = 'home' | 'docs' | 'privacy' | 'not-found';

export function routeOf(path: string): Route {
  const p = path.replace(/\/+$/, '') || '/';
  if (p === '/' || p === '/index.html') return 'home';
  if (p === '/docs' || p === '/docs.html') return 'docs';
  if (p === '/privacy' || p === '/privacy.html') return 'privacy';
  return 'not-found';
}
