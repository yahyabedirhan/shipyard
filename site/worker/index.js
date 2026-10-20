// Answers the requests that match no file in site/dist. Cloudflare serves files first, so only an unknown path
// reaches this script. A browser navigation gets the site's 404 page; anything else, such as curl or an agent's
// fetch, gets a short plain-text 404 that points to the docs for agents. Both are real 404s.
const BODY = `Not found.

shipyard has no file at this path.
Docs for AI agents: https://shipyard.yahyapak.dev/llms.txt
`;

const HEADERS = { 'cache-control': 'public, max-age=0, must-revalidate', 'x-content-type-options': 'nosniff' };

export default {
  async fetch(request, env) {
    const wantsPage = request.method === 'GET' && (request.headers.get('accept') ?? '').includes('text/html');
    if (wantsPage && env.ASSETS) {
      const page = await env.ASSETS.fetch(new URL('/404', request.url));
      if (page.ok) return new Response(page.body, { status: 404, headers: { ...HEADERS, 'content-type': 'text/html; charset=utf-8' } });
    }
    return new Response(BODY, { status: 404, headers: { ...HEADERS, 'content-type': 'text/plain; charset=utf-8' } });
  },
};
