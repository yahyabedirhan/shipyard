// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from 'vitest';

const { report, startSentry } = vi.hoisted(() => {
  const report = vi.fn();
  const startSentry = vi.fn(() => ({ report }));
  return { report, startSentry };
});

vi.mock('./sentry', () => ({ startSentry }));

import { isTransitionAborted } from './errors';

function transitionError(name: string, message: string) {
  const err = new Error(message);
  err.name = name;
  return err;
}

describe('isTransitionAborted', () => {
  it('recognises a skipped or aborted view transition', () => {
    expect(isTransitionAborted(transitionError('InvalidStateError', 'Transition was aborted because of invalid state'))).toBe(true);
    expect(isTransitionAborted(transitionError('InvalidStateError', 'Skipping view transition because the document visibility state has become hidden.'))).toBe(true);
    expect(isTransitionAborted(transitionError('AbortError', 'The view transition was skipped'))).toBe(true);
    expect(isTransitionAborted('InvalidStateError: Transition was aborted because of invalid state')).toBe(true);
  });

  it('lets other errors through, including other invalid-state errors', () => {
    expect(isTransitionAborted(transitionError('InvalidStateError', 'The document is not focused'))).toBe(false);
    expect(isTransitionAborted(new TypeError('undefined is not a function'))).toBe(false);
    expect(isTransitionAborted('boom')).toBe(false);
    expect(isTransitionAborted(null)).toBe(false);
    expect(isTransitionAborted(undefined)).toBe(false);
  });
});

describe('the early window buffer', () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllEnvs();
    vi.resetModules();
    startSentry.mockReset();
    report.mockReset();
  });

  it('queues a real window error and skips a view-transition abort, then hands the queue to sentry', async () => {
    vi.resetModules();
    vi.stubEnv('VITE_SENTRY_DSN', 'https://examplePublicKey@o0.ingest.sentry.io/0');
    vi.stubGlobal('requestIdleCallback', undefined);
    vi.useFakeTimers();
    const { startErrorReporting } = await import('./errors');
    startErrorReporting();

    const real = new TypeError('undefined is not a function');
    const skipped = transitionError('InvalidStateError', 'Transition was aborted because of invalid state');
    window.dispatchEvent(new ErrorEvent('error', { error: real, message: real.message }));
    window.dispatchEvent(new ErrorEvent('error', { error: skipped, message: skipped.message }));
    const rejection = new Event('unhandledrejection', { cancelable: true }) as PromiseRejectionEvent;
    Object.defineProperty(rejection, 'reason', { value: skipped });
    window.dispatchEvent(rejection);

    await vi.runAllTimersAsync();
    expect(startSentry).toHaveBeenCalledOnce();
    expect(report).toHaveBeenCalledTimes(1);
    expect(report).toHaveBeenCalledWith({ kind: 'error', error: real, context: { source: 'window.error' } });
  });
});
