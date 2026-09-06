# Security

Pocket Envelopes is a local-first personal-finance app. This page says what
that means in practice, so you can decide how to run it.

## Threat model in one paragraph

The app is a single HTML file served by a small Python process that also
owns your budget, `finance-data.json`. **There is no authentication of any
kind.** Whoever can open the server's port can read and overwrite your
finances through the `/data` API. Access control is therefore entirely about
*who can reach the port*, and the defaults are chosen accordingly:

- `serve.py` binds to `127.0.0.1` — only the machine it runs on can reach it.
- The launchers (`launch.bat`, `launch.sh`, `serve-daemon.cmd`) pin that bind.
- The data file, its rotating backups, log files and dot-directories are
  refused as static assets, and directory listings are disabled, so the
  budget can only be reached through `/data`.
- The app makes no outbound network calls and loads nothing from a CDN.
  Chart.js is vendored. There is no telemetry.

## What you must not do

- **Do not set `BIND=0.0.0.0` on a network you do not fully trust.** It
  exposes the unauthenticated API to every device on that network.
- **Do not put the port behind a public reverse proxy, and never run
  `tailscale funnel` on it.** The supported multi-device setup is
  `tailscale serve`, which keeps the origin private to your own tailnet while
  the server stays on loopback. See the README.
- Do not commit `finance-data.json` or its `.bak` siblings. The `.gitignore`
  already excludes them.

## What the app protects against

- **Torn writes**: saves go to a temp file, are `fsync`ed, then atomically
  renamed; the previous five versions rotate into `finance-data.bak.0…4`.
- **Concurrent edits**: every save carries an `If-Match` ETag; a stale save
  is refused with `409` and a dialog, never silently merged.
- **Malformed data**: the server rejects non-JSON bodies and oversized
  bodies; the app validates the structure before migrating it and refuses
  a corrupt file rather than "fixing" it.
- **Injection**: every user-supplied string rendered into HTML goes through
  `esc()`. Payees, notes, envelope, account and tag names are all escaped.

## The Windows installer

The installer is not code-signed, so SmartScreen shows an "unrecognised
publisher" warning. Each release page prints the installer's SHA-256; check
it before running, or build the installer yourself from the repository with
`installer\build.ps1` (it fetches only the official python.org runtime and
verifies that download against a pinned hash). The installer writes only to
your user profile and adds no services, drivers or firewall rules; the
bundled server binds to `127.0.0.1` like every other way of running it.

## Reporting a vulnerability

Please do not open a public issue for anything that could expose someone's
financial data. Use GitHub's private vulnerability reporting on this
repository ("Security" tab → "Report a vulnerability"). Include the version
(commit) and a way to reproduce. Only the latest commit on `main` is
supported; there are no backported fixes.
