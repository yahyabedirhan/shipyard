# GitHub device flow

Checked 2026-09-25 against [Authorizing OAuth apps: device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow).

1. The app requests a device code and a user code from GitHub, using an OAuth App's client ID. There's no client secret, so it's safe in a desktop app.
2. The app shows the user code and opens `https://github.com/login/device`, where the user enters it.
3. The app polls the access-token endpoint at least `interval` seconds apart. A `slow_down` error adds 5 seconds to the interval, and the app keeps polling at the new one.
4. The device and user codes expire after 900 seconds (15 minutes). After that, start over with a new request.

The device flow has to be enabled in the OAuth App's settings. ghbar (`~/Developer/open-source/ghbar/Sources/GHBar/DeviceFlowAuth.swift`) is a working Swift implementation to learn from.
