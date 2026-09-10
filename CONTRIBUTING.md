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

### Run the checks

Use Node.js 22+ and Python 3.8+ for the core checks, from the repository root:

```sh
node audit/run-audit.mjs
python audit/test_server.py
```

Use `python3` if that is your Python command. The first command tests the
accounting, reporting and asynchronous save functions with synthetic fixtures.
The second starts temporary loopback servers and verifies real save/load,
concurrent edits, backup rotation and restoration, and interrupted uploads.
Neither command reads your budget.

Browser checks need Python 3.12+ and optional development dependencies:

```sh
python -m venv .venv
# Activate: .venv\Scripts\activate on Windows; source .venv/bin/activate on macOS/Linux
python -m pip install -r audit/requirements.txt
python -m playwright install chromium
python audit/run_browser.py
```

On Linux, use `python -m playwright install --with-deps chromium` if system
browser libraries are missing. `run_browser.py` creates and cleans up its own
scratch server on a free port. It runs responsive/theme checks and a browser
save/conflict/restore scenario. There is no need to start your normal server.
To use an installed Edge or Chrome, set `BROWSER_CHANNEL=msedge` or `chrome`.

The **Checks** workflow runs on pull requests and pushes to `main`: core checks
on Windows, macOS and Linux, plus Chromium browser checks on Linux. The workflow
definition is not a claim that every platform has already passed locally.

### A first contribution

Start with [ROADMAP.md](ROADMAP.md). Useful contributions include a clearer
first-budget walkthrough, synthetic bank-import examples, and additional browser
coverage. For a larger feature, describe the intended behavior in a Discussion
before implementing it. Improvements that help other households are welcome
when they preserve accurate accounting, local ownership and the small runtime.

For code changes, start at the relevant helper in `CLAUDE.md`, add a synthetic
example that demonstrates the problem, then change the behavior and run the
checks above. Describe the expected numbers in your pull request so another
person can verify them without sharing a real budget.

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
