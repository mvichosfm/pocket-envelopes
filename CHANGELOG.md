# Changelog

All notable changes, newest first. Dates are when the change landed in the
author's working copy; the public repository starts from the 2026-09-06
state. Changes that touch how money is counted are marked **(accounting)**,
because those are the ones worth re-checking your own figures after.

## 2026-09-06 — public release

- Transaction **tags**: one optional tag per transaction or recurring entry,
  from a short user-defined list (up to eight). Filter and search by tag, a
  by-tag spending doughnut and a month-by-tag table in Reports, a tag picker
  on the transaction, recurring and CSV-import forms, last-used tag suggested
  per payee. Tags apply to transfers too; a tagged transfer counts as outflow
  for its purpose in the tag reports.
- Reports doughnuts are now destroyed on view switch (they leaked one chart
  instance per visit).
- Server binds to `127.0.0.1` by default and refuses to serve the data file,
  its backups, logs and dot-directories as static assets.
- First-run locale follows the browser instead of a fixed one.
- Help tab and README brought up to date; Chart.js license text vendored.

## 2026-09-01

- The close-out review dialog is wider and restacks on narrow screens
  instead of scrolling sideways past its only control.

## 2026-08-19

- **(accounting)** The forecast no longer charges the current month's
  allowance twice: it drains what is *left* of each envelope's budget, not a
  fresh full month on top of spending already in the balances.
- A **reserve envelope** (emergency / catch-all) with a `sweep` close-out
  policy: leftovers move into it as envelope-to-envelope transfers, and an
  overspent envelope is brought back to zero out of it.

## 2026-08-15

- Server-backed persistence: `serve.py` owns `finance-data.json` behind
  `GET`/`PUT /data` with atomic writes, five rotating backups and ETag
  concurrency (a stale save gets a conflict dialog, never a silent merge).
  Replaces the browser File System Access path.
- Installable as a PWA: manifest, icons, and a service worker that caches the
  app shell network-first and never caches the data.
- Multi-device access through `tailscale serve`, loopback bind, a windowless
  always-on launcher for Windows.
- Renamed to Pocket Envelopes.

## 2026-08-01

- **(accounting)** "Fund the month" assigns the budgeted amount rather than
  topping up to the budget, so last month's overspend is felt this month.
- **(accounting)** The Fund dialog re-runs the forecast with the proposed
  funding instead of estimating it arithmetically; the estimate had been
  wrong by up to the whole amount being funded.
- **(accounting)** Envelope bookkeeping (returns, close-out adjustments) no
  longer counts as spending in Reports or close-out.
- **(accounting)** Recurring entries on specific months no longer drop
  occurrences when the months were typed out of order.
- **(accounting)** The spendable forecast no longer charges funded envelopes
  twice; each envelope has its own projected series, floored at zero.
- Envelope balances shown in the transaction form's envelope dropdown.

## 2026-07-01

- The Recurring tab shows overdue occurrences instead of hiding them behind a
  future "Next" date.
- No-cache headers so edits to the app file are never served stale.

## 2026-06-01

- Command palette (Ctrl/Cmd-K).
- Schema validation and a corrupt-file guard.
- Split transactions across several envelopes.
- CSV bank-statement import with a column-mapping wizard and saved profiles.
- Auto theme following the system preference.
- Draggable and resizable dialogs on desktop.

## 2026-05-31

- A full review pass: undo now covers add/edit transaction and close-out; the
  due-review partial apply no longer buries skipped occurrences; a NaN guard
  on investment value updates; light-theme contrast; accessibility and
  keyboard fixes.
- Per-envelope "Return to spendable" and a balance-adjust dialog.

## 2026-05-27 — v0.1.0

- Undo (Ctrl-Z and an Undo toast), rolling daily backups in the browser,
  flush-on-close, DST-safe day arithmetic. First tagged version.
