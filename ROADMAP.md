# Road to 1.0

Pocket Envelopes aims to be a dependable household budgeting app that keeps
your data on your own machine. A 1.0 release needs evidence that people can
set it up, trust its numbers, and recover their budget independently.

This is a readiness checklist, not a release-date promise. Checked items below
are implemented in the working tree; see CHANGELOG.md for released versions.

## Reliability milestone

- [x] Serialize saves and preserve newer edits until their own save succeeds.
- [x] Preserve genuine conflicts for the user to resolve explicitly.
- [x] Count UTF-8 bytes for the browser's keepalive limit; handle interrupted loads.
- [x] Show twelve distinct reporting months, including month-end/leap dates.
- [x] Keep scheduled transactions out of actual-spending figures until their date.
- [x] Treat envelope reallocations and sweeps as reservations, not spending.
- [x] Exercise disk save/load, concurrent edits, backup rotation and restoration
  with disposable budgets, plus browser save/conflict/restore checks.
- [x] Add pull-request checks for Windows, macOS and Linux and browser checks for Chromium.
- [ ] Observe the new workflow passing on GitHub and configure required checks.
- [ ] Recheck and triage the remaining findings in the September review before
  claiming the audit backlog is resolved.

The historical [review](docs/REVIEW-360-2026-09-10.md) describes an older commit;
its findings are not all current bugs. Its status note records the fixed groups.
Further audit fixes should get a reproduction and regression check before
being marked complete.

## Newcomer milestone

- [ ] A short walkthrough from an empty budget to a useful forecast, with
  synthetic figures and explicit explanations of the forecast assumptions.
- [ ] A public demo that only uses synthetic data and cannot access a real budget.
- [ ] Five independent setup trials across different households and supported
  platforms; record anonymized friction and fix the common problems.
- [ ] Verify keyboard-only navigation and document Firefox/Safari coverage.

For each setup trial, ask the participant to create an account and envelope,
fund it, record a purchase, explain the spendable figure, and export/restore
their sample budget. Record success, where they needed help, and their platform.
Use synthetic finances; do not collect their real budget. Recruitment and trial
results are still pending.

## Useful first contributions

| Contribution | Done when |
| --- | --- |
| First-budget walkthrough | A newcomer can follow it with synthetic numbers and reproduce the stated balances. |
| CSV import examples | Synthetic comma/semicolon, debit-credit and date-format fixtures cover documented import behavior. |
| More browser coverage | The isolated browser checks run under Firefox or WebKit and any differences are documented. |

## Current limits

There is no authentication or public hosting support for real budgets. Runtime
dependencies remain vendored Chart.js and standard-library Python. Financial
data has not changed schema in this milestone.

A page closed while a save is in flight, or while a budget exceeds the browser's
keepalive byte limit, can still lose a last unsaved edit. The saved indicator
must stay honest; full offline editing or durable queued writes require separate
design work. Browser daily backups are supplementary and can be lost when
browser storage is cleared; disk backups and explicit exports remain important.
