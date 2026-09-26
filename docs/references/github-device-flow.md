# GitHub device flow

Checked 2026-09-25 against [Authorizing OAuth apps: device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow); the per-app limits checked 2026-09-26 against the same page.

1. The app requests a device code and a user code from GitHub, using an OAuth App's client ID. There's no client secret, so it's safe in a desktop app.
2. The app shows the user code and opens `https://github.com/login/device`, where the user enters it.
3. The app polls the access-token endpoint at least `interval` seconds apart. A `slow_down` error adds 5 seconds to the interval, and the app keeps polling at the new one.
4. The device and user codes expire after 900 seconds (15 minutes). After that, start over with a new request.

The device flow has to be enabled in the OAuth App's settings. ghbar (`~/Developer/open-source/ghbar/Sources/GHBar/DeviceFlowAuth.swift`) is a working Swift implementation to learn from.

## Per-app limits

Both count per OAuth App, so every copy of shipyard built with the same client ID shares them.

- **50 device-code submissions an hour per application** ("Rate limits for the device flow"): when users enter the verification code in the browser, GitHub allows 50 submissions an hour for the application. Polling too often is a separate limit, answered with `slow_down`.
- **At most 10 tokens per user, application and scope** ("Creating multiple tokens for OAuth apps"): an eleventh token for the same user and scopes makes GitHub revoke an existing one: the oldest unused first, then the least recently used, then the oldest. Signing in with GitHub on more than ten Macs (or ten times without signing out) revokes an earlier token, and that copy of shipyard gets a 401 and returns to the connect screen.

## Where the client ID lives

`OAuthApp.clientID` in `Sources/ShipyardCore/GitHub/Auth/DeviceFlow.swift`. While it's the placeholder, `DeviceFlow.requestCode()` throws `clientIDMissing` and the connect screen shows Sign in with GitHub as unavailable. Forks register their own OAuth App (with **Enable Device Flow** ticked) and put its client ID there; the README says how.
