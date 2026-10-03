# Notices may reach in over the tailnet

An agent on another machine posts a notice (`shipyard notify`) that should show on the Mac within about a second. Remote pings arrive on the Mac's 30-second poll through Herdr (ADR 0005), which is too slow for "this just happened". So **notices, and only notices, may reach in**: the other machine sends the notice straight to the app on the Mac over the user's tailnet (Tailscale). This is a narrow exception to ADR 0005's "the Mac reaches out, a machine never reaches in". Pings, and everything else, still go the Mac's way.

The route, end to end:

- **Opt-in on the Mac.** The app listens only when `config.toml` says `[notify] listen = true`. Nothing listens by default.
- **127.0.0.1 only.** The app's listener binds the loopback address, at `[notify] port` (47420 by default). It's never reachable from the Mac's LAN or the internet by itself.
- **Tailscale exposes it.** The user runs `tailscale serve --bg --http=<port> http://127.0.0.1:<port>` once on the Mac. `serve` makes the port reachable from the user's own tailnet only, and puts the sender's login on each request as `Tailscale-User-Login`, removing any such header the sender wrote. Shipyard never installs or configures Tailscale.
- **Identity.** The app takes a notice only when that header is exactly the Mac's own Tailscale login, which it learns from `tailscale status --json` (the `Self` device's user) for each request. A request without the header, with another login, or arriving while the Mac's login can't be learned (Tailscale stopped, logged out, not installed) is refused with why. Machines join the tailnet as the user's own untagged devices, since tagged devices' requests carry no login.
- **Browsers are refused.** A request with `Origin` or `Sec-Fetch-Site`, which a browser adds and the `shipyard` command never sends, is refused, so a web page can't post a notice to 127.0.0.1, even by pointing a name of its own at it.
- **The other machine** names the Mac in its own `cli.toml` (ADR 0008): `[notify] app-machine = "<MagicDNS name>"`, with `app-scheme` (`http` by default) and `app-port` (47420 by default) beside it, named apart from `config.toml`'s `[notify] port` since no setting appears in both files. The command posts the request's JSON (a notice, or a withdrawal by id) to `<app-scheme>://<app-machine>:<app-port>/notify` and waits up to 3 seconds (a second more per megabyte past the first, for a notice carrying an image) for the app's verdict: shown, or refused with why. Nothing is queued or retried; a Mac asleep or away is exit 1. Without `app-machine` the notice takes the poll route through the herdr-shipyard plugin instead.
- **No Herdr actions.** A request over the tailnet names no machine, so a notice whose click or a button focuses Herdr would focus the Mac's own Herdr. The command refuses one before sending (exit 2), and the app refuses one that arrives anyway; the poll route, which knows the machine, carries them.

**`http` and the port are assumptions.** The Tailscale spike (#188) checks whether `serve --http` works without the tailnet's HTTPS certificates, whether `--bg` survives a reboot, and that the macOS firewall stays quiet. Its answer is a setting, not code: `app-scheme = "https"` and `app-port = 443` in `cli.toml` when `--https=443` is what works.

## Considered Options

- **Poll faster through Herdr.** Keeps one direction of trust, but a poll every few seconds per machine costs the Mac and each machine all day, and still isn't "within about a second".
- **A relay or push service** (ntfy, a hosted queue). A third party in the path of every notice, and an account to keep (ADR 0005 turned these down for pings).
- **A listener on the Mac's network interfaces, with a shared secret.** shipyard would own the transport's security: secrets to issue, store and rotate, and a port open to the LAN.
- **Tailscale `serve` in front of a loopback listener (chosen).** The tailnet already connects the user's machines with their identity. `serve` carries the identity to the app, the loopback bind keeps the listener off every network but Tailscale's, and the user's one setting turns it all on or off.

## Consequences

- The app gains a listener (`NoticeListener`), started and stopped as `[notify] listen` and `port` change, and a port for the Mac's login (`TailnetIdentity`, whose real adapter `TailscaleCLI` runs `tailscale status --json`). The identity check lives in the core (`Shipyard.receive(_:from:)`), where scenarios cover it.
- Any process on the Mac can reach 127.0.0.1 and write the header itself. That's the same user's machine; a process able to do it could already run `shipyard notify` over the control socket. Tailscale's documentation recommends exactly this loopback-only shape for identity headers.
- Linux's `shipyard` now links ShipyardNotices, and with it FoundationNetworking for the HTTP request. It still never links Config, Control or Core, and CI's link checks say so.
- Tagged devices, app-capability grants and tighter access policies are out of scope until someone else joins the tailnet.
- Only notices take this route. Moving pings to it would be a new decision.
