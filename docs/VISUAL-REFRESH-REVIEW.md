# Visual refresh — review checklist

Landed on `main` as commit `654b589` (2026-09-10); reviewed the same day (see CLAUDE.md decision #51 and the CHANGELOG).

Open **http://127.0.0.1:8765/?demo=1** while the server is running from
this checkout. The demo is synthetic and does not read or write the real
budget. Refreshing resets the demo.

## The ten proposals

| # | Change | Where to review |
|---|---|---|
| 1 | Responsive cards and forecast controls eliminate page-wide overflow. Tables retain scrolling inside their cards. | Forecast and Reports at 390px and 320px; all other views were also checked. |
| 2 | Spendable cash is the dashboard's main panel; wealth totals are secondary. | Dashboard: recorded spendable today, projected low, low date, exact horizon and assumptions. |
| 3 | Horizon controls sit above the chart. Profiles, accounts and assumptions occupy a readable vertical panel, initially collapsed on phones. | Forecast: change horizons, accounts, chart lines and allowances; open sections stay open. |
| 4 | Envelope balances explicitly say Available. Spending text says how much of the monthly budget has been spent, with Today labelling the pace tick. | Envelopes: monthly, annual and unbudgeted/reserve cards. |
| 5 | Desktop navigation groups Everyday, Explore and administration. Phones have four direct destinations plus More. | Resize below 720px; use More to reach Accounts, Recurring, Net Worth, Reports, Settings and Help. |
| 6 | Bulk controls appear only after selection. Search remains visible; Filters holds secondary controls and shows their active count. | Transactions: filter, collapse filters, edit a row, select rows, clear selection. |
| 7 | Supporting copy is larger, labels use sentence case, and charts inherit readable theme colours and type. | Toggle light/dark; compare cards, chart axes, legends and forms. |
| 8 | The main cash panel, quieter wealth strip, consistent spacing and simpler card hierarchy distinguish primary from supporting information. | Dashboard and Envelopes on desktop and phone. |
| 9 | One Needs attention panel replaces the two full-width dashboard banners. Its buttons name the review action. | Dashboard: Review the previous month and Review recurring. Existing review dialogs still control changes. |
| 10 | Transaction entry features the amount, groups allocations, expands optional notes and keeps actions visible. Validation remains beside the field. | Add transaction: try an empty amount, `12+`, `50+12`, unbalanced splits and same-account transfers. |

## Financial meaning preserved

- No accounting engine, server API or data-schema change.
- Spendable today uses **recorded** balances less **positive** envelope
  reservations, respecting backing accounts and archived reservations.
- The projected low uses the existing forecast engine, including due entries
  still to be recorded. A pending bill can make the starting projection differ
  from recorded cash; that difference is intentional.
- The Dashboard uses the selected accounts, allowance setting and **exact**
  horizon. An explicitly empty account selection stays empty. Chart-line
  visibility does not hide its spendable summary.
- A low is not labelled as a guaranteed maximum amount to fund. Fund the month
  still recalculates the effect of the proposed funding.
- Incomplete splits and invalid calculations are refused without clearing the
  form. Valid transactions use the existing save/undo path.

## Validation

- Existing mechanical/accounting audit: **22 passed, 0 warnings, 0 failures**.
- Browser smoke suite: **108 passed**, including 80 layout combinations
  (10 views × 4 widths × 2 themes), selection/filter behaviour, entry/edit,
  calculations, notes, split and transfer validation, short-viewport footer,
  mobile navigation, forecast state and actual-versus-projected cash.
- Browser suite blocks every `/data` request and verifies none was attempted.
- No browser runtime errors during the smoke suite.
- Desktop and phone screenshots inspected during development. The five README
  screenshots are refreshed from demo data.
- Mobile checks use browser viewport emulation; a physical phone keyboard and
  installed PWA should receive a final hands-on check before release.

Repeat the checks with a running local server:

```text
node audit/run-audit.mjs
python audit/visual-smoke.py
python screenshots/capture.py
```

The two Python browser helpers need the same optional Playwright environment.
Set `BROWSER_CHANNEL=msedge` or `chrome` to use an installed browser, or install
Playwright's Chromium. There are no new application dependencies.

## Suggested review order

1. Dashboard in both themes: is the emphasis on spendable cash useful?
2. Envelopes: compare Available with Spent and the Today marker.
3. Forecast: try one week, different accounts and the allowance switch.
4. Transactions: filter, add, edit and deliberately trigger an error.
5. Phone layout: use all five bottom-navigation destinations, scroll Reports,
   open a transaction and confirm the keyboard leaves the action accessible.
