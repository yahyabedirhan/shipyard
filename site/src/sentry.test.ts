// @vitest-environment happy-dom
import { describe, expect, it, vi } from 'vitest';

vi.mock('@sentry/browser', () => ({
  init: vi.fn(),
  captureException: vi.fn(),
  captureMessage: vi.fn(),
}));

import * as Sentry from '@sentry/browser';
import { TRANSITION_ABORTED } from './errors';
import { startSentry } from './sentry';

describe('startSentry', () => {
  it('drops view-transition aborts and only keeps the site\'s own bundled scripts', () => {
    startSentry('https://examplePublicKey@o0.ingest.sentry.io/0', 10);
    expect(Sentry.init).toHaveBeenCalledWith(expect.objectContaining({
      ignoreErrors: [TRANSITION_ABORTED],
      allowUrls: [`${location.origin}/_astro/`],
      dataCollection: expect.objectContaining({ userInfo: false }),
    }));
  });
});
