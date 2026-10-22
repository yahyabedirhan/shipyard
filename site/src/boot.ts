// Runs once per full page load, from src/layouts/Base.astro, and keeps working across the client router's page
// changes: error reporting, analytics, the outbound-link count and the pageviews of client-side navigations.
import { pageLeft, pageShown, startAnalytics, track, type OutboundTarget } from './analytics';
import { startErrorReporting } from './errors';

startErrorReporting();
startAnalytics();

// An outbound link names its fixed target in data-out, so a click is counted by target, never by its address.
document.addEventListener('click', (e) => {
  const a = (e.target as Element | null)?.closest?.<HTMLAnchorElement>('a[data-out]');
  if (a) track('outbound_clicked', { target: a.dataset.out as OutboundTarget });
});

document.addEventListener('astro:before-swap', pageLeft);
document.addEventListener('astro:after-swap', pageShown);
