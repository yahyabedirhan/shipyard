import { describe, expect, it } from 'vitest';
import worker from './index.js';

const env = { ASSETS: { fetch: async () => new Response('<!doctype html><title>404</title>', { status: 200 }) } };

describe('the worker', () => {
  it('answers a browser with the 404 page and a 404 status', async () => {
    const res = await worker.fetch(new Request('https://shipyard.yahyapak.dev/nope', { headers: { accept: 'text/html' } }), env);
    expect(res.status).toBe(404);
    expect(res.headers.get('content-type')).toContain('text/html');
  });

  it('answers anything else with plain text that points to llms.txt', async () => {
    const res = await worker.fetch(new Request('https://shipyard.yahyapak.dev/nope.json'), env);
    expect(res.status).toBe(404);
    expect(await res.text()).toContain('https://shipyard.yahyapak.dev/llms.txt');
  });
});
