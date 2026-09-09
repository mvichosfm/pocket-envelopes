# Changelog

All notable changes, newest first. Dates are when the change landed in the
author's working copy; the public repository starts from the 2026-09-06
state. Changes that touch how money is counted are marked **(accounting)**,
because those are the ones worth re-checking your own figures after.

## Unreleased

- **A hand-typed bill can be linked to its due occurrence.** The due review
  now spots a transaction you entered by hand that looks like a due
  occurrence (same type and account, the same amount to the cent, dated
  within three days of the schedule, not itself generated from a recurring)
  and offers **Link** as that row's default. Applying it marks your
  transaction as the record of the occurrence, so the due clears and the
  forecast stops counting the bill twice **(accounting: forecast start
  point only, and only when you choose Link)**. The dashboard banner says
  how many due entries look already recorded. The match is offered, never
  applied on its own, and is one undo step with the rest of the review.
- **Faster renders on large files.** Account and envelope balances are
  computed once per render instead of once per place that shows them; no
  figure changes.

## 2026-09-09 — v0.7.1, budget vs actual at a glance

- **Budget vs actual reads at a glance.** Each Spent figure carries a bar
  of the budget beneath it (ochre when ahead of the calendar in the current
  month, red past the budget, with the month-progress tick from the envelope
  cards), rows that went over are tinted, and the Over / under column says
  "€50.00 over" or "€150.00 under" instead of a signed number whose colour
  had to be decoded.

## 2026-09-09 — v0.7.0, one typeface, one icon set, a phone header and a day-grouped ledger

- **One typeface.** Figures, table headings and card captions no longer
  switch to a monospace face; everything is the UI font with tabular
  numerals, so amounts still align on the decimal without the terminal look.
- **Transactions grouped by day.** The list gets one heading per day
  (Today, Yesterday, Tomorrow, else the date with its weekday; future days
  say "scheduled"), the date column goes, the type is a coloured dot (red
  expense, green income, blue transfers; the word is in the tooltip and for
  screen readers), and on screens wide enough for the table to fit, the
  column header stays put under the app header while the list scrolls.
- **One icon set.** The pushpin and moon emoji, the text drag handle and the
  arrow, bolt and cross glyphs are replaced by a small inline SVG set that
  takes the colour of its text in both themes.
- **A one-row phone header.** Below 720px the title, status and the
  Reload / Save / theme buttons share one row (the buttons shrink, the
  status truncates, and under 460px it collapses to its coloured dot unless
  there is a conflict), and the tab strip scrolls without a scrollbar, with
  edge fades that say there is more on that side. The active tab is
  scrolled into view when a drill-through or a link lands on it.

## 2026-09-09 — v0.6.1, tag limit setting, header fix, honest signing note

- The README no longer claims SignPath code signing: the application was
  declined, so the installer stays unsigned and the release page's SHA-256
  is the verification. The workflow's signing job stays dormant.
- **The tag limit is a setting.** Settings → Tag limit (1–50, default 8)
  replaces the fixed cap of eight. Lowering it below the tags you already
  have keeps them all and only disables "+ Add tag"; chip and chart colours
  repeat after the eighth tag.

- The tab strip takes its own row up to 1440px wide (was 1380px): between
  the two, a long status label pushed the Help tab off the header.
- README screenshots regenerated for the v0.6.0 look; the Playwright script
  that makes them now lives in `screenshots/capture.py`.

## 2026-09-08 — v0.6.0, pace bars, a marked forecast low, a lighter light theme

- **Envelope cards show the month's pace.** The printed-tint fill (a hatch
  whose height was balance ÷ budget) is replaced by a small bar of this
  month's spending against this month's budget, with a tick at how far
  through the month we are. Ochre when spending runs ahead of the calendar,
  red once past the budget. A coloured spine on the card's left edge keeps
  the old warning: red for a negative balance, ochre for under a quarter of
  the budget. No figures changed.
- **The forecast chart marks its low point.** A dot and a "Lowest … · date"
  label on the featured line (spendable when it is drawn, otherwise the
  combined total), the area under a sole line is shaded, a dashed zero line
  appears whenever the chart crosses zero, and the axis reads "16 Sep" instead
  of a rotated ISO date (the year joins in only when the horizon crosses into
  another year).
- **The dashboard's "lowest in period" tile is coloured by meaning.** It used
  to carry a red or amber border whatever the figure was. Now it is neutral
  when the low is fine, amber with "under your … floor" when it dips under a
  new *Forecast warning floor* in Settings (optional), and red with "goes
  below zero" when it does.
- **The light theme lifts off the page.** Cards are white sheets with a
  faint shadow on a cool light-grey ground instead of a slightly lighter
  manila on manila; inputs, buttons and tiles sit on a distinct inset tone,
  borders are a step darker, and secondary buttons keep a visible edge on
  hover. Ink and the darker semantic colours are unchanged.
- **Three buttons per card, not six.** Spend, Fund and Return stay; Edit,
  Archive and Delete move under a "⋯" menu (Escape or a click elsewhere
  closes it). The dimmed buttons they replace were near-invisible in the
  light theme and wrapped onto a second line on phones.

## 2026-09-08 — v0.5.0, backed envelopes and archiving

- **Archive instead of delete.** Accounts and envelopes gain an Archive
  button (Accounts row, envelope card). Deleting is still refused while
  history points at the record; archiving keeps every transaction and every
  figure and only hides the record from lists, pickers, the dashboard strip,
  Fund the month, close-out and the forecast's account selection. An
  archived envelope also has no budget any more, so it leaves the monthly
  totals and the forecast's allowances **(accounting, budget totals only —
  balances and net worth are unchanged)**; its balance stays earmarked until
  you ↩ Return it. Archived records sit in a collapsed list at the bottom of
  their tab with an Unarchive button; editing an old transaction still
  offers its archived account or envelope, marked "(archived)". The reserve
  envelope, and anything an active recurring entry still posts to, cannot
  be archived until that is changed first. Undoable both ways.
- **Envelopes can be backed by an account (accounting, forecast only).**
  A new *Backed by account* field in the envelope dialog names the account
  that holds an envelope's money. A forecast that selects only some accounts
  now subtracts only the envelopes those accounts hold (plus every
  *Household* envelope, the default), and drains a backed envelope's
  allowance from that account. Before, a per-person forecast profile charged
  every envelope in the file against one partner's cash, so spendable came
  out too low and Fund the month warned against money that was there. With
  every cash account selected, or with no backing set, the figures are
  unchanged to the cent. The Forecast tab lists what a selection left out.
  The reserve envelope is always household-wide.

## 2026-09-08 — v0.4.0, skips, month-aware envelopes, a stronger Transactions tab

- **Skip an occurrence** in the due-recurring review. Each due row now has
  Record / Skip / Decide later; a skipped occurrence (a waived fee, a month
  you paid nothing) stops being offered instead of reappearing in every
  review. Skips live in `rec.skippedDates` until the recurring's applied
  watermark passes them. The whole review is one undo step. The Recurring
  tab has a matching ⏭ button per row that skips the next occurrence, due
  or upcoming, without opening the review.
- **Envelope cards show this month's spending** ("spent €97.30 this month ·
  €502.70 of budget left"), and Reports gains a **Budget vs actual** table
  for any month — the same figures the close-out review uses.
- **Transactions tab**: filters survive edits (they used to reset after every
  save), a from / to date range with a "This month" shortcut, cash in / out /
  net for the rows shown, and the search box matches amounts. Same-day rows
  no longer reshuffle when you type in the search box.
- **Bulk edit**: tick rows, then set a tag or an envelope for all of them or
  delete them — one undo step each. Envelope changes leave transfers and
  split transactions alone and say so.
- **Drill-through**: account and envelope names on the Accounts tab, the
  envelope cards, both dashboard tables and the new report open Transactions
  pre-filtered. `?view=transactions&acc=…&env=…&tag=…&q=…&from=…&to=…`
  does the same from a bookmark.
- **Payee picker + looser matching**: the payee field suggests every payee
  you have used, and auto-fill now matches a bank description that merely
  contains a prior payee ("CARD 1234 SUPERMARKET 12/08" → Supermarket), so
  CSV import finally learns from history.
- **Scheduled transactions**: anything dated after today is badged
  "scheduled" and dimmed in both transaction lists, and the Accounts tab
  shows the net scheduled amount under each balance — balances have always
  excluded future-dated entries; now the lists say so.
- **Redo** (Ctrl+Y or Ctrl+Shift+Z, also in the command palette), and "Reset
  all data" is undoable until you reload.
- Dashboard copy: the "Lowest spendable" tile no longer claims to be the
  "max safe to allocate today" or that spendable "drops by the funded
  amount" — neither has been true since the per-envelope floor (the Fund
  modal re-forecasts instead). The Help FAQ and the Fund modal tip say the
  same.
- The per-account **Currency** field is hidden: nothing converted by it, so
  it implied FX that never happened. Stored values are untouched.
- Light theme: text on solid primary / danger buttons, the completed
  onboarding step marker and the CSV-import "dup?" badge is now white. It
  was a hardcoded near-black ink that only ever suited the dark theme's
  paler fills, so "+ Add transaction" and friends were dark-on-dark on
  paper. A new `--on-fill` token carries the ink colour per theme.

## 2026-09-06 — v0.3.0, Windows installer

- A Windows installer (`PocketEnvelopes-Setup-<version>.exe`, built by
  `installer\build.ps1` with Inno Setup): per-user, no administrator rights,
  no Python to install — it bundles the official embeddable CPython runtime.
  Start-menu shortcut starts the server if needed and opens the app; optional
  desktop shortcut and sign-in autostart; upgrades and uninstalls stop a
  running server first; the uninstaller keeps your budget.
- `serve.py` honours `DATA_DIR`: the installer keeps the budget in
  `%LOCALAPPDATA%\PocketEnvelopes` instead of the program folder. A source
  checkout is unchanged (default is still next to `serve.py`).

## 2026-09-06 — v0.2.0, public release

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
