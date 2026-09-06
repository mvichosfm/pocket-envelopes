# Contributing

Thanks for looking. This is a small, opinionated project maintained by one
person who runs their own household budget on it, so the bar for changes is
"does this keep my money right", not "is this feature nice". Bug reports with
a reproduction are always welcome; feature proposals are welcome too, but
expect some to be declined to keep the app small.

## Ground rules

- **One file, no build.** `pocket-envelopes.app` stays a single HTML file
  with inline CSS and JS. No bundler, no modules, no npm. The one dependency
  (Chart.js) is vendored under `vendor/`.
- **Stdlib-only Python.** `serve.py` must run on a bare Python 3.8+ with no
  `pip install`.
- **Local only.** No outbound network calls, no telemetry, no accounts.
- **Money logic is measured, not guessed.** If a change touches balances,
  forecasting or close-out, say in the pull request what you expected the
  numbers to do and what they did. `CLAUDE.md` records every past decision
  of that kind and why; read the relevant entry before changing behaviour it
  describes, and add an entry if you change a rule.
- **Never quote a real budget in a commit or an issue.** Use the demo data
  (`?demo=1`) or synthetic round numbers.

## Working on it

1. Clone, then run `./launch.sh` (macOS/Linux) or `launch.bat` (Windows).
   The app opens at `http://localhost:8765/`.
2. Do your testing against a scratch copy, not your own budget: copy
   `serve.py`, `pocket-envelopes.app` and `vendor/` into another folder and
   run it on a different port (`PORT=8799 python serve.py`). Or use
   `?demo=1`, which never writes to the server.
3. `node audit/run-audit.mjs` syntax-checks the app and unit-tests the
   accounting helpers. Run it before opening a pull request.
4. If you change anything the service worker caches (the app file, the
   vendored chart library, icons, manifest), bump `CACHE_NAME` in `sw.js`.

`CLAUDE.md` is the developer guide: architecture invariants, data model,
helpers worth knowing, and the decision log. It is written for coding
assistants as much as for people; `AGENTS.md` points at it for tools that
look for that name.

## Pull requests

- Keep them focused: one fix or one feature.
- Describe the behaviour before and after, not just the diff.
- Include what you tested and how (which tab, which data).
- Update the in-app Help tab and the README if the change is user-visible,
  and add a line to `CHANGELOG.md`.

## Reporting bugs

Open an issue with your OS, Python version, browser and version, whether the
server runs locally or behind `tailscale serve`, and the steps to reproduce
on the demo data if at all possible. For anything that could expose
financial data, see `SECURITY.md` instead.
