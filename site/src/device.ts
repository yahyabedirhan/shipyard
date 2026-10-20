/** Coarse device facts for the analytics' super properties. No identifiers. */
import type { SuperProperties } from './analytics';

/** Operating system family from the user agent. Never a version. */
export function osFamily(ua = navigator.userAgent): string {
  return /iPhone|iPad|iPod/.test(ua) ? 'ios'
    : /Android/.test(ua) ? 'android'
      : /Windows/.test(ua) ? 'windows'
        : /Mac OS X|Macintosh/.test(ua) ? 'macos'
          : /CrOS/.test(ua) ? 'chromeos'
            : /Linux/.test(ua) ? 'linux' : 'other';
}

export function isMobile(ua = navigator.userAgent): boolean {
  return /Mobi|iPhone|iPad|Android/.test(ua);
}

export function viewportClass(width = innerWidth): 'phone' | 'tablet' | 'desktop' {
  return width <= 720 ? 'phone' : width <= 1100 ? 'tablet' : 'desktop';
}

/** The page a visit is on, from its path. */
export function pageOf(path = location.pathname): SuperProperties['page'] {
  return /^\/docs\/?$/.test(path) ? 'docs' : /^\/privacy\/?$/.test(path) ? 'privacy' : path === '/' ? 'home' : 'other';
}

/** The super properties registered once after PostHog starts. */
export function superProperties(): SuperProperties {
  const mobile = isMobile();
  return {
    site: 'shipyard',
    app: 'shipyard-site',
    app_version: typeof __APP_VERSION__ === 'string' ? __APP_VERSION__ : 'dev',
    viewport_class: viewportClass(),
    is_mobile: mobile,
    platform: mobile ? 'mobile' : 'desktop',
    os: osFamily(),
    page: pageOf(),
  };
}
