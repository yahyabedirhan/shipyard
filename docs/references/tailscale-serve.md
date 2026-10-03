# Tailscale Serve and identity

What notices over the tailnet depend on (ADR 0010): how `tailscale serve` exposes the app's loopback listener, the identity headers it adds, and where the Mac's own login comes from.

Checked 2026-10-04 against:
- [tailscale serve command](https://tailscale.com/kb/1242/tailscale-serve) (last validated by Tailscale 2026-01-26)
- [Tailscale Serve](https://tailscale.com/kb/1312/serve) (last validated by Tailscale 2026-01-20)
- `tailscale status --json` from Tailscale 1.102.4 (the Standalone macOS variant), keys only

## Exposing a local port

- `tailscale serve [flags] <target>`. `--http=<port>` exposes an HTTP server at that port on the tailnet, `--https=<port>` an HTTPS one (the default). The target, for a reverse proxy, is a port number, `localhost:<port>` or a full URL; only `http://127.0.0.1` is supported for proxies. So shipyard documents `tailscale serve --bg --http=47420 http://127.0.0.1:47420`.
- HTTP servers are reachable with short MagicDNS names, `http://my-node`; HTTPS uses the full `my-node.<tailnet>.ts.net` with a certificate Tailscale provisions.
- `--bg` runs it in the background, persistently: it resumes after a reboot or `tailscale down`/`up`. Without `--bg` it must be started again by hand.
- `tailscale serve status` lists what's served; `tailscale serve --http=<port> off` turns one off; `tailscale serve reset` clears everything.
- The Serve page warns that Serve needs HTTPS certificates enabled for the tailnet (the CLI offers to turn them on). Whether `--http` alone needs them is one of the Tailscale spike's (#188) questions; `cli.toml`'s `scheme` and `port` let its answer be a setting.
- On macOS's App Store and Standalone variants, Serve can share ports, but not files or folders.

## Identity headers

- Proxied Serve traffic from the tailnet carries `Tailscale-User-Login` (the requester's login name, such as `alice@example.com`), `Tailscale-User-Name` and `Tailscale-User-Profile-Pic`. Serve **removes** these headers when the incoming request already has them, so a sender can't spoof them through Serve.
- They aren't set for traffic from **tagged devices**, nor for Funnel (public) traffic. They are set for users who accepted a share of the device, which is why shipyard compares the login with the Mac's own rather than only checking it's present.
- Non-ASCII values may be RFC 2047 "Q"-encoded (`=?utf-8?q?…?=`). Logins are e-mail-like and ASCII in practice; shipyard compares the header as is.
- Tailscale's advice: a service that trusts these headers should listen on localhost only, since anyone who can reach it directly could set them. Shipyard binds 127.0.0.1.

## The Mac's own login

`tailscale status --json` (1.102.4) has, among others, `BackendState` (`Running`, `Stopped`, `NeedsLogin`, …), `Self` (this device; its `UserID` is a number) and `User` (a map from user ID, as a string, to `{"ID", "LoginName", "DisplayName", "ProfilePicURL"}`). The Mac's own login is `User[String(Self.UserID)].LoginName`, while `BackendState` is `Running`. On the Standalone variant `/usr/local/bin/tailscale` is a small script that runs the app's binary; the app's binary itself (`/Applications/Tailscale.app/Contents/MacOS/Tailscale`) acts as the CLI.
