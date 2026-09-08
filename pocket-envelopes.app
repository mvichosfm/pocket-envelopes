<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Pocket Envelopes</title>
<!-- Installable-app metadata. Only takes effect over a secure origin, which on
     the tailnet means the https://<host>.ts.net URL that `tailscale serve`
     publishes; plain http://host:8765 still works, just not installable. -->
<link rel="manifest" href="manifest.webmanifest">
<link rel="icon" type="image/png" href="icons/icon-192.png">
<link rel="apple-touch-icon" href="icons/icon-180.png">
<!-- Tints the browser/OS chrome around the app. Two entries so the bar follows
     the OS scheme, matching the app's own 'auto' theme default. -->
<meta name="theme-color" content="#0f1419" media="(prefers-color-scheme: dark)">
<meta name="theme-color" content="#f6f8fa" media="(prefers-color-scheme: light)">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Envelopes">
<!-- First-paint theme: follow the OS until the data file's saved preference loads
     (applyTheme() then resolves dark/light/auto). Avoids a dark flash on light systems. -->
<script>try{document.documentElement.dataset.theme=matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';}catch(e){}</script>
<script src="vendor/chart.umd.min.js"></script>
<style>
  /* ── "Security tint" ─────────────────────────────────────────────────────
     The palette is taken from the object this app is about: a paper envelope.
     Ink navy is the inside of the envelope, manila is the paper itself, and
     the blue is the security tint printed inside bank envelopes so the
     contents can't be read through them. That blue is the interactive colour
     AND the material the envelope cards fill with — see .envelope below.
     Semantics stay separated so nothing has to do double duty: blue acts,
     green credits, red debits, ochre warns.                                  */
  :root {
    --bg: #0d131f;          /* ink — envelope interior */
    --bg-2: #141c29;
    --bg-3: #1e2836;
    --border: #2c3746;
    --text: #e8edf4;
    --text-dim: #8e9bad;
    --accent: #5b93c7;      /* security tint — interactive */
    --accent-2: #7fa8ce;
    --warn: #d9a441;
    --bad: #d2685c;         /* stamp red */
    --good: #6baf7f;        /* ledger green */
    --on-fill: #08110d;     /* ink on a solid accent/warn/bad/good fill */
    --manila: #d9c89e;      /* the paper — structural, never semantic */
    --manila-soft: rgba(217, 200, 158, .13);
    --shadow: 0 4px 16px rgba(0,0,0,.35);
    --radius: 10px;
    --chart-grid: rgba(255,255,255,.06);
    --chart-total: #d9c89e;
    /* Money and data are set in a tabular mono so decimal columns line up the
       way they would in a ledger. Body copy stays in the UI sans. */
    --font-mono: ui-monospace, "SF Mono", "Cascadia Mono", "Segoe UI Mono", "Roboto Mono", Menlo, Consolas, monospace;
  }
  /* Light: white sheets on a cool light-grey desk. The first light theme was
     manila stock with a barely lighter sheet on it; cards had almost no
     separation from the page and the secondary buttons vanished into it.
     Cards now lift off the ground with a faint shadow (--shadow-card, light
     only), inputs and buttons sit on a distinct inset tone, and borders are
     a full step darker than the surfaces they divide. Ink and the darker
     semantic tones are unchanged — they already passed AA on white. */
  [data-theme="light"] {
    --bg: #eceef2;          /* the desk */
    --bg-2: #ffffff;        /* the sheet */
    --bg-3: #eef1f5;        /* insets: inputs, buttons, tiles, badges */
    --border: #c9d2dd;
    --text: #1b222e;        /* ink */
    --text-dim: #5c6472;
    --shadow: 0 6px 20px rgba(20,30,50,.14);
    --shadow-card: 0 1px 2px rgba(20,30,50,.05), 0 3px 10px rgba(20,30,50,.06);
    /* Darker semantic tones — the dark-mode hues fail WCAG AA on paper. */
    --accent: #1f5f94;
    --accent-2: #0f4c81;
    --warn: #8a6516;
    --bad: #b3453a;
    --good: #2e7d4f;
    --on-fill: #ffffff;     /* the light fills are dark, so the ink on them is white */
    --manila: #8a7c58;
    --manila-soft: rgba(20, 30, 50, .06);
    --chart-grid: rgba(0,0,0,.07);
    --chart-total: #8a6516;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; background: var(--bg); color: var(--text);
    font: 14px/1.4 -apple-system, "Segoe UI", Roboto, sans-serif; }
  button { font: inherit; color: inherit; cursor: pointer; }
  input, select, textarea { font: inherit; color: inherit; }
  a { color: var(--accent-2); }

  header.top {
    background: var(--bg-2); border-bottom: 1px solid var(--border);
    padding: 0 20px; display: flex; align-items: stretch; gap: 16px;
    position: sticky; top: 0; z-index: 50; min-height: 48px;
    /* Installed on iOS the app runs under a translucent status bar
       (viewport-fit=cover + black-translucent), so the header must reserve the
       notch/clock height or the title sits underneath it. env() resolves to 0
       in a normal browser tab, so this is inert everywhere else. */
    padding-top: env(safe-area-inset-top, 0px);
    padding-left: calc(20px + env(safe-area-inset-left, 0px));
    padding-right: calc(20px + env(safe-area-inset-right, 0px));
  }
  /* Same idea at the bottom: keep content clear of the iOS home indicator. */
  main { padding-bottom: env(safe-area-inset-bottom, 0px); }
  header.top h1 { font-size: 16px; margin: 0; font-weight: 650;
    display: flex; align-items: center; flex-shrink: 0; letter-spacing: -.015em; }
  /* A hairline of manila under the header: the edge of the paper. */
  header.top { border-bottom-color: var(--border); box-shadow: 0 1px 0 var(--manila-soft); }
  nav.tabs button { letter-spacing: .01em; }
  header.top .file-status { align-self: center; flex-shrink: 0; }
  header.top > button.btn { align-self: center; flex-shrink: 0; }
  .file-status { font-size: 12px; color: var(--text-dim); display: flex; align-items: center; gap: 6px; }
  .file-status .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--text-dim); }
  .file-status.saved .dot { background: var(--good); }
  .file-status.unsaved .dot { background: var(--warn); }
  .file-status.no-file .dot { background: var(--bad); }
  .file-status.conflict { cursor: pointer; color: var(--warn); }
  .file-status.conflict .dot { background: var(--warn); animation: pulse 1.6s ease-in-out infinite; }
  /* Below 720px the desktop one-row layout runs out of room. Stack: title +
     status + buttons on row 1; horizontally-scrolling tabs on row 2. */
  @media (max-width: 720px) {
    header.top { flex-wrap: wrap; padding: 8px 14px; gap: 8px; min-height: 0;
      padding-top: calc(8px + env(safe-area-inset-top, 0px));
      padding-left: calc(14px + env(safe-area-inset-left, 0px));
      padding-right: calc(14px + env(safe-area-inset-right, 0px)); }
    header.top nav.tabs { order: 99; flex-basis: 100%; }
    header.top h1 { font-size: 15px; }
    header.top .file-status { font-size: 11px; }
  }
  /* Between ~720px and ~1380px the single-row header can't fit the title +
     status + buttons + all 10 tabs, so the tab strip would clip behind a
     horizontal scrollbar (1280px laptops hit this). Drop the tabs to their own
     full-width row — without the small-screen font shrink above. */
  @media (min-width: 721px) and (max-width: 1380px) {
    header.top { flex-wrap: wrap; }
    header.top nav.tabs { order: 99; flex-basis: 100%; }
  }
  .file-status.conflict:hover { color: var(--text); }
  @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: .35; } }

  .btn { background: var(--bg-3); color: var(--text); border: 1px solid var(--border);
    padding: 7px 12px; border-radius: 7px; font-size: 13px; transition: .15s; }
  .btn:hover { background: var(--border); }
  .btn.primary { background: var(--accent); border-color: var(--accent); color: var(--on-fill); font-weight: 600; }
  .btn.primary:hover { filter: brightness(1.08); }
  .btn.danger { color: var(--text-dim); border-color: var(--border); background: transparent; }
  .btn.danger:hover { color: var(--bad); border-color: var(--bad); background: rgba(224,108,117,.08); }
  .btn.danger.solid { background: var(--bad); border-color: var(--bad); color: var(--on-fill); font-weight: 600; }
  .btn.danger.solid:hover { filter: brightness(1.08); background: var(--bad); color: var(--on-fill); }
  .btn.ghost { background: transparent; border: 1px solid transparent; color: var(--text-dim); }
  .btn.ghost:hover { color: var(--text); background: var(--bg-3); }
  [data-theme="light"] .btn.ghost:hover,
  [data-theme="light"] .btn.ghost:focus-visible { border-color: var(--border); }
  [data-theme="light"] .btn:not(.primary):not(.ghost) { background: var(--bg-2); }
  [data-theme="light"] .btn:not(.primary):not(.ghost):hover { background: var(--bg-3); }
  .btn.sm { padding: 4px 8px; font-size: 12px; min-height: 24px; }
  .btn.icon { padding: 4px 6px; font-size: 14px; line-height: 1; min-width: 24px; min-height: 24px; }
  /* WCAG 2.5.8 wants ≥24px targets; touch (coarse) pointers want roomier ones. */
  @media (pointer: coarse) {
    .btn.sm, .btn.icon { min-height: 32px; }
    .btn.icon { min-width: 32px; }
  }
  .btn.selected { background: var(--bg-3); border-color: var(--accent); color: var(--accent); font-weight: 600; }
  .btn.selected:hover { filter: none; background: var(--bg-3); }

  nav.tabs {
    display: flex; gap: 4px; overflow-x: auto;
    flex: 1; min-width: 0;
  }
  nav.tabs button {
    background: none; border: none; padding: 16px 14px 14px;
    border-bottom: 2px solid transparent; color: var(--text-dim);
    font-size: 13px; font-weight: 500; white-space: nowrap;
  }
  nav.tabs button.active { color: var(--text); border-bottom-color: var(--accent); }
  nav.tabs button:hover { color: var(--text); }

  main { padding: 20px; max-width: 1500px; margin: 0 auto; }
  h2 { margin: 0 0 14px 0; font-size: 22px; font-weight: 700; letter-spacing: -.01em; }
  h3 { margin: 0 0 10px 0; font-size: 15px; font-weight: 700; color: var(--text); }

  .card { background: var(--bg-2); border: 1px solid var(--border); border-radius: var(--radius);
    padding: 14px; box-shadow: var(--shadow-card, none); }
  /* Scroll-shadow hint: when a card's content overflows horizontally, soft
     shadows fade in at the left/right edges so users see scrollable content
     exists. The first two gradients mask the shadows when the card is at
     its scroll start/end (background-attachment:local). */
  .card {
    background:
      linear-gradient(to right, var(--bg-2) 30%, transparent) 0 0 / 40px 100% no-repeat local,
      linear-gradient(to left,  var(--bg-2) 30%, transparent) 100% 0 / 40px 100% no-repeat local,
      linear-gradient(to right, rgba(0,0,0,.18), transparent) 0 0 / 14px 100% no-repeat scroll,
      linear-gradient(to left,  rgba(0,0,0,.18), transparent) 100% 0 / 14px 100% no-repeat scroll,
      var(--bg-2);
  }
  [data-theme="light"] .card {
    background:
      linear-gradient(to right, var(--bg-2) 30%, transparent) 0 0 / 40px 100% no-repeat local,
      linear-gradient(to left,  var(--bg-2) 30%, transparent) 100% 0 / 40px 100% no-repeat local,
      linear-gradient(to right, rgba(0,0,0,.10), transparent) 0 0 / 14px 100% no-repeat scroll,
      linear-gradient(to left,  rgba(0,0,0,.10), transparent) 100% 0 / 14px 100% no-repeat scroll,
      var(--bg-2);
  }
  .grid { display: grid; gap: 14px; }
  .grid.cols-3 { grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); }
  .grid.cols-2 { grid-template-columns: repeat(auto-fit, minmax(380px, 1fr)); }

  /* Figures are the content here, so they get the ledger treatment: tabular
     mono, tightened, with the scale contrast carrying the hierarchy instead
     of colour. Tabular numerals mean a column of amounts aligns on the
     decimal even when the digits differ. */
  .stat { font-size: 26px; font-weight: 600; font-family: var(--font-mono);
    font-variant-numeric: tabular-nums; letter-spacing: -.02em; }
  .stat.lg { font-size: 34px; letter-spacing: -.03em; }
  .stat .currency { color: var(--text-dim); font-size: .65em; margin-left: 4px; }
  /* Eyebrow labels read like the ruled headings on a statement. */
  .stat-label { font-size: 11px; color: var(--text-dim); text-transform: uppercase;
    letter-spacing: .12em; font-family: var(--font-mono); font-weight: 500; }
  .delta { font-size: 13px; margin-top: 4px; }
  .delta.up { color: var(--good); }

  .dash-fc-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 10px; }
  .dash-fc-cell { background: var(--bg-3); border: 1px solid var(--border); border-radius: 8px; padding: 10px 12px; }
  .dash-fc-label { font-size: 11px; color: var(--text-dim); text-transform: uppercase; letter-spacing: .5px; }
  .dash-fc-value { font-size: 19px; font-weight: 600; font-variant-numeric: tabular-nums; margin-top: 2px; }
  .dash-fc-value.neg { color: var(--bad); }
  /* Low-point tiles carry a tone only when there is something to say. */
  .dash-fc-cell.tone-warn { border-color: var(--warn); }
  .dash-fc-cell.tone-warn .dash-fc-value { color: var(--warn); }
  .dash-fc-cell.tone-bad { border-color: var(--bad); }
  .dash-fc-cell.tone-bad .dash-fc-value { color: var(--bad); }
  .dash-fc-note { font-size: 11px; margin-top: 4px; }
  .tone-warn .dash-fc-note { color: var(--warn); }
  .tone-bad .dash-fc-note { color: var(--bad); }
  .dash-fc-delta { font-size: 12px; margin-top: 2px; font-variant-numeric: tabular-nums; }
  .dash-fc-delta.up { color: var(--good); }
  .dash-fc-delta.down { color: var(--bad); }
  .dash-fc-spend { font-size: 11px; color: var(--warn); margin-top: 4px; font-variant-numeric: tabular-nums; }
  .delta.down { color: var(--bad); }

  /* Account drag-and-drop polish — used both on the Dashboard's pinned-accounts
     strip and on the Accounts tab table. The drop-position indicator uses
     box-shadow rather than border so it doesn't shift the row's height (a
     border would, even at 2px). drag-source dims the row being carried;
     drop-above/drop-below draws a 2px accent line on the correct edge of the
     hovered row so it's obvious where it will land. */
  tr.drag-row { cursor: move; }
  tr.drag-row.drag-source { opacity: .35; }
  tr.drag-row.drop-above td { box-shadow: inset 0 2px 0 0 var(--accent); }
  tr.drag-row.drop-below td { box-shadow: inset 0 -2px 0 0 var(--accent); }
  .drag-handle { color: var(--text-dim); margin-right: 6px; cursor: grab; user-select: none; }
  .drag-handle:active { cursor: grabbing; }

  /* Let any wide table inside a card scroll horizontally instead of squishing
     columns or breaking the layout on narrow viewports. Cards with padding:0
     (the table-only ones on Transactions/Recurring) get the scroll directly;
     padded cards just gain horizontal overflow if their table outgrows them. */
  .card { overflow-x: auto; }
  table { width: 100%; border-collapse: collapse; }
  table th, table td { padding: 11px 10px; text-align: left; border-bottom: 1px solid var(--border); font-size: 13px; }
  table th { color: var(--text-dim); font-weight: 500; font-size: 11px;
    text-transform: uppercase; letter-spacing: .12em; font-family: var(--font-mono); }
  table tr:hover td { background: var(--bg-3); }
  /* Amount columns in the ledger face, so they align on the decimal. */
  td.num, th.num { text-align: right; font-variant-numeric: tabular-nums;
    font-family: var(--font-mono); letter-spacing: -.01em; }
  td.actions { text-align: right; white-space: nowrap; }
  .neg { color: var(--bad); }
  .pos { color: var(--good); }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 999px;
    font-size: 11px; background: var(--bg-3); color: var(--text-dim); border: 1px solid var(--border); }
  .badge.invest { color: var(--accent-2); border-color: var(--accent-2); }
  .badge.income { color: var(--good); border-color: var(--good); }
  .badge.expense { color: var(--bad); border-color: var(--bad); }
  .badge.transfer { color: var(--text-dim); border-color: var(--text-dim); }
  .badge.due { color: var(--warn); border-color: var(--warn); }
  /* A transaction dated after today. Balances exclude it (accountBalance /
     envelopeBalance stop at today), so the row must not look like a posted one. */
  .badge.scheduled { color: var(--warn); border-color: var(--warn); border-style: dashed; }
  tr.tx-future td { color: var(--text-dim); }
  tr.tx-future td.num { opacity: .7; }
  /* Drill-through links: an account or envelope name that opens the
     Transactions tab pre-filtered. Looks like text until hovered. */
  a.drill { color: inherit; text-decoration: none; border-bottom: 1px dotted transparent; }
  a.drill:hover, a.drill:focus-visible { color: var(--accent); border-bottom-color: var(--accent); }
  /* Bulk-edit bar on the Transactions tab — appears once a row is ticked. */
  .bulk-bar { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; padding: 8px 12px;
    margin-bottom: 10px; background: var(--bg-3); border: 1px solid var(--accent); border-radius: 7px; font-size: 13px; }
  .bulk-bar select { padding: 5px 8px; background: var(--bg); color: var(--text); border: 1px solid var(--border); border-radius: 6px; }
  .tx-totals { color: var(--text-dim); font-variant-numeric: tabular-nums; display: flex; gap: 10px; flex-wrap: wrap; align-items: baseline; }
  /* Transaction tag chip. --tag-c is set inline per chip from chartPalette()
     (so chip and chart slice share a colour and follow the theme); a stray tag
     with no --tag-c falls back to the plain grey badge. */
  .badge.tag { color: var(--tag-c, var(--text-dim)); border-color: var(--tag-c, var(--border));
    background: color-mix(in srgb, var(--tag-c, var(--text-dim)) 12%, transparent);
    max-width: 140px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; vertical-align: middle; }

  .env-cat-head { display: flex; align-items: baseline; justify-content: space-between; margin: 18px 0 8px; gap: 12px; flex-wrap: wrap; }
  .env-cat-head h3 { margin: 0; }
  .env-cat-summary { font-size: 13px; font-variant-numeric: tabular-nums; }
  /* ── The envelope ────────────────────────────────────────────────────────
     Until 2026-09-08 the card filled bodily with a printed security tint
     (hatching whose height was balance / budget). It looked like the object
     but it read as texture: the level was hard to see, the hatch competed
     with the figures, and it answered "how full is the envelope" when the
     question an envelope budgeter asks mid-month is "how is the month going".
     The card now carries a pace bar (.ev-bar): this month's spending against
     this month's budget, with a tick at how far through the month we are.
     Spending ahead of the calendar turns the bar ochre; past the budget, red.
     A 3px spine on the left keeps the old at-a-glance state: red when the
     balance is negative, ochre when it is under a quarter of the budget. The
     colours stay in CSS via data attributes — no hex reaches JS.           */
  /* overflow: visible overrides the card's scroll-shadow overflow:auto — the
     "⋯" menu drops below the card edge and must not be clipped. */
  .envelope { padding: 14px; position: relative; border-left: 3px solid transparent; overflow: visible; }
  .envelope[data-state="over"] { border-left-color: var(--bad); }
  .envelope[data-state="low"]  { border-left-color: var(--warn); }
  .envelope .ev-head { display: flex; justify-content: space-between; align-items: baseline;
    margin-bottom: 6px; gap: 10px; }
  .envelope .ev-name { font-weight: 600; font-size: 15px; letter-spacing: -.01em; }
  .envelope .ev-bal { font-size: 19px; font-family: var(--font-mono);
    font-variant-numeric: tabular-nums; letter-spacing: -.02em; }
  .envelope .ev-meta { display: flex; justify-content: space-between; font-size: 11px;
    color: var(--text-dim); font-family: var(--font-mono); letter-spacing: .04em;
    margin-top: 10px; padding-top: 8px; border-top: 1px dashed var(--border); }
  /* The pace bar. Track = this month's budget; fill = what is spent of it;
     tick = today's position in the month. Fill ahead of the tick means the
     month is being spent faster than the calendar. */
  .envelope .ev-bar { position: relative; height: 6px; border-radius: 3px; margin-top: 10px;
    background: var(--bg-3); }
  .envelope .ev-bar-fill { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 3px;
    background: var(--accent); transition: width .35s cubic-bezier(.4,0,.2,1); }
  .envelope .ev-bar[data-pace="ahead"] .ev-bar-fill { background: var(--warn); }
  .envelope .ev-bar[data-pace="over"]  .ev-bar-fill { background: var(--bad); }
  .envelope .ev-bar-tick { position: absolute; top: -3px; bottom: -3px; width: 2px; margin-left: -1px;
    background: var(--text-dim); border-radius: 1px; }
  @media (prefers-reduced-motion: reduce) { .envelope .ev-bar-fill { transition: none; } }
  /* This month's spending against the budget — the figure an envelope
     budgeter checks most, and the one the balance alone doesn't tell you. */
  .envelope .ev-month { display: flex; justify-content: space-between; font-size: 11px;
    color: var(--text-dim); font-family: var(--font-mono); letter-spacing: .04em; margin-top: 4px; }
  .envelope .ev-month .over { color: var(--bad); }
  /* Three money actions you came for, then a "⋯" menu for the rare ones
     (Edit, Archive, Delete). Six buttons per card read as clutter, and the
     dimmed ghost buttons they replaced were near-invisible in the light
     theme; on a phone the delete button wrapped onto its own line. */
  .envelope .ev-actions { display: flex; gap: 6px; margin-top: 10px; flex-wrap: wrap; align-items: center; }
  .ev-more { position: relative; margin-left: auto; }
  .ev-more > summary { list-style: none; cursor: pointer; display: inline-flex; align-items: center;
    justify-content: center; min-width: 28px; font-size: 16px; line-height: 1; letter-spacing: .1em; }
  .ev-more > summary::-webkit-details-marker { display: none; }
  .ev-more[open] > summary { color: var(--text); background: var(--bg-3); }
  .ev-more .menu { position: absolute; right: 0; top: calc(100% + 4px); min-width: 150px; z-index: 20;
    background: var(--bg-2); border: 1px solid var(--border); border-radius: 6px; padding: 4px;
    box-shadow: 0 8px 24px rgba(0,0,0,.35); }
  .menu-item { display: block; width: 100%; text-align: left; background: none; border: none;
    color: var(--text); padding: 7px 10px; border-radius: 4px; font: inherit; font-size: 13px; cursor: pointer; }
  .menu-item:hover, .menu-item:focus-visible { background: var(--bg-3); }
  .menu-item.danger { color: var(--bad); }
  /* An open menu must paint over the neighbouring cards. */
  .envelope:has(.ev-more[open]) { z-index: 5; }

  /* Modal */
  .modal-bg { position: fixed; inset: 0; background: rgba(0,0,0,.6); z-index: 100;
    display: none; align-items: center; justify-content: center; padding: 20px; }
  .modal-bg.open { display: flex; }
  .modal { background: var(--bg-2); border: 1px solid var(--border); border-radius: var(--radius);
    padding: 20px; max-width: 520px; width: 100%; max-height: 90vh; overflow-y: auto; }
  .modal h2 { margin-bottom: 16px; }
  /* Desktop (mouse) only: modals can be dragged by their title bar (JS) and
     resized from the bottom-right grip. `width: min(...)` keeps the natural
     520px default while `max-width` lets the grip grow it. Touch devices keep
     the full-width centered modal — the @media gate skips both. Each modal
     opens reset to centered/default size (see openModal). */
  @media (pointer: fine) {
    .modal { resize: both; overflow: auto; width: min(520px, 100%);
      max-width: 92vw; min-width: 320px; min-height: 140px; }
    .modal.wide { width: min(900px, 100%); }
  }
  /* Wide dialogs. A six-column review table cannot live in a 520px box without
     horizontal scrolling, which is the one thing a table like that must not do. */
  .modal.wide { max-width: 900px; }
  /* Close-out review: the modal itself becomes the flex column so the table
     region is the ONLY scroller — otherwise the intro copy pushes the modal
     past 90vh and the dialog and the table each grow their own scrollbar. */
  .modal.co-modal { display: flex; flex-direction: column; }
  /* padding-right keeps the right-aligned figures clear of the overlay
     scrollbar, which sits on top of the content rather than beside it. */
  .co-scroll { flex: 1 1 auto; min-height: 0; overflow-y: auto; overflow-x: hidden;
    padding-right: 10px; }
  .co-table th, .co-table td { padding: 9px 8px; }
  .co-table td.num, .co-table th.num { white-space: nowrap; }
  .co-table select { padding: 4px 6px; background: var(--bg-3); color: var(--text);
    border: 1px solid var(--border); border-radius: 4px; max-width: 100%; }
  .co-note { margin-top: 10px; color: var(--text-dim); font-size: 13px; }
  .co-note summary { cursor: pointer; }
  .co-note p { margin-top: 6px; }
  /* Under ~760px six columns cannot fit however tightly they are padded, so the
     rows restack as labelled blocks. No horizontal scrollbar at any width. */
  @media (max-width: 760px) {
    .co-table, .co-table tbody, .co-table td { display: block; }
    .co-table thead { display: none; }
    /* Two figures per line, so a row is four lines tall rather than six. */
    .co-table tr { display: grid; grid-template-columns: 1fr 1fr; column-gap: 16px;
      border-bottom: 1px solid var(--border); padding: 8px 0; }
    .co-table tr:hover td { background: none; }
    .co-table td { border: none; padding: 3px 0; display: flex; gap: 10px;
      justify-content: space-between; align-items: baseline; }
    .co-table td::before { content: attr(data-label); color: var(--text-dim);
      font-size: 11px; text-transform: uppercase; letter-spacing: .12em;
      font-family: var(--font-mono); }
    .co-table td.co-name, .co-table td.co-action { grid-column: 1 / -1; }
    /* Block, not flex: the name and its badge must read as one line, and
       space-between would fling the badge to the far edge. */
    .co-table td.co-name { display: block; font-weight: 600; padding-bottom: 4px; }
    .co-table td.co-name::before { content: none; }
    .co-table td.co-action select { flex: 0 1 auto; min-width: 0; }
  }
  /* Phone width: even two figures per line clip, so one per line, and the
     action select drops under its own label rather than sharing it. */
  @media (max-width: 460px) {
    .co-table tr { grid-template-columns: 1fr; }
    .co-table td.co-action { flex-wrap: wrap; }
    .co-table td.co-action select { flex: 1 0 100%; }
  }
  .field { margin-bottom: 12px; }
  .field label { display: block; font-size: 12px; color: var(--text-dim);
    margin-bottom: 4px; text-transform: uppercase; letter-spacing: .5px; }
  .field input:not([type="checkbox"]), .field select, .field textarea {
    width: 100%; padding: 8px 10px; background: var(--bg); color: var(--text);
    border: 1px solid var(--border); border-radius: 6px; }
  /* Keyboard-only focus ring on interactive elements that the UA outline
     used to handle but our dark theme made invisible. Mouse clicks don't
     trigger :focus-visible, so this only shows for keyboard navigation. */
  .btn:focus-visible,
  nav.tabs button:focus-visible,
  .pin-btn:focus-visible,
  .drag-handle:focus-visible,
  summary:focus-visible,
  a:focus-visible,
  [role="button"]:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
    border-radius: 4px;
  }
  .field input:focus, .field select:focus, .field textarea:focus {
    outline: none; border-color: var(--accent); }
  .field.check label {
    display: flex; align-items: center; gap: 8px;
    text-transform: none; letter-spacing: normal;
    font-size: 14px; color: var(--text); margin-bottom: 0; cursor: pointer; }
  .field.check input[type="checkbox"] {
    width: auto; margin: 0; padding: 0; flex: none; cursor: pointer; }
  .field-row { display: flex; gap: 10px; }
  .field-row .field { flex: 1; }
  .modal-actions { display: flex; justify-content: flex-end; gap: 8px; margin-top: 16px; }

  /* Toolbar */
  .toolbar { display: flex; gap: 10px; align-items: center; margin-bottom: 14px; flex-wrap: wrap; }
  .toolbar .spacer { flex: 1; }
  .toolbar-stat { display: flex; flex-direction: column; align-items: flex-end; gap: 1px; }
  .toolbar-stat strong { font-size: 16px; font-variant-numeric: tabular-nums; }
  .filter-input { padding: 6px 10px; background: var(--bg-2); border: 1px solid var(--border);
    border-radius: 6px; color: var(--text); }
  .filter-group { display: flex; gap: 6px; padding: 3px 4px; background: var(--bg); border: 1px solid var(--border); border-radius: 7px; align-items: center; flex-wrap: wrap; }
  .filter-group .filter-input { background: transparent; border: none; padding: 4px 8px; border-radius: 4px; }
  .filter-group .filter-input:focus { outline: 1px solid var(--accent); outline-offset: -1px; }
  .filter-group select.filter-input option { background: var(--bg-2); color: var(--text); }

  /* Onboarding */
  .empty-state { text-align: center; padding: 60px 20px; }
  .empty-state h2 { font-size: 22px; margin-bottom: 8px; }
  .empty-state p { color: var(--text-dim); margin-bottom: 18px; max-width: 500px; margin-left: auto; margin-right: auto; }
  .empty-state .btns { display: flex; gap: 10px; justify-content: center; flex-wrap: wrap; }

  /* First-run setup checklist on the dashboard */
  .ob-card { margin-bottom: 14px; border-left: 3px solid var(--accent); }
  .ob-head { margin-bottom: 14px; }
  .ob-list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 8px; }
  .ob-step { display: flex; align-items: center; gap: 14px; padding: 12px; background: var(--bg-3);
    border: 1px solid var(--border); border-radius: 8px; }
  .ob-step.ob-done { opacity: .72; }
  .ob-step.ob-locked { opacity: .55; }
  .ob-num { flex: none; width: 28px; height: 28px; border-radius: 50%;
    display: inline-flex; align-items: center; justify-content: center;
    background: var(--bg); border: 1px solid var(--border);
    font-weight: 600; font-size: 13px; color: var(--text-dim); }
  .ob-step.ob-done .ob-num { background: var(--good); color: var(--on-fill); border-color: var(--good); }
  .ob-body { flex: 1; min-width: 0; }
  .ob-title { font-weight: 600; font-size: 14px; }
  .ob-blurb { font-size: 12px; color: var(--text-dim); margin-top: 2px; }
  @media (max-width: 600px) {
    .ob-step { flex-wrap: wrap; }
    .ob-body { flex-basis: calc(100% - 42px); }
    .ob-step .btn { margin-left: 42px; }
  }

  /* Settings */
  .setting-row { display: flex; justify-content: space-between; align-items: center;
    padding: 10px 0; border-bottom: 1px solid var(--border); max-width: 720px; }
  .setting-row:last-child { border-bottom: none; }
  /* Promotion of the inline 11px muted micro-copy used in ~15 places. */
  .micro { font-size: 11px; color: var(--text-dim); }
  .setting-row .label { font-weight: 500; }
  .setting-row .desc { font-size: 12px; color: var(--text-dim); margin-top: 2px; }
  .setting-row input, .setting-row select {
    padding: 8px 10px; background: var(--bg); color: var(--text);
    border: 1px solid var(--border); border-radius: 6px; }
  .setting-row input:focus, .setting-row select:focus {
    outline: none; border-color: var(--accent); }

  /* Transaction form quick */
  .quick-add { display: grid; gap: 8px; grid-template-columns: 110px 1fr 1fr 1fr 100px 80px; align-items: end; }
  @media (max-width: 900px) { .quick-add { grid-template-columns: 1fr 1fr; } }

  .toast { position: fixed; bottom: 20px; right: 20px; background: var(--bg-3);
    border: 1px solid var(--border); border-left: 3px solid var(--text-dim);
    padding: 10px 14px 10px 12px; border-radius: 7px;
    box-shadow: var(--shadow); z-index: 200; opacity: 0; transition: opacity .2s;
    pointer-events: none; }
  .toast.show { opacity: 1; }
  .toast.success { border-left-color: var(--good); }
  .toast.error { border-left-color: var(--bad); }
  .toast.info { border-left-color: var(--accent-2); }
  .toast.has-action { pointer-events: auto; }
  .toast button.toast-action { margin-left: 12px; background: transparent;
    color: var(--accent); border: 0; padding: 2px 4px; font: inherit;
    font-weight: 600; cursor: pointer; }
  .toast button.toast-action:hover { text-decoration: underline; }

  .pill { display: inline-block; padding: 1px 7px; border-radius: 4px;
    font-size: 11px; background: var(--bg-3); color: var(--text-dim); }

  /* Tiny "?" bubble next to labels for jargon explanations. The text lives
     in the native title attribute — works on desktop hover and screen readers
     out of the box, and degrades to nothing on touch (which is acceptable
     since the surrounding labels stay readable). */
  .help-tip {
    display: inline-block;
    width: 14px; height: 14px;
    margin-left: 5px;
    border-radius: 50%;
    border: 1px solid var(--border);
    background: var(--bg-3);
    color: var(--text-dim);
    font: 600 10px/13px ui-sans-serif, -apple-system, sans-serif;
    text-align: center;
    vertical-align: 1px;
    cursor: help;
    user-select: none;
    transition: background .15s, color .15s, border-color .15s;
  }
  .help-tip:hover, .help-tip:focus { background: var(--accent); color: var(--bg-2); border-color: var(--accent); outline: none; }
  label .help-tip { vertical-align: middle; }

  kbd { display: inline-block; padding: 1px 6px; border-radius: 4px;
    font: 12px/1.4 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    background: var(--bg-3); color: var(--text); border: 1px solid var(--border);
    box-shadow: 0 1px 0 var(--border); }

  .checkbox-list { max-height: 220px; overflow-y: auto; border: 1px solid var(--border);
    border-radius: 6px; padding: 6px; background: var(--bg); }
  .checkbox-list label { display: flex; align-items: center; padding: 4px 6px;
    border-radius: 4px; cursor: pointer; }
  .checkbox-list label:hover { background: var(--bg-3); }
  .checkbox-list input { margin-right: 8px; }

  .fc-acc-picker { background: var(--bg); border: 1px solid var(--border); border-radius: 6px; }
  details.archived-list > summary { cursor: pointer; color: var(--text-dim); font-size: 13px; padding: 6px 0; }
  details.archived-list[open] > summary { color: var(--text); }
  .fc-acc-picker summary { padding: 8px 10px; cursor: pointer; display: flex; justify-content: space-between; align-items: center; list-style: none; user-select: none; font-size: 13px; }
  .fc-acc-picker summary::-webkit-details-marker { display: none; }
  .fc-acc-picker summary::marker { content: ""; }
  .fc-acc-picker[open] summary { border-bottom: 1px solid var(--border); }
  .fc-acc-picker[open] .fc-acc-caret { transform: rotate(180deg); }
  .fc-acc-caret { color: var(--text-dim); transition: transform .15s; }
  .fc-acc-picker .checkbox-list { border: none; max-height: 240px; border-radius: 0 0 6px 6px; }

  /* Forecast layout: controls on the left, chart on the right */
  .forecast-row { display: flex; gap: 0; align-items: stretch; flex-wrap: wrap; }
  .forecast-controls { display: flex; gap: 14px; flex: 0 0 var(--forecast-controls-w, 460px);
    min-width: 280px; align-content: flex-start; }
  .forecast-controls > div { flex: 1 1 220px; min-width: 0; }
  .forecast-splitter { flex: 0 0 8px; cursor: col-resize; position: relative;
    align-self: stretch; }
  .forecast-splitter::before { content: ""; position: absolute; left: 50%;
    top: 0; bottom: 0; width: 2px; transform: translateX(-50%);
    background: var(--border); border-radius: 1px; transition: background .15s, width .15s; }
  .forecast-splitter:hover::before, .forecast-splitter.dragging::before {
    background: var(--accent); width: 4px; }
  .forecast-chart-card { flex: 1 1 0; min-width: 320px; display: flex; }
  .forecast-chart-card > div { flex: 1; min-height: 60vh; min-width: 0; }
  body.forecast-resizing { cursor: col-resize; user-select: none; }
  body.forecast-resizing * { cursor: col-resize !important; }

  .due-banner { display: flex; align-items: center; justify-content: space-between;
    gap: 14px; flex-wrap: wrap; border-left: 3px solid var(--accent-2); }
  .due-banner .pos { color: var(--good); }
  .due-banner .neg { color: var(--bad); }

  a.rec-link { color: var(--text); text-decoration: none; border-bottom: 1px dotted var(--text-dim); }
  a.rec-link:hover { color: var(--accent); border-bottom-color: var(--accent); }

  details { margin: 6px 0; }
  summary { cursor: pointer; padding: 6px 0; user-select: none; }
  summary:hover { color: var(--accent); }

  /* Help tab — capped width for readable prose on wide monitors, looser line
     height than the rest of the app, and a quieter FAQ style so the
     details/summary list reads as reference rather than UI. */
  .help { max-width: 860px; line-height: 1.55; }
  .help h3 { margin-top: 28px; margin-bottom: 8px; }
  .help h3:first-of-type { margin-top: 0; }
  .help p { color: var(--text); }
  .help .help-lead { color: var(--text-dim); margin-bottom: 18px; }
  .help dl { display: grid; grid-template-columns: max-content 1fr; gap: 6px 16px; margin: 8px 0; }
  .help dl dt { color: var(--accent); font-weight: 600; }
  .help dl dd { margin: 0; color: var(--text); }
  .help kbd { display: inline-block; padding: 1px 6px; background: var(--bg-3); border: 1px solid var(--border);
    border-radius: 4px; font: 12px ui-monospace, Menlo, Consolas, monospace; color: var(--text); }
  .help details.faq { background: var(--bg-3); border: 1px solid var(--border); border-radius: 6px;
    padding: 4px 12px; margin: 8px 0; }
  .help details.faq summary { padding: 8px 0; font-weight: 500; }
  .help details.faq[open] summary { color: var(--accent); }
  .help details.faq > div { padding: 0 0 10px; color: var(--text); }
</style>
</head>
<body>
<header class="top">
  <h1>💰 Pocket Envelopes</h1>
  <nav class="tabs" id="tabs">
    <button data-view="dashboard" class="active" aria-current="page">Dashboard</button>
    <button data-view="accounts">Accounts</button>
    <button data-view="envelopes">Envelopes</button>
    <button data-view="transactions">Transactions</button>
    <button data-view="recurring">Recurring</button>
    <button data-view="forecast">Forecast</button>
    <button data-view="networth">Net Worth</button>
    <button data-view="reports">Reports</button>
    <button data-view="settings">Settings</button>
    <button data-view="help">Help</button>
  </nav>
  <div class="file-status no-file" id="fileStatus">
    <span class="dot"></span><span id="fileLabel">No file open</span>
  </div>
  <button class="btn" id="btnReload" title="Reload the latest version from the server">Reload</button>
  <button class="btn" id="btnSave">Save</button>
  <button class="btn ghost" id="btnTheme" title="Toggle theme" aria-label="Toggle theme">🌗</button>
</header>

<main id="main"></main>

<div class="modal-bg" id="modalBg" role="dialog" aria-modal="true" aria-labelledby="modalTitle"><div class="modal" id="modal"></div></div>
<div class="toast" id="toast" role="status" aria-live="polite" aria-atomic="true"></div>

<script>
//=============================================================================
// STATE & STORAGE
//=============================================================================
const SCHEMA_VERSION = 2;
// Max user-defined transaction tags (settings.tags). A UI limit only — migrate()
// never truncates a longer list from a hand-edited file. Raise freely.
const TAG_LIMIT = 8;
// Number/date formatting locale when the data file has none (first run, or a
// hand-edited file): follow the browser rather than pin one country's format.
const DEFAULT_LOCALE = (typeof navigator !== 'undefined' && navigator.language) || "en-US";
// Rolling daily backups in localStorage. Each slot is its own key so we only
// rewrite one slot per day (vs. re-serialising a 7-element array). The index
// is kept in date-sorted order, oldest first, so prune is a shift().
// These are a SECOND line of defence only — the server keeps its own
// finance-data.bak.N rotation on disk. Everything else in localStorage is UI
// preference, never budget data: the server is the single source of truth.
const LS_BACKUP_PREFIX = "envBudget_bak_";
const LS_BACKUP_INDEX  = "envBudget_bak_index";
const BACKUP_SLOTS = 7;

// Server persistence. The app talks to serve.py over the same origin it was
// loaded from, so it works identically on this machine and from any device on
// the tailnet. `serverEtag` is the sha256 the server handed us with the last
// successful GET/PUT; we send it back as If-Match so a write that would clobber
// a newer version from another device is rejected (409) instead of silently
// winning. See handleConflict().
const DATA_URL = "data";      // relative — keeps working behind any path prefix
let serverEtag = null;        // last known server version, null = unknown/force
let conflictPending = false;  // a 409 is unresolved; auto-save is paused
let demoMode = false;         // ?demo=1 — purely in-memory, never touches the server

let data = null;            // loaded budget data
let dirty = false;
let activeView = "dashboard";
let currentChart = null;    // active chart instance to destroy on view switch
let reportCharts = [];      // the Reports doughnuts — destroyed alongside currentChart in render()

const uid = () => Math.random().toString(36).slice(2, 11);

function emptyData() {
  return {
    version: SCHEMA_VERSION,
    settings: {
      currency: "EUR",
      locale: DEFAULT_LOCALE,   // first run follows the browser; changed in Settings
      theme: "auto",
      monthStartDay: 1,
      household: ["You", "Partner"],
      tags: []                 // user-defined tag names; tx.tag / rec.tag reference them by string
    },
    accounts: [],
    envelopes: [],
    transactions: [],
    recurring: [],
    netWorthSnapshots: [], // [{date, value}]
    forecastProfiles: [],  // [{id, name, accountIds, days, chartLines, includeAllowances, showSpendable}]
    importProfiles: [],    // [{id, name, delimiter, hasHeader, dateOrder, amountMode, map:{date,desc,amount,debit,credit}, accountId}] — CSV import
    defaultForecastProfileId: null,  // id of the profile auto-applied on session start; null = no default
    lastClosedMonth: null  // "YYYY-MM" of the most recent month the user has closed-out via the review flow; null = never closed
  };
}

// Load the authoritative copy from the server. Returns true when `data` was
// populated, false when the server has no file yet (first ever run) or the
// fetch failed — the caller then shows the welcome screen.
//
// There is deliberately NO localStorage fallback for hydration. With several
// devices editing the same file, a per-browser mirror is as likely to be a
// stale copy of someone else's older state as it is to be a lost edit, so
// silently preferring it would resurrect deleted transactions. Recovery runs
// through the dated backups (Settings → Backups) and the server's own
// finance-data.bak.N rotation instead, both of which the user picks explicitly.
async function loadFromServer() {
  let res;
  try {
    res = await fetch(DATA_URL, { cache: "no-store" });
  } catch (e) {
    updateFileStatus("server unreachable", "no-file");
    toast("Could not reach the server — is serve.py still running? Your data is safe on disk; reload once it's back.", 8000, "error");
    console.error("loadFromServer: fetch failed", e);
    return false;
  }
  if (!res.ok) {
    updateFileStatus("server error " + res.status, "no-file");
    toast(`Server returned ${res.status} loading your data. Nothing has been changed.`, 7000, "error");
    return false;
  }
  serverEtag = res.headers.get("ETag");
  const text = await res.text();
  // X-Data-New means serve.py found no finance-data.json at all — a genuinely
  // first run, as opposed to a file that exists and happens to be empty.
  if (res.headers.get("X-Data-New") === "1") {
    updateFileStatus("no data file yet", "no-file");
    return false;
  }
  const parsed = safeParseData(text, "finance-data.json");
  if (!parsed) return false; // parse failure already toasted; welcome screen follows
  data = parsed;
  updateFileStatus("finance-data.json", true);
  return true;
}

// Wraps migrate(JSON.parse(text)) with a clear error toast on parse failure.
// Returns null on failure so callers can preserve their existing `data` via
// `data = safeParseData(...) || data`. A malformed file used to silently nuke
// the in-memory state (importViaInput) or fail with cryptic console-only
// errors (a corrupt file on the server). This helper makes the failure visible
// and recoverable — pair with the rolling backups (Settings → Backups).
// Structural sanity check for a parsed data object — catches a malformed/corrupt
// file BEFORE migrate() bolts defaults onto it and we render garbage (or crash on
// a `.map` over a non-array). Returns a list of human-readable problems (empty =
// looks valid). Lenient: missing keys are fine (migrate fills them); it only
// rejects clearly-wrong shapes (non-object root, a collection that isn't a list,
// settings that isn't an object, or a non-object entry inside a core list).
function validateData(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return ['not a Pocket Envelopes data object'];
  const problems = [];
  const arrayKeys = ['accounts', 'envelopes', 'transactions', 'recurring', 'netWorthSnapshots', 'forecastProfiles', 'importProfiles'];
  for (const k of arrayKeys) if (raw[k] !== undefined && !Array.isArray(raw[k])) problems.push(`"${k}" is not a list`);
  if (raw.settings !== undefined && (typeof raw.settings !== 'object' || raw.settings === null || Array.isArray(raw.settings))) problems.push('"settings" is not an object');
  if (raw.settings && raw.settings.tags !== undefined && !Array.isArray(raw.settings.tags)) problems.push('"settings.tags" is not a list');
  for (const k of ['accounts', 'envelopes', 'transactions', 'recurring']) {
    if (Array.isArray(raw[k]) && raw[k].some(x => !x || typeof x !== 'object' || Array.isArray(x))) problems.push(`"${k}" has an invalid entry`);
  }
  return problems;
}

function safeParseData(text, sourceLabel) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    const m = e && e.message ? e.message : String(e);
    const short = m.length > 90 ? m.slice(0, 90) + '…' : m;
    toast(`${sourceLabel}: not valid JSON — ${short}. Existing data preserved; try Settings → Backups to restore.`, 7000, 'error');
    console.error(`safeParseData: JSON parse failed for ${sourceLabel}:`, e);
    return null;
  }
  const problems = validateData(parsed);
  if (problems.length) {
    toast(`${sourceLabel}: ${problems[0]} — refusing to load a corrupt file. Existing data preserved; try Settings → Backups to restore.`, 8000, 'error');
    console.error(`safeParseData: validation failed for ${sourceLabel}:`, problems);
    return null;
  }
  try {
    return migrate(parsed);
  } catch (e) {
    toast(`${sourceLabel}: could not load (${e && e.message ? e.message : e}). Existing data preserved; try Settings → Backups to restore.`, 8000, 'error');
    console.error(`safeParseData: migrate failed for ${sourceLabel}:`, e);
    return null;
  }
}

function migrate(raw) {
  // future migrations can go here
  if (!raw.version) raw.version = SCHEMA_VERSION;
  raw.settings = { ...emptyData().settings, ...(raw.settings || {}) };
  // Tags: additive, no version bump. The list is sanitised (strings, trimmed,
  // case-insensitive dedupe) but NOT truncated to TAG_LIMIT — cutting a
  // hand-edited list would orphan tags for no safety gain. A tx/rec tag that
  // names nothing in the list is kept, not dropped: migrate runs before any
  // pushUndo, so a drop here would be silent, irreversible data loss on an
  // import from a device whose tag list was edited later. Stray tags render
  // as a plain grey chip and the edit form offers them as "(unlisted)".
  {
    const seen = new Set();
    raw.settings.tags = (Array.isArray(raw.settings.tags) ? raw.settings.tags : [])
      .map(t => String(t ?? '').trim())
      .filter(t => t && !seen.has(t.toLowerCase()) && seen.add(t.toLowerCase()));
    const canon = new Map(raw.settings.tags.map(t => [t.toLowerCase(), t]));
    const fixTag = x => {
      if (x.tag === undefined) return;
      const s = typeof x.tag === 'string' ? x.tag.trim() : '';
      if (!s) { delete x.tag; return; }
      x.tag = canon.get(s.toLowerCase()) || s;   // snap case to the canonical spelling
    };
    for (const t of (raw.transactions || [])) fixTag(t);
    for (const r of (raw.recurring || [])) fixTag(r);
  }
  raw.accounts = raw.accounts || [];
  raw.envelopes = raw.envelopes || [];
  raw.transactions = raw.transactions || [];
  raw.recurring = raw.recurring || [];
  raw.netWorthSnapshots = raw.netWorthSnapshots || [];
  raw.forecastProfiles = raw.forecastProfiles || [];
  raw.importProfiles = raw.importProfiles || [];   // CSV-import column mappings (additive, v2+)
  // Self-heal forecast profiles that reference accounts deleted in a prior
  // session: drop any account id no longer present so loading them can't
  // reintroduce an orphan id into the projection (which blanks the views).
  {
    const _liveAccIds = new Set((raw.accounts || []).map(a => a.id));
    for (const _p of raw.forecastProfiles)
      if (Array.isArray(_p.accountIds)) _p.accountIds = _p.accountIds.filter(id => _liveAccIds.has(id));
  }
  if (raw.defaultForecastProfileId === undefined) raw.defaultForecastProfileId = null;
  // Close-out review (v2): lastClosedMonth tracks the most recent month the
  // user has reviewed. null = never reviewed → the banner offers the previous
  // calendar month. closeOutDue() always returns AT MOST the previous month
  // (one banner at a time), so anchoring to null is safe — it doesn't unleash
  // a multi-month catch-up prompt. The earlier v1 attempt anchored to the
  // CURRENT month, which suppressed the legitimate previous-month banner; v2
  // forces lastClosedMonth back to null on upgrade to undo that.
  if (!raw.version || raw.version < 2) {
    raw.lastClosedMonth = null;
    raw.version = 2;
  }
  if (raw.lastClosedMonth === undefined) raw.lastClosedMonth = null;
  // Existing recurring entries created before lastAppliedDate existed: anchor to
  // today so we don't suddenly try to back-apply months of past occurrences.
  // New recurring entries set lastAppliedDate explicitly on creation if needed.
  const today = todayISO();
  for (const r of raw.recurring) {
    if (r.lastAppliedDate === undefined) r.lastAppliedDate = today;
  }
  // Envelope cadence migration: rename monthlyBudget → budgetAmount, default
  // cadence to "monthly". Annual envelopes store the full yearly amount in
  // budgetAmount and are accounted for as budgetAmount/12 per month.
  // rolloverPolicy: 'rollover' (carry balance to next month, default — preserves
  // existing behavior) or 'reset' (close-out review zeroes the leftover and
  // returns it to the spendable pool). Annual envelopes always rollover; the
  // policy field is ignored for them.
  for (const e of raw.envelopes) {
    if (!e.cadence) e.cadence = "monthly";
    if (e.budgetAmount === undefined) {
      e.budgetAmount = e.monthlyBudget || 0;
    }
    delete e.monthlyBudget;
    if (!e.rolloverPolicy) e.rolloverPolicy = "rollover";
    // pinned floats an envelope above the activity-based sort in renderEnvelopes.
    // Additive field, no version bump needed — undefined is treated as false
    // everywhere the field is read.
    if (e.pinned === undefined) e.pinned = false;
    // isReserve marks the single catch-all / emergency envelope: it is never
    // funded by "Fund the month", never projects an allowance in the forecast
    // (its budgetAmount is forced to 0), and is the destination for close-out
    // sweeps. Additive field, no version bump — undefined → false.
    if (e.isReserve === undefined) e.isReserve = false;
    // accountId ("backed by") is additive and optional: undefined = household.
    // A reserve envelope is always household-wide (it is fed by sweeps from
    // envelopes backed by any account), and an id whose account no longer
    // exists degrades to household rather than silently excluding the
    // envelope from every filtered forecast.
    if (e.isReserve || (e.accountId && !raw.accounts.some(a => a.id === e.accountId))) delete e.accountId;
  }
  // Pinned accounts: a small dashboard strip surfaces the live balance of any
  // account the user pins. Additive field, no version bump — undefined → false.
  // Order of pinned accounts on the dashboard follows the order in
  // raw.accounts itself; drag-to-reorder on the dashboard mutates this array.
  for (const a of raw.accounts) {
    if (a.pinned === undefined) a.pinned = false;
  }
  // Forecast profiles: collapse legacy {showTotal, onlyTotal} into the new
  // single-axis chartLines tri-state. After migration each profile carries
  // only chartLines for this concern; the old fields are dropped so they
  // don't quietly diverge from the source of truth.
  for (const p of raw.forecastProfiles) {
    if (!p.chartLines) p.chartLines = chartLinesFromLegacy(p);
    delete p.showTotal;
    delete p.onlyTotal;
  }
  return raw;
}

// Start a brand-new budget on a server that has no finance-data.json yet.
// The PUT creates the file; from then on it is an ordinary save.
async function newFile() {
  data = emptyData();
  const ok = await writeFile();
  if (ok) {
    render();
    toast("Created finance-data.json on the server");
  }
}

// Persist `data` to the server. Returns true on success.
//
// `force` skips the If-Match precondition — the deliberate "my version wins"
// choice offered by the conflict dialog. Everything else sends the ETag we
// last saw, so a write racing another device is refused rather than silently
// overwriting it.
async function writeFile({ force = false, keepalive = false } = {}) {
  if (!data) return false;
  // ?demo=1 is a sandbox: edits are allowed and stay in memory, but nothing is
  // ever written to the server. Keep the label honest rather than saying "saved".
  if (demoMode) { dirty = false; updateFileStatus("demo data (not saved)", "no-file"); return true; }
  const body = JSON.stringify(data, null, 2);
  const headers = { "Content-Type": "application/json" };
  if (serverEtag && !force) headers["If-Match"] = serverEtag;
  let res;
  try {
    // keepalive lets a save started by pagehide/visibilitychange outlive the
    // page. It is capped at 64KB by the spec, so a real budget file outgrows
    // it quickly — fall back to a normal fetch above that and accept that a
    // tab closed inside the same millisecond may lose the very last edit.
    const useKeepalive = keepalive && body.length < 60000;
    res = await fetch(DATA_URL, { method: "PUT", headers, body, keepalive: useKeepalive });
  } catch (e) {
    setStatus("unsaved");
    toast("Save failed — server unreachable. Your changes are still here in this tab; they'll save once serve.py is back.", 8000, "error");
    console.error("writeFile: fetch failed", e);
    return false;
  }
  if (res.status === 409) {
    handleConflict(res.headers.get("ETag"));
    return false;
  }
  if (!res.ok) {
    setStatus("unsaved");
    toast(`Save failed (server said ${res.status}). Your changes are still here in this tab.`, 8000, "error");
    return false;
  }
  serverEtag = res.headers.get("ETag") || serverEtag;
  conflictPending = false;
  try { ensureDailyBackup(); } catch {}
  dirty = false;
  // Rewrite the whole indicator, not just the dot: a save that resolves a
  // conflict (or the first save after a failed one) has to clear the stale
  // "conflict — server has a newer version" label as well as the colour.
  updateFileStatus("finance-data.json", true);
  return true;
}

// Another device wrote since we loaded. We do NOT touch the in-memory data —
// the user's unsaved work stays exactly where it is — and we pause auto-save
// so we aren't hammering the server with writes that will keep failing. The
// dialog offers the only two honest options: take theirs (reload) or take
// ours (force-overwrite).
function handleConflict(currentEtag) {
  conflictPending = true;
  dirty = true;
  setStatus("conflict");
  updateFileStatus("conflict — server has a newer version", "conflict");
  if (document.getElementById("modalBg").classList.contains("open") &&
      document.getElementById("modal").dataset.conflict === "1") return; // already open
  openModal(`<h2>Data changed on server</h2>
    <p style="color:var(--text-dim);line-height:1.5;">
      Data changed on the server since your last load — reload to see the newer
      version. Your unsaved changes are preserved in this tab until you decide.
    </p>
    <p style="color:var(--text-dim);line-height:1.5;">
      Another device (or another tab) saved a newer <code>finance-data.json</code>.
      Auto-save is paused until you choose.
    </p>
    <div class="btns" style="margin-top:16px;display:flex;gap:8px;flex-wrap:wrap;">
      <button class="btn" id="cf_reload">Reload from server</button>
      <button class="btn danger" id="cf_force">Overwrite server with this tab</button>
      <button class="btn ghost" id="cf_later">Keep working</button>
    </div>`);
  document.getElementById("modal").dataset.conflict = "1";
  document.getElementById("cf_reload").onclick = () => location.reload();
  document.getElementById("cf_force").onclick = async () => {
    closeModal();
    document.getElementById("modal").dataset.conflict = "";
    // Retry without If-Match. The server rotates the version we are about to
    // replace into finance-data.bak.0, so the overwritten copy is recoverable.
    const ok = await writeFile({ force: true });
    if (ok) toast("Overwrote the server with this tab's data (previous version kept as finance-data.bak.0)", 7000, "success");
  };
  document.getElementById("cf_later").onclick = () => {
    closeModal();
    document.getElementById("modal").dataset.conflict = "";
    if (currentEtag) toast("Auto-save stays paused until you reload or overwrite.", 5000, "info");
  };
}

let saveTimer = null;
function saveDirty() {
  dirty = true;
  setStatus("unsaved");
  if (conflictPending) return;   // paused until the user resolves the conflict
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => writeFile(), 1200);
}

// Force an immediate flush, bypassing the 1.2s debounce. Used by pagehide /
// visibilitychange:hidden / blur so a tab close or background-eviction can't
// strand the last edit inside the pending timer. Uses a keepalive fetch so the
// request survives the page going away (see the size cap in writeFile).
function flushNow() {
  if (!dirty || !data || conflictPending) return;
  if (saveTimer) { clearTimeout(saveTimer); saveTimer = null; }
  try { ensureDailyBackup(); } catch {}
  writeFile({ keepalive: true }).catch(() => {});
}

// Undo: snapshot-based. Each destructive mutation calls pushUndo(label) BEFORE
// touching data; performUndo() pops the last snapshot. Ring-buffered to 30 so
// worst case ~30 deep-clones of data sit in RAM (a few MB at typical sizes).
// In-memory only — reloads clear the stack; crash recovery is the localStorage
// mirror, not this.
const UNDO_STACK_MAX = 30;
let undoStack = [];
// Redo is the same mechanism run the other way: performUndo parks the state
// it is leaving on redoStack, performRedo pops it back. Any NEW mutation
// (pushUndo) clears the redo stack — the usual linear-history rule — so a redo
// can never resurrect a state that a later edit has since diverged from.
let redoStack = [];
function pushUndo(label) {
  if (!data) return;
  undoStack.push({ snapshot: JSON.parse(JSON.stringify(data)), label });
  if (undoStack.length > UNDO_STACK_MAX) undoStack.shift();
  redoStack = [];
}
function performUndo() {
  if (!undoStack.length) { toast("Nothing to undo"); return; }
  const { snapshot, label } = undoStack.pop();
  redoStack.push({ snapshot: JSON.parse(JSON.stringify(data)), label });
  if (redoStack.length > UNDO_STACK_MAX) redoStack.shift();
  data = snapshot;
  saveDirty();
  render();
  toast("Undone: " + label, 4000, undefined, { label: "Redo", onClick: performRedo });
}
function performRedo() {
  if (!redoStack.length) { toast("Nothing to redo"); return; }
  const { snapshot, label } = redoStack.pop();
  undoStack.push({ snapshot: JSON.parse(JSON.stringify(data)), label });
  if (undoStack.length > UNDO_STACK_MAX) undoStack.shift();
  data = snapshot;
  saveDirty();
  render();
  toast("Redone: " + label);
}

// Backups: rolling daily snapshots in localStorage. One slot per calendar day,
// max BACKUP_SLOTS days kept. Called from writeFile()/flushNow() so any save
// path covers it. Quota errors must NOT throw out of here — failing to record
// a bonus backup must never break the save that triggered it. These are a
// second line of defence behind the server's own finance-data.bak.N files.
function _readBackupIndex() {
  try { return JSON.parse(localStorage.getItem(LS_BACKUP_INDEX) || '{"dates":[]}'); }
  catch { return { dates: [] }; }
}
function _writeBackupIndex(idx) {
  try { localStorage.setItem(LS_BACKUP_INDEX, JSON.stringify(idx)); } catch {}
}
function ensureDailyBackup() {
  if (!data) return;
  const today = todayISO();
  const idx = _readBackupIndex();
  if (idx.dates.includes(today)) return; // already backed up today
  const payload = JSON.stringify(data);
  try {
    localStorage.setItem(LS_BACKUP_PREFIX + today, payload);
  } catch {
    // Quota — try dropping the oldest backup once and retry.
    if (idx.dates.length) {
      const stale = idx.dates.shift();
      localStorage.removeItem(LS_BACKUP_PREFIX + stale);
      _writeBackupIndex(idx);
      try { localStorage.setItem(LS_BACKUP_PREFIX + today, payload); }
      catch { return; } // still failing — give up silently
    } else {
      return;
    }
  }
  idx.dates.push(today);
  idx.dates.sort();
  while (idx.dates.length > BACKUP_SLOTS) {
    const stale = idx.dates.shift();
    localStorage.removeItem(LS_BACKUP_PREFIX + stale);
  }
  _writeBackupIndex(idx);
}
// Returns [{date, size}] oldest first. Used by the Settings UI.
function listBackups() {
  const idx = _readBackupIndex();
  return idx.dates.map(date => {
    const raw = localStorage.getItem(LS_BACKUP_PREFIX + date);
    return { date, size: raw ? raw.length : 0 };
  });
}
function restoreBackup(date) {
  const raw = localStorage.getItem(LS_BACKUP_PREFIX + date);
  if (!raw) { toast("Backup not found", 3000, "error"); return; }
  let parsed;
  try { parsed = JSON.parse(raw); }
  catch { toast("Backup is corrupt (invalid JSON)", 3000, "error"); return; }
  // Structurally validate BEFORE pushUndo/migrate so a corrupt backup can't
  // leave a no-op undo entry or throw past this point. Same guard as load.
  const problems = validateData(parsed);
  if (problems.length) { toast(`Backup is corrupt (${problems[0]})`, 3500, "error"); return; }
  pushUndo(`Restore backup ${date}`);
  data = migrate(parsed);
  saveDirty();
  render();
  toast(`Restored backup from ${date}`, 5000, "success", { label: "Undo", onClick: performUndo });
}
function deleteBackup(date) {
  localStorage.removeItem(LS_BACKUP_PREFIX + date);
  const idx = _readBackupIndex();
  idx.dates = idx.dates.filter(d => d !== date);
  _writeBackupIndex(idx);
}
function downloadBackup(date) {
  const raw = localStorage.getItem(LS_BACKUP_PREFIX + date);
  if (!raw) { toast("Backup not found", 3000, "error"); return; }
  // Pretty-print for the downloaded file — matches writeFile()'s on-disk format.
  let pretty;
  try { pretty = JSON.stringify(JSON.parse(raw), null, 2); }
  catch { pretty = raw; }
  const blob = new Blob([pretty], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `finance-data.bak-${date}.json`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

function setStatus(s) {
  const el = document.getElementById("fileStatus");
  el.classList.remove("saved", "unsaved", "no-file", "conflict");
  // An unresolved conflict outranks saved/unsaved: edits are staying in this
  // tab only, and saying "unsaved" understates that they cannot currently be
  // written at all.
  if (conflictPending && (s === "saved" || s === "unsaved")) s = "conflict";
  el.classList.add(s);
}
// `saved` may be a boolean (true=saved, false=unsaved) for the common case, or
// a literal status string ("conflict", "no-file") for special states.
function updateFileStatus(name, saved) {
  document.getElementById("fileLabel").textContent = name;
  if (typeof saved === "string") setStatus(saved);
  else setStatus(saved ? "saved" : "unsaved");
  const el = document.getElementById("fileStatus");
  if (saved === "conflict") {
    el.title = 'Another device saved a newer version. Auto-save is paused — reload, or overwrite the server from the dialog.';
  } else if (typeof saved === "string") {
    el.title = '';
  } else {
    el.title = saved ? 'Saved to ' + name + ' on the server' : 'Unsaved changes — auto-saving to ' + name;
  }
}

// Import replaces the in-memory state and immediately pushes it to the server,
// so a device that imports is instantly the version everyone else will load.
// The write is forced: the file the user just picked is by definition meant to
// win over whatever is on the server.
function importViaInput() {
  const inp = document.createElement("input");
  inp.type = "file"; inp.accept = ".json,application/json";
  inp.onchange = async () => {
    const f = inp.files[0]; if (!f) return;
    const parsed = safeParseData(await f.text(), f.name);
    if (!parsed) return; // parse failure already toasted
    pushUndo(`Import ${f.name}`);
    data = parsed;
    render();
    const ok = await writeFile({ force: true });
    if (ok) {
      updateFileStatus("finance-data.json", true);
      toast(`Imported ${f.name} and saved it to the server`, 5000, "success", { label: "Undo", onClick: performUndo });
    }
  };
  inp.click();
}

function exportFile() {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = "finance-data.json"; a.click();
  URL.revokeObjectURL(url);
}

//=============================================================================
// FORMATTERS
//=============================================================================
function fmt(n) {
  if (n == null || isNaN(n)) return "—";
  const locale = data?.settings?.locale || DEFAULT_LOCALE;
  const currency = data?.settings?.currency || "EUR";
  // A free-text typo in Settings (e.g. "EU" instead of "EUR") makes Intl throw
  // a RangeError and blanks the page mid-render. Fall back to EUR rather than
  // taking the whole UI down.
  try {
    return new Intl.NumberFormat(locale, { style: "currency", currency }).format(n);
  } catch {
    return new Intl.NumberFormat(locale, { style: "currency", currency: "EUR" }).format(n);
  }
}
function fmtNum(n) {
  return new Intl.NumberFormat(data?.settings?.locale || DEFAULT_LOCALE,
    { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n);
}
function fmtDate(iso) {
  if (!iso) return '';
  return new Intl.DateTimeFormat(data?.settings?.locale || DEFAULT_LOCALE,
    { day: 'numeric', month: 'short', year: 'numeric' }).format(parseDate(iso));
}
function parseDate(s) { return new Date(s + "T00:00:00"); }
function addDays(d, n) { const r = new Date(d); r.setDate(r.getDate() + n); return r; }
function addMonths(d, n) { const r = new Date(d); r.setMonth(r.getMonth() + n); return r; }
// Step forward `n` months from a base date while preserving the original
// day-of-month. JS's setMonth overflows (Jan 31 + 1mo -> Mar 3), and naively
// chaining that mutation makes a Jan-31 recurring drift forever (Mar 3 -> Apr
// 3 -> May 3...). This re-anchors each step to (baseYear, baseMonth+n,
// baseDay) and clamps baseDay to the target month's last day.
function addMonthsAnchored(base, n) {
  const y = base.getFullYear();
  const m = base.getMonth() + n;
  const targetYear = y + Math.floor(m / 12);
  const targetMonth = ((m % 12) + 12) % 12;
  const lastDay = new Date(targetYear, targetMonth + 1, 0).getDate();
  const day = Math.min(base.getDate(), lastDay);
  return new Date(targetYear, targetMonth, day);
}
// Format a Date as YYYY-MM-DD using LOCAL components — using toISOString() here
// would convert to UTC and drop a day for users east of UTC.
function isoDate(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}
function todayISO() { return isoDate(new Date()); }
// DST-safe day delta: normalise both inputs to midnight LOCAL before
// subtracting. Without this, a 23h spring-forward / 25h fall-back day plus
// fractional time-of-day from `today = new Date()` can push the rounding
// across a 0.5 boundary and give an off-by-one result. After truncation,
// the only remaining DST drift is 1h between two midnights — well below
// the rounding threshold.
function daysBetween(a, b) {
  const da = new Date(a.getFullYear(), a.getMonth(), a.getDate());
  const db = new Date(b.getFullYear(), b.getMonth(), b.getDate());
  return Math.round((db - da) / 86400000);
}

//=============================================================================
// TOAST + MODAL
//=============================================================================
function toast(msg, ms = 2400, kind, action) {
  const t = document.getElementById("toast");
  if (!kind) {
    if (/fail|required|different|fill all|missing|invalid/i.test(msg)) kind = 'error';
    else if (/loaded|created|saved|applied|updated|refilled|moved|added|deleted|removed|imported|exported/i.test(msg)) kind = 'success';
    else kind = 'info';
  }
  // Errors interrupt the screen reader; success/info wait their turn.
  t.setAttribute("aria-live", kind === "error" ? "assertive" : "polite");
  // When an `action` ({label, onClick}) is supplied the toast gets an
  // interactive button. We swap textContent for a small DOM tree and flip
  // pointer-events on so the button is clickable; plain toasts keep the
  // existing pass-through behaviour.
  let classes = 'toast ' + kind + ' show';
  if (action && action.label && typeof action.onClick === 'function') {
    t.textContent = '';
    const span = document.createElement('span');
    span.textContent = msg;
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'toast-action';
    btn.textContent = action.label;
    btn.addEventListener('click', () => {
      t.classList.remove('show', 'has-action');
      clearTimeout(toast._t);
      action.onClick();
    });
    t.appendChild(span);
    t.appendChild(btn);
    // The action button auto-dismisses and isn't a natural keyboard stop, so for
    // undo toasts also surface the always-available Ctrl/⌘+Z path in the
    // (aria-live announced) text — rather than yanking focus into a transient
    // element, which strands focus on dismissal.
    if (action.onClick === performUndo) {
      const hint = document.createElement('span');
      hint.style.cssText = 'margin-left:8px;color:var(--text-dim);font-size:12px;';
      hint.textContent = 'or ⌘/Ctrl+Z';
      t.appendChild(hint);
    }
    classes += ' has-action';
  } else {
    t.textContent = msg;
  }
  t.className = classes;
  clearTimeout(toast._t);
  toast._t = setTimeout(() => t.classList.remove("show", "has-action"), ms);
}

// Modal a11y state — track which element was focused before opening so we can
// restore focus on close, and trap Tab/Shift+Tab inside the modal while open.
let _modalPrevFocus = null;
const FOCUSABLE_SEL = 'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), summary, [tabindex]:not([tabindex="-1"])';

function _modalFocusables() {
  return Array.from(document.getElementById("modal").querySelectorAll(FOCUSABLE_SEL))
    .filter(el => el.offsetParent !== null || el === document.activeElement);
}

// Native title tooltips don't surface on keyboard focus, and a bare focusable
// <span title> is announced inconsistently — mirror title into aria-label so
// keyboard + screen-reader users get the help text.
function linkHelpTips(root) {
  root.querySelectorAll('.help-tip[title]').forEach(t => {
    if (!t.getAttribute('aria-label')) t.setAttribute('aria-label', t.getAttribute('title'));
  });
}

// Desktop drag: move a modal by its title bar. Pointer-events based and gated on
// (pointer: fine) so it's a no-op on touch. Translates from the centered rest
// position and clamps so the WHOLE modal stays on-screen — the title bar is the
// only grab handle, so it must never leave the viewport. Offset accumulates
// across gestures on this modal; openModal resets it on the next open.
function makeModalDraggable(modal, handle) {
  if (!window.matchMedia('(pointer: fine)').matches) return;
  handle.style.cursor = 'move';
  handle.style.userSelect = 'none';
  let dx = 0, dy = 0, sx = 0, sy = 0, on = false;
  handle.addEventListener('pointerdown', e => {
    if (e.button !== 0) return;
    on = true; sx = e.clientX; sy = e.clientY;
    try { handle.setPointerCapture(e.pointerId); } catch (_) {}
    e.preventDefault();
  });
  handle.addEventListener('pointermove', e => {
    if (!on) return;
    const maxX = Math.max(0, (innerWidth  - modal.offsetWidth)  / 2 - 8);
    const maxY = Math.max(0, (innerHeight - modal.offsetHeight) / 2 - 8);
    dx = Math.max(-maxX, Math.min(maxX, dx + e.clientX - sx));
    dy = Math.max(-maxY, Math.min(maxY, dy + e.clientY - sy));
    sx = e.clientX; sy = e.clientY;
    modal.style.transform = `translate(${dx}px, ${dy}px)`;
  });
  const end = e => { if (on) { on = false; try { handle.releasePointerCapture(e.pointerId); } catch (_) {} } };
  handle.addEventListener('pointerup', end);
  handle.addEventListener('pointercancel', end);
}

function openModal(html, opts) {
  _modalPrevFocus = document.activeElement;
  const modal = document.getElementById("modal");
  modal.innerHTML = html;
  // Reset each open: clear any drag offset / resized dimensions left on the
  // reused #modal element by a previous dialog so this one opens centered.
  // The class list is reset the same way, so a per-dialog variant (`wide`,
  // `co-modal`) can never leak into the next modal opened.
  modal.className = "modal" + (opts && opts.className ? " " + opts.className : "");
  modal.style.transform = '';
  modal.style.width = '';
  modal.style.height = '';
  // Auto-label the dialog from the first heading (h2) inside it so screen
  // readers announce the modal title; fall back to a generic label.
  const heading = modal.querySelector("h2, h3");
  if (heading && !heading.id) heading.id = "modalTitle";
  // Programmatically associate each field's <label> with its control so screen
  // readers announce inputs by name and clicking the label focuses it. Pattern:
  // <div class="field"><label>Name</label><input id="..."></div>. Skip labels
  // that already wrap their control (checkbox/radio rows) or already have `for`.
  modal.querySelectorAll("label").forEach(label => {
    if (label.htmlFor || label.querySelector("input, select, textarea")) return;
    const field = label.closest(".field") || label.parentElement;
    const ctrl = field && field.querySelector("input, select, textarea");
    if (!ctrl) return;
    if (!ctrl.id) ctrl.id = "fld_" + uid();
    label.htmlFor = ctrl.id;
  });
  linkHelpTips(modal);
  if (heading) makeModalDraggable(modal, heading);
  document.getElementById("modalBg").classList.add("open");
  // Focus the first focusable element on next tick (modal must be visible).
  setTimeout(() => {
    const f = _modalFocusables();
    if (f.length) f[0].focus();
    else modal.focus();
  }, 0);
}
function closeModal() {
  document.getElementById("modalBg").classList.remove("open");
  // Restore focus to whatever triggered the modal so keyboard users don't lose
  // their place. Guard against the element no longer being in the DOM.
  if (_modalPrevFocus && document.contains(_modalPrevFocus)) {
    try { _modalPrevFocus.focus(); } catch (_) {}
  }
  _modalPrevFocus = null;
}
// Backdrop click closes — but ONLY when the press *started* on the backdrop.
// Resizing a modal (grip at its corner) or dragging its title bar can release
// the pointer over the backdrop, which would otherwise fire a click whose target
// is #modalBg and close the dialog mid-interaction. Requiring pointerdown to have
// landed on the backdrop too rules that out.
let _modalBgPressedOnBg = false;
document.getElementById("modalBg").addEventListener("pointerdown", e => {
  _modalBgPressedOnBg = e.target.id === "modalBg";
});
document.getElementById("modalBg").addEventListener("click", e => {
  if (e.target.id === "modalBg" && _modalBgPressedOnBg) closeModal();
  _modalBgPressedOnBg = false;
});

// Keyboard cheatsheet — opened with '?' from anywhere outside an input/modal.
function showShortcuts() {
  openModal(`
    <h2>Keyboard shortcuts</h2>
    <table style="width:100%; border-collapse:collapse;">
      <tbody>
        <tr><td style="padding:6px 8px;"><kbd>Ctrl</kbd>/<kbd>⌘</kbd>+<kbd>K</kbd></td><td style="padding:6px 8px; color:var(--text-dim);">Command palette (jump anywhere / run any action)</td></tr>
        <tr><td style="padding:6px 8px;"><kbd>n</kbd></td><td style="padding:6px 8px; color:var(--text-dim);">New transaction</td></tr>
        <tr><td style="padding:6px 8px;"><kbd>c</kbd></td><td style="padding:6px 8px; color:var(--text-dim);">Duplicate the focused/hovered transaction to today</td></tr>
        <tr><td style="padding:6px 8px;"><kbd>Ctrl</kbd>+<kbd>Z</kbd></td><td style="padding:6px 8px; color:var(--text-dim);">Undo last destructive change (delete or apply recurring)</td></tr>
        <tr><td style="padding:6px 8px;"><kbd>Ctrl</kbd>+<kbd>Y</kbd> / <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd></td><td style="padding:6px 8px; color:var(--text-dim);">Redo what you just undid</td></tr>
        <tr><td style="padding:6px 8px;"><kbd>?</kbd></td><td style="padding:6px 8px; color:var(--text-dim);">Show this list</td></tr>
        <tr><td style="padding:6px 8px;"><kbd>Esc</kbd></td><td style="padding:6px 8px; color:var(--text-dim);">Close any open modal</td></tr>
        <tr><td style="padding:6px 8px;"><kbd>Enter</kbd></td><td style="padding:6px 8px; color:var(--text-dim);">Submit the current form</td></tr>
        <tr><td style="padding:6px 8px;"><kbd>Tab</kbd> / <kbd>Shift+Tab</kbd></td><td style="padding:6px 8px; color:var(--text-dim);">Cycle through controls (stays inside open modal)</td></tr>
      </tbody>
    </table>
    <div class="modal-actions"><button class="btn" onclick="closeModal()">Close</button></div>
  `);
}
// Modal keyboard handling: Escape closes; Tab/Shift+Tab cycle within the modal.
document.getElementById("modalBg").addEventListener("keydown", e => {
  if (!document.getElementById("modalBg").classList.contains("open")) return;
  if (e.key === "Escape") { e.preventDefault(); closeModal(); return; }
  if (e.key === "Tab") {
    const f = _modalFocusables();
    if (!f.length) { e.preventDefault(); return; }
    const first = f[0], last = f[f.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  }
});

//=============================================================================
// COMPUTED HELPERS
//=============================================================================
function accountById(id) { return data.accounts.find(a => a.id === id); }
function envelopeById(id) { return data.envelopes.find(e => e.id === id); }

// ARCHIVED ACCOUNTS AND ENVELOPES (decision #42). `archived: true` hides a
// record from lists, pickers, Fund the month, close-out and the forecast's
// default selection while every transaction that references it stays put:
// balances, net worth and history do not move. An archived envelope also has
// no budget (envMonthlyEquiv returns 0), which is what keeps it out of the
// allowance projection and the monthly-budget totals. Pickers still list an
// archived record when the entry being edited already points at it, marked
// "(archived)", so re-saving an old transaction can't silently drop it.
function activeAccounts() { return data.accounts.filter(a => !a.archived); }
function activeEnvelopes() { return data.envelopes.filter(e => !e.archived); }
// A picker's list: the active records plus whichever archived ones the
// current selection names (`selected` = one id or an array of ids).
function pickerList(list, selected) {
  const keep = new Set([].concat(selected || []).filter(Boolean));
  return list.filter(x => !x.archived || keep.has(x.id));
}
const pickAccounts = sel => pickerList(data.accounts, sel);
const pickEnvelopes = sel => pickerList(data.envelopes, sel);
const archSuffix = x => x.archived ? ' (archived)' : '';

// Suggest envelope + account defaults for a payee based on history. Used by
// editTransaction to pre-fill the form when the user types a payee they've
// used before. Case-insensitive exact match on the trimmed payee string;
// returns the most-common envelopeId and most-common accountId from prior
// transactions, or null if no match. Only considers expense/income (not
// transfers — they don't have a single primary envelope or account).
// Payees the app books on its own; they are bookkeeping, not somewhere the
// user shops, so they stay out of the payee picker and out of fuzzy matching.
const BOOKKEEPING_PAYEES = new Set(['Envelope refill', 'Close-out adjustment', 'Close-out sweep', 'Market adjustment']);

// Distinct user-typed payees, most recently used first, for the tx form's
// <datalist>. Capped so a years-old file doesn't ship a 5,000-option list.
function payeeHistory(limit = 300) {
  const seen = new Set(), out = [];
  for (let i = data.transactions.length - 1; i >= 0 && out.length < limit; i--) {
    const p = (data.transactions[i].payee || '').trim();
    if (!p || BOOKKEEPING_PAYEES.has(p)) continue;
    const k = p.toLowerCase();
    if (seen.has(k)) continue;
    seen.add(k); out.push(p);
  }
  return out;
}

// Index of normalised payee → its transactions, built once per CSV review so
// fuzzy matching 200 statement rows doesn't rescan the tx list 200 times.
function payeeIndex() {
  const m = new Map();
  for (const t of data.transactions) {
    const p = (t.payee || '').trim();
    if (!p || BOOKKEEPING_PAYEES.has(p)) continue;
    const k = p.toLowerCase();
    if (!m.has(k)) m.set(k, { key: k, payee: p, txs: [] });
    m.get(k).txs.push(t);
  }
  return [...m.values()];
}

// suggestPayeeDefaults(payee, opts?) → { accountId, envelopeId, tag, sampleCount,
// matchedPayee } or null. An exact (case-insensitive) match wins. With
// opts.fuzzy, a description that merely CONTAINS a prior payee — or is
// contained by one — matches too, longest prior payee first: bank statement
// lines ("CARD 1234 SUPERMARKET ATHENS 12/08") almost never equal the name the
// user typed by hand, so exact-only meant CSV import learned nothing from
// history. Four-character minimum so "sa" can't claim every row.
function suggestPayeeDefaults(payee, opts) {
  if (!payee || !payee.trim()) return null;
  const key = payee.trim().toLowerCase();
  // Account/envelope defaults come from expense+income history only (a
  // transfer has neither); the tag suggestion looks at every type, because
  // a tagged transfer ("petty cash" → Work) is exactly the case worth
  // repeating.
  let all = data.transactions.filter(t => (t.payee || '').trim().toLowerCase() === key);
  let matchedPayee = null;
  if (!all.length && opts && opts.fuzzy && key.length >= 4) {
    const idx = opts.index || payeeIndex();
    let best = null;
    for (const e of idx) {
      if (e.key.length < 4) continue;
      if (!(key.includes(e.key) || e.key.includes(key))) continue;
      if (!best || e.key.length > best.key.length) best = e;
    }
    if (best) { all = best.txs; matchedPayee = best.payee; }
  }
  const matches = all.filter(t => t.type === 'expense' || t.type === 'income');
  if (!all.length) return null;
  const mostCommon = (arr, getter) => {
    const counts = new Map();
    for (const item of arr) {
      const v = getter(item);
      if (v) counts.set(v, (counts.get(v) || 0) + 1);
    }
    let best = null, bestCount = 0;
    for (const [v, c] of counts) if (c > bestCount) { best = v; bestCount = c; }
    return best;
  };
  return {
    accountId: mostCommon(matches, t => t.accountId),
    envelopeId: mostCommon(matches, t => t.envelopeId),
    tag: mostCommon(all, t => t.tag),
    sampleCount: all.length,
    matchedPayee
  };
}

// Read a CSS custom property off <body> so chart code follows the active
// theme. Fallback is the original dark-mode hex so charts still render if a
// token is missing (e.g. on a partially-loaded stylesheet).
function themeColor(name, fallback) {
  const v = getComputedStyle(document.body).getPropertyValue(name).trim();
  return v || fallback;
}
function chartPalette() {
  return [
    themeColor('--accent', '#4fc3a1'),
    themeColor('--accent-2', '#5b8def'),
    themeColor('--warn', '#f0a64a'),
    themeColor('--bad', '#e06c75'),
    '#c678dd', '#56b6c2', '#d19a66', '#98c379',
    themeColor('--text-dim', '#abb2bf')
  ];
}

//---------------------------------------------------------------------------
// TRANSACTION TAGS
// One optional tag per transaction (and per recurring template), chosen from
// the small user-defined list in settings.tags. Stored as the tag's name
// string; undefined = untagged. Colour = position in the list, taken from
// chartPalette() so a chip and its chart slice always match and follow the
// theme. Tags that name nothing in the list ("stray": hand-edited file, an
// import from a device with a different list) are tolerated everywhere and
// drawn as a plain grey chip — see the note in migrate().
//---------------------------------------------------------------------------
function tagList() { return (data && data.settings && data.settings.tags) || []; }
function strayTags() {
  const known = new Set(tagList());
  const out = new Set();
  for (const t of data.transactions) if (t.tag && !known.has(t.tag)) out.add(t.tag);
  for (const r of data.recurring) if (r.tag && !known.has(r.tag)) out.add(r.tag);
  return [...out].sort((a, b) => a.localeCompare(b));
}
function allTags() { return [...tagList(), ...strayTags()]; }
function tagIndex(tag) { return tagList().indexOf(tag); }
function tagColor(tag) {
  const i = tagIndex(tag);
  // The palette's last entry (--text-dim) is reserved for "Untagged" in the charts.
  return i < 0 ? null : chartPalette()[i % (chartPalette().length - 1)];
}
function tagChip(tag) {
  if (!tag) return '';
  const c = tagColor(tag);
  return `<span class="badge tag"${c ? ` style="--tag-c:${esc(c)}"` : ''} title="Tag: ${esc(tag)}">${esc(tag)}</span>`;
}
// <option>s for a tag <select>. A stray value on the record being edited is
// appended as "(unlisted)" so opening and saving the form can't silently clear it.
function tagOptions(selected) {
  const list = tagList();
  let html = `<option value="">— no tag —</option>` +
    list.map(t => `<option value="${esc(t)}" ${t === selected ? 'selected' : ''}>${esc(t)}</option>`).join('');
  if (selected && !list.includes(selected)) html += `<option value="${esc(selected)}" selected>${esc(selected)} (unlisted)</option>`;
  return html;
}
// Returns an error message, or null when the name is acceptable. `ignore` is
// the tag being renamed, so a case-only rename of itself passes.
function validateTagName(name, ignore) {
  const s = (name || '').trim();
  if (!s) return 'Tag name is empty';
  if (s.length > 24) return 'Tag names are limited to 24 characters';
  const dup = tagList().find(t => t !== ignore && t.toLowerCase() === s.toLowerCase());
  if (dup) return `A tag named "${dup}" already exists`;
  return null;
}
function tagUsage(tag) {
  return {
    tx: data.transactions.filter(t => t.tag === tag).length,
    rec: data.recurring.filter(r => r.tag === tag).length
  };
}
// Both cascades leave pushUndo() to the caller (Settings does it), so the
// snapshot label can say which action it was.
function renameTag(oldName, newName) {
  const i = tagIndex(oldName);
  if (i >= 0) data.settings.tags[i] = newName;
  for (const t of data.transactions) if (t.tag === oldName) t.tag = newName;
  for (const r of data.recurring) if (r.tag === oldName) r.tag = newName;
}
function deleteTag(name) {
  const i = tagIndex(name);
  if (i >= 0) data.settings.tags.splice(i, 1);
  for (const t of data.transactions) if (t.tag === name) delete t.tag;
  for (const r of data.recurring) if (r.tag === name) delete r.tag;
}

// Safely evaluate a small arithmetic expression in an Amount field so the
// user can do "balance minus what I want to keep" without leaving the modal.
// Whitelist: digits, decimal point, + - * /, parens. Anything else returns
// NaN. Comma is normalised to dot so European decimals ("," as separator)
// work identically to "." — so an entry like "2380,50-100" parses.
// Implementation uses the Function constructor on the sanitised string; the
// regex above guarantees no identifiers, function calls, or other code can
// reach it.
function evalAmount(s) {
  s = String(s == null ? '' : s).replace(/,/g, '.').replace(/\s+/g, '');
  if (!s) return NaN;
  if (!/^[\d.+\-*/()]+$/.test(s)) return NaN;
  try {
    const v = Function('"use strict"; return (' + s + ')')();
    return (typeof v === 'number' && isFinite(v)) ? v : NaN;
  } catch {
    return NaN;
  }
}

// "1 cat" / "2 cats", with an explicit irregular plural where needed
// (e.g. plural(n, 'entry', 'entries')). Centralises the `n === 1 ? '' : 's'` idiom.
function plural(n, one, many) {
  return `${n} ${n === 1 ? one : (many || one + 's')}`;
}

// Wire an Amount field's live arithmetic preview: "= 75,00 €" when the value
// contains an operator, "⚠ invalid expression" when evalAmount can't parse it,
// nothing for a plain number. Returns the update fn so callers can prime the
// preview once. Shared by Add Tx, Move Funds, recurring entry, investment value.
function wireAmountPreview(inputId, previewId) {
  const input = document.getElementById(inputId);
  const preview = document.getElementById(previewId);
  const update = () => {
    const raw = input.value;
    if (!/[+\-*/()]/.test(raw)) { preview.textContent = ''; return; }
    const v = evalAmount(raw);
    preview.textContent = isNaN(v) ? '⚠ invalid expression' : '= ' + fmt(Math.abs(v));
  };
  input.addEventListener('input', update);
  return update;
}

// Returns net change a transaction applies to account/envelope, signed.
// type=expense -> account decreases, envelope decreases (consumed)
// type=income  -> account increases, envelope increases (funded)
// type=transfer-account -> from account decreases, to account increases (no envelope effect)
// type=transfer-envelope -> from envelope decreases, to envelope increases (no account effect)
function txAccountDelta(tx, accountId) {
  if (tx.type === "expense" && tx.accountId === accountId) return -Math.abs(tx.amount);
  if (tx.type === "income" && tx.accountId === accountId) return Math.abs(tx.amount);
  if (tx.type === "transfer-account") {
    if (tx.fromAccountId === accountId) return -Math.abs(tx.amount);
    if (tx.toAccountId === accountId) return Math.abs(tx.amount);
  }
  return 0;
}
// Unsigned amount an expense/income tx allocates to a given envelope.
// Split-aware: a tx with splits[] distributes tx.amount across envelopes; a
// plain tx puts the whole amount on tx.envelopeId. Single source of truth so
// balances, reports, forecast and close-out all agree on splits.
function txEnvelopePortion(tx, envelopeId) {
  if (tx.type !== "expense" && tx.type !== "income") return 0;
  if (tx.splits && tx.splits.length) {
    let s = 0;
    for (const sp of tx.splits) if (sp.envelopeId === envelopeId) s += Math.abs(sp.amount || 0);
    return s;
  }
  return tx.envelopeId === envelopeId ? Math.abs(tx.amount) : 0;
}
function txEnvelopeDelta(tx, envelopeId) {
  if (tx.type === "expense") return -txEnvelopePortion(tx, envelopeId);
  if (tx.type === "income") return txEnvelopePortion(tx, envelopeId);
  if (tx.type === "transfer-envelope") {
    if (tx.fromEnvelopeId === envelopeId) return -Math.abs(tx.amount);
    if (tx.toEnvelopeId === envelopeId) return Math.abs(tx.amount);
  }
  return 0;
}

function accountBalance(account) {
  // start from openingBalance + sum transaction deltas up to today
  const today = todayISO();
  let bal = account.openingBalance || 0;
  for (const tx of data.transactions) {
    if (tx.date <= today) bal += txAccountDelta(tx, account.id);
  }
  return bal;
}
function envelopeBalance(env) {
  const today = todayISO();
  let bal = env.openingBalance || 0;
  for (const tx of data.transactions) {
    if (tx.date <= today) bal += txEnvelopeDelta(tx, env.id);
  }
  return bal;
}

// Monthly-equivalent budget: an annual envelope of €600 contributes €50/month
// to dashboard burn-rate totals and forecast smoothing. Monthly envelopes
// contribute their full amount.
function envMonthlyEquiv(e) {
  if (e.archived) return 0;   // out of the budget: no allowance, no totals, no close-out variance
  const b = e.budgetAmount || 0;
  return e.cadence === "annual" ? b / 12 : b;
}

// The reserve (emergency / catch-all) envelope, or null. At most one envelope
// carries the flag — editEnvelope clears it from every other envelope on save
// — but this defensively takes the first so a hand-edited file can't produce
// two sweep destinations.
function reserveEnvelope() {
  return data.envelopes.find(e => e.isReserve) || null;
}

function totalNetWorth() {
  let v = 0;
  for (const a of data.accounts) {
    if (a.includeInNetWorth === false) continue;
    v += accountBalance(a);
  }
  return v;
}
function totalAssets() {
  let v = 0;
  for (const a of data.accounts) {
    if (a.includeInNetWorth === false) continue;
    const b = accountBalance(a);
    if (b > 0) v += b;
  }
  return v;
}
function totalLiabilities() {
  let v = 0;
  for (const a of data.accounts) {
    if (a.includeInNetWorth === false) continue;
    const b = accountBalance(a);
    if (b < 0) v += b;
  }
  return v;
}
function totalInvestments() {
  return data.accounts.filter(a => a.isInvestment)
    .reduce((s, a) => s + accountBalance(a), 0);
}

//=============================================================================
// RECURRING TRANSACTIONS - generate occurrences
//=============================================================================
function* recurringOccurrences(rec, fromDate, toDate) {
  // schedule: {kind: "monthly"|"weekly"|"biweekly"|"yearly"|"once",
  //   dayOfMonth?, dayOfWeek?, month?, day?, startDate, endDate?}
  const start = parseDate(rec.startDate || todayISO());
  const end = rec.endDate ? parseDate(rec.endDate) : null;
  const horizon = toDate < (end || toDate) ? toDate : (end || toDate);

  if (rec.schedule === "once") {
    const d = parseDate(rec.startDate);
    if (d >= fromDate && d <= horizon) yield isoDate(d);
    return;
  }

  let cursor = new Date(start);
  // Fast-forward to within window
  if (rec.schedule === "monthly") {
    // Anchor on the original start so a Jan-31 recurring stays on the 31st
    // (clamped to month-end in shorter months) instead of drifting to the 3rd.
    let step = 0;
    while (cursor < fromDate) { step++; cursor = addMonthsAnchored(start, step); }
    while (cursor <= horizon) { yield isoDate(cursor); step++; cursor = addMonthsAnchored(start, step); }
  } else if (rec.schedule === "weekly") {
    while (cursor < fromDate) cursor = addDays(cursor, 7);
    while (cursor <= horizon) { yield isoDate(cursor); cursor = addDays(cursor, 7); }
  } else if (rec.schedule === "biweekly") {
    while (cursor < fromDate) cursor = addDays(cursor, 14);
    while (cursor <= horizon) { yield isoDate(cursor); cursor = addDays(cursor, 14); }
  } else if (rec.schedule === "yearly") {
    // Anchor on the original start so Feb-29 yearly stays on Feb-29 in leap
    // years and clamps to Feb-28 otherwise (instead of drifting to Mar-1).
    let step = 0;
    while (cursor < fromDate) { step++; cursor = addMonthsAnchored(start, step * 12); }
    while (cursor <= horizon) { yield isoDate(cursor); step++; cursor = addMonthsAnchored(start, step * 12); }
  } else if (rec.schedule === "custom-months") {
    // rec.months = [1,4,7,10] for quarterly etc; uses startDate's day of month.
    // Iterate year-by-year over the months list; gate each candidate on the
    // rec's startDate so months earlier in the start year (e.g. months=[3,6,9,12]
    // with startDate=2026-09-15) don't emit pre-start dates like March/June 2026.
    //
    // SORT ASCENDING — load-bearing, not tidiness. The loop walks the list in
    // order within each year and bails out of the whole generator on the first
    // candidate past the horizon. Stored unsorted (months=[12,4] is the natural
    // way to type "Christmas and Easter"), December is tested first, so:
    //   - a horizon ending mid-year returned on December and silently dropped
    //     every April occurrence — a 12-month forecast lost the entire spring
    //     bonus, and a past-due April never reached dueRecurringOccurrences();
    //   - the yielded sequence came out non-chronological (Dec 27 before Apr
    //     27), and firstPendingOccurrence takes the FIRST value yielded, so the
    //     Recurring tab could show a reassuring December date while an April
    //     occurrence was already overdue — the exact tab/dashboard disagreement
    //     fixed for monthly recurrings in the "Next column" change.
    // Sorted, dates increase monotonically within and across years, which is
    // the precondition the early return below assumes.
    const months = [...(rec.months || [])].sort((a, b) => a - b);
    let y = cursor.getFullYear();
    const dom = cursor.getDate();
    while (true) {
      for (const m of months) {
        // Clamp dom to the target month's last day (Jan 31 in custom-months
        // [1,2] would otherwise overflow Feb to Mar 3).
        const lastDay = new Date(y, m, 0).getDate();
        const d = new Date(y, m - 1, Math.min(dom, lastDay));
        if (d >= start && d >= fromDate && d <= horizon) yield isoDate(d);
        if (d > horizon) return;
      }
      y++;
      if (new Date(y, 0, 1) > horizon) return;
    }
  }
}

// Returns the next pending occurrence — the oldest scheduled date that hasn't
// been applied yet (per rec.lastAppliedDate). This CAN return a past date if the
// recurring is overdue — that's deliberate: the Recurring tab's "Next" column
// shows the oldest pending occurrence (flagged "Overdue" when past) so it agrees
// with the Dashboard's Review-Due banner. An earlier `nextDue` clamped its scan
// to today and stepped over overdue occurrences, which made the tab show a
// reassuring future date ("moved to July") while the dashboard still flagged the
// unrecorded June occurrence as due — the two views silently disagreed. Also
// used by "Apply next instance now" to decide which scheduled instance to consume.
function firstPendingOccurrence(rec) {
  const today = parseDate(todayISO());
  const fromD = recurringResumeDate(rec, rec.startDate ? parseDate(rec.startDate) : today);
  const horizon = addMonths(today, 24);
  // If fromD is already past the horizon (paused for years with a remote start)
  // extend the search window so we still find the next occurrence.
  const upper = fromD > horizon ? addMonths(fromD, 24) : horizon;
  for (const d of recurringOccurrences(rec, fromD, upper)) if (!isSkippedOccurrence(rec, d)) return d;
  return null;
}

// A deliberately skipped occurrence — the "this month's gym fee was waived"
// case. rec.skippedDates holds ISO dates the user chose to skip in the due
// review. It only ever lists dates AFTER lastAppliedDate: once the watermark
// moves past a skipped date the entry is pruned (see showDueReview), so the
// list stays short and lastAppliedDate keeps its single meaning. Both
// pending-occurrence readers honour it; the forecast doesn't need to, since
// skips are past dates and the forecast projects from tomorrow.
function isSkippedOccurrence(rec, iso) {
  return !!(rec.skippedDates && rec.skippedDates.includes(iso));
}

// Recurring entries are NOT auto-recorded. This finds occurrences whose date is
// on/before today and which haven't been applied yet (per rec.lastAppliedDate).
function dueRecurringOccurrences() {
  const today = todayISO();
  const out = [];
  for (const rec of data.recurring) {
    if (rec.active === false) continue;
    // Look back from one day after the last apply (or from startDate if never applied)
    const fromISO = isoDate(recurringResumeDate(rec, parseDate(rec.startDate || today)));
    const fromD = parseDate(fromISO);
    const todayD = parseDate(today);
    if (fromD > todayD) continue;
    for (const d of recurringOccurrences(rec, fromD, todayD)) {
      if (isSkippedOccurrence(rec, d)) continue;
      out.push({ rec, date: d });
    }
  }
  out.sort((a, b) => a.date.localeCompare(b.date));
  return out;
}

// Build a real transaction from a recurring template for a given date/amount.
// Single source of truth for the type→field routing (expense/income use
// account+envelope; transfers use from/to) — shared by applyDueRecurring, the
// due-review "Apply selected" handler, and applyRecurringInstanceNow so a new
// field or transfer subtype is added in exactly one place.
function recurringToTx(rec, date, amount) {
  const tx = {
    id: uid(), date, type: rec.type, amount,
    payee: rec.name, notes: "From recurring: " + rec.name, fromRecurringId: rec.id
  };
  if (rec.type === 'expense' || rec.type === 'income') {
    tx.accountId = rec.accountId || null;
    tx.envelopeId = rec.envelopeId || null;
  } else if (rec.type === 'transfer-account') {
    tx.fromAccountId = rec.fromAccountId;
    tx.toAccountId = rec.toAccountId;
  } else if (rec.type === 'transfer-envelope') {
    tx.fromEnvelopeId = rec.fromEnvelopeId;
    tx.toEnvelopeId = rec.toEnvelopeId;
  }
  if (rec.tag) tx.tag = rec.tag;
  return tx;
}

// One day after lastAppliedDate (so a just-consumed occurrence doesn't reappear),
// or `fallback` when the recurring was never applied. Returns a Date; callers
// needing an ISO string wrap with isoDate(). The fallback stays explicit per
// caller (today / tomorrow / startDate-or-today) — each is context-correct.
function recurringResumeDate(rec, fallback) {
  return rec.lastAppliedDate ? addDays(parseDate(rec.lastAppliedDate), 1) : fallback;
}

function applyDueRecurring() {
  const due = dueRecurringOccurrences();
  if (!due.length) return 0;
  pushUndo(`Apply ${due.length} recurring ${due.length === 1 ? "entry" : "entries"}`);
  for (const { rec, date } of due) {
    const tx = recurringToTx(rec, date, rec.amount);
    data.transactions.push(tx);
    rec.lastAppliedDate = date > (rec.lastAppliedDate || '') ? date : rec.lastAppliedDate;
  }
  // Each rec's lastAppliedDate is now its max applied occurrence — the sole
  // authority. We deliberately do NOT advance it to today: that would bury a
  // future-dated gap and re-introduce the silent skip fixed in the due-review
  // handler (decision #12). (Removed a dead no-op loop that claimed to do this.)
  saveDirty();
  return due.length;
}

//=============================================================================
// FORECAST
//=============================================================================
// Monthly-equivalent amount of a recurring, whatever its schedule. Used to
// net recurring streams against an envelope's budgeted allowance.
function recurringMonthlyEquiv(rec) {
  const a = Math.abs(rec.amount || 0);
  switch (rec.schedule) {
    case 'weekly':        return a * 52 / 12;
    case 'biweekly':      return a * 26 / 12;
    case 'yearly':        return a / 12;
    case 'custom-months': return a * ((rec.months || []).length) / 12;
    default:              return a;   // monthly
  }
}

// How much of this envelope's monthly budget is ALREADY modelled by active
// recurring transactions, and so must not be double-counted as a forecasted
// allowance outflow. Returns an amount, not a flag: this used to be boolean
// (`envelopeIsCoveredByRecurring`), so a single €50/mo subscription wiped out
// a €300/mo envelope's entire allowance and the forecast under-projected
// spending by €250 every month.
function recurringMonthlyForEnvelope(env) {
  let covered = 0;
  for (const rec of data.recurring) {
    if (rec.active === false) continue;
    if (rec.envelopeId === env.id) covered += recurringMonthlyEquiv(rec);
    // Only the destination of a transfer-envelope recurring counts — the
    // source envelope loses money on each occurrence and still needs its own
    // allowance smoothing. Counting both sides hid that drain.
    else if (rec.type === 'transfer-envelope' && rec.toEnvelopeId === env.id) {
      covered += recurringMonthlyEquiv(rec);
    }
  }
  return covered;
}

// BACKED ENVELOPES (decision #41). An envelope may name the account that holds
// its money (env.accountId — "Backed by" in the envelope dialog). The forecast
// uses it in two places: a backed envelope is subtracted from spendable only
// when its account is among the selected ones, and its allowance drains from
// that account rather than from the spending-history guess. An envelope with
// no backing account is household-wide: it is subtracted from every selection
// and its allowance routes by history, exactly as every envelope did before
// the field existed — so a file that never sets it forecasts as before.
function envelopeBackingAccount(env) {
  if (!env || !env.accountId) return null;
  return accountById(env.accountId) || null;   // a dangling id degrades to household
}
// Does this envelope's balance count against the spendable line of a forecast
// over `accountIds`? Household envelopes always do; backed ones only when
// their account is selected.
function envelopeCountsFor(env, accountIds) {
  const acc = envelopeBackingAccount(env);
  return !acc || accountIds.includes(acc.id);
}

// Pick a "spending account" for an envelope when projecting its allowance.
// Rules:
//   0. A backed envelope drains from its backing account — if that account is
//      among the forecast-selected ones; otherwise null (its money is not in
//      this forecast at all, so neither is its spending).
//   1. If there's expense history for this envelope, use the most recent
//      expense's account — but only if it's among the forecast-selected
//      accounts. If it isn't, return null (don't re-route to a different
//      account; the user is purposefully filtering that one out).
//   2. If there's no history at all, fall back to the first selected
//      non-investment account.
function envelopeSpendingAccount(env, candidateAccountIds) {
  const backing = envelopeBackingAccount(env);
  if (backing) return candidateAccountIds.includes(backing.id) ? backing : null;
  let bestTx = null;
  for (const tx of data.transactions) {
    if (tx.type === "expense" && tx.envelopeId === env.id && tx.accountId) {
      if (!bestTx || tx.date > bestTx.date) bestTx = tx;
    }
  }
  if (bestTx) {
    const a = accountById(bestTx.accountId);
    return (a && candidateAccountIds.includes(a.id)) ? a : null;
  }
  for (const id of candidateAccountIds) {
    const a = accountById(id);
    if (a && !a.isInvestment && !a.archived) return a;
  }
  return null;
}

function forecastAccountBalances(accountIds, days, opts) {
  // returns { dates, series, total, envelopeTotal, spendable, allowanceInfo,
  //           excludedEnvelopes }
  // - total: sum of selected account balances over time
  // - envelopeTotal: sum of the envelope balances that live in the selected
  //   accounts, each floored at zero: every household envelope (no backing
  //   account) plus every envelope backed by a selected account. Envelopes
  //   backed by an account outside the selection are listed in
  //   excludedEnvelopes and subtracted from nothing — their money is not in
  //   `total` either (decision #41). Projected spending draws down the
  //   envelope it belongs to before it reaches spendable; see the clamp at
  //   the aggregation step.
  // - spendable: total − envelopeTotal, i.e. how much of the selected
  //   accounts' projected balance is NOT earmarked by any envelope.
  opts = opts || {};
  const includeAllowances = !!opts.includeAllowances;
  // Defensive: drop ids whose account no longer exists. series[] below is only
  // seeded for live accounts (missing ones are `continue`d past), so an orphan
  // id — e.g. a deleted account still referenced by a saved forecast profile or
  // the persisted selection — would make the cumulative/total loops index an
  // undefined series and throw, blanking BOTH the Forecast tab and the
  // Dashboard's forecast card.
  accountIds = (accountIds || []).filter(id => accountById(id));
  const today = parseDate(todayISO());
  const dates = [];
  for (let i = 0; i <= days; i++) dates.push(isoDate(addDays(today, i)));

  const series = {};
  for (const accId of accountIds) {
    const acc = accountById(accId);
    if (!acc) continue;
    series[accId] = new Array(days + 1).fill(0);
    series[accId][0] = accountBalance(acc);
  }
  // Per-envelope projected balance — one series each, seeded with today's
  // balance, then layered with future deltas the same way we do for accounts.
  // These are aggregated into `envelopeTotal` at the end with a FLOOR AT ZERO
  // per envelope (see the clamp below for why it can't be one running total).
  const envSeries = {};
  for (const e of data.envelopes) {
    envSeries[e.id] = new Array(days + 1).fill(0);
    envSeries[e.id][0] = envelopeBalance(e);
  }

  // Fold due-but-unapplied recurring occurrences into idx 0. The starting
  // balance and envelope totals above reflect only POSTED transactions — they
  // miss bills whose scheduled date is on/before today that the user hasn't
  // yet applied via the dashboard ⚡ button. Without this step the forecast
  // (and its "lowest in period" stat) is optimistic by exactly the sum of
  // those dues: the dip lands the moment the user clicks Apply, but never
  // shows up in the projection. A user who wants to exclude a due (e.g. a
  // cancelled subscription) still dismisses it via the dashboard banner,
  // which advances rec.lastAppliedDate and drops it from this list.
  for (const { rec } of dueRecurringOccurrences()) {
    const fakeTx = {
      type: rec.type,
      amount: rec.amount,
      accountId: rec.accountId,
      envelopeId: rec.envelopeId,
      fromAccountId: rec.fromAccountId,
      toAccountId: rec.toAccountId,
      fromEnvelopeId: rec.fromEnvelopeId,
      toEnvelopeId: rec.toEnvelopeId
    };
    for (const accId of accountIds) {
      const delta = txAccountDelta(fakeTx, accId);
      if (delta !== 0) series[accId][0] += delta;
    }
    for (const env of data.envelopes) {
      const ed = txEnvelopeDelta(fakeTx, env.id);
      if (ed !== 0) envSeries[env.id][0] += ed;
    }
  }

  // For each recurring transaction, project occurrences forward and apply delta
  const horizon = parseDate(dates[dates.length - 1]);
  const tomorrow = addDays(today, 1);

  for (const rec of data.recurring) {
    if (rec.active === false) continue;
    // Skip occurrences on/before lastAppliedDate — otherwise an instance the
    // user already materialised via "Apply next instance today" (which sets
    // lastAppliedDate to the scheduled date and posts a real tx dated today)
    // would be counted a second time on its scheduled date in the forecast.
    // Mirrors the same guard the dashboard's "Upcoming 7 days" panel uses.
    const recFromD = recurringResumeDate(rec, tomorrow);
    const recFromDate = recFromD > tomorrow ? recFromD : tomorrow;
    for (const d of recurringOccurrences(rec, recFromDate, horizon)) {
      const idx = daysBetween(today, parseDate(d));
      if (idx < 0 || idx > days) continue;
      const fakeTx = {
        type: rec.type,
        amount: rec.amount,
        accountId: rec.accountId,
        envelopeId: rec.envelopeId,
        fromAccountId: rec.fromAccountId,
        toAccountId: rec.toAccountId,
        fromEnvelopeId: rec.fromEnvelopeId,
        toEnvelopeId: rec.toEnvelopeId
      };
      for (const accId of accountIds) {
        const delta = txAccountDelta(fakeTx, accId);
        if (delta !== 0) series[accId][idx] += delta;
      }
      for (const env of data.envelopes) {
        const ed = txEnvelopeDelta(fakeTx, env.id);
        if (ed !== 0) envSeries[env.id][idx] += ed;
      }
    }
  }

  // Also include scheduled future one-off transactions already in tx log
  for (const tx of data.transactions) {
    if (tx.date <= todayISO()) continue;
    const idx = daysBetween(today, parseDate(tx.date));
    if (idx < 0 || idx > days) continue;
    for (const accId of accountIds) {
      const delta = txAccountDelta(tx, accId);
      if (delta !== 0) series[accId][idx] += delta;
    }
    for (const env of data.envelopes) {
      const ed = txEnvelopeDelta(tx, env.id);
      if (ed !== 0) envSeries[env.id][idx] += ed;
    }
  }

  // Optional: project envelope monthly allowances as smoothed daily outflows
  // against each envelope's "spending account". Nets off the amount active
  // recurrings already model for that envelope (decision #23 — a partial
  // amount, not a skip); an envelope fully covered that way is skipped.
  //
  // CALENDAR-ANCHORED SMOOTHING (fix 2026-05-14):
  // The previous version drained `daily` from days [1..N] of a rolling window
  // anchored at "today". That meant the cumulative drain at any fixed future
  // calendar date silently dropped by `daily` every time today advanced — so
  // "Lowest in period" rose by ~€daily/day even when no real spending happened.
  // Now we anchor the smoothing to the calendar month: each FUTURE month
  // contributes its full monthly allowance regardless of which day of the
  // month you ask from, so the cumulative drain at any future-month date is
  // independent of today's date — and so is the minimum point, which is what
  // "Lowest in period" measures. The CURRENT month is not a full month: it
  // contributes only what is left of each envelope's budget after the
  // spending already posted this month (decision #34), spread across the days
  // that remain. Re-charging the elapsed part of the month — which the
  // original catch-up did — double-counts spending that is already inside
  // accountBalance().
  const allowanceInfo = { included: [], skipped: [], unassigned: [], totalMonthly: 0 };
  if (includeAllowances) {
    // Smoothing anchors:
    //   todayDay              = today's day-of-month (1..31). Days already "used".
    //   daysInThisMonth       = 28/29/30/31 of the current calendar month.
    //   remainingAfterToday   = days strictly after today, up to month-end (0..30).
    //                           These are the days the projection actually visits
    //                           inside the current month (the loop runs i=1..days,
    //                           and i=1 is tomorrow).
    // remainingAfterToday is the denominator for the current month: whatever
    // is left of an envelope's budget is spread evenly over those days. When
    // it is 0 (today is the last day of the month) the current month drains
    // nothing more and the projection resumes on the 1st.
    const todayDay = today.getDate();
    const daysInThisMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();
    const remainingAfterToday = daysInThisMonth - todayDay;
    // CURRENT MONTH = WHAT'S LEFT OF IT, NOT A FRESH ONE (fix 2026-08-19).
    // The elapsed part of this month used to be "caught up" — redistributed
    // into the days that remain — so on the 19th of a 31-day month the whole
    // monthly allowance was drained across the last 12 days. But the spending
    // that actually happened in those 19 days is ALREADY subtracted from
    // accountBalance(), so the month was charged twice: once really, once
    // again as smoothed allowance. Measured on a real month (12 envelopes,
    // on the 19th): every horizon — 30, 90 and 365 days — came out low by
    // the same constant, which was to the cent the month's posted envelope
    // spending, and it manufactured a spendable dip a week out that did not
    // exist. The catch-up was introduced to keep the projection
    // stable as today advances; that goal is preserved where it matters,
    // because only the CURRENT month's rate now moves — every future month
    // still drains exactly one month's allowance, so a minimum falling in a
    // future month (the usual case) is as stable as before. The current
    // month's figure now tracks what you have actually spent, which is
    // information rather than noise.
    // Diagnostic only — nothing renders this today; it exists so the smoothing
    // anchors are inspectable from the console when a projection looks wrong.
    allowanceInfo.calendarAnchor = {
      monthStart: isoDate(new Date(today.getFullYear(), today.getMonth(), 1)),
      todayDay,
      remainingAfterToday
    };
    // Per-day fraction OF ONE MONTH'S allowance to drain, precomputed once for
    // every projected day and reused for every envelope (it depends only on the
    // calendar, not on the envelope). Each day divides by ITS OWN month length,
    // so every future calendar month drains exactly `monthly` — no more, no
    // less. The previous code used a fixed monthly/30.44 rate, which made a
    // 31-day month over-drain by 1.8% and February under-drain by 8%, breaking
    // the very invariant the calendar-anchor comment above claims to hold.
    //
    // dayFactor covers FUTURE months only (1 / that month's own length, so each
    // future calendar month drains exactly one month's allowance — decision
    // #24). Days inside the current month get a per-envelope rate instead,
    // computed in the loop below, because how much of this month's budget is
    // left differs per envelope.
    const dayFactor = new Array(days + 1).fill(0);
    const inCurrentMonth = new Array(days + 1).fill(false);
    for (let i = 1; i <= days; i++) {
      const projDate = addDays(today, i);
      const cur =
        projDate.getFullYear() === today.getFullYear() &&
        projDate.getMonth() === today.getMonth();
      inCurrentMonth[i] = cur;
      dayFactor[i] = cur ? 0
        : 1 / new Date(projDate.getFullYear(), projDate.getMonth() + 1, 0).getDate();
    }
    // What each envelope has already consumed this calendar month, from posted
    // transactions. Split-aware via txEnvelopePortion, and one-sided envelope
    // bookkeeping (refills, close-out resets, balance adjustments) is excluded
    // by isCashflowTx — those move no real money and must not be read as
    // "this month's budget is already used up" (decision #26).
    //
    // Transactions materialised from a recurring that ALREADY covers this
    // envelope are skipped: `covered` below nets that recurring off the
    // allowance for the whole month, so counting its posted occurrence here
    // too would subtract it twice and make the month optimistic.
    const monthStartKey = isoDate(new Date(today.getFullYear(), today.getMonth(), 1));
    const todayKey = todayISO();
    const coveringRecs = {};   // envelopeId -> Set of recurring ids netted off below
    for (const rec of data.recurring) {
      if (rec.active === false) continue;
      const envId = rec.envelopeId || (rec.type === 'transfer-envelope' ? rec.toEnvelopeId : null);
      if (!envId) continue;
      (coveringRecs[envId] = coveringRecs[envId] || new Set()).add(rec.id);
    }
    const spentThisMonth = {};
    for (const tx of data.transactions) {
      if (tx.date < monthStartKey || tx.date > todayKey) continue;
      if (tx.type !== 'expense' || !isCashflowTx(tx)) continue;
      for (const e of data.envelopes) {
        if (tx.fromRecurringId && coveringRecs[e.id] && coveringRecs[e.id].has(tx.fromRecurringId)) continue;
        const portion = txEnvelopePortion(tx, e.id);
        if (portion) spentThisMonth[e.id] = (spentThisMonth[e.id] || 0) + portion;
      }
    }
    for (const env of data.envelopes) {
      const budgeted = envMonthlyEquiv(env);
      if (budgeted <= 0) continue;
      // Partial coverage: subtract only what active recurrings already model,
      // not the whole allowance. A €50/mo subscription on a €300/mo envelope
      // used to zero the entire allowance, under-projecting spending by €250 a
      // month on both the total and spendable lines.
      const covered = recurringMonthlyForEnvelope(env);
      const monthly = budgeted - covered;
      if (monthly <= 0.005) {
        allowanceInfo.skipped.push({ name: env.name, monthly: budgeted, covered });
        continue;
      }
      const acc = envelopeSpendingAccount(env, accountIds);
      if (!acc) {
        allowanceInfo.unassigned.push({ name: env.name, monthly });
        continue;
      }
      allowanceInfo.included.push({ name: env.name, monthly, covered, accountName: acc.name });
      allowanceInfo.totalMonthly += monthly;
      const accSeries = series[acc.id];
      const eSeries = envSeries[env.id];
      // Whatever is left of THIS month's budget for this envelope, spread over
      // the days that remain. Floored at zero: an envelope already spent past
      // its monthly budget projects no further allowance (the overspend is
      // real and already in the balances) rather than a negative drain that
      // would quietly credit the account back.
      const curLeft = Math.max(0, monthly - (spentThisMonth[env.id] || 0));
      const curRate = remainingAfterToday > 0 ? curLeft / remainingAfterToday : 0;
      for (let i = 1; i <= days; i++) {
        const drain = inCurrentMonth[i] ? curRate : monthly * dayFactor[i];
        accSeries[i] -= drain;
        // Mirror the drain onto the envelope. Projected envelope spending is
        // paid for out of that envelope's OWN balance first; only the part it
        // can't cover reaches the unallocated pool. The zero floor applied
        // during aggregation below is what makes that true without letting an
        // envelope drain to -∞ (the reason this mirror was originally omitted).
        eSeries[i] -= drain;
      }
    }
  }

  // running cumulative
  for (const accId of accountIds) {
    for (let i = 1; i <= days; i++) {
      series[accId][i] += series[accId][i - 1];
    }
  }
  // Aggregate the per-envelope series into one envelope total, flooring each
  // envelope at zero on every day.
  //
  // WHY THE FLOOR (this is what "Lowest spendable in period" hinges on):
  // spendable = total − envelopeTotal, so an envelope's balance is money the
  // spendable line has already set aside. Projected spending against that
  // envelope must therefore consume the envelope BEFORE it touches spendable —
  // otherwise the same euro is deducted twice (once as an envelope balance,
  // once as the account outflow that spends it), and "lowest spendable" comes
  // out understated by the whole funded balance. Flooring at zero is exactly
  // "spend the envelope down, then start eating unallocated cash": below zero
  // the envelope has nothing left to contribute, and the overspend correctly
  // lands on spendable. The floor also bounds the other direction — a
  // recurring that drains an envelope every month used to walk the envelope
  // total to -∞ over a long horizon, which pinned spendable flat and pretended
  // the bill was free.
  //
  // Envelopes backed by an account outside `accountIds` are skipped here: the
  // cash behind them is not in `total`, so charging them against it would
  // understate spendable by money that was never selected (the old
  // "envelopes are global allocations" rule did exactly that for a per-person
  // forecast profile — decision #41).
  const envelopeTotal = new Array(days + 1).fill(0);
  const excludedEnvelopes = [];
  for (const e of data.envelopes) {
    const s = envSeries[e.id];
    for (let i = 1; i <= days; i++) s[i] += s[i - 1];
    if (!envelopeCountsFor(e, accountIds)) {
      excludedEnvelopes.push({ id: e.id, name: e.name, accountName: envelopeBackingAccount(e).name, balance: s[0] });
      continue;
    }
    for (let i = 0; i <= days; i++) if (s[i] > 0) envelopeTotal[i] += s[i];
  }

  const total = new Array(days + 1).fill(0);
  for (const accId of accountIds) for (let i = 0; i <= days; i++) total[i] += series[accId][i];

  const spendable = new Array(days + 1);
  for (let i = 0; i <= days; i++) spendable[i] = total[i] - envelopeTotal[i];

  return { dates, series, total, envelopeTotal, spendable, allowanceInfo, excludedEnvelopes };
}

// Lowest point of a forecast's spendable line, with the date it falls on.
// Tone of a projected low point, for the dashboard tiles (decision #44):
// 'bad' below zero, 'warn' under the user's floor (settings.forecastWarnBelow,
// unset = no floor), '' otherwise. A healthy low should look healthy.
function lowTone(value) {
  if (value === null || value === undefined || !isFinite(value)) return '';
  if (value < 0) return 'bad';
  const floor = data?.settings?.forecastWarnBelow;
  if (typeof floor === 'number' && isFinite(floor) && value < floor) return 'warn';
  return '';
}
function lowToneNote(value) {
  const t = lowTone(value);
  if (t === 'bad') return '⚠ goes below zero';
  if (t === 'warn') return `⚠ under your ${fmt(data.settings.forecastWarnBelow)} floor`;
  return '';
}

function spendableLow(fc) {
  let min = Infinity, idx = 0;
  for (let i = 0; i < fc.spendable.length; i++) {
    if (fc.spendable[i] < min) { min = fc.spendable[i]; idx = i; }
  }
  return { min, date: fc.dates[idx] };
}

// Exact projected spendable low AFTER applying a proposed set of envelope
// fundings — `fundings` is [{envelopeId, amount, date}].
//
// The Fund modal used to estimate this arithmetically as `spendMin − total`, on
// the assumption that every funded euro lowers the spendable line by exactly a
// euro on every day. That was true when envelope balances were a single frozen
// running total. It stopped being true the moment envelopes gained their own
// projected balance with a floor at zero (decision #22), in two ways:
//   - funding an OVERSPENT envelope mostly just lifts it off the floor, and the
//     negative part was never counted against spendable to begin with;
//   - funding an envelope that has an allowance of its own gets spent back down
//     inside the horizon, so it doesn't depress the low point at all.
// Measured against a real 12-envelope month (5 of them overspent by 1.913
// total, 8.483 proposed), the linear guess was 1.913 too pessimistic with
// allowances off and 8.478 too pessimistic with them on — easily enough to fire
// an "over-allocates by …" warning against money the user plainly had, which is
// the same false-alarm class decision #22 set out to kill.
//
// So: actually run the forecast. The probe rows are appended to a COPY and the
// original array reference is restored in `finally`, so a throw mid-forecast
// can't leave synthetic transactions in the user's data.
function spendableMinAfterFunding(accountIds, days, opts, fundings) {
  const saved = data.transactions;
  try {
    data.transactions = saved.concat(fundings.map((f, i) => ({
      id: '__fundProbe' + i, date: f.date, type: 'income', amount: f.amount,
      accountId: null, envelopeId: f.envelopeId, payee: 'Envelope refill'
    })));
    return spendableLow(forecastAccountBalances(accountIds, days, opts));
  } finally {
    data.transactions = saved;
  }
}

//=============================================================================
// VIEW ROUTER
//=============================================================================
function render() {
  if (currentChart) { currentChart.destroy(); currentChart = null; }
  // innerHTML drops the canvases but Chart.js keeps each instance (and its
  // resize observer) registered until destroy() — the Reports doughnuts used
  // to leak one instance per visit.
  for (const c of reportCharts) c.destroy();
  reportCharts = [];
  const main = document.getElementById("main");
  if (!data) {
    main.innerHTML = renderWelcome();
    bindWelcome();
    return;
  }
  document.querySelectorAll("nav.tabs button").forEach(b => {
    const on = b.dataset.view === activeView;
    b.classList.toggle("active", on);
    // Convey the current tab programmatically, not just by colour/underline.
    if (on) b.setAttribute("aria-current", "page");
    else b.removeAttribute("aria-current");
  });
  switch (activeView) {
    case "dashboard": main.innerHTML = renderDashboard(); bindDashboard(); break;
    case "accounts": main.innerHTML = renderAccounts(); bindAccounts(); break;
    case "envelopes": main.innerHTML = renderEnvelopes(); bindEnvelopes(); break;
    case "transactions": main.innerHTML = renderTransactions(); bindTransactions(); break;
    case "recurring": main.innerHTML = renderRecurring(); bindRecurring(); break;
    case "forecast": main.innerHTML = renderForecast(); bindForecast(); break;
    case "networth": main.innerHTML = renderNetWorth(); bindNetWorth(); break;
    case "reports": main.innerHTML = renderReports(); bindReports(); break;
    case "settings": main.innerHTML = renderSettings(); bindSettings(); break;
    case "help": main.innerHTML = renderHelp(); break;
  }
  linkHelpTips(main);
  // ensure today's snapshot updates
  if (data) snapshotIfNeeded();
}

function snapshotIfNeeded() {
  const today = todayISO();
  const last = data.netWorthSnapshots[data.netWorthSnapshots.length - 1];
  const v = totalNetWorth();
  if (!last || last.date !== today) {
    data.netWorthSnapshots.push({ date: today, value: v });
    saveDirty();
  } else if (last.value !== v) {
    last.value = v;
    saveDirty();
  }
}

//=============================================================================
// WELCOME
//=============================================================================
function renderWelcome() {
  return `<div class="empty-state">
    <h2>Welcome to your envelope budget</h2>
    <p>Your data lives in <strong>finance-data.json</strong> next to <code>serve.py</code>,
       on the machine serving this page. Every device you open the app from reads and
       writes that same file, so there is only ever one copy to back up or edit by hand.</p>
    <div class="btns">
      <button class="btn primary" id="welNew">Create new budget</button>
      <button class="btn" id="welOpen">Import a JSON file</button>
    </div>
    <p style="margin-top:30px;font-size:12px;">
      Any browser works — there is no File System Access permission to grant.
      The server keeps rolling <code>finance-data.bak.N</code> backups of the last five saves.
    </p>
  </div>`;
}
function bindWelcome() {
  document.getElementById("welNew").onclick = newFile;
  document.getElementById("welOpen").onclick = importViaInput;
}

//=============================================================================
// DASHBOARD
//=============================================================================
// Renders the first-run setup checklist. Shown above the dashboard while any
// of accounts/envelopes/recurring is empty; on a fully-empty file it replaces
// the dashboard entirely (the stat cards and panels would all show €0.00 and
// give no path forward). Each step lights up as it's completed.
function renderOnboarding() {
  const hasAcc = data.accounts.length > 0;
  const hasEnv = data.envelopes.length > 0;
  const hasRec = data.recurring.length > 0;
  const step = (done, num, title, blurb, btnId, btnText, disabled) => `
    <li class="ob-step ${done ? 'ob-done' : ''} ${disabled ? 'ob-locked' : ''}">
      <span class="ob-num" aria-hidden="true">${done ? '✓' : num}</span>
      <div class="ob-body">
        <div class="ob-title">${title}</div>
        <div class="ob-blurb">${blurb}</div>
      </div>
      <button class="btn ${done ? '' : 'primary'}" id="${btnId}" ${disabled ? 'disabled' : ''}>${btnText}</button>
    </li>`;
  return `
    <div class="card ob-card">
      <div class="ob-head">
        <h2 style="margin:0;">Welcome — let's set up your budget</h2>
        <p style="color:var(--text-dim);margin:6px 0 0;">A virtual envelope for every euro. Four short steps:</p>
      </div>
      <ol class="ob-list">
        ${step(hasAcc, 1, 'Add your accounts',
          'Checking, savings, credit cards, cash, investments, loans — every real-world place your money lives.',
          'obAcc', hasAcc ? 'View accounts' : 'Add an account', false)}
        ${step(hasEnv, 2, 'Add your envelopes',
          'Virtual budget categories: Groceries, Rent, Fun, Christmas fund, Emergency fund…',
          'obEnv', hasEnv ? 'View envelopes' : 'Add an envelope', false)}
        ${step(hasRec, 3, 'Set up recurring entries',
          'Salaries, rent, utilities, subscriptions, holiday bonuses — anything that happens on a schedule.',
          'obRec', hasRec ? 'View recurring' : 'Add a recurring entry', !hasAcc)}
        ${step(false, 4, 'Fund the month',
          'Once each month after salaries land, top every envelope up to its budget in one click.',
          'obFund', 'Open Envelopes tab', !(hasAcc && hasEnv))}
      </ol>
    </div>`;
}
function bindOnboarding() {
  const go = (view, then) => () => { activeView = view; render(); if (then) setTimeout(then, 0); };
  const obAcc = document.getElementById('obAcc');
  const obEnv = document.getElementById('obEnv');
  const obRec = document.getElementById('obRec');
  const obFund = document.getElementById('obFund');
  if (obAcc) obAcc.onclick = go('accounts', () => {
    if (data.accounts.length === 0) document.getElementById('addAcc')?.click();
  });
  if (obEnv) obEnv.onclick = go('envelopes', () => {
    if (data.envelopes.length === 0) document.getElementById('addEnv')?.click();
  });
  if (obRec) obRec.onclick = go('recurring', () => {
    if (data.recurring.length === 0) document.getElementById('addRec')?.click();
  });
  if (obFund) obFund.onclick = go('envelopes');
}

function renderDashboard() {
  const showOnboarding =
    data.accounts.length === 0 ||
    data.envelopes.length === 0 ||
    data.recurring.length === 0;
  // Fully empty file: skip the all-zeros dashboard entirely and show only the
  // setup steps so the user has a clear next action.
  const fullyEmpty = data.accounts.length === 0 &&
    data.envelopes.length === 0 &&
    data.recurring.length === 0 &&
    data.transactions.length === 0;
  if (fullyEmpty) return renderOnboarding();
  const onboardingHTML = showOnboarding ? renderOnboarding() : '';

  const nw = totalNetWorth();
  const a = totalAssets();
  const l = totalLiabilities();
  const inv = totalInvestments();

  // 30-day delta
  const snaps = data.netWorthSnapshots;
  let delta30 = null;
  if (snaps.length > 1) {
    const cutoff = isoDate(addDays(parseDate(todayISO()), -30));
    const prior = [...snaps].reverse().find(s => s.date <= cutoff);
    if (prior) delta30 = nw - prior.value;
  }

  // upcoming recurring (next 7 days)
  const today = parseDate(todayISO());
  const upcoming = [];
  for (const rec of data.recurring.filter(r => r.active !== false)) {
    // Skip occurrences on/before lastAppliedDate — otherwise an instance
    // just consumed via ⚡ keeps appearing in this panel until tomorrow.
    const fromD = recurringResumeDate(rec, today);
    const start = fromD > today ? fromD : today;
    for (const d of recurringOccurrences(rec, start, addDays(today, 7))) {
      if (isSkippedOccurrence(rec, d)) continue;
      upcoming.push({ rec, date: d });
    }
  }
  upcoming.sort((a, b) => a.date.localeCompare(b.date));

  // Same ordering as the Transactions tab (date desc, then most recently
  // added first) so a freshly logged entry tops today's block in both places.
  const recentTx = sortTxsDesc(data.transactions).slice(0, 8);

  const envSummary = activeEnvelopes().map(e => ({
    e, bal: envelopeBalance(e)
  })).sort((a,b) => a.bal - b.bal).slice(0, 5);

  // Pinned accounts strip — preserves the order of data.accounts itself, so
  // drag-to-reorder on the dashboard mutates the array directly. Card is
  // hidden entirely when nothing is pinned (no empty placeholder).
  const pinnedAccs = activeAccounts().filter(x => x.pinned).map(a => ({ a, b: accountBalance(a) }));

  // Dashboard forecast horizons (1mo, 3mo, 6mo, 12mo, 2yr).
  // Mirrors the Forecast tab so the two views agree: same account selection
  // and same "include envelope allowances" toggle. Defaults to non-investment
  // accounts that count toward net worth when nothing is selected yet.
  const fcAccountIds = (forecastState.accountIds && forecastState.accountIds.length)
    ? forecastState.accountIds
    : activeAccounts().filter(a => !a.isInvestment && a.includeInNetWorth !== false).map(a => a.id);
  // Resolve the active forecast profile (if one is selected on the Forecast
  // tab) so the dashboard can label its forecast block with the profile name.
  const activeProfile = forecastState.selectedProfileId
    ? data.forecastProfiles.find(p => p.id === forecastState.selectedProfileId)
    : null;
  // Use the same day counts as the Forecast tab's HORIZONS so the dashboard
  // and Forecast tab projections agree to the cent at each horizon. Horizons
  // beyond the profile's chosen time-horizon (forecastState.days) are hidden
  // so the dashboard mirrors the profile's scope — e.g. a 1-month profile
  // won't surface 2-year numbers.
  const allDashHorizons = [
    { label: "1 month",   days: 30  },
    { label: "3 months",  days: 90  },
    { label: "6 months",  days: 180 },
    { label: "12 months", days: 365 },
    { label: "2 years",   days: 730 }
  ];
  const fcDays = forecastState.days || 90;
  let dashHorizons = allDashHorizons.filter(h => h.days <= fcDays);
  // Always show at least one horizon — if the profile's horizon is shorter
  // than 30 days (e.g. the 1-week option), fall back to the smallest cell.
  if (dashHorizons.length === 0) dashHorizons = [allDashHorizons[0]];
  // Mirror the chart's visibility settings:
  //   "individual" hides the combined total → don't feature it on the dashboard
  //   "spendable"  hides ALL account/total lines AND implies showSpendable
  // In either of those cases the spendable line becomes the primary metric.
  const showTotalLine = forecastState.chartLines === "both" || forecastState.chartLines === "total";
  const showSpendLine = !!forecastState.showSpendable || forecastState.chartLines === "spendable";
  const primaryIsSpendable = !showTotalLine && showSpendLine;
  // If the user has hidden BOTH the total and spendable lines on the Forecast
  // tab, there's nothing meaningful to surface on the dashboard — hide the
  // whole forecast card.
  const dashFcVisible = showTotalLine || showSpendLine;
  let dashFc = null;
  if (fcAccountIds.length > 0 && dashFcVisible) {
    const horizonMax = dashHorizons[dashHorizons.length - 1].days;
    const fc = forecastAccountBalances(fcAccountIds, horizonMax, { includeAllowances: forecastState.includeAllowances });
    const cur = fc.total[0];
    const curSpend = fc.spendable[0];
    // Find the lowest projected value and the date it occurs over the
    // visible horizon — surfaces "the worst point" the user should plan for.
    // We only compute the minimum for lines the profile says are visible;
    // hidden lines stay null so the dashboard doesn't surface them.
    let totalMin = null, totalMinDate = null;
    if (showTotalLine) {
      let minVal = Infinity, minIdx = 0;
      for (let i = 0; i <= horizonMax && i < fc.total.length; i++) {
        if (fc.total[i] < minVal) { minVal = fc.total[i]; minIdx = i; }
      }
      totalMin = minVal;
      totalMinDate = fc.dates[minIdx];
    }
    let spendMin = null, spendMinDate = null;
    if (showSpendLine) {
      let minVal = Infinity, minIdx = 0;
      for (let i = 0; i <= horizonMax && i < fc.spendable.length; i++) {
        if (fc.spendable[i] < minVal) { minVal = fc.spendable[i]; minIdx = i; }
      }
      spendMin = minVal;
      spendMinDate = fc.dates[minIdx];
    }
    dashFc = {
      cur, curSpend, primaryIsSpendable, showTotalLine, showSpendLine,
      totalMin, totalMinDate, spendMin, spendMinDate,
      points: dashHorizons.map(h => ({
        label: h.label,
        value: fc.total[h.days],
        delta: fc.total[h.days] - cur,
        spendable: fc.spendable[h.days],
        spendableDelta: fc.spendable[h.days] - curSpend
      }))
    };
  }

  const due = dueRecurringOccurrences();
  const dueTotal = due.reduce((s, u) =>
    s + (u.rec.type === 'expense' ? -u.rec.amount : (u.rec.type === 'income' ? u.rec.amount : 0)), 0);

  const closeYM = closeOutDue();
  const closeMonthLabel = closeYM ? (() => {
    const [y, m] = closeYM.split('-').map(Number);
    return new Date(y, m - 1, 1).toLocaleDateString('en', { month: 'long', year: 'numeric' });
  })() : '';

  return `
  ${onboardingHTML}
  <h2>Dashboard</h2>
  ${closeYM ? `<div class="card due-banner" style="margin-bottom:14px;border-left:3px solid var(--accent);">
    <div>
      <strong>Close out ${esc(closeMonthLabel)}.</strong>
      <div style="color:var(--text-dim);font-size:13px;margin-top:4px;">
        Review last month's envelope activity — pick rollover or reset for each, then archive the month.
      </div>
    </div>
    <div style="display:flex;gap:8px;">
      <button class="btn primary" id="closeOutBtn">Review</button>
    </div>
  </div>` : ''}
  ${due.length ? `<div class="card due-banner" style="margin-bottom:14px;">
    <div>
      <strong>${due.length} recurring ${due.length === 1 ? 'entry is' : 'entries are'} due since your last apply.</strong>
      <div style="color:var(--text-dim);font-size:13px;margin-top:4px;">
        ${due.slice(0, 4).map(u => esc(u.rec.name) + ' (' + fmtDate(u.date) + ')').join(', ')}${due.length > 4 ? ` and ${due.length - 4} more` : ''}
        ${dueTotal !== 0 ? ` · net <span class="${dueTotal >= 0 ? 'pos' : 'neg'}">${dueTotal >= 0 ? '+' : ''}${fmt(dueTotal)}</span>` : ''}
      </div>
    </div>
    <div style="display:flex;gap:8px;">
      <button class="btn" id="dueReview">Review</button>
      <button class="btn primary" id="dueApply">Apply ${due.length}</button>
    </div>
  </div>` : ''}
  <div class="grid cols-3" style="margin-bottom:18px;">
    <div class="card">
      <div class="stat-label">Net worth</div>
      <div class="stat lg">${fmt(nw)}</div>
      ${delta30 != null ? `<div class="delta ${delta30 >= 0 ? 'up' : 'down'}">
        ${delta30 >= 0 ? '▲' : '▼'} ${fmt(Math.abs(delta30))} (30d)</div>` : ''}
    </div>
    <div class="card">
      <div class="stat-label">Assets</div>
      <div class="stat" style="color:var(--good)">${fmt(a)}</div>
      <div class="delta">Liabilities: ${fmt(l)}</div>
    </div>
    <div class="card">
      <div class="stat-label">Investments</div>
      <div class="stat" style="color:var(--accent-2)">${fmt(inv)}</div>
      <div class="delta">${nw > 0 ? ((inv / nw) * 100).toFixed(1) : 0}% of net worth</div>
    </div>
  </div>

  ${dashFc ? `
  <div class="card" style="margin-bottom:18px;">
    <div style="display:flex;align-items:baseline;justify-content:space-between;gap:12px;flex-wrap:wrap;margin-bottom:10px;">
      <h3 style="margin:0;">Forecast — ${dashFc.primaryIsSpendable ? 'spendable cash' : 'projected balance'}</h3>
      <span style="color:var(--text-dim);font-size:12px;">
        ${activeProfile ? `Profile: <strong style="color:var(--text);">${esc(activeProfile.name)}</strong> · ` : ''}${fcAccountIds.length} account${fcAccountIds.length === 1 ? '' : 's'}${dashFc.showTotalLine ? ` · today: <strong style="color:var(--text);">${fmt(dashFc.cur)}</strong>` : ''}${dashFc.showSpendLine ? ` · spendable today: <strong style="color:var(--warn);">${fmt(dashFc.curSpend)}</strong>` : ''}
      </span>
    </div>
    <div class="dash-fc-grid">
      ${dashFc.points.map(p => {
        // When spendable is the primary metric (user hid the total line on the
        // Forecast tab), feature the spendable value+delta in the big slots and
        // skip the total entirely. Otherwise feature the total and tuck the
        // spendable beneath when the user has it enabled.
        if (dashFc.primaryIsSpendable) {
          return `
            <div class="dash-fc-cell">
              <div class="dash-fc-label">${p.label}</div>
              <div class="dash-fc-value ${p.spendable < 0 ? 'neg' : ''}" style="color:var(--warn);">${fmt(p.spendable)}</div>
              <div class="dash-fc-delta ${p.spendableDelta >= 0 ? 'up' : 'down'}">
                ${p.spendableDelta > 0 ? '+' : ''}${fmt(p.spendableDelta)}
              </div>
            </div>`;
        }
        return `
          <div class="dash-fc-cell">
            <div class="dash-fc-label">${p.label}</div>
            <div class="dash-fc-value ${p.value < 0 ? 'neg' : ''}">${fmt(p.value)}</div>
            <div class="dash-fc-delta ${p.delta >= 0 ? 'up' : 'down'}">
              ${p.delta > 0 ? '+' : ''}${fmt(p.delta)}
            </div>
            ${dashFc.showSpendLine ? `
              <div class="dash-fc-spend">
                Spendable <strong>${fmt(p.spendable)}</strong>
              </div>
            ` : ''}
          </div>`;
      }).join('')}
      ${(() => {
        // "Lowest in period" cell — the worst projected point over the
        // dashboard's horizon, plus the date it falls on. Mirrors the same
        // primary/secondary logic as the horizon cells: spendable is featured
        // when it's the primary line, otherwise total is featured (with the
        // spendable low tucked beneath when both lines are visible).
        if (dashFc.primaryIsSpendable) {
          return `
            <div class="dash-fc-cell ${lowTone(dashFc.spendMin) ? 'tone-' + lowTone(dashFc.spendMin) : ''}">
              <div class="dash-fc-label">Lowest spendable in period <span class="help-tip" tabindex="0" title="The lowest your SPENDABLE cash dips to in the horizon — total of your accounts minus the envelope balances they hold (Available-to-Budget; an envelope backed by an account outside the forecast is left out). Funding envelopes pulls money into buckets, which reduces spendable but leaves your account totals unchanged. Projected envelope spending is paid out of that envelope's own balance first and only reduces spendable once the envelope runs dry. Due-but-unapplied recurrings are folded in, so this is the realistic worst case.">?</span></div>
              <div class="dash-fc-value">${fmt(dashFc.spendMin)}</div>
              <div class="dash-fc-delta" style="color:var(--text-dim);">on ${fmtDate(dashFc.spendMinDate)}</div>
              ${lowToneNote(dashFc.spendMin) ? `<div class="dash-fc-note">${lowToneNote(dashFc.spendMin)}</div>` : ''}
              <div class="dash-fc-spend" style="font-style:italic;color:var(--text-dim);">if you fund nothing · Fund the month shows the effect of a proposal</div>
            </div>`;
        }
        return `
          <div class="dash-fc-cell ${lowTone(dashFc.totalMin) ? 'tone-' + lowTone(dashFc.totalMin) : ''}">
            <div class="dash-fc-label">Lowest total in period <span class="help-tip" tabindex="0" title="The lowest your TOTAL account balance dips to in the horizon — sum of selected accounts, ignoring envelope allocations. Note: funding envelopes does NOT change this number (it just moves money into virtual buckets). For "how much is safe to fund?" look at the Spendable line.">?</span></div>
            <div class="dash-fc-value">${fmt(dashFc.totalMin)}</div>
            <div class="dash-fc-delta" style="color:var(--text-dim);">on ${fmtDate(dashFc.totalMinDate)}</div>
            ${lowToneNote(dashFc.totalMin) ? `<div class="dash-fc-note">${lowToneNote(dashFc.totalMin)}</div>` : ''}
            ${dashFc.showSpendLine ? `
              <div class="dash-fc-spend">
                Lowest spendable <strong>${fmt(dashFc.spendMin)}</strong>
                <span style="color:var(--text-dim);font-weight:400;"> on ${fmtDate(dashFc.spendMinDate)}</span>
                <div style="font-style:italic;color:var(--text-dim);font-size:11px;margin-top:2px;">if you fund nothing · Fund the month re-forecasts with your proposal applied</div>
              </div>
            ` : ''}
          </div>`;
      })()}
    </div>
    <div style="color:var(--text-dim);font-size:12px;margin-top:8px;">
      Mirrors the Forecast tab${activeProfile ? ` — profile <strong style="color:var(--text);">${esc(activeProfile.name)}</strong>` : ' (no profile selected — using current settings)'} · ${forecastState.includeAllowances ? '<strong style="color:var(--text);">including</strong>' : 'excluding'} envelope allowances${dashFc.primaryIsSpendable ? ' · showing spendable cash (total line hidden in profile)' : (dashFc.showSpendLine ? ' · spendable cash shown' : '')}. Adjust on the Forecast tab.
    </div>
  </div>
  ` : ''}

  <div class="grid ${pinnedAccs.length ? 'cols-3' : 'cols-2'}">
    <div class="card">
      <h3>Upcoming (next 7 days)</h3>
      ${upcoming.length === 0 ? '<p style="color:var(--text-dim);">Nothing scheduled.</p>' :
        `<table><thead><tr><th>Date</th><th>Description</th><th class="num">Amount</th></tr></thead><tbody>${upcoming.map(u => `
        <tr>
          <td>${fmtDate(u.date)}</td>
          <td><a href="#" class="rec-link" data-edit-rec="${u.rec.id}" title="Edit recurring entry">${esc(u.rec.name)}</a> <span class="badge ${u.rec.type}">${u.rec.type}</span></td>
          <td class="num ${u.rec.type === 'expense' ? 'neg' : (u.rec.type === 'income' ? 'pos' : '')}">
            ${u.rec.type === 'expense' ? '-' : (u.rec.type === 'income' ? '+' : '')}${fmt(u.rec.amount)}
          </td>
        </tr>`).join('')}</tbody></table>`}
    </div>
    <div class="card">
      <h3>Lowest envelopes</h3>
      ${envSummary.length === 0 ? '<p style="color:var(--text-dim);">No envelopes yet.</p>' :
        `<table><thead><tr><th>Envelope</th><th class="num">Balance</th></tr></thead><tbody>${envSummary.map(({e, bal}) => `
        <tr>
          <td><a href="#" class="drill" data-tx-env="${e.id}" title="Show this envelope's transactions">${esc(e.name)}</a></td>
          <td class="num ${bal < 0 ? 'neg' : ''}">${fmt(bal)}<span style="color:var(--text-dim);font-weight:400;font-size:.85em;margin-left:6px;">/ ${fmt(e.budgetAmount || 0)}${e.cadence === 'annual' ? '/yr' : ''}</span></td>
        </tr>`).join('')}</tbody></table>`}
    </div>
    ${pinnedAccs.length ? `<div class="card">
      <h3 style="display:flex;align-items:baseline;justify-content:space-between;gap:8px;">
        <span>Pinned accounts</span>
        <span style="font-weight:400;font-size:11px;color:var(--text-dim);">drag to reorder</span>
      </h3>
      <table><thead><tr><th>Account</th><th class="num">Balance</th></tr></thead>
        <tbody id="pinnedAccTbody">${pinnedAccs.map(({a, b}) => `
        <tr class="drag-row" draggable="true" data-acc-id="${a.id}">
          <td>
            <span class="drag-handle" title="Drag to reorder">⋮⋮</span>
            <a href="#" class="drill" data-tx-acc="${a.id}" title="Show this account's transactions">${esc(a.name)}</a>
            ${a.type ? `<span style="color:var(--text-dim);font-size:.85em;margin-left:6px;">${esc(a.type)}</span>` : ''}
          </td>
          <td class="num ${b < 0 ? 'neg' : ''}"><strong>${fmt(b)}</strong></td>
        </tr>`).join('')}</tbody>
      </table>
    </div>` : ''}
  </div>
  <!-- Recent transactions lives OUTSIDE the grid above. When it was inside
       with grid-column: 1 / -1, that span pinned auto-fit's track count to
       the original (uncollapsed) layout — so the 3 visible cards above stayed
       at min-width instead of stretching to fill the row. Moving it to a
       sibling card frees the inner grid to expand. -->
  <div class="card" style="margin-top:14px;">
    <div style="display:flex;align-items:baseline;justify-content:space-between;gap:12px;margin-bottom:8px;flex-wrap:wrap;">
      <h3 style="margin:0;">Recent transactions</h3>
      ${(() => {
        // Today's total expenses — sum of expense-type transactions dated
        // today. Shown alongside the card title so it's the first thing
        // the user sees when scanning the bottom of the dashboard.
        const tISO = todayISO();
        const todays = data.transactions.filter(tx => tx.type === 'expense' && tx.date === tISO);
        const todaysExpenses = todays.reduce((s, tx) => s + (tx.amount || 0), 0);
        const count = todays.length;
        return `<div style="font-size:13px;color:var(--text-dim);">
          Today's expenses
          <strong style="color:${todaysExpenses > 0 ? 'var(--bad)' : 'var(--text)'};font-size:15px;margin-left:6px;">${fmt(todaysExpenses)}</strong>
          ${count ? `<span style="margin-left:6px;">· ${count} ${count === 1 ? 'transaction' : 'transactions'}</span>` : ''}
        </div>`;
      })()}
    </div>
    ${recentTx.length === 0 ? '<p style="color:var(--text-dim);">No transactions yet.</p>' :
      `<table><thead><tr>
        <th>Date</th><th>Description</th><th>Account</th><th>Envelope</th><th class="num">Amount</th>
      </tr></thead><tbody>${recentTx.map(tx => txRow(tx)).join('')}</tbody></table>`}
  </div>
  `;
}
function bindDashboard() {
  bindOnboarding();
  const apply = document.getElementById("dueApply");
  if (apply) apply.onclick = () => {
    const n = applyDueRecurring();
    if (n > 0) toast(`Applied ${n} recurring ${n === 1 ? 'entry' : 'entries'}`, 5000, 'success', { label: 'Undo', onClick: performUndo });
    render();
  };
  const review = document.getElementById("dueReview");
  if (review) review.onclick = () => showDueReview();
  const closeBtn = document.getElementById("closeOutBtn");
  if (closeBtn) closeBtn.onclick = () => showCloseOut();
  document.querySelectorAll("a.rec-link[data-edit-rec]").forEach(a =>
    a.onclick = (e) => { e.preventDefault(); editRecurring(a.dataset.editRec); });
  wireDrillLinks();

  wireAccountDragReorder();
}

// Drill-through: any <a class="drill" data-tx-acc|data-tx-env> in the current
// view opens the Transactions tab filtered to that account / envelope. The
// Accounts tab, envelope cards and both dashboard tables use it.
function wireDrillLinks() {
  document.querySelectorAll("a.drill[data-tx-acc],a.drill[data-tx-env]").forEach(a =>
    a.onclick = (e) => {
      e.preventDefault();
      goToTransactions(a.dataset.txAcc ? { acc: a.dataset.txAcc } : { env: a.dataset.txEnv });
    });
}

// Shared drag-to-reorder for account rows. Used by both bindDashboard (pinned
// strip) and bindAccounts (full Accounts table) — operates on every visible
// tr.drag-row[data-acc-id] in the current view. Reorders data.accounts in
// place so the dashboard order, the Accounts-tab order, and account dropdowns
// stay consistent.
//
// UX: drag a row anywhere; while dragging, the hovered row shows a 2px accent
// line on its top or bottom edge depending on which half of the row the cursor
// is in, indicating where the source will land on drop.
function wireAccountDragReorder() {
  const rows = document.querySelectorAll("tr.drag-row[data-acc-id]");
  if (!rows.length) return;
  let dragSrcId = null;
  const clearDropMarks = () => rows.forEach(r => r.classList.remove("drop-above", "drop-below"));
  rows.forEach(row => {
    row.addEventListener("dragstart", (ev) => {
      dragSrcId = row.dataset.accId;
      row.classList.add("drag-source");
      // Required for Firefox to actually start the drag.
      try { ev.dataTransfer.setData("text/plain", dragSrcId); } catch (_) {}
      ev.dataTransfer.effectAllowed = "move";
    });
    row.addEventListener("dragend", () => {
      row.classList.remove("drag-source");
      clearDropMarks();
      dragSrcId = null;
    });
    row.addEventListener("dragover", (ev) => {
      ev.preventDefault();
      ev.dataTransfer.dropEffect = "move";
      // Skip the indicator when hovering over the source itself — no useful
      // drop position there.
      if (!dragSrcId || row.dataset.accId === dragSrcId) return;
      // Upper half = drop above this row; lower half = drop below. Using the
      // midpoint of the row's bounding rect keeps the math frame-rate-cheap.
      const rect = row.getBoundingClientRect();
      const above = ev.clientY < rect.top + rect.height / 2;
      // Clear marks on every other row so only one indicator is ever visible.
      rows.forEach(r => { if (r !== row) r.classList.remove("drop-above", "drop-below"); });
      row.classList.toggle("drop-above", above);
      row.classList.toggle("drop-below", !above);
    });
    row.addEventListener("dragleave", (ev) => {
      // Only clear when leaving the row entirely (the relatedTarget check
      // avoids flickering when moving between this row's TDs).
      if (!row.contains(ev.relatedTarget)) {
        row.classList.remove("drop-above", "drop-below");
      }
    });
    row.addEventListener("drop", (ev) => {
      ev.preventDefault();
      const tgtId = row.dataset.accId;
      const dropAbove = row.classList.contains("drop-above");
      clearDropMarks();
      if (!dragSrcId || dragSrcId === tgtId) { dragSrcId = null; return; }
      const srcIdx = data.accounts.findIndex(a => a.id === dragSrcId);
      if (srcIdx < 0) return;
      const [moved] = data.accounts.splice(srcIdx, 1);
      // Re-resolve target index after the splice (it shifts left if the source
      // was earlier in the array than the target). Then insert before or after
      // depending on which half of the row the user dropped on.
      const newTgtIdx = data.accounts.findIndex(a => a.id === tgtId);
      const insertAt = dropAbove ? newTgtIdx : newTgtIdx + 1;
      data.accounts.splice(insertAt, 0, moved);
      dragSrcId = null;
      saveDirty(); render();
    });
  });
}

function showDueReview() {
  const due = dueRecurringOccurrences();
  if (!due.length) { toast("Nothing due"); return; }
  const rows = due.map((u, i) => {
    const inputColor = u.rec.type === 'expense' ? 'var(--bad)'
      : (u.rec.type === 'income' ? 'var(--good)' : 'var(--text)');
    return `<tr>
      <td style="white-space:nowrap;">${fmtDate(u.date)}</td>
      <td>${esc(u.rec.name)} <span class="badge ${u.rec.type}">${u.rec.type}</span></td>
      <td class="num">
        <input type="text" inputmode="decimal" autocomplete="off" data-due-amt="${i}" value="${(u.rec.amount || 0).toFixed(2)}"
          style="width:100px;text-align:right;padding:4px 6px;background:var(--bg);border:1px solid var(--border);border-radius:4px;color:${inputColor};font-variant-numeric:tabular-nums;">
      </td>
      <td>${esc(u.rec.type === 'transfer-account'
        ? (accountById(u.rec.fromAccountId)?.name + '→' + accountById(u.rec.toAccountId)?.name)
        : (accountById(u.rec.accountId)?.name || ''))}</td>
      <td>
        <select data-due-act="${i}" aria-label="What to do with ${esc(u.rec.name)} on ${fmtDate(u.date)}" style="padding:4px 6px;background:var(--bg);color:var(--text);border:1px solid var(--border);border-radius:4px;">
          <option value="record">Record</option>
          <option value="skip">Skip</option>
          <option value="later">Decide later</option>
        </select>
      </td>
    </tr>`;
  }).join('');
  openModal(`
    <h2>Review due recurring</h2>
    <p style="color:var(--text-dim);margin-top:0;"><strong style="color:var(--text);">Record</strong> books the transaction;
      <strong style="color:var(--text);">skip</strong> marks this one occurrence as never happening (a waived fee, a month you paid nothing) so it stops being offered;
      <strong style="color:var(--text);">decide later</strong> leaves it due. Edit an amount for this occurrence only — the template is unchanged.</p>
    <div style="margin:-4px 0 10px 0;font-size:12px;color:var(--text-dim);">
      Set all:
      <button type="button" class="btn sm ghost" data-dueall="record">Record</button>
      <button type="button" class="btn sm ghost" data-dueall="skip">Skip</button>
      <button type="button" class="btn sm ghost" data-dueall="later">Decide later</button>
    </div>
    <div style="max-height:50vh;overflow:auto;">
      <table>
        <thead><tr><th>Date</th><th>Name</th><th class="num">Amount</th><th>Account</th><th>Action</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn primary" id="dueApplySel">Apply</button>
    </div>
  `, { className: 'wide' });
  document.querySelectorAll("[data-dueall]").forEach(b => b.onclick = () => {
    document.querySelectorAll("[data-due-act]").forEach(sel => { sel.value = b.dataset.dueall; });
  });
  document.getElementById("dueApplySel").onclick = () => {
    const action = {};
    document.querySelectorAll("[data-due-act]").forEach(sel => { action[+sel.dataset.dueAct] = sel.value; });
    const anyChange = Object.values(action).some(a => a !== 'later');
    if (!anyChange) { closeModal(); return; }
    // Per-row amount overrides go through evalAmount like every other amount
    // field; blank, invalid or non-positive falls back to the template amount.
    const overrides = {};
    document.querySelectorAll("[data-due-amt]").forEach(inp => {
      const idx = +inp.dataset.dueAmt;
      const v = evalAmount(inp.value);
      if (!isNaN(v) && v > 0) overrides[idx] = v;
    });
    pushUndo('Review due recurring');
    let n = 0, skipped = 0;
    due.forEach(({ rec, date }, i) => {
      if (action[i] === 'record') {
        data.transactions.push(recurringToTx(rec, date, overrides[i] !== undefined ? overrides[i] : rec.amount));
        n++;
      } else if (action[i] === 'skip') {
        rec.skippedDates = rec.skippedDates || [];
        if (!rec.skippedDates.includes(date)) rec.skippedDates.push(date);
        skipped++;
      }
    });
    // Advance each recurring's lastAppliedDate ONLY through its contiguous
    // resolved prefix — recorded or skipped occurrences up to the first one
    // left for later. Advancing to the max recorded date used to jump the
    // watermark past an unresolved earlier occurrence, which then sat before
    // lastAppliedDate and was silently never offered again (financial data
    // loss). A later occurrence resolved across a "later" gap is safe either
    // way: a recorded one reappears in the next review (visible, recoverable),
    // and a skipped one stays in skippedDates until the watermark reaches it.
    const occByRec = new Map();
    due.forEach(({ rec, date }, i) => {
      if (!occByRec.has(rec.id)) occByRec.set(rec.id, { rec, occ: [] });
      occByRec.get(rec.id).occ.push({ date, resolved: action[i] !== 'later' });
    });
    for (const { rec, occ } of occByRec.values()) {
      occ.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
      let watermark = null;
      for (const o of occ) {
        if (!o.resolved) break;    // stop at the first "decide later"
        watermark = o.date;        // contiguous resolved prefix extends to here
      }
      if (watermark && (!rec.lastAppliedDate || rec.lastAppliedDate < watermark)) {
        rec.lastAppliedDate = watermark;
      }
      // Skips at or before the watermark are implied by it now — prune so the
      // list never grows past the handful of dates still ahead of the watermark.
      if (rec.skippedDates && rec.lastAppliedDate) {
        rec.skippedDates = rec.skippedDates.filter(d => d > rec.lastAppliedDate);
        if (!rec.skippedDates.length) delete rec.skippedDates;
      }
    }
    saveDirty();
    closeModal();
    const bits = [];
    if (n) bits.push(`recorded ${plural(n, 'entry', 'entries')}`);
    if (skipped) bits.push(`skipped ${skipped}`);
    if (bits.length) toast(bits.join(', ') + ' (Ctrl+Z to undo)', 4000, 'success', { label: 'Undo', onClick: performUndo });
    render();
  };
}

// Sign + transfer-aware, escaped account/envelope display strings for a tx.
// Shared by txRow (dashboard) and txDataRow (transactions table) so the two
// renderers can't drift on how transfers / missing accounts display.
function txDisplayParts(tx) {
  const sign = tx.type === 'expense' ? '-' : (tx.type === 'income' ? '+' : '');
  const acc = tx.type === 'transfer-account'
    ? `${esc(accountById(tx.fromAccountId)?.name || '?')} → ${esc(accountById(tx.toAccountId)?.name || '?')}`
    : esc(accountById(tx.accountId)?.name || '');
  const env = tx.type === 'transfer-envelope'
    ? `${esc(envelopeById(tx.fromEnvelopeId)?.name || '?')} → ${esc(envelopeById(tx.toEnvelopeId)?.name || '?')}`
    : (tx.splits && tx.splits.length)
      ? `<span title="${esc(tx.splits.map(s => (envelopeById(s.envelopeId)?.name || '?') + ': ' + fmt(Math.abs(s.amount || 0))).join(', '))}">Split · ${tx.splits.length}</span>`
      : esc(envelopeById(tx.envelopeId)?.name || '');
  const tag = tagChip(tx.tag);
  return { sign, acc, env, tag };
}

function txRow(tx) {
  const { sign, acc, env, tag } = txDisplayParts(tx);
  return `<tr class="${tx.date > todayISO() ? 'tx-future' : ''}">
    <td style="white-space:nowrap;">${txDateCell(tx)}</td>
    <td>${esc(tx.payee || tx.notes || '')} ${tag} <span class="badge ${tx.type}">${tx.type}</span></td>
    <td>${acc}</td>
    <td>${env}</td>
    <td class="num ${tx.type==='expense'?'neg':(tx.type==='income'?'pos':'')}">${sign}${fmt(tx.amount)}</td>
  </tr>`;
}

function esc(s) {
  return String(s ?? "").replace(/[&<>"']/g, c =>
    ({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c]));
}

//=============================================================================
// ACCOUNTS
//=============================================================================
function renderAccounts() {
  // `sched` = net effect of transactions dated after today, which the balance
  // excludes (accountBalance stops at today). Shown under the balance so a
  // future-dated entry can't make the figure look wrong next to its own list.
  const today = todayISO();
  const allAccs = data.accounts.map(a => {
    let sched = 0;
    for (const tx of data.transactions) if (tx.date > today) sched += txAccountDelta(tx, a.id);
    return { a, b: accountBalance(a), sched };
  });
  const accs = allAccs.filter(x => !x.a.archived);
  const archived = allAccs.filter(x => x.a.archived);
  // Archived accounts keep counting: archiving hides, it does not close.
  const total = allAccs.filter(x => x.a.includeInNetWorth !== false).reduce((s,x) => s + x.b, 0);
  return `
  <h2>Accounts</h2>
  <div class="toolbar">
    <button class="btn primary" id="addAcc">+ Add account</button>
    <div class="spacer"></div>
    <div class="toolbar-stat">
      <span class="stat-label">Total in net worth</span>
      <strong>${fmt(total)}</strong>
    </div>
  </div>
  <div class="card" style="padding:0;">
    <table>
      <thead><tr>
        <th>Name</th><th>Type</th><th>Owner</th><th>Opening</th>
        <th class="num">Current balance</th><th></th>
      </tr></thead>
      <tbody>
        ${accs.length === 0 ? `<tr><td colspan="6" style="text-align:center;padding:30px;color:var(--text-dim);">
          No accounts yet. Add your bank accounts, credit cards, cash and investment accounts.</td></tr>` :
          accs.map(({a, b, sched}) => `<tr class="drag-row" draggable="true" data-acc-id="${a.id}">
          <td>
            <span class="drag-handle" title="Drag to reorder">⋮⋮</span>
            <button class="pin-btn" data-pin-acc="${a.id}" title="${a.pinned ? 'Unpin from dashboard' : 'Pin to dashboard'}" aria-label="${a.pinned ? 'Unpin ' + esc(a.name) + ' from dashboard' : 'Pin ' + esc(a.name) + ' to dashboard'}" aria-pressed="${a.pinned ? 'true' : 'false'}" style="background:none;border:none;cursor:pointer;font-size:14px;padding:0 6px 0 0;opacity:${a.pinned ? '1' : '0.5'};vertical-align:middle;">📌</button>
            <strong style="font-size:14px;"><a href="#" class="drill" data-tx-acc="${a.id}" title="Show this account's transactions">${esc(a.name)}</a></strong>
            ${a.isInvestment ? '<span class="badge invest">Investment</span>' : ''}
            ${a.includeInNetWorth === false ? '<span class="badge">Excluded</span>' : ''}
          </td>
          <td>${esc(a.type || '')}</td>
          <td>${esc(a.owner || '')}</td>
          <td class="num">${fmt(a.openingBalance || 0)}</td>
          <td class="num ${b < 0 ? 'neg' : ''}"><strong>${fmt(b)}</strong>${Math.abs(sched) >= 0.005 ? `<div class="micro" title="Net of transactions dated after today, which the balance excludes">${sched > 0 ? '+' : ''}${fmt(sched)} scheduled</div>` : ''}</td>
          <td class="actions">
            <button class="btn sm" data-edit="${a.id}">Edit</button>
            ${a.isInvestment ? `<button class="btn sm" data-update="${a.id}">Update value</button>` : ''}
            <button class="btn sm ghost" data-archive="${a.id}" aria-label="Archive account ${esc(a.name)}" title="Archive — hide from lists and pickers, keep every transaction">Archive</button>
            <button class="btn sm danger" data-del="${a.id}" aria-label="Delete account ${esc(a.name)}" title="Delete account">×</button>
          </td>
        </tr>`).join('')}
      </tbody>
    </table>
  </div>
  ${archived.length ? `
  <details class="archived-list" style="margin-top:14px;">
    <summary>${plural(archived.length, 'archived account')} <span class="micro" style="margin-left:6px;">— hidden from pickers and the forecast; balances still count</span></summary>
    <div class="card" style="padding:0;margin-top:8px;">
      <table>
        <tbody>
          ${archived.map(({a, b}) => `<tr>
            <td><strong><a href="#" class="drill" data-tx-acc="${a.id}" title="Show this account's transactions">${esc(a.name)}</a></strong> <span class="badge">archived</span></td>
            <td>${esc(a.type || '')}</td>
            <td class="num ${b < 0 ? 'neg' : ''}"><strong>${fmt(b)}</strong></td>
            <td class="actions">
              <button class="btn sm" data-unarchive="${a.id}">Unarchive</button>
              <button class="btn sm ghost" data-edit="${a.id}">Edit</button>
              <button class="btn sm danger" data-del="${a.id}" aria-label="Delete account ${esc(a.name)}" title="Delete account">×</button>
            </td>
          </tr>`).join('')}
        </tbody>
      </table>
    </div>
  </details>` : ''}
  `;
}
function bindAccounts() {
  document.getElementById("addAcc").onclick = () => editAccount();
  document.querySelectorAll("[data-edit]").forEach(b => b.onclick = () => editAccount(b.dataset.edit));
  document.querySelectorAll("[data-del]").forEach(b => b.onclick = () => deleteAccount(b.dataset.del));
  document.querySelectorAll("[data-update]").forEach(b => b.onclick = () => updateInvestmentValue(b.dataset.update));
  document.querySelectorAll("[data-pin-acc]").forEach(b => b.onclick = () => toggleAccountPin(b.dataset.pinAcc));
  document.querySelectorAll("[data-archive]").forEach(b => b.onclick = () => archiveAccount(b.dataset.archive));
  document.querySelectorAll("[data-unarchive]").forEach(b => b.onclick = () => unarchiveAccount(b.dataset.unarchive));
  wireDrillLinks();
  wireAccountDragReorder();
}

// Archive = hide, not close. The account's transactions stay and keep counting
// in balances and net worth; it just leaves the lists, the pickers, the pinned
// strip and the forecast's account selection. Refused while an ACTIVE
// recurring entry still posts to it — that would keep generating transactions
// into an account the user has said is retired.
function archiveAccount(id) {
  const a = accountById(id); if (!a) return;
  const recs = data.recurring.filter(r => r.active !== false &&
    (r.accountId === id || r.fromAccountId === id || r.toAccountId === id));
  if (recs.length) {
    alert(`Cannot archive account "${a.name}" — ${plural(recs.length, 'active recurring entry', 'active recurring entries')} still ` +
      `${recs.length === 1 ? 'posts' : 'post'} to it (${recs.map(r => r.name).join(', ')}).\n\nDeactivate or reassign ${recs.length === 1 ? 'it' : 'them'} first.`);
    return;
  }
  const bal = accountBalance(a);
  const note = Math.abs(bal) >= 0.005
    ? `\n\nIts balance of ${fmt(bal)} stays in your totals — archiving hides the account, it does not close it.`
    : '';
  if (!confirm(`Archive account "${a.name}"?${note}`)) return;
  pushUndo(`Archive account "${a.name}"`);
  a.archived = true;
  a.pinned = false;
  if (Array.isArray(forecastState.accountIds))
    forecastState.accountIds = forecastState.accountIds.filter(x => x !== id);
  for (const p of data.forecastProfiles)
    if (Array.isArray(p.accountIds)) p.accountIds = p.accountIds.filter(x => x !== id);
  saveDirty(); render();
  toast(`Archived "${a.name}"`, 5000, 'success', { label: 'Undo', onClick: performUndo });
}
function unarchiveAccount(id) {
  const a = accountById(id); if (!a) return;
  pushUndo(`Unarchive account "${a.name}"`);
  delete a.archived;
  saveDirty(); render();
  toast(`Restored "${a.name}"`, 3000, 'success');
}

// Pin / unpin an account from the Dashboard's pinned-accounts strip. Order on
// the dashboard follows the order of data.accounts itself, so newly pinned
// accounts appear at the bottom of the strip until the user drags them.
function toggleAccountPin(id) {
  const a = accountById(id); if (!a) return;
  a.pinned = !a.pinned;
  saveDirty(); render();
}

function editAccount(id) {
  const a = id ? accountById(id) : { id: uid(), type: "checking", owner: "joint", currency: "EUR", openingBalance: 0, includeInNetWorth: true };
  openModal(`
    <h2>${id ? "Edit" : "Add"} account</h2>
    <div class="field"><label>Name</label><input id="f_name" value="${esc(a.name || '')}"></div>
    <div class="field-row">
      <div class="field"><label>Type</label>
        <select id="f_type">
          ${["checking","savings","credit","cash","investment","loan","other"].map(t =>
            `<option ${a.type===t?'selected':''}>${t}</option>`).join('')}
        </select>
      </div>
      <div class="field"><label>Owner</label>
        <select id="f_owner">
          <option value="joint" ${a.owner==='joint'?'selected':''}>Joint</option>
          <option value="you" ${a.owner==='you'?'selected':''}>You</option>
          <option value="partner" ${a.owner==='partner'?'selected':''}>Partner</option>
        </select>
      </div>
    </div>
    <div class="field-row">
      <div class="field"><label>Opening balance</label>
        <input type="number" step="0.01" id="f_open" value="${a.openingBalance ?? 0}"></div>
      <div class="field"><label>Current balance</label>
        <input type="number" step="0.01" id="f_current" value="${(id ? accountBalance(a) : (a.openingBalance ?? 0)).toFixed(2)}"></div>
    </div>
    <div style="font-size:11px;color:var(--text-dim);margin:-6px 0 12px;line-height:1.4;">
      Edit either field — typing a new Current balance updates Opening balance by the same amount, so the figure on the Accounts page matches what your bank shows.
    </div>
    <div class="field check"><label><input type="checkbox" id="f_inv" ${a.isInvestment?'checked':''}> Investment account</label></div>
    <div class="field check"><label><input type="checkbox" id="f_nw" ${a.includeInNetWorth!==false?'checked':''}> Include in net worth</label></div>
    <div class="field"><label>Notes</label><textarea id="f_notes" rows="2">${esc(a.notes || '')}</textarea></div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn primary" id="f_save">${id ? 'Save' : 'Add'}</button>
    </div>
  `);
  // Live two-way binding between Opening balance and Current balance.
  // txDelta = sum of booked transaction effects on this account. Editing one
  // field adjusts the other by the same delta, so the user can pick whichever
  // is easier to think about ("opening at year start" vs "what my bank shows
  // right now"). On save we only persist openingBalance — Current balance is
  // always derived.
  {
    const fOpen = document.getElementById("f_open");
    const fCurrent = document.getElementById("f_current");
    const txDelta = id ? (accountBalance(a) - (a.openingBalance || 0)) : 0;
    fOpen.addEventListener("input", () => {
      const v = parseFloat(fOpen.value);
      if (!isNaN(v)) fCurrent.value = (v + txDelta).toFixed(2);
    });
    fCurrent.addEventListener("input", () => {
      const v = parseFloat(fCurrent.value);
      if (!isNaN(v)) fOpen.value = (v - txDelta).toFixed(2);
    });
  }
  document.getElementById("f_save").onclick = () => {
    a.name = document.getElementById("f_name").value.trim();
    if (!a.name) { toast("Name required"); return; }
    a.type = document.getElementById("f_type").value;
    a.owner = document.getElementById("f_owner").value;
    a.openingBalance = parseFloat(document.getElementById("f_open").value) || 0;
    // a.currency is left as stored. Nothing converts by it, so the editor no
    // longer shows it — a visible field implied FX that never happened
    // (roadmap: per-account currency + FX table).
    a.isInvestment = document.getElementById("f_inv").checked;
    a.includeInNetWorth = document.getElementById("f_nw").checked;
    a.notes = document.getElementById("f_notes").value;
    if (!id) data.accounts.push(a);
    saveDirty(); closeModal(); render();
  };
}

function deleteAccount(id) {
  const a = accountById(id); if (!a) return;
  // Refuse to delete when other records still reference this account —
  // dropping it would orphan transactions and silently distort net worth
  // (a transfer's destination credit would vanish while the source debit
  // still applies). The user must reassign or delete linked records first.
  const txCount = data.transactions.filter(tx =>
    tx.accountId === id || tx.fromAccountId === id || tx.toAccountId === id).length;
  const recCount = data.recurring.filter(r =>
    r.accountId === id || r.fromAccountId === id || r.toAccountId === id).length;
  if (txCount || recCount) {
    const parts = [];
    if (txCount) parts.push(plural(txCount, 'transaction'));
    if (recCount) parts.push(plural(recCount, 'recurring entry', 'recurring entries'));
    alert(
      `Cannot delete account "${a.name}" — it still has ${parts.join(' and ')} ` +
      `pointing at it.

Delete or reassign those first (open the Transactions / ` +
      `Recurring tabs and filter by this account), then try again.

If you only want it out of the way, use Archive instead — the history stays.`
    );
    return;
  }
  const bal = accountBalance(a);
  const backed = data.envelopes.filter(e => e.accountId === id);
  const backedNote = backed.length
    ? `\n\n${plural(backed.length, 'envelope is', 'envelopes are')} backed by it (${backed.map(e => e.name).join(', ')}) and will become household-wide.`
    : '';
  if (!confirm(`Delete account "${a.name}" (balance ${fmt(bal)})?${backedNote}`)) return;
  pushUndo(`Delete account "${a.name}"`);
  data.accounts = data.accounts.filter(x => x.id !== id);
  // Envelopes it backed degrade to household-wide (migrate would treat a
  // dangling id the same way — this just keeps the file clean).
  for (const e of backed) delete e.accountId;
  // Scrub the deleted account from forecast selections and saved profiles so
  // the projection (Forecast tab + Dashboard card) never indexes a now-missing
  // account — that would throw and blank out both views.
  if (Array.isArray(forecastState.accountIds))
    forecastState.accountIds = forecastState.accountIds.filter(x => x !== id);
  for (const p of data.forecastProfiles)
    if (Array.isArray(p.accountIds)) p.accountIds = p.accountIds.filter(x => x !== id);
  saveDirty(); render();
  toast(`Deleted account "${a.name}"`, 5000, 'success', { label: 'Undo', onClick: performUndo });
}

function updateInvestmentValue(id) {
  const a = accountById(id); if (!a) return;
  const cur = accountBalance(a);
  openModal(`
    <h2>Update ${esc(a.name)} value</h2>
    <p style="color:var(--text-dim);">Current calculated value: <strong>${fmt(cur)}</strong>.
    Enter the actual current market value — this will record a balancing transaction so the account matches reality.</p>
    <div class="field"><label>Actual value today</label>
      <input type="text" inputmode="decimal" id="iv_value" value="${cur.toFixed(2)}"
        placeholder="e.g. 14250 or 14000+250" autocomplete="off">
      <div class="micro" id="iv_value_preview" style="margin-top:4px; min-height:14px;"></div>
    </div>
    <div class="field"><label>Notes (optional)</label>
      <input id="iv_notes" placeholder="e.g. monthly statement"></div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn primary" id="iv_save">Record</button>
    </div>
  `);
  // Live arithmetic preview (e.g. "14000+250" -> "= 14.250,00 €").
  wireAmountPreview("iv_value", "iv_value_preview");

  document.getElementById("iv_save").onclick = () => {
    const newVal = evalAmount(document.getElementById("iv_value").value);
    // evalAmount returns NaN for a cleared field or an incomplete expression
    // (e.g. "14000+"). Without this guard, diff is NaN, the no-change check
    // (NaN < 0.005 is false) falls through, and a NaN-amount tx is booked —
    // permanently poisoning accountBalance/net worth/forecast. Mirror the other
    // evalAmount save sites and refuse it.
    if (isNaN(newVal)) { toast("Enter a valid amount", 3000, 'error'); return; }
    const diff = newVal - cur;
    if (Math.abs(diff) < 0.005) { toast("No change"); closeModal(); return; }
    const notes = document.getElementById("iv_notes").value || "Market value adjustment";
    data.transactions.push({
      id: uid(),
      date: todayISO(),
      type: diff > 0 ? "income" : "expense",
      amount: Math.abs(diff),
      accountId: id,
      envelopeId: null,
      payee: "Market adjustment",
      notes
    });
    saveDirty(); closeModal(); render();
    toast(`${esc(a.name)} updated`);
  };
}

//=============================================================================
// ENVELOPES
//=============================================================================
// Counts the user's "real" activity on an envelope in the trailing 90 days —
// expenses, real income, and envelope-side transfers. Excludes anything with
// accountId === null, which is how Fund-the-month and close-out adjustments
// post (envelope-only allocations, not actual usage). Used by
// envelopeActivityTier() to sort the envelope grid by frequency-of-use.
function envelopeRecentTxCount(env) {
  const cutoff = isoDate(addDays(parseDate(todayISO()), -90));
  let n = 0;
  for (const tx of data.transactions) {
    if (tx.date < cutoff) continue;
    if (tx.accountId === null) continue;          // fund / close-out — skip
    if ((tx.type === 'expense' || tx.type === 'income') && txEnvelopePortion(tx, env.id) > 0) n++;
    else if (tx.type === 'transfer-envelope' && (tx.fromEnvelopeId === env.id || tx.toEnvelopeId === env.id)) n++;
  }
  return n;
}

// Bucketed sort key so envelopes don't shuffle positions every time the user
// logs a transaction — only when an envelope crosses a tier boundary. Lower
// number = closer to the front of the category group.
//   0 — pinned (env.pinned === true)
//   1 — active (5+ tx in trailing 90 days)
//   2 — occasional (1–4 tx)
//   3 — dormant (0 tx, or annual envelopes that fired once a year ago)
function envelopeActivityTier(env) {
  if (env.pinned) return 0;
  const n = envelopeRecentTxCount(env);
  if (n >= 5) return 1;
  if (n >= 1) return 2;
  return 3;
}

// Real spending per envelope in one calendar month, one pass over the tx
// list: {envId: spent}. Same rules as envelopeMonthSummary's `spent` (split-
// aware, isCashflowTx so one-sided bookkeeping doesn't count, transfers out
// count) but for every envelope at once — the card grid needs all of them.
function envelopeMonthSpendMap(ym) {
  const start = ym + "-01", last = lastDayOfMonthKey(ym);
  const out = {};
  for (const tx of data.transactions) {
    if (tx.date < start || tx.date > last) continue;
    if (tx.type === 'expense' && isCashflowTx(tx)) {
      if (tx.splits && tx.splits.length) {
        for (const sp of tx.splits) if (sp.envelopeId) out[sp.envelopeId] = (out[sp.envelopeId] || 0) + Math.abs(sp.amount || 0);
      } else if (tx.envelopeId) out[tx.envelopeId] = (out[tx.envelopeId] || 0) + tx.amount;
    } else if (tx.type === 'transfer-envelope' && tx.fromEnvelopeId) {
      out[tx.fromEnvelopeId] = (out[tx.fromEnvelopeId] || 0) + tx.amount;
    }
  }
  return out;
}

function renderEnvelopes() {
  // Precompute the activity tier once per envelope — calling it inside the sort
  // comparator below re-ran an O(transactions) scan O(n log n) times.
  const spentMap = envelopeMonthSpendMap(todayISO().slice(0, 7));
  const envs = activeEnvelopes().map(e => ({ e, bal: envelopeBalance(e), tier: envelopeActivityTier(e), spent: spentMap[e.id] || 0 }));
  const archivedEnvs = data.envelopes.filter(e => e.archived).map(e => ({ e, bal: envelopeBalance(e) }));
  const groups = {};
  for (const x of envs) {
    const cat = x.e.category || "Uncategorized";
    (groups[cat] = groups[cat] || []).push(x);
  }
  // Sort envelopes within each category by activity tier (pinned → active →
  // occasional → dormant), alphabetically inside each tier so the order is
  // stable until something actually crosses a threshold.
  for (const cat of Object.keys(groups)) {
    groups[cat].sort((a, b) => {
      if (a.tier !== b.tier) return a.tier - b.tier;
      return (a.e.name || '').localeCompare(b.e.name || '');
    });
  }
  const totalBal = envs.reduce((s,x)=>s+x.bal,0);
  const totalBudget = envs.reduce((s,x)=>s+envMonthlyEquiv(x.e),0);

  return `
  <h2>Envelopes</h2>
  <div class="toolbar">
    <button class="btn primary" id="addEnv">+ Add envelope</button>
    <button class="btn" id="refillBtn" title="Assign one month's budget to each envelope (or top up to full target)">⟳ Fund the month</button>
    <button class="btn" id="transferBtn">⇄ Move funds</button>
    <div class="spacer"></div>
    <div class="toolbar-stat">
      <span class="stat-label">Balance / monthly budget</span>
      <strong>${fmt(totalBal)} <span style="color:var(--text-dim);font-weight:400;font-size:.85em;">/ ${fmt(totalBudget)}</span></strong>
    </div>
  </div>
  ${Object.keys(groups).length === 0 ?
    '<div class="card empty-state"><p>No envelopes yet. Add categories like Groceries, Utilities, Kids School…</p></div>' :
    Object.entries(groups).map(([cat, items]) => {
      const catBal = items.reduce((s, x) => s + x.bal, 0);
      const catBudget = items.reduce((s, x) => s + envMonthlyEquiv(x.e), 0);
      return `
      <div class="env-cat-head">
        <h3>${esc(cat)}</h3>
        <div class="env-cat-summary">
          <strong>${fmt(catBal)}</strong>
          <span style="color:var(--text-dim);">/ ${fmt(catBudget)} mo</span>
        </div>
      </div>
      <div class="grid cols-3" style="margin-bottom:14px;">
        ${items.map(({e, bal, spent}) => envelopeCard(e, bal, spent)).join('')}
      </div>
    `;}).join('')}
  ${archivedEnvs.length ? `
  <details class="archived-list">
    <summary>${plural(archivedEnvs.length, 'archived envelope')} <span class="micro" style="margin-left:6px;">— no budget, hidden from pickers and Fund the month; any balance stays earmarked</span></summary>
    <div class="card" style="padding:0;margin-top:8px;">
      <table>
        <tbody>
          ${archivedEnvs.map(({e, bal}) => `<tr>
            <td><strong><a href="#" class="drill" data-tx-env="${e.id}" title="Show this envelope's transactions">${esc(e.name)}</a></strong> <span class="badge">archived</span>${e.category ? ` <span class="micro">${esc(e.category)}</span>` : ''}</td>
            <td class="num ${bal < 0 ? 'neg' : ''}"><strong>${fmt(bal)}</strong></td>
            <td class="actions">
              <button class="btn sm" data-unarchive-env="${e.id}">Unarchive</button>
              ${bal > 0 ? `<button class="btn sm" data-return="${e.id}" title="Un-earmark the balance back to spendable cash">↩ Return</button>` : ''}
              <button class="btn sm ghost" data-edit-env="${e.id}">Edit</button>
              <button class="btn sm danger" data-del-env="${e.id}" aria-label="Delete envelope ${esc(e.name)}" title="Delete envelope">×</button>
            </td>
          </tr>`).join('')}
        </tbody>
      </table>
    </div>
  </details>` : ''}
  `;
}
function envelopeCard(e, bal, spent) {
  const budget = e.budgetAmount || 0;
  // This month's spending vs the monthly budget (1/12 for annual). Balance
  // says what's left in the envelope; this says how the month is going.
  const monthly = envMonthlyEquiv(e);
  const left = monthly - (spent || 0);
  const monthLine = e.isReserve ? '' : `<div class="ev-month">
      <span>spent ${fmt(spent || 0)} this month</span>
      ${monthly > 0 ? `<span class="${left < 0 ? 'over' : ''}">${left < 0 ? fmt(-left) + ' over budget' : fmt(left) + ' of budget left'}</span>` : ''}
    </div>`;
  const isAnnual = e.cadence === "annual";
  const isReset = !isAnnual && e.rolloverPolicy === "reset";
  const isSweep = !isAnnual && !e.isReserve && e.rolloverPolicy === "sweep";
  const isReserve = !!e.isReserve;
  const isPinned = !!e.pinned;
  const pct = budget ? Math.max(0, Math.min(100, (bal / budget) * 100)) : 0;
  // The state drives the card's spine colour; the colours live in CSS
  // (.envelope[data-state]) so no hex ever reaches JS.
  const state = bal < 0 ? "over" : (e.isReserve || pct >= 25) ? "ok" : "low";
  // Pace bar: this month's spending against this month's budget, with a tick
  // at how far through the month we are. "ahead" = spending is running ahead
  // of the calendar; "over" = past the budget. Reserve and unbudgeted
  // envelopes have no month to pace, so they get no bar.
  let bar = '';
  if (!e.isReserve && monthly > 0) {
    const now = new Date();
    const dim = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const monthPct = (now.getDate() / dim) * 100;
    const spentPct = Math.min(100, ((spent || 0) / monthly) * 100);
    const pace = spentPct >= 100 ? 'over' : spentPct > monthPct + 0.5 ? 'ahead' : 'ok';
    const label = `${Math.round(spentPct)}% of this month's budget spent, ${Math.round(monthPct)}% of the month gone`;
    bar = `<div class="ev-bar" data-pace="${pace}" role="img" aria-label="${label}" title="${label}">
      <span class="ev-bar-fill" style="width:${spentPct.toFixed(1)}%"></span>
      <span class="ev-bar-tick" style="left:${monthPct.toFixed(1)}%"></span>
    </div>`;
  }
  return `<div class="card envelope" data-state="${state}">
    <div class="ev-head">
      <div class="ev-name">${isPinned ? '<span title="Pinned to top of group" style="color:var(--accent);margin-right:4px;">📌</span>' : ''}<a href="#" class="drill" data-tx-env="${e.id}" title="Show this envelope's transactions">${esc(e.name)}</a>${isAnnual ? ' <span class="badge" style="margin-left:4px;">annual</span>' : ''}${isReset ? ' <span class="badge" style="margin-left:4px;" title="Leftover returns to spendable each month">resets</span>' : ''}${isSweep ? ' <span class="badge" style="margin-left:4px;" title="Leftover sweeps into the reserve envelope at close-out">sweeps</span>' : ''}${isReserve ? ' <span class="badge" style="margin-left:4px;" title="Reserve envelope — never funded by Fund the month; receives close-out sweeps">reserve</span>' : ''}</div>
      <div class="ev-bal ${bal<0?'neg':''}">${fmt(bal)}</div>
    </div>
    <div class="ev-meta">
      ${isReserve
        ? '<span>held for emergencies</span><span>no budget</span>'
        : `<span>${pct.toFixed(0)}% of ${isAnnual ? 'annual' : 'monthly'}</span>
      <span>${fmt(budget)} / ${isAnnual ? 'yr' : 'mo'}</span>`}
    </div>
    ${bar}
    ${monthLine}
    <div class="ev-actions">
      <button class="btn sm" data-spend="${e.id}">Spend</button>
      <button class="btn sm" data-fund="${e.id}">Fund</button>
      <button class="btn sm" data-return="${e.id}" title="Un-earmark money from this envelope and return it to spendable cash (no account is touched)" ${bal <= 0 ? 'disabled' : ''}>↩ Return</button>
      <details class="ev-more">
        <summary class="btn sm ghost" aria-label="More actions for ${esc(e.name)}" title="Edit, archive or delete">⋯</summary>
        <div class="menu" role="menu">
          <button class="menu-item" role="menuitem" data-edit-env="${e.id}">Edit…</button>
          <button class="menu-item" role="menuitem" data-archive-env="${e.id}" title="Drop it from the budget and the pickers, keep its history">Archive</button>
          <button class="menu-item danger" role="menuitem" data-del-env="${e.id}">Delete…</button>
        </div>
      </details>
    </div>
  </div>`;
}
function bindEnvelopes() {
  document.getElementById("addEnv").onclick = () => editEnvelope();
  document.getElementById("refillBtn").onclick = refillEnvelopes;
  document.getElementById("transferBtn").onclick = () => transferEnvelopes();
  document.querySelectorAll("[data-edit-env]").forEach(b =>
    b.onclick = () => editEnvelope(b.dataset.editEnv));
  document.querySelectorAll("[data-del-env]").forEach(b =>
    b.onclick = () => deleteEnvelope(b.dataset.delEnv));
  document.querySelectorAll("[data-spend]").forEach(b =>
    b.onclick = () => quickTx("expense", { envelopeId: b.dataset.spend }));
  document.querySelectorAll("[data-fund]").forEach(b =>
    b.onclick = () => quickTx("income", { envelopeId: b.dataset.fund }));
  document.querySelectorAll("[data-return]").forEach(b =>
    b.onclick = () => returnEnvelopeFunds(b.dataset.return));
  document.querySelectorAll("[data-archive-env]").forEach(b =>
    b.onclick = () => archiveEnvelope(b.dataset.archiveEnv));
  document.querySelectorAll("[data-unarchive-env]").forEach(b =>
    b.onclick = () => unarchiveEnvelope(b.dataset.unarchiveEnv));
  // A menu item closes its menu before acting (Edit opens a modal without a
  // re-render, so the menu would otherwise stay open behind it).
  document.querySelectorAll(".ev-more .menu-item").forEach(b =>
    b.addEventListener('click', () => { b.closest('details').open = false; }, true));
  wireDrillLinks();
}
// One-time: an open "⋯" menu closes on a click anywhere else or on Escape.
if (!window._evMoreWired) {
  window._evMoreWired = true;
  document.addEventListener('click', ev => {
    document.querySelectorAll('.ev-more[open]').forEach(d => { if (!d.contains(ev.target)) d.open = false; });
  });
  document.addEventListener('keydown', ev => {
    if (ev.key !== 'Escape') return;
    const open = document.querySelector('.ev-more[open]');
    if (open) { open.open = false; open.querySelector('summary').focus(); }
  });
}

// Archive = out of the budget, not out of the books. The envelope keeps its
// transactions and its balance (still earmarked — Return it first if the money
// should go back to spendable), but it has no budget any more (envMonthlyEquiv
// → 0), so it leaves the allowance projection, the monthly totals, Fund the
// month, close-out and every picker. The reserve can't be archived: the flag
// is the sweep destination. Refused while an active recurring still feeds it.
function archiveEnvelope(id) {
  const e = envelopeById(id); if (!e) return;
  if (e.isReserve) { alert(`"${e.name}" is the reserve envelope. Untick "Reserve envelope" in Edit first, then archive it.`); return; }
  const recs = data.recurring.filter(r => r.active !== false &&
    (r.envelopeId === id || r.fromEnvelopeId === id || r.toEnvelopeId === id));
  if (recs.length) {
    alert(`Cannot archive envelope "${e.name}" — ${plural(recs.length, 'active recurring entry', 'active recurring entries')} still ` +
      `${recs.length === 1 ? 'uses' : 'use'} it (${recs.map(r => r.name).join(', ')}).\n\nDeactivate or reassign ${recs.length === 1 ? 'it' : 'them'} first.`);
    return;
  }
  const bal = envelopeBalance(e);
  const note = Math.abs(bal) >= 0.005
    ? `\n\nIts balance of ${fmt(bal)} stays earmarked in the envelope. Use ↩ Return first if that money should go back to spendable cash.`
    : '';
  if (!confirm(`Archive envelope "${e.name}"?${note}`)) return;
  pushUndo(`Archive envelope "${e.name}"`);
  e.archived = true;
  e.pinned = false;
  saveDirty(); render();
  toast(`Archived "${e.name}"`, 5000, 'success', { label: 'Undo', onClick: performUndo });
}
function unarchiveEnvelope(id) {
  const e = envelopeById(id); if (!e) return;
  pushUndo(`Unarchive envelope "${e.name}"`);
  delete e.archived;
  saveDirty(); render();
  toast(`Restored "${e.name}"`, 3000, 'success');
}

function editEnvelope(id) {
  const e = id ? envelopeById(id) : { id: uid(), budgetAmount: 0, cadence: "monthly", openingBalance: 0, category: "", rolloverPolicy: "rollover", pinned: false, isReserve: false };
  // The existing reserve envelope, if any and if it isn't this one — used to
  // label the sweep policy and to warn that ticking the box moves the flag.
  const otherReserve = data.envelopes.find(x => x.isReserve && x.id !== e.id) || null;
  openModal(`
    <h2>${id ? "Edit" : "Add"} envelope</h2>
    <div class="field"><label>Name</label><input id="f_name" value="${esc(e.name || '')}"></div>
    <div class="field"><label>Category (group)</label>
      <input id="f_cat" value="${esc(e.category || '')}" list="catList" placeholder="e.g. Living, Family, Fun…">
      <datalist id="catList">
        ${[...new Set(data.envelopes.map(x => x.category).filter(Boolean))]
          .map(c => `<option value="${esc(c)}">`).join('')}
      </datalist>
    </div>
    <div class="field-row" id="f_budget_row">
      <div class="field"><label>Opening balance</label>
        <input type="number" step="0.01" id="f_open" value="${e.openingBalance ?? 0}"></div>
      <div class="field"><label>Budget amount <span class="help-tip" tabindex="0" title="The target amount for this envelope per cadence. For Monthly envelopes this is what you fund each month; for Annual envelopes this is the full yearly target — the app accrues 1/12 of it each month.">?</span></label>
        <input type="number" step="0.01" id="f_bud" value="${e.budgetAmount ?? 0}"></div>
      <div class="field"><label>Cadence <span class="help-tip" tabindex="0" title="Monthly: budget refills each month (e.g. Groceries €600/mo). Annual: budget is the YEARLY target — it accrues 1/12 per month so a €2,400/yr Holiday Fund builds up by €200/mo without you topping it up manually.">?</span></label>
        <select id="f_cad">
          <option value="monthly" ${e.cadence !== 'annual' ? 'selected' : ''}>per month</option>
          <option value="annual" ${e.cadence === 'annual' ? 'selected' : ''}>per year</option>
        </select></div>
    </div>
    <div class="field" id="f_roll_field" ${(e.cadence === 'annual' || e.isReserve) ? 'style="display:none;"' : ''}>
      <label>Month-end policy
        <span style="color:var(--text-dim);font-weight:400;font-size:12px;margin-left:6px;">— used by close-out review</span>
      </label>
      <select id="f_roll">
        <option value="rollover" ${(e.rolloverPolicy !== 'reset' && e.rolloverPolicy !== 'sweep') ? 'selected' : ''}>Rollover — carry balance into next month</option>
        <option value="reset" ${e.rolloverPolicy === 'reset' ? 'selected' : ''}>Reset — return any leftover to spendable on the 1st</option>
        <option value="sweep" ${e.rolloverPolicy === 'sweep' ? 'selected' : ''}>Sweep — move any leftover into the reserve envelope</option>
      </select>
      <div class="micro" style="margin-top:4px;">Sweep needs a reserve envelope${(otherReserve || e.isReserve) ? '' : ' — tick “Reserve envelope” on one envelope first'}.</div>
    </div>
    <div class="field" id="f_acc_field" ${e.isReserve ? 'style="display:none;"' : ''}>
      <label>Backed by account <span class="help-tip" tabindex="0" title="Which account holds this envelope's money. It only matters when a forecast selects some accounts and not others: a backed envelope counts against spendable cash only in forecasts that include its account, and its allowance drains from that account. Household means any account — the envelope counts in every forecast, which is how all envelopes behaved before this field existed.">?</span></label>
      <select id="f_acc">
        <option value="">Household — any account</option>
        ${pickAccounts(e.accountId).filter(a => !a.isInvestment).map(a =>
          `<option value="${a.id}" ${e.accountId === a.id ? 'selected' : ''}>${esc(a.name)}${archSuffix(a)}${a.owner && a.owner !== 'joint' ? ` (${esc(a.owner === 'you' ? (data.settings.household?.[0] || 'You') : (data.settings.household?.[1] || 'Partner'))})` : ''}</option>`
        ).join('')}
      </select>
    </div>
    <div class="field"><label>Notes</label><textarea id="f_notes" rows="2">${esc(e.notes || '')}</textarea></div>
    ${id ? `
    <div class="field" style="background:var(--bg-3);padding:10px 12px;border-radius:6px;border:1px solid var(--border);">
      <label>Adjust current balance <span class="help-tip" tabindex="0" title="Set the envelope balance to a target value by recording a single one-sided transaction (envelope only — no account is touched). Budget amount per cadence is NOT changed, no other envelopes are touched. Spendable cash IS affected: raising the envelope balance earmarks more money, so spendable drops by the adjustment amount (and vice versa). You can type arithmetic (e.g. 500-23 → 477).">?</span></label>
      <div style="display:flex;gap:10px;align-items:baseline;margin:6px 0;flex-wrap:wrap;">
        <span style="color:var(--text-dim);font-size:12px;">Current:</span>
        <strong style="font-variant-numeric:tabular-nums;">${fmt(envelopeBalance(e))}</strong>
        <span style="color:var(--text-dim);font-size:12px;margin-left:auto;">Adjust to:</span>
        <input type="text" inputmode="decimal" id="f_adjust"
          placeholder="leave empty for no change" autocomplete="off"
          style="width:130px;text-align:right;padding:4px 6px;background:var(--bg);border:1px solid var(--border);border-radius:4px;color:var(--text);font-variant-numeric:tabular-nums;">
      </div>
      <div class="micro" id="f_adjust_preview" style="min-height:14px;margin-bottom:6px;"></div>
      <div style="margin-top:4px;">
        <label style="font-size:11px;color:var(--text-dim);text-transform:uppercase;letter-spacing:.5px;display:block;margin-bottom:4px;">Adjustment notes (optional)</label>
        <input id="f_adjust_notes" placeholder="e.g. reconciled with bank app"
          style="width:100%;padding:6px 8px;background:var(--bg);border:1px solid var(--border);border-radius:4px;color:var(--text);">
      </div>
    </div>
    ` : ''}
    <div class="field">
      <label style="display:flex;align-items:center;gap:8px;cursor:pointer;font-weight:400;text-transform:none;letter-spacing:0;font-size:13px;color:var(--text);">
        <input type="checkbox" id="f_pin" ${e.pinned ? 'checked' : ''} style="width:auto;margin:0;">
        Pin to top of group
        <span style="color:var(--text-dim);font-size:12px;">— floats above the activity-based sort</span>
      </label>
    </div>
    <div class="field">
      <label style="display:flex;align-items:center;gap:8px;cursor:pointer;font-weight:400;text-transform:none;letter-spacing:0;font-size:13px;color:var(--text);">
        <input type="checkbox" id="f_reserve" ${e.isReserve ? 'checked' : ''} style="width:auto;margin:0;">
        Reserve envelope (emergency / catch-all)
        <span class="help-tip" tabindex="0" title="A reserve envelope has no budget and is never proposed by 'Fund the month'. It just sits holding money you've set aside. At month-end close-out you can sweep any envelope's leftover into it, and you move money back out with 'Move funds' whenever a real envelope needs it. Only one envelope can be the reserve.">?</span>
      </label>
      <div class="micro" id="f_reserve_note" style="margin-top:4px;">
        ${otherReserve ? `Currently: <strong>${esc(otherReserve.name)}</strong> — ticking this moves the flag here.` : ''}
      </div>
    </div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn primary" id="f_save">${id ? 'Save' : 'Add'}</button>
    </div>
  `);
  // Hide the rollover-policy field whenever cadence flips to annual — annuals
  // always rollover (it makes no sense to "reset" a yearly bucket each month).
  const _reserveBox = document.getElementById("f_reserve");
  const _syncReserveUI = () => {
    const on = _reserveBox.checked;
    // A reserve envelope has no budget, no cadence and no month-end policy of
    // its own: hiding the fields is what keeps it out of the forecast's
    // allowance projection (budgetAmount 0 → envMonthlyEquiv 0 → skipped) and
    // out of the Fund modal, rather than a second set of guards everywhere.
    document.getElementById("f_budget_row").style.display = on ? "none" : "";
    document.getElementById("f_acc_field").style.display = on ? "none" : "";
    document.getElementById("f_roll_field").style.display =
      (on || document.getElementById("f_cad").value === "annual") ? "none" : "";
  };
  _reserveBox.addEventListener('change', _syncReserveUI);
  document.getElementById("f_cad").onchange = (ev) => {
    if (_reserveBox.checked) return;
    document.getElementById("f_roll_field").style.display = ev.target.value === "annual" ? "none" : "";
  };
  // Live preview for the "Adjust current balance" field. Only present when
  // editing an existing envelope (the field is omitted for new ones).
  if (id) {
    const _adjIn = document.getElementById("f_adjust");
    const _adjPv = document.getElementById("f_adjust_preview");
    const _updateAdjPreview = () => {
      const raw = _adjIn.value;
      if (!raw || !raw.trim()) { _adjPv.textContent = ''; return; }
      const target = evalAmount(raw);
      if (isNaN(target)) { _adjPv.textContent = '⚠ invalid expression'; return; }
      const cur = envelopeBalance(e);
      const diff = target - cur;
      if (Math.abs(diff) < 0.005) { _adjPv.textContent = 'no change'; return; }
      const sign = diff > 0 ? '+' : '−';
      _adjPv.textContent = `→ books ${sign}${fmt(Math.abs(diff))} adjustment dated today`;
    };
    _adjIn.addEventListener('input', _updateAdjPreview);
  }
  document.getElementById("f_save").onclick = () => {
    const name = document.getElementById("f_name").value.trim();
    if (!name) { toast("Name required"); return; }

    // Compute the balance adjustment FIRST so any pushUndo captures the
    // pre-state (envelope shape + the not-yet-pushed adjustment tx).
    // Skip when adding a brand-new envelope — the Adjust field is not
    // rendered in that case (use Opening balance instead).
    let adjustmentTx = null;
    if (id) {
      const adjustRaw = document.getElementById("f_adjust").value;
      if (adjustRaw && adjustRaw.trim()) {
        const target = evalAmount(adjustRaw);
        if (!isNaN(target)) {
          const current = envelopeBalance(e);
          const diff = target - current;
          if (Math.abs(diff) >= 0.005) {
            const userNotes = document.getElementById("f_adjust_notes").value.trim();
            adjustmentTx = {
              id: uid(),
              date: todayISO(),
              type: diff > 0 ? 'income' : 'expense',
              amount: Math.abs(diff),
              accountId: null,
              envelopeId: e.id,
              payee: 'Balance adjustment',
              notes: userNotes || `Adjust to ${fmt(target)}`
            };
          }
        } else {
          toast("Adjust-to: invalid expression", 3000, 'error');
          return;
        }
      }
    }

    if (adjustmentTx) {
      pushUndo(`Adjust "${name}" balance by ${adjustmentTx.type === 'income' ? '+' : '−'}${fmt(adjustmentTx.amount)}`);
    }

    e.name = name;
    e.category = document.getElementById("f_cat").value.trim();
    e.openingBalance = parseFloat(document.getElementById("f_open").value) || 0;
    e.budgetAmount = parseFloat(document.getElementById("f_bud").value) || 0;
    e.cadence = document.getElementById("f_cad").value || "monthly";
    e.rolloverPolicy = e.cadence === "annual" ? "rollover" : (document.getElementById("f_roll").value || "rollover");
    e.isReserve = document.getElementById("f_reserve").checked;
    if (e.isReserve) {
      // Exactly one reserve envelope: the flag is the sweep destination, so a
      // second one would make "sweep to the reserve" ambiguous. Ticking it here
      // takes it away from whoever held it.
      for (const x of data.envelopes) { if (x.id !== e.id) x.isReserve = false; }
      e.budgetAmount = 0;
      e.cadence = "monthly";
      e.rolloverPolicy = "rollover";
    }
    // Backing account: a real id or nothing at all (never null/"") so the
    // field reads as absent in exports. A reserve is always household-wide.
    const backedBy = e.isReserve ? "" : (document.getElementById("f_acc").value || "");
    if (backedBy && accountById(backedBy)) e.accountId = backedBy; else delete e.accountId;
    // A sweep policy with no reserve envelope to sweep into is a no-op that
    // would silently behave like rollover at close-out; degrade it explicitly.
    if (e.rolloverPolicy === "sweep" && !data.envelopes.some(x => x.isReserve && x.id !== e.id)) {
      e.rolloverPolicy = "rollover";
    }
    e.pinned = document.getElementById("f_pin").checked;
    e.notes = document.getElementById("f_notes").value;
    if (!id) data.envelopes.push(e);
    if (adjustmentTx) data.transactions.push(adjustmentTx);
    saveDirty(); closeModal(); render();
    if (adjustmentTx) {
      const sign = adjustmentTx.type === 'income' ? '+' : '−';
      toast(`Balance adjusted (${sign}${fmt(adjustmentTx.amount)})`, 3500, 'success', { label: 'Undo', onClick: performUndo });
    }
  };
}

function deleteEnvelope(id) {
  const e = envelopeById(id); if (!e) return;
  // Same rationale as deleteAccount: orphaned envelope refs distort the
  // "what is each euro earmarked for?" view and break envelope-transfer
  // pairs. Force the user to clean up references first.
  const txCount = data.transactions.filter(tx =>
    tx.envelopeId === id || tx.fromEnvelopeId === id || tx.toEnvelopeId === id ||
    (tx.splits && tx.splits.some(s => s.envelopeId === id))).length;
  const recCount = data.recurring.filter(r =>
    r.envelopeId === id || r.fromEnvelopeId === id || r.toEnvelopeId === id).length;
  if (txCount || recCount) {
    const parts = [];
    if (txCount) parts.push(plural(txCount, 'transaction'));
    if (recCount) parts.push(plural(recCount, 'recurring entry', 'recurring entries'));
    alert(
      `Cannot delete envelope "${e.name}" — it still has ${parts.join(' and ')} ` +
      `pointing at it.

Delete or reassign those first (open the Transactions / ` +
      `Recurring tabs and filter by this envelope), then try again.

If you only want it out of the way, use Archive instead — the history stays.`
    );
    return;
  }
  const bal = envelopeBalance(e);
  if (!confirm(`Delete envelope "${e.name}" (balance ${fmt(bal)})?`)) return;
  pushUndo(`Delete envelope "${e.name}"`);
  data.envelopes = data.envelopes.filter(x => x.id !== id);
  saveDirty(); render();
  toast(`Deleted envelope "${e.name}"`, 5000, 'success', { label: 'Undo', onClick: performUndo });
}

// Un-earmark money from an envelope and "return it" to spendable cash. Books
// a one-sided expense (envelopeId set, accountId null) — the symmetric inverse
// of refilling. No account is touched; the money was never really moved out
// of accounts in the first place, just labeled. Removing the label returns it
// to the unallocated pool, which is exactly what raises the spendable line.
function returnEnvelopeFunds(id) {
  const env = envelopeById(id);
  if (!env) return;
  const current = envelopeBalance(env);
  if (current <= 0.005) {
    toast(`"${env.name}" has no balance to return`, 3000);
    return;
  }
  openModal(`
    <h2>Return funds from ${esc(env.name)}</h2>
    <p style="color:var(--text-dim);margin-top:-4px;">
      Current balance: <strong style="color:var(--text);">${fmt(current)}</strong>.
      Un-earmarks money from this envelope and returns it to spendable cash —
      no account is touched. Books a one-sided expense dated today.
    </p>
    <div class="field"><label>Amount to return</label>
      <input type="text" inputmode="decimal" id="ret_amt" value="${current.toFixed(2)}"
        placeholder="e.g. 100 or 423.50-23" autocomplete="off">
      <div class="micro" id="ret_amt_preview" style="margin-top:4px; min-height:14px;"></div>
    </div>
    <div class="field"><label>Notes (optional)</label>
      <input id="ret_notes" placeholder="e.g. over-funded last month, reallocating">
    </div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn primary" id="ret_save">Return</button>
    </div>
  `);

  // Live preview — show resulting envelope balance and spendable rise.
  const _retIn = document.getElementById("ret_amt");
  const _retPv = document.getElementById("ret_amt_preview");
  const _updateRetPreview = () => {
    const raw = _retIn.value;
    if (!raw || !raw.trim()) { _retPv.textContent = ''; return; }
    const amt = evalAmount(raw);
    if (isNaN(amt)) { _retPv.textContent = '⚠ invalid expression'; return; }
    if (amt <= 0) { _retPv.textContent = '⚠ amount must be positive'; return; }
    if (amt > current + 0.005) { _retPv.textContent = `⚠ exceeds current balance of ${fmt(current)}`; return; }
    _retPv.textContent = `→ new envelope balance: ${fmt(current - amt)} · spendable rises by ${fmt(amt)}`;
  };
  _retIn.addEventListener('input', _updateRetPreview);
  _updateRetPreview();

  document.getElementById("ret_save").onclick = () => {
    const amt = evalAmount(_retIn.value);
    if (isNaN(amt) || amt <= 0) {
      toast("Enter a valid positive amount", 3000, 'error');
      return;
    }
    if (amt > current + 0.005) {
      toast(`Cannot return more than the current balance of ${fmt(current)}`, 3500, 'error');
      return;
    }
    const userNotes = document.getElementById("ret_notes").value.trim();
    pushUndo(`Return ${fmt(amt)} from "${env.name}"`);
    data.transactions.push({
      id: uid(),
      date: todayISO(),
      type: 'expense',
      amount: amt,
      accountId: null,
      envelopeId: env.id,
      payee: 'Return to spendable',
      notes: userNotes || `Un-earmarked from ${env.name}`
    });
    saveDirty(); closeModal(); render();
    toast(`Returned ${fmt(amt)} from "${env.name}" to spendable`, 3500, 'success',
      { label: 'Undo', onClick: performUndo });
  };
}

// The two funding modes answer genuinely different questions:
//
//   "month" — ASSIGN one month's budget. Monthly envelope gets budgetAmount,
//             annual gets budgetAmount/12. The current balance does NOT enter
//             the sum, so an envelope you overspent last month lands at
//             (budget − overspend): shopping at −735 with a 1.000 budget is
//             funded 1.000 and ends the month at 265, and last month's
//             overspend is felt this month, which is the whole point.
//   "full"  — TOP UP to the target balance, i.e. budgetAmount − bal. Useful at
//             year-start for an annual sinking fund, or as a one-shot repair
//             after an overspend you don't want carried.
//
// Before 2026-08-01 "month" also computed budget − bal for monthly envelopes,
// which made it identical to "full" for everything except annuals — and meant
// "Fund one month" silently repaid overdrafts. On a real 12-envelope month it
// proposed noticeably more than one month's budget; the whole difference was
// overspend repair the user had not asked for.
//
// Only annual keeps a cap. For an annual envelope budgetAmount is a TARGET
// BALANCE (the amount to have saved by year end), so accruing past it is meaningless. For
// a monthly envelope it is a MONTHLY FLOW, so there is no ceiling to clamp to
// and a rollover envelope is free to accumulate — that is what rollover is for.
function envelopeFundSuggestion(env, mode) {
  const bal = envelopeBalance(env);
  const budget = env.budgetAmount || 0;
  if (mode === "full") {
    return { bal, target: budget, suggested: Math.max(0, budget - bal) };
  }
  // mode === "month"
  if (env.cadence === "annual") {
    const headroom = Math.max(0, budget - bal);
    return { bal, target: budget, suggested: Math.max(0, Math.min(budget / 12, headroom)) };
  }
  return { bal, target: budget, suggested: Math.max(0, budget) };
}

function refillEnvelopes() {
  // Reserve envelopes are deliberately absent from this modal: they hold money
  // that has already been budgeted once (swept out of other envelopes at
  // close-out), so proposing to fund them again would double-allocate it.
  const fundable = data.envelopes.filter(e => !e.isReserve && !e.archived);
  if (data.envelopes.length === 0) {
    toast("No envelopes to fund yet");
    return;
  }
  if (fundable.length === 0) {
    toast("Only reserve envelopes exist — those are never funded");
    return;
  }

  // Same forecast the Dashboard mirrors, so this modal's baseline agrees with
  // the Dashboard's "Lowest in period" tile. This is the fund-NOTHING low point
  // only — the post-funding figure under the list comes from re-forecasting
  // with the proposed rows applied (spendableMinAfterFunding), because the
  // spendable line is piecewise since the per-envelope zero floor landed and no
  // scalar "max safe to fund" exists any more: the cost of a euro depends on
  // which envelope it goes into, and on whether that envelope will spend it
  // back inside the horizon.
  const fcAccountIds = (forecastState.accountIds && forecastState.accountIds.length)
    ? forecastState.accountIds
    : activeAccounts().filter(a => !a.isInvestment && a.includeInNetWorth !== false).map(a => a.id);
  const fcDays = forecastState.days || 90;
  const fcOpts = { includeAllowances: forecastState.includeAllowances };
  let headroom = null;
  if (fcAccountIds.length > 0) {
    const fc = forecastAccountBalances(fcAccountIds, fcDays, fcOpts);
    const lo = spendableLow(fc);
    headroom = {
      spendNow: fc.spendable[0],
      spendMin: lo.min,
      spendMinDate: lo.date,
      horizonDays: fcDays,
      accountIds: fcAccountIds,
      opts: fcOpts
    };
  }

  // Each invocation re-renders the modal body so the user can flip between
  // "month" and "full" modes; we keep one closure-scoped state object and a
  // helper that paints rows from it.
  const state = { mode: "month" };

  const draw = () => {
    const rows = fundable.map(env => {
      const s = envelopeFundSuggestion(env, state.mode);
      return { env, ...s };
    });
    const total = rows.reduce((sum, r) => sum + r.suggested, 0);
    const isAnnualNote = state.mode === "month"
      ? "Assigns one month's budget to each envelope — the monthly amount, or budget ÷ 12 for annual envelopes. An envelope you overspent last month lands below its budget, so the overspend is felt this month rather than quietly repaid."
      : "Tops each envelope up TO its target balance (the monthly amount, or the full yearly amount for annual) — so an overspent envelope is brought back to its budget in one go.";

    const headroomBlock = headroom ? `
      <div style="display:flex;gap:18px;flex-wrap:wrap;padding:10px 12px;margin:0 0 12px 0;background:var(--bg-2);border:1px solid var(--border);border-radius:6px;">
        <div>
          <div class="stat-label">Spendable today</div>
          <div style="font-size:16px;font-weight:600;font-variant-numeric:tabular-nums;">${fmt(headroom.spendNow)}</div>
        </div>
        <div>
          <div class="stat-label">Spendable min in horizon <span class="help-tip" tabindex="0" title="Spendable = total of your accounts − the envelope balances they hold (the YNAB Available-to-Budget concept; envelopes backed by accounts outside the forecast are left out). Funding envelopes moves money INTO buckets, so spendable drops even though your total account balance is unchanged — but not always one-for-one: funding an overspent envelope first fills its hole, and money in an envelope with an allowance gets spent from that envelope inside the horizon. That is why the figure below the list is a real re-forecast with your proposal applied, not this number minus the total.">?</span></div>
          <div style="font-size:16px;font-weight:600;font-variant-numeric:tabular-nums;color:var(--warn);">
            ${fmt(headroom.spendMin)}
            <span style="font-size:12px;font-weight:400;color:var(--text-dim);">on ${fmtDate(headroom.spendMinDate)}</span>
          </div>
          <div style="font-size:11px;font-style:italic;color:var(--text-dim);">if you fund nothing</div>
        </div>
      </div>` : '';

    document.getElementById("rf_body").innerHTML = `
      ${headroomBlock}
      <p style="color:var(--text-dim);margin-top:0;">${isAnnualNote}
         This records a funding income on each envelope (no account effect —
         envelopes are virtual allocations; your real cash stays where it is).</p>
      <div class="field-row">
        <div class="field"><label>Mode</label>
          <select id="rf_mode">
            <option value="month" ${state.mode === 'month' ? 'selected' : ''}>Assign one month's budget</option>
            <option value="full" ${state.mode === 'full' ? 'selected' : ''}>Top up to full target</option>
          </select>
        </div>
        <div class="field"><label>Date</label>
          <input type="date" id="rf_date" value="${todayISO()}"></div>
      </div>
      <div class="checkbox-list" style="max-height:48vh;overflow:auto;">
        ${rows.map(r => {
          const isAnnual = r.env.cadence === 'annual';
          const isReset = !isAnnual && r.env.rolloverPolicy === 'reset';
          const isSweep = !isAnnual && r.env.rolloverPolicy === 'sweep';
          const noNeed = r.suggested < 0.005;
          return `
            <label style="${noNeed ? 'opacity:.55;' : ''}">
              <input type="checkbox" data-rf="${r.env.id}" ${noNeed ? '' : 'checked'} ${noNeed ? 'disabled' : ''}>
              <span style="flex:1;">${esc(r.env.name)}
                ${isAnnual ? '<span class="badge" style="margin-left:4px;">annual</span>' : ''}
                ${isReset ? '<span class="badge" style="margin-left:4px;">resets</span>' : ''}
                ${isSweep ? '<span class="badge" style="margin-left:4px;">sweeps</span>' : ''}
              </span>
              <span style="color:var(--text-dim);font-size:12px;width:140px;text-align:right;">
                ${fmt(r.bal)} / ${fmt(r.target)}${isAnnual ? '/yr' : ''}
              </span>
              <input type="text" inputmode="decimal" data-rf-amt="${r.env.id}"
                value="${r.suggested.toFixed(2)}"
                style="width:90px;text-align:right;padding:4px 6px;background:var(--bg);border:1px solid var(--border);border-radius:4px;color:${noNeed ? 'var(--text-dim)' : 'var(--good)'};font-variant-numeric:tabular-nums;margin-left:10px;"
                ${noNeed ? 'disabled' : ''}>
            </label>`;
        }).join('')}
      </div>
      <div style="margin-top:10px;color:var(--text-dim);" id="rf_total"></div>
    `;
    document.getElementById("rf_mode").onchange = (ev) => {
      state.mode = ev.target.value;
      draw();
    };
    // Keep the running total honest as the user tweaks individual amounts,
    // and surface the post-funding projection so they can see immediately
    // whether the proposed allocation breaks the projected spendable floor.
    document.querySelectorAll("[data-rf-amt]").forEach(inp => {
      inp.oninput = recalcTotal;
    });
    document.querySelectorAll("[data-rf]").forEach(c => {
      c.onchange = recalcTotal;
    });
    recalcTotal();
  };

  // Read the currently ticked rows as [{envelopeId, amount, date}]. Shared by
  // the live preview and the save handler so the number the user is shown and
  // the number the soft block tests are always the same computation.
  const _readFundings = () => {
    const date = (document.getElementById("rf_date") || {}).value || todayISO();
    const out = [];
    document.querySelectorAll("[data-rf]:checked").forEach(c => {
      const id = c.dataset.rf;
      const inp = document.querySelector(`[data-rf-amt="${id}"]`);
      if (!inp) return;
      const v = evalAmount(inp.value);
      if (!isNaN(v) && v >= 0.005) out.push({ envelopeId: id, amount: v, date });
    });
    return out;
  };

  // Single source of truth for the running total + post-funding projection.
  // Called on every keystroke / checkbox flip and once after each draw().
  // The projection is a real re-forecast, not `spendMin − total` — see
  // spendableMinAfterFunding() for why the arithmetic shortcut is wrong now.
  const recalcTotal = () => {
    const fundings = _readFundings();
    const t = fundings.reduce((s, f) => s + f.amount, 0);
    const tEl = document.getElementById("rf_total");
    if (!tEl) return;
    let html = `Total to fund: <strong style="color:var(--text);">${fmt(t)}</strong>`;
    if (headroom) {
      const lo = spendableMinAfterFunding(headroom.accountIds, headroom.horizonDays, headroom.opts, fundings);
      const over = lo.min < -0.005;
      html += ` · Projected spendable after funding: <strong style="color:${over ? 'var(--bad)' : 'var(--text)'};">${fmt(lo.min)}</strong> <span style="color:var(--text-dim);font-weight:400;">on ${fmtDate(lo.date)}</span>`;
      if (over) {
        html += `<div style="color:var(--bad);font-size:12px;margin-top:4px;">⚠ Over-allocates by ${fmt(-lo.min)} — your projected spendable cash would dip below zero on ${fmtDate(lo.date)}.</div>`;
      }
    }
    tEl.innerHTML = html;
  };

  openModal(`
    <h2>Fund envelopes</h2>
    <div id="rf_body"></div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn primary" id="rf_save">Fund</button>
    </div>
  `);
  draw();

  document.getElementById("rf_save").onclick = () => {
    // Re-read fresh so the constraint check sees the user's latest edits.
    const fundings = _readFundings();
    const proposed = fundings.reduce((s, f) => s + f.amount, 0);

    // Soft block: when funding would push the projected spendable line
    // below zero we ask before applying, so the user can keep going if they
    // know something the forecast doesn't (e.g. an inflow they haven't yet
    // entered as recurring). Hard-blocking would be wrong since this is a
    // forecast, not a fact. The test re-forecasts with the proposed fundings
    // applied rather than subtracting the total from the current low — the
    // arithmetic version fired on money the user actually had.
    if (headroom) {
      const lo = spendableMinAfterFunding(headroom.accountIds, headroom.horizonDays, headroom.opts, fundings);
      if (lo.min < -0.005) {
        const ok = confirm(
          `This funds ${fmt(proposed)}.\n\n` +
          `Projected spendable cash would dip to ${fmt(lo.min)} on ${fmtDate(lo.date)} ` +
          `over the next ${headroom.horizonDays} days (over-allocates by ${fmt(-lo.min)}).\n\n` +
          `Continue anyway?`
        );
        if (!ok) return;
      }
    }

    const date = document.getElementById("rf_date").value || todayISO();
    let count = 0;
    let total = 0;
    document.querySelectorAll("[data-rf]:checked").forEach(c => {
      const id = c.dataset.rf;
      const env = envelopeById(id);
      if (!env) return; // envelope was deleted in another tab — skip silently
      const inp = document.querySelector(`[data-rf-amt="${id}"]`);
      const amt = evalAmount(inp.value);
      if (isNaN(amt) || amt < 0.005) return;
      data.transactions.push({
        id: uid(), date, type: "income", amount: amt,
        accountId: null, envelopeId: env.id,
        payee: "Envelope refill", notes: ""
      });
      count++;
      total += amt;
    });
    if (count > 0) { saveDirty(); toast(`Funded ${count} envelope${count === 1 ? '' : 's'} (${fmt(total)})`); }
    closeModal(); render();
  };
}

//=============================================================================
// MONTHLY CLOSE-OUT REVIEW
//=============================================================================
// Returns the YYYY-MM key of the month immediately before the given ISO date.
function prevMonthKey(isoStr) {
  const d = parseDate(isoStr);
  d.setDate(1);
  d.setMonth(d.getMonth() - 1);
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`;
}
function lastDayOfMonthKey(ym) {
  // ym = "YYYY-MM" → ISO date for the final day of that month.
  const [y, m] = ym.split('-').map(Number);
  // Day 0 of next month = last day of current.
  const d = new Date(y, m, 0);
  return isoDate(d);
}

// True if the given YYYY-MM contains any envelope-affecting transaction.
// Used to suppress the close-out banner for months that had no real activity
// (e.g. you started using the app this month — there's nothing to review for
// last month).
function monthHasEnvelopeActivity(ym) {
  const start = ym + "-01";
  const end = lastDayOfMonthKey(ym);
  for (const tx of data.transactions) {
    if (tx.date < start || tx.date > end) continue;
    if ((tx.type === 'expense' || tx.type === 'income') && (tx.envelopeId || (tx.splits && tx.splits.length))) return true;
    if (tx.type === 'transfer-envelope') return true;
  }
  return false;
}

// Returns the YYYY-MM of a month ready to close out, or null. Due when:
//   - the previous calendar month is later than data.lastClosedMonth, AND
//   - that previous month had at least one envelope transaction
// closeOutDue() always returns AT MOST the previous month, so even after a
// long gap a single banner appears (not a stack of missed months).
function closeOutDue() {
  const last = data.lastClosedMonth;
  const prevYM = prevMonthKey(todayISO());
  const isLater = !last || last < prevYM;
  if (!isLater) return null;
  if (!monthHasEnvelopeActivity(prevYM)) return null;
  return prevYM;
}

// Variance summary for one envelope across the given YYYY-MM. Spent = sum of
// expense tx.amount on that envelope dated within the month. Funded = sum of
// income (envelope refills) dated in the month, plus net envelope-to-envelope
// transfer in. Balance-at-end = balance computed as if "today" was the last
// day of the month.
//
// `spent` skips one-sided expenses (accountId null, via isCashflowTx) because
// those are envelope bookkeeping, not spending — "Return to spendable" and
// "Adjust current balance" would otherwise inflate the Spent and Variance
// columns of the close-out review with money that never left an account.
// `funded` deliberately does NOT apply the same guard: envelope refills are
// legitimately one-sided income, and filtering them would empty the column.
function envelopeMonthSummary(env, ym) {
  const last = lastDayOfMonthKey(ym);
  const start = ym + "-01";
  let spent = 0, funded = 0;
  for (const tx of data.transactions) {
    if (tx.date < start || tx.date > last) continue;
    if (tx.type === 'expense') { if (isCashflowTx(tx)) spent += txEnvelopePortion(tx, env.id); }
    else if (tx.type === 'income') funded += txEnvelopePortion(tx, env.id);
    if (tx.type === 'transfer-envelope') {
      if (tx.toEnvelopeId === env.id) funded += tx.amount;
      if (tx.fromEnvelopeId === env.id) spent += tx.amount;
    }
  }
  // Balance at month end: rerun the envelopeBalance logic but capped by `last`.
  let bal = env.openingBalance || 0;
  for (const tx of data.transactions) {
    if (tx.date <= last) bal += txEnvelopeDelta(tx, env.id);
  }
  return { spent, funded, balance: bal };
}

function showCloseOut(forcedYM) {
  const ym = forcedYM || closeOutDue();
  if (!ym) {
    toast("No month to close out — you're up to date");
    return;
  }
  if (data.envelopes.length === 0) {
    // Nothing to review; still mark the month as closed so the banner stops.
    data.lastClosedMonth = ym;
    saveDirty();
    toast("Closed " + ym + " (no envelopes)");
    return;
  }

  const monthLabel = (() => {
    const [y, m] = ym.split('-').map(Number);
    return new Date(y, m - 1, 1).toLocaleDateString('en', { month: 'long', year: 'numeric' });
  })();
  const adjustDate = lastDayOfMonthKey(ym);

  // The sweep destination. With no reserve envelope the sweep action is simply
  // absent from the dropdowns and nothing else in this modal changes.
  const reserve = reserveEnvelope();
  const rows = activeEnvelopes().map(env => {
    const s = envelopeMonthSummary(env, ym);
    const monthlyBudget = envMonthlyEquiv(env);
    const variance = s.spent - monthlyBudget; // positive = over, negative = under
    const isAnnual = env.cadence === 'annual';
    const isReserveRow = !!env.isReserve;
    const canSweep = !!reserve && !isAnnual && !isReserveRow;
    // Default action follows policy. Annuals always rollover, and so does the
    // reserve itself (it is the destination; it can't sweep into itself). For
    // envelopes with no activity and zero balance, "rollover" is a no-op anyway.
    const defaultAction = (isAnnual || isReserveRow) ? "rollover"
      : (env.rolloverPolicy === "sweep" && canSweep) ? "sweep"
      : (env.rolloverPolicy === "reset") ? "reset" : "rollover";
    return { env, ...s, monthlyBudget, variance, isAnnual, isReserveRow, canSweep, defaultAction };
  });

  openModal(`
    <h2>Close out ${esc(monthLabel)}</h2>
    <p style="color:var(--text-dim);margin-top:0;">
      Pick what happens to each envelope's balance from last month.
      <strong style="color:var(--text);">Rollover</strong> carries it into this month;
      <strong style="color:var(--text);">reset</strong> returns a leftover to spendable and
      covers an overspend from it${reserve ? `;
      <strong style="color:var(--text);">sweep</strong> does the same through
      <strong style="color:var(--text);">${esc(reserve.name)}</strong> instead of spendable` : ''}.
      Annual envelopes always rollover.
    </p>
    ${reserve ? `<div style="margin:-4px 0 10px 0;font-size:12px;color:var(--text-dim);">
      Set all:
      <button type="button" class="btn sm ghost" data-coall="rollover">Rollover</button>
      <button type="button" class="btn sm ghost" data-coall="reset">Reset</button>
      <button type="button" class="btn sm ghost" data-coall="sweep">Sweep to ${esc(reserve.name)}</button>
    </div>` : ''}
    <div class="co-scroll">
      <table class="co-table">
        <thead><tr>
          <th>Envelope</th>
          <th class="num">Spent</th>
          <th class="num">Budget</th>
          <th class="num">Variance</th>
          <th class="num">Balance end</th>
          <th>Action</th>
        </tr></thead>
        <tbody>
          ${rows.map((r, i) => {
            const varClass = Math.abs(r.variance) < 0.005 ? '' : (r.variance > 0 ? 'neg' : 'pos');
            const varSign = r.variance > 0 ? '+' : '';
            return `<tr>
              <td class="co-name">${esc(r.env.name)}${r.isAnnual ? ' <span class="badge">annual</span>' : ''}${r.isReserveRow ? ' <span class="badge">reserve</span>' : ''}${!r.isAnnual && !r.isReserveRow && r.env.rolloverPolicy === 'reset' ? ' <span class="badge">resets</span>' : ''}${!r.isAnnual && !r.isReserveRow && r.env.rolloverPolicy === 'sweep' ? ' <span class="badge">sweeps</span>' : ''}</td>
              <td class="num" data-label="Spent">${fmt(r.spent)}</td>
              <td class="num" data-label="Budget" style="color:var(--text-dim);">${fmt(r.monthlyBudget)}</td>
              <td class="num ${varClass}" data-label="Variance">${varSign}${fmt(r.variance)}</td>
              <td class="num ${r.balance < 0 ? 'neg' : ''}" data-label="Balance end">${fmt(r.balance)}</td>
              <td class="co-action" data-label="Action">
                <select data-co="${i}" ${(r.isAnnual || r.isReserveRow) ? 'disabled' : ''}>
                  <option value="rollover" ${r.defaultAction === 'rollover' ? 'selected' : ''}>Rollover</option>
                  <option value="reset" ${r.defaultAction === 'reset' ? 'selected' : ''}>Reset to 0</option>
                  ${r.canSweep ? `<option value="sweep" ${r.defaultAction === 'sweep' ? 'selected' : ''}>Sweep to ${esc(reserve.name)}</option>` : ''}
                </select>
              </td>
            </tr>`;
          }).join('')}
        </tbody>
      </table>
    </div>
    <details class="co-note">
      <summary>How these adjustments are recorded</summary>
      <p>
        Resets${reserve ? ' and sweeps' : ''} post a single adjusting transaction dated
        <strong style="color:var(--text);">${fmtDate(adjustDate)}</strong>.
        Reset adjustments are one tx per envelope, type <em>income</em> (when balance was negative) or
        <em>expense</em> (when balance was positive), no account attached — same accounting model as
        the Fund button. You can find them later in the Transactions tab tagged
        "Close-out adjustment". Sweeps are envelope-to-envelope transfers tagged
        "Close-out sweep" — no account is touched. A positive leftover leaves spendable
        cash unchanged (the money stays earmarked, just in the reserve); covering an
        overspend from the reserve raises spendable, because reserved money fills the hole.
      </p>
    </details>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn primary" id="co_apply">Apply &amp; close ${esc(monthLabel)}</button>
    </div>
  `, { className: 'wide co-modal' });

  document.querySelectorAll("[data-coall]").forEach(b => b.onclick = () => {
    const want = b.dataset.coall;
    document.querySelectorAll("[data-co]").forEach(sel => {
      if (sel.disabled) return;
      // Only assign an option the row actually offers (sweep is absent on rows
      // that can't sweep), otherwise the select would silently blank out.
      if ([...sel.options].some(o => o.value === want)) sel.value = want;
    });
  });

  document.getElementById("co_apply").onclick = () => {
    // Batch-destructive: posts an adjusting tx per reset envelope and advances
    // the close-out cursor. One snapshot covers it all so Ctrl-Z reverses the
    // whole close-out (decision #8).
    pushUndo('Close out ' + ym);
    let resets = 0, sweeps = 0;
    rows.forEach((r, i) => {
      const sel = document.querySelector(`[data-co="${i}"]`);
      if (!sel) return;
      const action = sel.value;
      if (action !== 'reset' && action !== 'sweep') return;
      if (r.isAnnual || r.isReserveRow) return;
      const bal = r.balance;
      if (Math.abs(bal) < 0.005) return; // already at zero
      if (action === 'sweep') {
        if (!reserve || !r.canSweep) return;
        // Envelope-to-envelope, so the money stays earmarked and spendable cash
        // is unchanged. A positive leftover moves INTO the reserve; an
        // overspent envelope is brought back to zero out of the reserve, which
        // is what an emergency buffer is for.
        const isPositive = bal > 0;
        data.transactions.push({
          id: uid(),
          date: adjustDate,
          type: "transfer-envelope",
          amount: Math.abs(bal),
          fromEnvelopeId: isPositive ? r.env.id : reserve.id,
          toEnvelopeId: isPositive ? reserve.id : r.env.id,
          payee: "Close-out sweep",
          notes: `Sweep for ${ym} (was ${fmt(bal)})`
        });
        sweeps++;
        return;
      }
      // If balance is positive, we deduct it (expense to envelope) so leftover
      // returns to spendable. If negative, we add it (income to envelope) to
      // cover the overspend from spendable.
      const isPositive = bal > 0;
      data.transactions.push({
        id: uid(),
        date: adjustDate,
        type: isPositive ? "expense" : "income",
        amount: Math.abs(bal),
        accountId: null,
        envelopeId: r.env.id,
        payee: "Close-out adjustment",
        notes: `Reset for ${ym} (was ${fmt(bal)})`
      });
      resets++;
    });
    data.lastClosedMonth = ym;
    saveDirty();
    closeModal();
    render();
    const bits = [];
    if (resets > 0) bits.push(`${resets} ${plural(resets, 'envelope', 'envelopes')} reset`);
    if (sweeps > 0) bits.push(`${sweeps} swept to ${reserve.name}`);
    toast(bits.length ? `Closed ${ym} — ${bits.join(', ')}` : `Closed ${ym}`);
  };
}

function transferEnvelopes(fromId) {
  const opts = pickEnvelopes(fromId).map(e =>
    `<option value="${e.id}">${esc(e.name)}${archSuffix(e)} (${fmt(envelopeBalance(e))})</option>`).join('');
  openModal(`
    <h2>Move funds between envelopes</h2>
    <div class="field-row">
      <div class="field"><label>From</label>
        <select id="tr_from">${opts}</select></div>
      <div class="field"><label>To</label>
        <select id="tr_to">${opts}</select></div>
    </div>
    <div class="field-row">
      <div class="field"><label>Amount</label>
        <input type="text" inputmode="decimal" id="tr_amt"
          placeholder="e.g. 50 or 200-30" autocomplete="off"></div>
      <div class="field"><label>Date</label>
        <input type="date" id="tr_date" value="${todayISO()}"></div>
    </div>
    <div class="micro" id="tr_amt_preview" style="margin-top:-8px; margin-bottom:10px; min-height:14px;"></div>
    <div class="field"><label>Note</label><input id="tr_note"></div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn primary" id="tr_save">Transfer</button>
    </div>
  `);
  if (fromId) document.getElementById("tr_from").value = fromId;

  // Same arithmetic-preview pattern as the Add Transaction modal: stays empty
  // for plain numbers, shows "= 170,00 €" / "⚠ invalid" once the user types
  // an operator. Save handler re-evaluates from raw input so the user can
  // submit without blurring the field first.
  wireAmountPreview("tr_amt", "tr_amt_preview");

  document.getElementById("tr_save").onclick = () => {
    const from = document.getElementById("tr_from").value;
    const to = document.getElementById("tr_to").value;
    const amt = Math.abs(evalAmount(document.getElementById("tr_amt").value) || 0);
    if (!from || !to || from === to || !amt) { toast("Fill all fields"); return; }
    data.transactions.push({
      id: uid(), date: document.getElementById("tr_date").value || todayISO(),
      type: "transfer-envelope", amount: amt,
      fromEnvelopeId: from, toEnvelopeId: to,
      notes: document.getElementById("tr_note").value
    });
    saveDirty(); closeModal(); render(); toast("Funds moved");
  };
}

//=============================================================================
// TRANSACTIONS
//=============================================================================
// Sort by date desc, then by insertion order desc so a transaction logged
// just now appears at the top of today's block (not buried under earlier
// same-day entries). Array index is a stable proxy for "most recently added"
// since transactions are appended to data.transactions. Shared by the
// Transactions tab (initial render AND every filter pass — the filter used to
// re-sort by date alone, so same-day rows reshuffled as soon as you typed)
// and the dashboard's Recent transactions.
function sortTxsDesc(txs) {
  const orderIdx = new Map(data.transactions.map((tx, i) => [tx.id, i]));
  return [...txs].sort((a, b) => {
    const d = b.date.localeCompare(a.date);
    if (d !== 0) return d;
    return (orderIdx.get(b.id) || 0) - (orderIdx.get(a.id) || 0);
  });
}

// Transactions-tab filter state. Module-level so it survives the full
// re-render every mutation triggers (editing one row used to reset every
// filter) and so other views can pre-fill it: goToTransactions({acc}) is the
// drill-through from an account or envelope name, and ?acc=/?env=/?tag=/?q=
// in the URL do the same for a bookmark.
let txFilter = { q: '', type: '', acc: '', env: '', tag: '', from: '', to: '' };
let txSelected = new Set();   // bulk-edit selection (tx ids); cleared on every full render
function goToTransactions(f) {
  txFilter = { q: '', type: '', acc: '', env: '', tag: '', from: '', to: '', ...f };
  activeView = 'transactions';
  render();
}
function filterTxs() {
  const f = txFilter;
  const q = (f.q || '').toLowerCase();
  let rows = sortTxsDesc(data.transactions);
  if (f.type) rows = rows.filter(t => t.type === f.type);
  if (f.acc) rows = rows.filter(t => t.accountId === f.acc || t.fromAccountId === f.acc || t.toAccountId === f.acc);
  if (f.env) rows = rows.filter(t => t.envelopeId === f.env || t.fromEnvelopeId === f.env || t.toEnvelopeId === f.env || (t.splits && t.splits.some(s => s.envelopeId === f.env)));
  // Tag filter values are prefixed ("u" = untagged, "t:<name>") so a
  // user-typed tag name can never collide with a sentinel.
  if (f.tag === 'u') rows = rows.filter(t => !t.tag);
  else if (f.tag && f.tag.startsWith('t:')) { const name = f.tag.slice(2); rows = rows.filter(t => t.tag === name); }
  if (f.from) rows = rows.filter(t => t.date >= f.from);
  if (f.to) rows = rows.filter(t => t.date <= f.to);
  // Search matches payee, notes, tag — and the amount, both as typed
  // ("49.9") and as displayed in the user's locale ("49,90").
  if (q) rows = rows.filter(t => (t.payee||"").toLowerCase().includes(q) || (t.notes||"").toLowerCase().includes(q) || (t.tag||"").toLowerCase().includes(q)
    || String(t.amount).includes(q) || fmtNum(t.amount).includes(q));
  return rows;
}
// Cash in / out / net for the rows on screen. Only real cashflow counts
// (isCashflowTx): transfers are internal movement and one-sided envelope
// bookkeeping moves no money, so neither belongs in a "how much did I spend"
// total — the caption says so.
function txTotalsHTML(rows) {
  let inc = 0, exp = 0;
  for (const t of rows) {
    if (!isCashflowTx(t)) continue;
    if (t.type === 'income') inc += t.amount; else if (t.type === 'expense') exp += t.amount;
  }
  const net = inc - exp;
  return `<span>${plural(rows.length, 'entry', 'entries')}</span>
    <span title="Income and expenses with an account, for the rows shown. Transfers and envelope-only bookkeeping are excluded.">cash in <strong class="pos">+${fmt(inc)}</strong> · out <strong class="neg">−${fmt(exp)}</strong> · net <strong class="${net >= 0 ? 'pos' : 'neg'}">${net >= 0 ? '+' : ''}${fmt(net)}</strong></span>`;
}
function renderTransactions() {
  txSelected = new Set();
  const f = txFilter;
  const txs = filterTxs();
  const activeCount = ['q','type','acc','env','tag','from','to'].filter(k => f[k]).length;
  return `
  <h2>Transactions</h2>
  <div class="toolbar">
    <button class="btn primary" id="addTx" title="Add transaction (press 'n' anywhere)">+ Add transaction</button>
    <button class="btn" id="addTransfer">⇄ Account transfer</button>
    <button class="btn" id="importCsv" title="Import transactions from a bank CSV statement">⤓ Import CSV</button>
    <div class="filter-group">
      <input class="filter-input" id="txFilter" placeholder="Search payee, notes, amount…" aria-label="Search transactions" style="width:200px;" value="${esc(f.q)}">
      <select class="filter-input" id="txTypeFilter" aria-label="Filter by type">
        <option value="">All types</option>
        <option value="expense" ${f.type === 'expense' ? 'selected' : ''}>Expense</option>
        <option value="income" ${f.type === 'income' ? 'selected' : ''}>Income</option>
        <option value="transfer-account" ${f.type === 'transfer-account' ? 'selected' : ''}>Account transfer</option>
        <option value="transfer-envelope" ${f.type === 'transfer-envelope' ? 'selected' : ''}>Envelope transfer</option>
      </select>
      <select class="filter-input" id="txAccFilter" aria-label="Filter by account">
        <option value="">All accounts</option>
        ${pickAccounts(f.acc).map(a => `<option value="${a.id}" ${f.acc === a.id ? 'selected' : ''}>${esc(a.name)}${archSuffix(a)}</option>`).join('')}
      </select>
      <select class="filter-input" id="txEnvFilter" aria-label="Filter by envelope">
        <option value="">All envelopes</option>
        ${pickEnvelopes(f.env).map(e => `<option value="${e.id}" ${f.env === e.id ? 'selected' : ''}>${esc(e.name)}${archSuffix(e)}</option>`).join('')}
      </select>
      <select class="filter-input" id="txTagFilter" aria-label="Filter by tag">
        <option value="">All tags</option>
        <option value="u" ${f.tag === 'u' ? 'selected' : ''}>Untagged</option>
        ${allTags().map(t => `<option value="t:${esc(t)}" ${f.tag === 't:' + t ? 'selected' : ''}>${esc(t)}</option>`).join('')}
      </select>
      <input type="date" class="filter-input" id="txFromFilter" aria-label="From date" title="From date" value="${esc(f.from)}">
      <span style="color:var(--text-dim);">–</span>
      <input type="date" class="filter-input" id="txToFilter" aria-label="To date" title="To date" value="${esc(f.to)}">
      <button class="btn sm ghost" id="txMonthFilter" title="This calendar month">This month</button>
      <button class="btn sm ghost" id="txClearFilter" title="Clear all filters" ${activeCount ? '' : 'disabled'}>✕ Clear</button>
    </div>
    <div class="spacer"></div>
    <div class="tx-totals" id="txCount">${txTotalsHTML(txs)}</div>
  </div>
  <div class="bulk-bar" id="txBulk" hidden>
    <strong id="txBulkCount"></strong>
    <label style="display:flex;gap:6px;align-items:center;">Tag
      <select id="bulkTag"><option value="">(no change)</option><option value="__clear">— remove tag —</option>${tagList().map(t => `<option value="${esc(t)}">${esc(t)}</option>`).join('')}</select></label>
    <label style="display:flex;gap:6px;align-items:center;">Envelope
      <select id="bulkEnv"><option value="">(no change)</option><option value="__clear">— none —</option>${activeEnvelopes().map(e => `<option value="${e.id}">${esc(e.name)}</option>`).join('')}</select></label>
    <button class="btn sm primary" id="bulkApply">Apply to selected</button>
    <button class="btn sm danger" id="bulkDelete">Delete selected</button>
    <button class="btn sm ghost" id="bulkClear">Clear selection</button>
  </div>
  <div class="card" style="padding:0;">
    <table>
      <thead><tr>
        <th style="width:28px;"><input type="checkbox" id="txSelAll" aria-label="Select all shown transactions" title="Select all shown"></th>
        <th>Date</th><th>Description</th><th>Type</th>
        <th>Account</th><th>Envelope</th><th>Tag</th><th class="num">Amount</th><th></th>
      </tr></thead>
      <tbody id="txBody">
        ${txs.map(tx => txDataRow(tx)).join('')}
      </tbody>
    </table>
  </div>
  `;
}
// Date cell shared by both transaction tables. A transaction dated after
// today is excluded from every balance (accountBalance / envelopeBalance stop
// at today), so it is labelled rather than shown as if it had posted.
function txDateCell(tx) {
  const future = tx.date > todayISO();
  return `${fmtDate(tx.date)}${future ? ' <span class="badge scheduled" title="Dated after today — not yet counted in any balance">scheduled</span>' : ''}`;
}
function txDataRow(tx) {
  const { sign, acc, env, tag } = txDisplayParts(tx);
  const future = tx.date > todayISO();
  return `<tr data-tx="${tx.id}" class="${future ? 'tx-future' : ''}">
    <td><input type="checkbox" data-sel-tx="${tx.id}" aria-label="Select transaction" ${txSelected.has(tx.id) ? 'checked' : ''}></td>
    <td style="white-space:nowrap;">${txDateCell(tx)}</td>
    <td>${esc(tx.payee || '')}${tx.notes ? `<br><span style="color:var(--text-dim);font-size:11px;">${esc(tx.notes)}</span>` : ''}</td>
    <td>${(tx.type === 'transfer-account' || tx.type === 'transfer-envelope')
      ? `<span class="badge ${tx.type}">${tx.type}</span>`
      : `<span style="color:var(--text-dim);">${tx.type}</span>`}</td>
    <td>${acc}</td>
    <td>${env}</td>
    <td>${tag}</td>
    <td class="num ${tx.type==='expense'?'neg':(tx.type==='income'?'pos':'')}">${sign}${fmt(tx.amount)}</td>
    <td class="actions">
      <button class="btn sm" data-edit-tx="${tx.id}">Edit</button>
      <button class="btn sm ghost" data-copy-tx="${tx.id}" title="Duplicate to today (or hover row + press 'c')" aria-label="Duplicate transaction to today">⎘</button>
      <button class="btn sm danger" data-del-tx="${tx.id}" aria-label="Delete transaction" title="Delete transaction">×</button>
    </td>
  </tr>`;
}
function bindTransactions() {
  document.getElementById("addTx").onclick = () => editTransaction();
  document.getElementById("addTransfer").onclick = () => editTransaction(null, "transfer-account");
  document.getElementById("importCsv").onclick = csvImportStart;

  // Row buttons + selection checkboxes are re-bound after every filter pass
  // (the tbody is rebuilt), so they live in one helper.
  const bindRows = () => {
    document.querySelectorAll("[data-edit-tx]").forEach(b =>
      b.onclick = () => editTransaction(b.dataset.editTx));
    document.querySelectorAll("[data-copy-tx]").forEach(b =>
      b.onclick = () => copyTransaction(b.dataset.copyTx));
    document.querySelectorAll("[data-del-tx]").forEach(b =>
      b.onclick = () => deleteTransaction(b.dataset.delTx));
    document.querySelectorAll("[data-sel-tx]").forEach(c =>
      c.onchange = () => { if (c.checked) txSelected.add(c.dataset.selTx); else txSelected.delete(c.dataset.selTx); updateBulk(); });
  };
  const updateBulk = () => {
    const bar = document.getElementById("txBulk");
    const n = txSelected.size;
    bar.hidden = n === 0;
    document.getElementById("txBulkCount").textContent = `${plural(n, 'transaction')} selected`;
    const all = document.getElementById("txSelAll");
    const shown = [...document.querySelectorAll("[data-sel-tx]")];
    all.checked = shown.length > 0 && shown.every(c => c.checked);
    all.indeterminate = !all.checked && shown.some(c => c.checked);
  };

  const filt = () => {
    txFilter = {
      q: document.getElementById("txFilter").value,
      type: document.getElementById("txTypeFilter").value,
      acc: document.getElementById("txAccFilter").value,
      env: document.getElementById("txEnvFilter").value,
      tag: document.getElementById("txTagFilter").value,
      from: document.getElementById("txFromFilter").value,
      to: document.getElementById("txToFilter").value
    };
    const rows = filterTxs();
    document.getElementById("txBody").innerHTML = rows.map(t => txDataRow(t)).join('');
    document.getElementById("txCount").innerHTML = txTotalsHTML(rows);
    document.getElementById("txClearFilter").disabled = !Object.values(txFilter).some(Boolean);
    bindRows();
    updateBulk();
  };
  ["txFilter","txTypeFilter","txAccFilter","txEnvFilter","txTagFilter","txFromFilter","txToFilter"].forEach(id =>
    document.getElementById(id).oninput = filt);
  document.getElementById("txMonthFilter").onclick = () => {
    const ym = todayISO().slice(0, 7);
    document.getElementById("txFromFilter").value = ym + "-01";
    document.getElementById("txToFilter").value = lastDayOfMonthKey(ym);
    filt();
  };
  document.getElementById("txClearFilter").onclick = () => {
    txFilter = { q: '', type: '', acc: '', env: '', tag: '', from: '', to: '' };
    render();
  };

  // Bulk edit. Each operation is one undo snapshot. Envelope changes apply
  // only to expense/income rows that aren't split — a transfer has no
  // envelope field and a split's envelopes live in splits[] — and the toast
  // says how many rows were left alone rather than silently touching them.
  document.getElementById("txSelAll").onchange = (e) => {
    document.querySelectorAll("[data-sel-tx]").forEach(c => {
      c.checked = e.target.checked;
      if (c.checked) txSelected.add(c.dataset.selTx); else txSelected.delete(c.dataset.selTx);
    });
    updateBulk();
  };
  document.getElementById("bulkClear").onclick = () => { txSelected.clear(); document.querySelectorAll("[data-sel-tx]").forEach(c => c.checked = false); updateBulk(); };
  document.getElementById("bulkApply").onclick = () => {
    const tagV = document.getElementById("bulkTag").value;
    const envV = document.getElementById("bulkEnv").value;
    if (!tagV && !envV) { toast("Pick a tag or an envelope to apply", 2600, 'info'); return; }
    const ids = txSelected;
    if (!ids.size) return;
    pushUndo(`Bulk edit ${plural(ids.size, 'transaction')}`);
    let changed = 0, envSkipped = 0;
    for (const tx of data.transactions) {
      if (!ids.has(tx.id)) continue;
      let touched = false;
      if (tagV) { if (tagV === '__clear') delete tx.tag; else tx.tag = tagV; touched = true; }
      if (envV) {
        const simple = (tx.type === 'expense' || tx.type === 'income') && !(tx.splits && tx.splits.length);
        if (simple) { tx.envelopeId = envV === '__clear' ? null : envV; touched = true; }
        else envSkipped++;
      }
      if (touched) changed++;
    }
    saveDirty(); render();
    toast(`Updated ${plural(changed, 'transaction')}${envSkipped ? ` · ${envSkipped} skipped for envelope (transfers / splits)` : ''} (Ctrl+Z to undo)`, 4500, 'success', { label: 'Undo', onClick: performUndo });
  };
  document.getElementById("bulkDelete").onclick = () => {
    const ids = txSelected;
    if (!ids.size) return;
    if (!confirm(`Delete ${plural(ids.size, 'transaction')}? Ctrl+Z restores them.`)) return;
    pushUndo(`Delete ${plural(ids.size, 'transaction')}`);
    const n = ids.size;
    data.transactions = data.transactions.filter(t => !ids.has(t.id));
    saveDirty(); render();
    toast(`Deleted ${plural(n, 'transaction')}`, 5000, 'success', { label: 'Undo', onClick: performUndo });
  };
  bindRows();
  updateBulk();
}

function editTransaction(id, defaultType) {
  const tx = id ? data.transactions.find(t => t.id === id) :
    { id: uid(), date: todayISO(), type: defaultType || "expense", amount: 0 };
  txFormModal(tx, !id);
}

function copyTransaction(id) {
  const orig = data.transactions.find(t => t.id === id);
  if (!orig) return;
  // Shallow clone with fresh id + today's date. Spreads preserve all type-specific
  // fields (accountId/envelopeId for expense/income, fromAccountId/toAccountId for
  // account transfers, fromEnvelopeId/toEnvelopeId for envelope transfers) and
  // notes — user can tweak any of them in the modal before saving.
  const copy = { ...orig, id: uid(), date: todayISO() };
  txFormModal(copy, true);
}

//=============================================================================
// CSV IMPORT (bank statements)
//=============================================================================
// Local-only: parse a CSV the user picks, map its columns (saveable as a named
// profile in data.importProfiles), review + dedupe the parsed rows, then import
// the ticked ones. Never auto-merges — the review step is the contract. Pure
// vanilla; a small RFC-4180-ish parser handles quoted fields and , ; or tab.
let _csvText = '';

function sniffDelimiter(text) {
  const line = (text.split(/\r?\n/).find(l => l.trim())) || '';
  const c = (line.match(/,/g) || []).length, s = (line.match(/;/g) || []).length, t = (line.match(/\t/g) || []).length;
  if (s > 0 && s >= c && s >= t) return ';';
  if (t > 0 && t >= c && t >= s) return '\t';
  return ',';
}

function parseCSV(text, delim) {
  const rows = []; let row = [], field = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (q) {
      if (ch === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else q = false; }
      else field += ch;
    } else if (ch === '"') q = true;
    else if (ch === delim) { row.push(field); field = ''; }
    else if (ch === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else if (ch !== '\r') field += ch;
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  return rows.filter(r => r.some(c => c.trim() !== ''));
}

// European/US decimal tolerant: "1.234,56" / "1,234.56" / "1234.56" / "-12,50" / "12,50-".
function parseImportAmount(s) {
  if (s == null) return NaN;
  let t = String(s).replace(/[^\d.,\-]/g, '').trim();
  if (!t) return NaN;
  const neg = /-/.test(t);
  t = t.replace(/-/g, '');
  if (!t) return NaN;
  const lc = t.lastIndexOf(','), ld = t.lastIndexOf('.');
  if (lc > -1 && ld > -1) t = lc > ld ? t.replace(/\./g, '').replace(',', '.') : t.replace(/,/g, '');
  else if (lc > -1) t = /,\d{1,2}$/.test(t) ? t.replace(',', '.') : t.replace(/,/g, '');
  const n = parseFloat(t);
  if (!isFinite(n)) return NaN;
  return neg ? -n : n;
}

function parseImportDate(s, order) {
  if (!s) return null;
  const m = String(s).trim().match(/(\d{1,4})[\/\-.](\d{1,2})[\/\-.](\d{1,4})/);
  if (!m) return null;
  let a = +m[1], b = +m[2], c = +m[3], y, mo, d;
  if (order === 'ymd') { y = a; mo = b; d = c; }
  else if (order === 'mdy') { mo = a; d = b; y = c; }
  else { d = a; mo = b; y = c; }
  if (y < 100) y += 2000;
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return `${y}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

function csvImportStart() {
  if (!data) { toast("Open or create a file first", 3000, 'error'); return; }
  if (!data.accounts.length) { toast("Add an account first — imports need a target account", 3500, 'error'); return; }
  const inp = document.createElement('input');
  inp.type = 'file'; inp.accept = '.csv,text/csv,text/plain';
  inp.onchange = () => {
    const f = inp.files && inp.files[0];
    if (!f) return;
    const r = new FileReader();
    r.onload = () => csvShowMapping(String(r.result || ''), f.name);
    r.onerror = () => toast("Could not read file", 3000, 'error');
    r.readAsText(f);
  };
  inp.click();
}

function _csvColOptions(p, selected) {
  const rows = parseCSV(_csvText, p.delimiter);
  const head = rows[0] || [];
  const cols = Math.max(1, ...rows.slice(0, 5).map(r => r.length));
  let html = '';
  for (let i = 0; i < cols; i++) {
    const label = p.hasHeader && head[i] ? `${i + 1}: ${head[i].trim().slice(0, 24)}` : `Column ${i + 1}`;
    html += `<option value="${i}" ${selected === i ? 'selected' : ''}>${esc(label)}</option>`;
  }
  return html;
}

function _csvReadForm(prev) {
  const v = id => { const el = document.getElementById(id); return el ? el.value : ''; };
  const chk = id => { const el = document.getElementById(id); return el ? el.checked : false; };
  const num = id => { const el = document.getElementById(id); return el && el.value !== '' ? +el.value : null; };
  const nameEl = document.getElementById('csv_savename');
  const colOr = (id, fb) => { const n = num(id); return n !== null ? n : fb; };
  return {
    id: prev.id || null,
    name: nameEl ? nameEl.value.trim() : (prev.name || ''),
    delimiter: v('csv_delim') || prev.delimiter,
    hasHeader: chk('csv_header'),
    dateOrder: v('csv_dateorder') || prev.dateOrder,
    amountMode: v('csv_amountmode') || prev.amountMode,
    map: {
      date: colOr('csv_col_date', prev.map.date),
      desc: colOr('csv_col_desc', prev.map.desc),
      amount: num('csv_col_amount'),
      debit: num('csv_col_debit'),
      credit: num('csv_col_credit')
    },
    accountId: v('csv_account') || prev.accountId
  };
}

function csvShowMapping(text, filename) {
  _csvText = text;
  const base = {
    id: null, name: '', delimiter: sniffDelimiter(text), hasHeader: true,
    dateOrder: 'dmy', amountMode: 'single',
    map: { date: 0, desc: 1, amount: 2, debit: null, credit: null },
    accountId: (activeAccounts()[0] || {}).id || ''
  };
  _csvRenderMapping(base, filename || 'CSV');
}

function _csvRenderMapping(p, filename) {
  const profiles = data.importProfiles || [];
  const rows = parseCSV(_csvText, p.delimiter);
  const dataRows = p.hasHeader ? rows.slice(1) : rows;
  const dCol = p.map.debit != null ? p.map.debit : 0;
  const cCol = p.map.credit != null ? p.map.credit : 1;
  const preview = [];
  for (const r of dataRows) {
    const iso = parseImportDate(r[p.map.date], p.dateOrder);
    let amt;
    if (p.amountMode === 'single') amt = parseImportAmount(r[p.map.amount]);
    else { const dr = parseImportAmount(r[dCol]), cr = parseImportAmount(r[cCol]); amt = (!isNaN(cr) && cr) ? Math.abs(cr) : (!isNaN(dr) && dr ? -Math.abs(dr) : NaN); }
    preview.push({ iso, payee: (r[p.map.desc] || '').trim(), amt });
    if (preview.length >= 3) break;
  }
  const accOpts = pickAccounts(p.accountId).map(a => `<option value="${a.id}" ${p.accountId === a.id ? 'selected' : ''}>${esc(a.name)}${archSuffix(a)}</option>`).join('');
  openModal(`
    <h2>Import CSV${filename ? ` — ${esc(filename)}` : ''}</h2>
    ${profiles.length ? `<div class="field"><label>Saved mapping</label>
      <select id="csv_profile"><option value="">— new mapping —</option>${profiles.map(pr => `<option value="${pr.id}" ${p.id === pr.id ? 'selected' : ''}>${esc(pr.name)}</option>`).join('')}</select></div>` : ''}
    <div class="field-row">
      <div class="field"><label>Delimiter</label><select id="csv_delim">
        <option value="," ${p.delimiter === ',' ? 'selected' : ''}>Comma ,</option>
        <option value=";" ${p.delimiter === ';' ? 'selected' : ''}>Semicolon ;</option>
        <option value="\t" ${p.delimiter === '\t' ? 'selected' : ''}>Tab</option>
      </select></div>
      <div class="field"><label>Date format</label><select id="csv_dateorder">
        <option value="dmy" ${p.dateOrder === 'dmy' ? 'selected' : ''}>DD/MM/YYYY</option>
        <option value="mdy" ${p.dateOrder === 'mdy' ? 'selected' : ''}>MM/DD/YYYY</option>
        <option value="ymd" ${p.dateOrder === 'ymd' ? 'selected' : ''}>YYYY-MM-DD</option>
      </select></div>
    </div>
    <div class="field"><label style="display:flex;align-items:center;gap:6px;cursor:pointer;"><input type="checkbox" id="csv_header" ${p.hasHeader ? 'checked' : ''}> First row is a header</label></div>
    <div class="field-row">
      <div class="field"><label>Date column</label><select id="csv_col_date">${_csvColOptions(p, p.map.date)}</select></div>
      <div class="field"><label>Description column</label><select id="csv_col_desc">${_csvColOptions(p, p.map.desc)}</select></div>
    </div>
    <div class="field"><label>Amount columns</label><select id="csv_amountmode">
      <option value="single" ${p.amountMode === 'single' ? 'selected' : ''}>One signed amount column</option>
      <option value="debitcredit" ${p.amountMode === 'debitcredit' ? 'selected' : ''}>Separate debit / credit columns</option>
    </select></div>
    ${p.amountMode === 'single'
      ? `<div class="field"><label>Amount column</label><select id="csv_col_amount">${_csvColOptions(p, p.map.amount != null ? p.map.amount : 2)}</select></div>`
      : `<div class="field-row">
          <div class="field"><label>Debit (money out)</label><select id="csv_col_debit">${_csvColOptions(p, dCol)}</select></div>
          <div class="field"><label>Credit (money in)</label><select id="csv_col_credit">${_csvColOptions(p, cCol)}</select></div>
        </div>`}
    <div class="field"><label>Import into account</label><select id="csv_account">${accOpts}</select></div>
    <div class="field" style="background:var(--bg-3);padding:10px 12px;border-radius:6px;border:1px solid var(--border);">
      <div style="color:var(--text-dim);font-size:12px;margin-bottom:6px;">Preview · ${dataRows.length} data row${dataRows.length === 1 ? '' : 's'}</div>
      ${preview.length ? preview.map(x => `<div style="font-variant-numeric:tabular-nums;font-size:13px;line-height:1.6;">${x.iso || '<span style="color:var(--bad)">bad date</span>'} · ${esc(x.payee || '—')} · ${isNaN(x.amt) ? '<span style="color:var(--bad)">bad amount</span>' : `<span class="${x.amt < 0 ? 'neg' : 'pos'}">${x.amt < 0 ? '−' : '+'}${fmt(Math.abs(x.amt))}</span>`}</div>`).join('') : '<div style="color:var(--bad)">No parseable rows — check the delimiter and column choices.</div>'}
    </div>
    <div class="field"><label style="display:flex;align-items:center;gap:6px;cursor:pointer;"><input type="checkbox" id="csv_save" ${p.id || p.name ? 'checked' : ''}> Save this mapping as a profile</label>
      <input id="csv_savename" value="${esc(p.name || '')}" placeholder="e.g. Main bank checking" style="margin-top:6px;"></div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn primary" id="csv_next">Review import →</button>
    </div>
  `);
  const rerender = () => _csvRenderMapping(_csvReadForm(p), filename);
  ['csv_delim', 'csv_header', 'csv_dateorder', 'csv_amountmode', 'csv_col_date', 'csv_col_desc', 'csv_col_amount', 'csv_col_debit', 'csv_col_credit', 'csv_account'].forEach(id => { const el = document.getElementById(id); if (el) el.onchange = rerender; });
  const profSel = document.getElementById('csv_profile');
  if (profSel) profSel.onchange = () => {
    const pr = (data.importProfiles || []).find(x => x.id === profSel.value);
    _csvRenderMapping(pr ? { ...pr } : { ...p, id: null, name: '' }, filename);
  };
  document.getElementById('csv_next').onclick = () => {
    const prof = _csvReadForm(p);
    prof.save = document.getElementById('csv_save').checked;
    if (!prof.accountId) { toast("Pick an account to import into", 3000, 'error'); return; }
    csvShowReview(prof, filename);
  };
}

function _csvIsDup(date, amount, payee) {
  const k = (payee || '').trim().toLowerCase();
  return data.transactions.some(t => t.date === date && Math.abs((t.amount || 0) - amount) < 0.005 && (t.payee || '').trim().toLowerCase() === k);
}

function csvShowReview(profile, filename) {
  const rows = parseCSV(_csvText, profile.delimiter);
  const dataRows = profile.hasHeader ? rows.slice(1) : rows;
  let skipped = 0;
  const cands = [];
  // One payee index for the whole file — fuzzy matching per row would
  // otherwise rescan the tx list once per statement line.
  const pIndex = payeeIndex();
  for (const r of dataRows) {
    const iso = parseImportDate(r[profile.map.date], profile.dateOrder);
    let amt;
    if (profile.amountMode === 'single') amt = parseImportAmount(r[profile.map.amount]);
    else { const dr = parseImportAmount(r[profile.map.debit]), cr = parseImportAmount(r[profile.map.credit]); amt = (!isNaN(cr) && cr) ? Math.abs(cr) : (!isNaN(dr) && dr ? -Math.abs(dr) : NaN); }
    if (iso === null || isNaN(amt) || amt === 0) { skipped++; continue; }
    const payee = (r[profile.map.desc] || '').trim();
    const sug = suggestPayeeDefaults(payee, { fuzzy: true, index: pIndex });
    cands.push({ date: iso, payee, amount: Math.abs(amt), type: amt < 0 ? 'expense' : 'income', envelopeId: (sug && sug.envelopeId) || '',
      tag: (sug && sug.tag && tagIndex(sug.tag) >= 0) ? sug.tag : '', dup: _csvIsDup(iso, Math.abs(amt), payee) });
  }
  if (!cands.length) { toast("No valid rows to import — check the mapping", 3500, 'error'); return; }
  const envOpts = sel => `<option value="">— none —</option>` + pickEnvelopes(sel).map(e => `<option value="${e.id}" ${sel === e.id ? 'selected' : ''}>${esc(e.name)}${archSuffix(e)}</option>`).join('');
  const hasTags = tagList().length > 0;   // no tags defined → no Tag column, nothing to pick
  const dupCount = cands.filter(c => c.dup).length;
  const acc = accountById(profile.accountId);
  const rowsHtml = cands.map((c, i) => `<tr>
    <td><input type="checkbox" data-csv-i="${i}" ${c.dup ? '' : 'checked'}></td>
    <td style="white-space:nowrap;">${c.date}</td>
    <td>${esc(c.payee || '—')}${c.dup ? ' <span class="badge" style="background:var(--warn);color:var(--on-fill);">dup?</span>' : ''}</td>
    <td class="num ${c.type === 'expense' ? 'neg' : 'pos'}" style="white-space:nowrap;">${c.type === 'expense' ? '−' : '+'}${fmt(c.amount)}</td>
    <td><select data-csv-env="${i}" style="max-width:160px;">${envOpts(c.envelopeId)}</select></td>
    ${hasTags ? `<td><select data-csv-tag="${i}" style="max-width:130px;">${tagOptions(c.tag)}</select></td>` : ''}
  </tr>`).join('');
  openModal(`
    <h2>Review import — ${cands.length} row${cands.length === 1 ? '' : 's'}</h2>
    <p style="color:var(--text-dim);margin-top:0;">Into <strong>${esc(acc ? acc.name : '?')}</strong>. Untick rows to skip${dupCount ? ` · ${dupCount} possible duplicate${dupCount === 1 ? '' : 's'} pre-unticked` : ''}${skipped ? ` · ${skipped} unparseable row${skipped === 1 ? '' : 's'} ignored` : ''}. Envelope${hasTags ? ' and tag are' : ' is'} auto-suggested from payee history — adjust as needed.</p>
    <div style="max-height:48vh;overflow:auto;"><table>
      <thead><tr><th></th><th>Date</th><th>Payee</th><th class="num">Amount</th><th>Envelope</th>${hasTags ? '<th>Tag</th>' : ''}</tr></thead>
      <tbody>${rowsHtml}</tbody>
    </table></div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn" id="csv_back">← Back</button>
      <button class="btn primary" id="csv_import">Import selected</button>
    </div>
  `);
  document.getElementById('csv_back').onclick = () => _csvRenderMapping(profile, filename);
  document.getElementById('csv_import').onclick = () => {
    const picked = [];
    document.querySelectorAll('[data-csv-i]').forEach(cb => {
      if (!cb.checked) return;
      const i = +cb.dataset.csvI;
      const envSel = document.querySelector(`[data-csv-env="${i}"]`);
      const tagSel = document.querySelector(`[data-csv-tag="${i}"]`);
      picked.push({ ...cands[i], envelopeId: envSel ? (envSel.value || null) : (cands[i].envelopeId || null),
        tag: tagSel ? tagSel.value : cands[i].tag });
    });
    if (!picked.length) { toast("Nothing selected"); return; }
    pushUndo(`Import ${picked.length} transaction${picked.length === 1 ? '' : 's'}`);
    for (const c of picked) {
      data.transactions.push({ id: uid(), date: c.date, type: c.type, amount: c.amount, accountId: profile.accountId, envelopeId: c.envelopeId, payee: c.payee, notes: '', source: 'import', ...(c.tag ? { tag: c.tag } : {}) });
    }
    if (profile.save && profile.name) {
      data.importProfiles = data.importProfiles || [];
      const rec = { name: profile.name, delimiter: profile.delimiter, hasHeader: profile.hasHeader, dateOrder: profile.dateOrder, amountMode: profile.amountMode, map: profile.map, accountId: profile.accountId };
      const existing = data.importProfiles.find(x => (x.name || '').toLowerCase() === profile.name.toLowerCase());
      if (existing) Object.assign(existing, rec); else data.importProfiles.push({ id: uid(), ...rec });
    }
    saveDirty(); closeModal();
    toast(`Imported ${picked.length} transaction${picked.length === 1 ? '' : 's'}`, 3000, 'success');
    render();
  };
}

function quickTx(type, prefill) {
  const tx = { id: uid(), date: todayISO(), type, amount: 0, ...prefill };
  txFormModal(tx, true);
}

function txFormModal(tx, isNew, opts) {
  // opts (optional):
  //   banner   — HTML string rendered as a small info strip under the h2
  //              (used when this modal is launched from a context like
  //              "applying a recurring instance now" so the user sees what
  //              scheduled occurrence is being consumed).
  //   afterSave(savedTx) — called after the transaction is appended/updated
  //                        and before saveDirty/render. Lets the caller do
  //                        side-effects like bumping rec.lastAppliedDate.
  //   tx.fromRecurringId is preserved on save (the generic save path used
  //   to drop unknown fields like this).
  // Show current balance next to each account name so the user can sanity-
  // check at-a-glance whether the source has the funds (esp. for transfers).
  // The em-dash separator matches our existing label/value pattern.
  const accOpts = ['<option value="">(none)</option>'].concat(
    pickAccounts(tx.accountId).map(a => `<option value="${a.id}" ${tx.accountId===a.id?'selected':''}>${esc(a.name)}${archSuffix(a)} — ${fmt(accountBalance(a))}</option>`)
  ).join('');
  const envOpts = ['<option value="">(none)</option>'].concat(
    pickEnvelopes(tx.envelopeId).map(e => `<option value="${e.id}" ${tx.envelopeId===e.id?'selected':''}>${esc(e.name)}${archSuffix(e)} — ${fmt(envelopeBalance(e))}</option>`)
  ).join('');
  openModal(`
    <h2>${isNew ? 'Add' : 'Edit'} transaction</h2>
    ${opts && opts.banner ? `<div style="background:var(--bg-3);padding:8px 12px;border-radius:6px;color:var(--text-dim);font-size:13px;margin:-4px 0 12px;">${opts.banner}</div>` : ''}
    <div class="field-row">
      <div class="field"><label>Date</label>
        <input type="date" id="t_date" value="${tx.date || todayISO()}"></div>
      <div class="field"><label>Type</label>
        <select id="t_type">
          <option value="expense" ${tx.type==='expense'?'selected':''}>Expense</option>
          <option value="income" ${tx.type==='income'?'selected':''}>Income</option>
          <option value="transfer-account" ${tx.type==='transfer-account'?'selected':''}>Account transfer</option>
          <option value="transfer-envelope" ${tx.type==='transfer-envelope'?'selected':''}>Envelope transfer</option>
        </select>
      </div>
    </div>
    <div class="field"><label>Amount</label>
      <input type="text" inputmode="decimal" id="t_amt" value="${tx.amount || ''}"
        placeholder="e.g. 50 or 2380-100" autocomplete="off">
      <div class="micro" id="t_amt_preview" style="margin-top:4px; min-height:14px;"></div>
    </div>

    <div id="t_simple">
      <div class="field"><label>Account</label><select id="t_acc">${accOpts}</select></div>
      <div class="field" id="t_env_single">
        <label style="display:flex;align-items:center;justify-content:space-between;gap:8px;"><span>Envelope</span>
          <button type="button" class="btn sm ghost" id="t_split_on" style="font-weight:500;">Split across envelopes…</button></label>
        <select id="t_env">${envOpts}</select>
      </div>
      <div class="field" id="t_split_wrap" style="display:none;">
        <label style="display:flex;align-items:center;justify-content:space-between;gap:8px;"><span>Split across envelopes</span>
          <button type="button" class="btn sm ghost" id="t_split_off" style="font-weight:500;">Use single envelope</button></label>
        <div id="t_split_rows"></div>
        <button type="button" class="btn sm" id="t_split_add" style="margin-top:6px;">+ Add envelope</button>
        <div class="micro" id="t_split_tally" style="margin-top:6px;"></div>
      </div>
    </div>
    <div id="t_xacc" style="display:none;">
      <div class="field"><label>From account</label>
        <select id="t_facc">${pickAccounts(tx.fromAccountId).map(a => `<option value="${a.id}" ${tx.fromAccountId===a.id?'selected':''}>${esc(a.name)}${archSuffix(a)} — ${fmt(accountBalance(a))}</option>`).join('')}</select>
      </div>
      <div class="field"><label>To account</label>
        <select id="t_tacc">${pickAccounts(tx.toAccountId).map(a => `<option value="${a.id}" ${tx.toAccountId===a.id?'selected':''}>${esc(a.name)}${archSuffix(a)} — ${fmt(accountBalance(a))}</option>`).join('')}</select>
      </div>
    </div>
    <div id="t_xenv" style="display:none;">
      <div class="field"><label>From envelope</label>
        <select id="t_fenv">${pickEnvelopes(tx.fromEnvelopeId).map(e => `<option value="${e.id}" ${tx.fromEnvelopeId===e.id?'selected':''}>${esc(e.name)}${archSuffix(e)} — ${fmt(envelopeBalance(e))}</option>`).join('')}</select>
      </div>
      <div class="field"><label>To envelope</label>
        <select id="t_tenv">${pickEnvelopes(tx.toEnvelopeId).map(e => `<option value="${e.id}" ${tx.toEnvelopeId===e.id?'selected':''}>${esc(e.name)}${archSuffix(e)} — ${fmt(envelopeBalance(e))}</option>`).join('')}</select>
      </div>
    </div>

    <div class="field"><label>Payee / description</label><input id="t_payee" value="${esc(tx.payee || '')}" list="payeeList" autocomplete="off">
      <datalist id="payeeList">${payeeHistory().map(p => `<option value="${esc(p)}">`).join('')}</datalist></div>
    <div class="field" ${tagList().length || tx.tag ? '' : 'style="display:none;"'}><label>Tag</label><select id="t_tag">${tagOptions(tx.tag)}</select></div>
    <div class="field"><label>Notes</label><textarea id="t_notes" rows="2">${esc(tx.notes || '')}</textarea></div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn primary" id="t_save">${isNew ? 'Add' : 'Save'}</button>
    </div>
  `);

  // Live arithmetic preview for the Amount field. Stays empty when the user
  // types a plain number (no noise) and shows "= 75,00 €" / "⚠ invalid"
  // otherwise. The value in the input is left untouched so the user can keep
  // editing the expression; the save handler re-evaluates on submit.
  wireAmountPreview("t_amt", "t_amt_preview")();

  // Payee-history auto-suggest: when the user types a payee they've used
  // before AND hasn't yet picked an account/envelope, pre-fill the dropdowns
  // with the most-common historical pair. Skipped when editing an existing tx
  // (we respect the saved values) and when the user has already chosen
  // anything in either dropdown.
  if (isNew) {
    const _payeeIn = document.getElementById('t_payee');
    _payeeIn.addEventListener('blur', () => {
      const sug = suggestPayeeDefaults(_payeeIn.value, { fuzzy: true });
      if (!sug) return;
      let applied = [];
      // The tag suggestion applies to every type (a tagged transfer is the
      // "petty cash → Work" case); account/envelope only to expense/income,
      // and only while the user hasn't touched either dropdown.
      const tagSel = document.getElementById('t_tag');
      if (sug.tag && tagSel && !tagSel.value && tagIndex(sug.tag) >= 0) {
        tagSel.value = sug.tag;
        tagSel.closest('.field').style.display = '';
        applied.push('tag');
      }
      const accSel = document.getElementById('t_acc');
      const envSel = document.getElementById('t_env');
      const simpleVisible = accSel && envSel && document.getElementById('t_simple').style.display !== 'none';
      if (simpleVisible && !accSel.value && !envSel.value) {
        if (sug.accountId && accountById(sug.accountId)) {
          accSel.value = sug.accountId;
          applied.push('account');
        }
        if (sug.envelopeId && envelopeById(sug.envelopeId)) {
          envSel.value = sug.envelopeId;
          applied.push('envelope');
        }
      }
      if (applied.length) {
        toast(`Auto-filled ${applied.join(' + ')} from ${sug.sampleCount} prior "${sug.matchedPayee || _payeeIn.value.trim()}" tx${sug.sampleCount === 1 ? '' : 's'}`, 2400, 'info');
      }
    });
  }

  function refreshType() {
    const t = document.getElementById("t_type").value;
    document.getElementById("t_simple").style.display = (t==='expense'||t==='income') ? '' : 'none';
    document.getElementById("t_xacc").style.display = t==='transfer-account' ? '' : 'none';
    document.getElementById("t_xenv").style.display = t==='transfer-envelope' ? '' : 'none';
  }
  document.getElementById("t_type").onchange = refreshType;
  refreshType();

  // --- Split across envelopes (expense/income only). Account side stays single
  // (debited by the total); the total is allocated across envelopes via splits[]. ---
  const _envOptsHtml = sel => ['<option value="">(envelope)</option>'].concat(
    pickEnvelopes(sel).map(e => `<option value="${e.id}" ${sel === e.id ? 'selected' : ''}>${esc(e.name)}${archSuffix(e)} — ${fmt(envelopeBalance(e))}</option>`)).join('');
  let splitMode = !!(tx.splits && tx.splits.length);
  function _splitReadRows() {
    return [...document.querySelectorAll('#t_split_rows [data-split-row]')].map(r => ({
      envelopeId: r.querySelector('.t-split-env').value || null,
      amount: Math.abs(evalAmount(r.querySelector('.t-split-amt').value) || 0)
    }));
  }
  function _splitTally() {
    const total = Math.abs(evalAmount(document.getElementById('t_amt').value) || 0);
    const sum = _splitReadRows().reduce((s, x) => s + (isNaN(x.amount) ? 0 : x.amount), 0);
    const rem = Math.round((total - sum) * 100) / 100;
    const ok = Math.abs(rem) < 0.005;
    const el = document.getElementById('t_split_tally');
    if (el) el.innerHTML = `Allocated ${fmt(sum)} of ${fmt(total)} · <span class="${ok ? 'pos' : 'neg'}">${ok ? 'balanced ✓' : (rem > 0 ? 'remainder ' + fmt(rem) : 'over by ' + fmt(-rem))}</span>`;
  }
  function _splitAddRow(envId, amt) {
    const row = document.createElement('div');
    row.className = 'field-row'; row.dataset.splitRow = '1'; row.style.cssText = 'margin-bottom:6px;align-items:center;gap:6px;';
    row.innerHTML = `<select class="t-split-env" style="flex:1;">${_envOptsHtml(envId || '')}</select>
      <input class="t-split-amt" type="text" inputmode="decimal" value="${amt != null && amt !== '' ? amt : ''}" placeholder="amount" style="max-width:120px;text-align:right;">
      <button type="button" class="btn icon t-split-del" title="Remove">×</button>`;
    document.getElementById('t_split_rows').appendChild(row);
    row.querySelector('.t-split-del').onclick = () => { row.remove(); _splitTally(); };
    row.querySelector('.t-split-amt').addEventListener('input', _splitTally);
    row.querySelector('.t-split-env').addEventListener('change', _splitTally);
  }
  function _splitSetMode(on, seed) {
    splitMode = on;
    document.getElementById('t_env_single').style.display = on ? 'none' : '';
    document.getElementById('t_split_wrap').style.display = on ? '' : 'none';
    if (on && seed && !document.querySelector('#t_split_rows [data-split-row]')) {
      const cur = document.getElementById('t_env').value;
      _splitAddRow(cur || '', Math.abs(evalAmount(document.getElementById('t_amt').value) || 0) || '');
      _splitAddRow('', '');
    }
    _splitTally();
  }
  document.getElementById('t_split_on').onclick = () => _splitSetMode(true, true);
  document.getElementById('t_split_off').onclick = () => _splitSetMode(false, false);
  document.getElementById('t_split_add').onclick = () => { _splitAddRow('', ''); _splitTally(); };
  document.getElementById('t_amt').addEventListener('input', () => { if (splitMode) _splitTally(); });
  if (tx.splits && tx.splits.length) { _splitSetMode(true, false); tx.splits.forEach(s => _splitAddRow(s.envelopeId, s.amount)); _splitTally(); }

  document.getElementById("t_save").onclick = () => {
    const t = document.getElementById("t_type").value;
    const out = {
      id: tx.id,
      date: document.getElementById("t_date").value || todayISO(),
      type: t,
      amount: Math.abs(evalAmount(document.getElementById("t_amt").value) || 0),
      payee: document.getElementById("t_payee").value,
      notes: document.getElementById("t_notes").value
    };
    // `out` is rebuilt from literals (see the fromRecurringId note below), so
    // every optional field has to be copied across explicitly.
    { const tag = document.getElementById("t_tag").value; if (tag) out.tag = tag; }
    if (!out.amount) { toast("Amount required"); return; }
    if (t === 'expense' || t === 'income') {
      out.accountId = document.getElementById("t_acc").value || null;
      if (splitMode) {
        const splits = _splitReadRows().filter(s => s.envelopeId && s.amount > 0);
        if (!splits.length) { toast("Add at least one split with an envelope and amount", 3000, 'error'); return; }
        const sum = splits.reduce((s, x) => s + x.amount, 0);
        if (Math.abs(sum - out.amount) >= 0.005) { toast(`Splits must add up to ${fmt(out.amount)} (now ${fmt(sum)})`, 3500, 'error'); return; }
        out.splits = splits;
        out.envelopeId = null;
      } else {
        out.envelopeId = document.getElementById("t_env").value || null;
      }
    } else if (t === 'transfer-account') {
      out.fromAccountId = document.getElementById("t_facc").value;
      out.toAccountId = document.getElementById("t_tacc").value;
      if (out.fromAccountId === out.toAccountId) { toast("Different accounts please"); return; }
    } else if (t === 'transfer-envelope') {
      out.fromEnvelopeId = document.getElementById("t_fenv").value;
      out.toEnvelopeId = document.getElementById("t_tenv").value;
      if (out.fromEnvelopeId === out.toEnvelopeId) { toast("Different envelopes please"); return; }
    }
    // Preserve recurring-source linkage if the input tx carried it. The form
    // has no UI for this field — without this line it would silently disappear
    // every time a recurring-sourced transaction is edited.
    if (tx.fromRecurringId) out.fromRecurringId = tx.fromRecurringId;
    // Snapshot before mutating. This handler backs Add Tx, Edit Tx and the
    // recurring-instance-now flow — the highest-frequency mutation in the app.
    // Without it, Ctrl-Z would pop an older snapshot and revert an unrelated
    // earlier change while this edit survived (decision #8 / undo contract).
    pushUndo(isNew ? 'Add transaction' : 'Edit transaction');
    if (isNew) data.transactions.push(out);
    else {
      const i = data.transactions.findIndex(x => x.id === tx.id);
      data.transactions[i] = out;
    }
    if (opts && typeof opts.afterSave === 'function') opts.afterSave(out);
    saveDirty(); closeModal(); render();
  };
}
function deleteTransaction(id) {
  const tx = data.transactions.find(t => t.id === id); if (!tx) return;
  const typeLabel = tx.type === 'transfer-account' ? 'account transfer'
    : tx.type === 'transfer-envelope' ? 'envelope transfer'
    : tx.type;
  const who = tx.payee ? ` "${tx.payee}"` : '';
  if (!confirm(`Delete ${typeLabel}${who} of ${fmt(tx.amount)} on ${fmtDate(tx.date)}?`)) return;
  pushUndo(`Delete ${typeLabel}${who}`);
  data.transactions = data.transactions.filter(t => t.id !== id);
  saveDirty(); render();
  toast(`Deleted ${typeLabel}${who}`, 5000, 'success', { label: 'Undo', onClick: performUndo });
}

//=============================================================================
// RECURRING
//=============================================================================
function renderRecurring() {
  // Sort: active entries first by Next date ascending, then paused entries.
  // Entries without a next occurrence (e.g. once-off past) sort to the bottom
  // of their group via the '￿' sentinel (sorts after any ISO date).
  const recs = data.recurring
    .map(r => ({ r, next: (r.active === false ? null : firstPendingOccurrence(r)) || '￿', paused: r.active === false }))
    .sort((a, b) => {
      if (a.paused !== b.paused) return a.paused ? 1 : -1;
      return a.next.localeCompare(b.next);
    })
    .map(x => x.r);
  return `
  <h2>Recurring transactions</h2>
  <div class="toolbar">
    <button class="btn primary" id="addRec">+ Add recurring</button>
    <div class="spacer"></div>
    <span style="color:var(--text-dim);">Income, salaries, rent, utilities, subscriptions, holiday bonuses…</span>
  </div>
  <div class="card" style="padding:0;">
    <table>
      <thead><tr>
        <th>Name</th><th>Type</th><th>Schedule</th><th>Account</th><th>Envelope</th>
        <th class="num">Amount</th><th>Next</th><th></th>
      </tr></thead>
      <tbody>
        ${recs.length === 0 ? `<tr><td colspan="8" style="text-align:center;padding:30px;color:var(--text-dim);">
          No recurring entries yet. Add salaries, rent, utilities, subscriptions, holiday bonuses…</td></tr>` :
          recs.map(r => {
            const pending = r.active === false ? null : firstPendingOccurrence(r);
            return `<tr>
          <td><strong>${esc(r.name)}</strong>${r.active===false?' <span class="badge">Paused</span>':''}</td>
          <td><span class="badge ${r.type}">${r.type}</span></td>
          <td>${esc(r.schedule)}${r.schedule==='custom-months'?` (${(r.months||[]).join(',')})`:''}</td>
          <td>${esc(r.type==='transfer-account' ?
            ((accountById(r.fromAccountId)?.name || '?') + '→' + (accountById(r.toAccountId)?.name || '?')) :
            r.type==='transfer-envelope' ? '' :
            (accountById(r.accountId)?.name || ''))}</td>
          <td>${esc(r.type==='transfer-envelope' ?
            ((envelopeById(r.fromEnvelopeId)?.name || '?') + '→' + (envelopeById(r.toEnvelopeId)?.name || '?')) :
            (envelopeById(r.envelopeId)?.name || ''))}</td>
          <td class="num ${r.type==='expense'?'neg':(r.type==='income'?'pos':'')}">${r.type==='expense'?'-':(r.type==='income'?'+':'')}${fmt(r.amount)}</td>
          <td>${(() => {
            if (!pending) return '—';
            const today = todayISO();
            if (pending < today) return `<span class="badge due" title="Overdue — scheduled but not yet recorded. Apply via ⚡ (a plain Add-transaction doesn't clear it).">Overdue</span> ${fmtDate(pending)}`;
            if (pending === today) return `<span class="badge due" title="Due today">Today</span> ${fmtDate(pending)}`;
            return fmtDate(pending);
          })()}</td>
          <td class="actions">
            <button class="btn sm" data-edit-rec="${r.id}">Edit</button>
            ${r.active===false
              ? ''
              : `<button class="btn sm ghost" data-apply-rec="${r.id}" ${pending ? `title="Apply next instance today (scheduled ${fmtDate(pending)})" aria-label="Apply next instance of ${esc(r.name)} today"` : `disabled title="No pending or upcoming instance" aria-label="No pending instance of ${esc(r.name)} to apply"`}>⚡</button>
                 <button class="btn sm ghost" data-skip-rec="${r.id}" ${pending ? `title="Skip the next occurrence (${fmtDate(pending)}) — it will never be offered; the one after moves up" aria-label="Skip next occurrence of ${esc(r.name)}"` : `disabled title="No pending or upcoming instance" aria-label="No pending occurrence of ${esc(r.name)} to skip"`}>⏭</button>`}
            ${r.active===false
              ? `<button class="btn sm" data-toggle-rec="${r.id}">▶ Enable</button>`
              : `<button class="btn sm ghost" data-toggle-rec="${r.id}">⏸ Pause</button>`}
            <button class="btn sm danger" data-del-rec="${r.id}" aria-label="Delete recurring ${esc(r.name)}" title="Delete recurring">×</button>
          </td>
        </tr>`;
          }).join('')}
      </tbody>
    </table>
  </div>
  `;
}
function bindRecurring() {
  document.getElementById("addRec").onclick = () => editRecurring();
  document.querySelectorAll("[data-edit-rec]").forEach(b =>
    b.onclick = () => editRecurring(b.dataset.editRec));
  document.querySelectorAll("[data-apply-rec]").forEach(b =>
    b.onclick = () => applyRecurringInstanceNow(b.dataset.applyRec));
  document.querySelectorAll("[data-skip-rec]").forEach(b =>
    b.onclick = () => skipRecurringOccurrence(b.dataset.skipRec));
  document.querySelectorAll("[data-del-rec]").forEach(b =>
    b.onclick = () => deleteRecurring(b.dataset.delRec));
  document.querySelectorAll("[data-toggle-rec]").forEach(b =>
    b.onclick = () => toggleRecurring(b.dataset.toggleRec));
}

// Pull the next pending occurrence of a recurring forward to today, with a
// chance to tweak the amount/envelope/notes before saving. Creates a one-off
// transaction (NOT a permanent change to the recurring template) and advances
// rec.lastAppliedDate to the scheduled occurrence being consumed, so the
// Dashboard's Review-Due banner won't flag it again. If the user cancels the
// modal, nothing is written and lastAppliedDate is untouched.
// The ⏭ button on the Recurring tab: mark the next pending occurrence as
// never happening, without booking anything. Because firstPendingOccurrence
// is by definition the earliest unresolved date, skipping it is always a
// contiguous resolution, so the watermark simply advances to it (same as
// applyRecurringInstanceNow does after booking) — no skippedDates entry is
// needed and any entries the watermark now covers are pruned. Works on a
// future occurrence too: the forecast projects from the watermark, so a
// skipped future bill leaves the projection. Undoable.
function skipRecurringOccurrence(recId) {
  const rec = data.recurring.find(r => r.id === recId);
  if (!rec) return;
  const pending = firstPendingOccurrence(rec);
  if (!pending) { toast("No pending or upcoming occurrence to skip"); return; }
  if (!confirm(`Skip "${rec.name}" on ${fmtDate(pending)}?\n\nThis occurrence will never be offered or recorded; the following one becomes "next". Ctrl+Z undoes it.`)) return;
  pushUndo(`Skip ${rec.name} (${fmtDate(pending)})`);
  if (!rec.lastAppliedDate || rec.lastAppliedDate < pending) rec.lastAppliedDate = pending;
  if (rec.skippedDates) {
    rec.skippedDates = rec.skippedDates.filter(d => d > rec.lastAppliedDate);
    if (!rec.skippedDates.length) delete rec.skippedDates;
  }
  saveDirty(); render();
  const next = firstPendingOccurrence(rec);
  toast(`Skipped ${rec.name} on ${fmtDate(pending)}${next ? ` · next ${fmtDate(next)}` : ''}`, 5000, 'success', { label: 'Undo', onClick: performUndo });
}

function applyRecurringInstanceNow(recId) {
  const rec = data.recurring.find(r => r.id === recId);
  if (!rec) return;
  const scheduled = firstPendingOccurrence(rec);
  if (!scheduled) { toast("No pending or upcoming instance to apply"); return; }
  const tx = recurringToTx(rec, todayISO(), rec.amount);
  txFormModal(tx, true, {
    banner: `From recurring: <strong>${esc(rec.name)}</strong> · scheduled <strong>${fmtDate(scheduled)}</strong>`,
    afterSave: () => {
      // Advance to the scheduled occurrence (not the user-chosen tx date) so the
      // bookkeeping reflects which instance was consumed, regardless of when
      // the user actually dated the resulting transaction.
      if (!rec.lastAppliedDate || rec.lastAppliedDate < scheduled) {
        rec.lastAppliedDate = scheduled;
      }
    }
  });
}

function editRecurring(id) {
  const r = id ? data.recurring.find(x => x.id === id) :
    { id: uid(), type: "expense", schedule: "monthly", startDate: todayISO(), active: true };
  openModal(`
    <h2>${id ? 'Edit' : 'Add'} recurring</h2>
    <div class="field"><label>Name</label><input id="r_name" value="${esc(r.name||'')}"></div>
    <div class="field" ${tagList().length || r.tag ? '' : 'style="display:none;"'}><label>Tag</label><select id="r_tag">${tagOptions(r.tag)}</select></div>
    <div class="field-row">
      <div class="field"><label>Type</label>
        <select id="r_type">
          <option value="income" ${r.type==='income'?'selected':''}>Income</option>
          <option value="expense" ${r.type==='expense'?'selected':''}>Expense</option>
          <option value="transfer-account" ${r.type==='transfer-account'?'selected':''}>Account transfer</option>
          <option value="transfer-envelope" ${r.type==='transfer-envelope'?'selected':''}>Envelope transfer</option>
        </select>
      </div>
      <div class="field"><label>Amount</label>
        <input type="text" inputmode="decimal" id="r_amt" value="${r.amount || ''}"
          placeholder="e.g. 50 or 100-25" autocomplete="off">
        <div class="micro" id="r_amt_preview" style="margin-top:4px; min-height:14px;"></div>
      </div>
    </div>
    <div class="field-row">
      <div class="field"><label>Schedule</label>
        <select id="r_sched">
          <option value="monthly" ${r.schedule==='monthly'?'selected':''}>Monthly</option>
          <option value="weekly" ${r.schedule==='weekly'?'selected':''}>Weekly</option>
          <option value="biweekly" ${r.schedule==='biweekly'?'selected':''}>Bi-weekly</option>
          <option value="yearly" ${r.schedule==='yearly'?'selected':''}>Yearly</option>
          <option value="custom-months" ${r.schedule==='custom-months'?'selected':''}>Specific months</option>
          <option value="once" ${r.schedule==='once'?'selected':''}>One-time future</option>
        </select>
      </div>
      <div class="field"><label>Start / on</label>
        <input type="date" id="r_start" value="${r.startDate||todayISO()}"></div>
    </div>
    <div class="field" id="r_months_wrap" style="display:${r.schedule==='custom-months'?'':'none'}">
      <label>Months (1-12, comma separated)</label>
      <input id="r_months" value="${(r.months||[]).join(',')}" placeholder="e.g. 4,8,12">
      <span style="font-size:11px;color:var(--text-dim);">Useful for Christmas (12), Easter (4), summer (7) bonuses.</span>
    </div>
    <div class="field"><label>End date (optional)</label>
      <input type="date" id="r_end" value="${r.endDate||''}"></div>

    <div id="r_simple" style="display:${(r.type==='transfer-account'||r.type==='transfer-envelope')?'none':''};">
      <div class="field"><label>Account</label>
        <select id="r_acc">
          <option value="">(none)</option>
          ${pickAccounts(r.accountId).map(a => `<option value="${a.id}" ${r.accountId===a.id?'selected':''}>${esc(a.name)}${archSuffix(a)}</option>`).join('')}
        </select>
      </div>
      <div class="field"><label>Envelope</label>
        <select id="r_env">
          <option value="">(none)</option>
          ${pickEnvelopes(r.envelopeId).map(e => `<option value="${e.id}" ${r.envelopeId===e.id?'selected':''}>${esc(e.name)}${archSuffix(e)}</option>`).join('')}
        </select>
      </div>
    </div>
    <div id="r_xacc" style="display:${r.type==='transfer-account'?'':'none'};">
      <div class="field"><label>From account</label>
        <select id="r_facc">${pickAccounts(r.fromAccountId).map(a => `<option value="${a.id}" ${r.fromAccountId===a.id?'selected':''}>${esc(a.name)}${archSuffix(a)}</option>`).join('')}</select>
      </div>
      <div class="field"><label>To account</label>
        <select id="r_tacc">${pickAccounts(r.toAccountId).map(a => `<option value="${a.id}" ${r.toAccountId===a.id?'selected':''}>${esc(a.name)}${archSuffix(a)}</option>`).join('')}</select>
      </div>
    </div>
    <div id="r_xenv" style="display:${r.type==='transfer-envelope'?'':'none'};">
      <div class="field"><label>From envelope</label>
        <select id="r_fenv">${pickEnvelopes(r.fromEnvelopeId).map(e => `<option value="${e.id}" ${r.fromEnvelopeId===e.id?'selected':''}>${esc(e.name)}${archSuffix(e)}</option>`).join('')}</select>
      </div>
      <div class="field"><label>To envelope</label>
        <select id="r_tenv">${pickEnvelopes(r.toEnvelopeId).map(e => `<option value="${e.id}" ${r.toEnvelopeId===e.id?'selected':''}>${esc(e.name)}${archSuffix(e)}</option>`).join('')}</select>
      </div>
    </div>

    <div class="field"><label>Notes</label><textarea id="r_notes" rows="2">${esc(r.notes||'')}</textarea></div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn primary" id="r_save">${id?'Save':'Add'}</button>
    </div>
  `);
  // Live arithmetic preview for the Amount field (matches Add Tx + Move Funds).
  wireAmountPreview("r_amt", "r_amt_preview")();

  document.getElementById("r_sched").onchange = (e) =>
    document.getElementById("r_months_wrap").style.display = e.target.value === 'custom-months' ? '' : 'none';
  document.getElementById("r_type").onchange = (e) => {
    const t = e.target.value;
    document.getElementById("r_simple").style.display = (t === 'transfer-account' || t === 'transfer-envelope') ? 'none' : '';
    document.getElementById("r_xacc").style.display = t === 'transfer-account' ? '' : 'none';
    document.getElementById("r_xenv").style.display = t === 'transfer-envelope' ? '' : 'none';
  };
  document.getElementById("r_save").onclick = () => {
    const out = {
      ...r,
      name: document.getElementById("r_name").value.trim(),
      type: document.getElementById("r_type").value,
      amount: Math.abs(evalAmount(document.getElementById("r_amt").value) || 0),
      schedule: document.getElementById("r_sched").value,
      startDate: document.getElementById("r_start").value,
      endDate: document.getElementById("r_end").value || null,
      notes: document.getElementById("r_notes").value,
      // `...r` above would keep a stale tag when the select is cleared, so
      // set it explicitly; undefined is dropped by JSON.stringify.
      tag: document.getElementById("r_tag").value || undefined,
      active: r.active !== false
    };
    if (!out.name) { toast("Name required"); return; }
    if (!out.amount) { toast("Amount required"); return; }
    if (out.schedule === 'custom-months') {
      out.months = document.getElementById("r_months").value.split(",")
        .map(s => parseInt(s.trim())).filter(n => n >= 1 && n <= 12);
    }
    if (out.type === 'transfer-account') {
      out.fromAccountId = document.getElementById("r_facc").value;
      out.toAccountId = document.getElementById("r_tacc").value;
      out.accountId = null; out.envelopeId = null;
      out.fromEnvelopeId = null; out.toEnvelopeId = null;
      if (!out.fromAccountId || !out.toAccountId) { toast("From and To account required"); return; }
      if (out.fromAccountId === out.toAccountId) { toast("From and To account must differ"); return; }
    } else if (out.type === 'transfer-envelope') {
      out.fromEnvelopeId = document.getElementById("r_fenv").value;
      out.toEnvelopeId = document.getElementById("r_tenv").value;
      out.accountId = null; out.envelopeId = null;
      out.fromAccountId = null; out.toAccountId = null;
      if (!out.fromEnvelopeId || !out.toEnvelopeId) { toast("From and To envelope required"); return; }
      if (out.fromEnvelopeId === out.toEnvelopeId) { toast("From and To envelope must differ"); return; }
    } else {
      out.accountId = document.getElementById("r_acc").value || null;
      out.envelopeId = document.getElementById("r_env").value || null;
      out.fromAccountId = null; out.toAccountId = null;
      out.fromEnvelopeId = null; out.toEnvelopeId = null;
    }
    if (!id) {
      // Anchor lastAppliedDate to the day before startDate so the first
      // occurrence on/after startDate is detected as due/overdue. Without this,
      // migrate() would later anchor it to today and miss backdated occurrences.
      out.lastAppliedDate = isoDate(addDays(parseDate(out.startDate), -1));
      data.recurring.push(out);
    } else {
      // If the user moved startDate to before the current lastAppliedDate,
      // reset lastAppliedDate so occurrences from the new startDate are detected.
      const newStart = parseDate(out.startDate);
      const lastApp = out.lastAppliedDate ? parseDate(out.lastAppliedDate) : null;
      if (lastApp && newStart < lastApp) {
        out.lastAppliedDate = isoDate(addDays(newStart, -1));
      }
      const i = data.recurring.findIndex(x => x.id === id); data.recurring[i] = out;
    }
    saveDirty(); closeModal(); render();
  };
}
function deleteRecurring(id) {
  const r = data.recurring.find(x => x.id === id); if (!r) return;
  const txCount = data.transactions.filter(t => t.fromRecurringId === id).length;
  const linked = txCount
    ? ` Past transactions it generated (${txCount}) will remain.`
    : '';
  if (!confirm(`Delete recurring "${r.name}" (${r.type}, ${fmt(r.amount)} ${r.schedule})?${linked}`)) return;
  pushUndo(`Delete recurring "${r.name}"`);
  const recName = r.name;
  data.recurring = data.recurring.filter(x => x.id !== id);
  saveDirty(); render();
  toast(`Deleted recurring "${recName}"`, 5000, "success", { label: "Undo", onClick: performUndo });
}
function toggleRecurring(id) {
  const r = data.recurring.find(x => x.id === id);
  r.active = r.active === false ? true : false;
  saveDirty(); render();
}

//=============================================================================
// FORECAST
//=============================================================================
const HORIZONS = [
  { label: "1 week", days: 7 },
  { label: "1 month", days: 30 },
  { label: "3 months", days: 90 },
  { label: "6 months", days: 180 },
  { label: "12 months", days: 365 },
  { label: "2 years", days: 730 }
];
let forecastState = {
  accountIds: null,
  days: 90,
  // chartLines: "both" | "total" | "individual" | "spendable" — which lines
  // to render on the forecast chart. Consolidates the prior showTotal/onlyTotal
  // pair into a single multi-state. "spendable" hides all account/total lines
  // and shows only the spendable-cash line regardless of showSpendable.
  // Old fields are migrated in migrate() and via chartLinesFromLegacy() when
  // loading profiles saved before this change.
  //
  // Default is "total" (combined-total line only) so the Dashboard's
  // "Lowest in period" tile features the TOTAL account balance prominently
  // — the metric that stays anchored when you fund envelopes. Per-account
  // lines are off by default to keep the chart readable for new users;
  // re-enable via the Forecast tab radio buttons.
  chartLines: "total",
  includeAllowances: false,
  showSpendable: false,
  selectedProfileId: null,  // transient: which saved profile is currently active
  profileDirty: false       // transient: have settings changed since the profile was loaded?
};

// Convert legacy {showTotal, onlyTotal} into the new chartLines value. Kept
// as a helper because old forecast profiles in finance-data.json may still
// carry the legacy pair until migrate() rewrites them.
function chartLinesFromLegacy(s) {
  if (s.chartLines === "both" || s.chartLines === "total"
      || s.chartLines === "individual" || s.chartLines === "spendable") {
    return s.chartLines;
  }
  const showTotal = s.showTotal !== false;  // default true
  const onlyTotal = !!s.onlyTotal;
  if (onlyTotal && showTotal) return "total";
  if (!showTotal && !onlyTotal) return "individual";
  // Degenerate combination (showTotal=false, onlyTotal=true): nothing useful
  // to render. Fall back to "both" so the chart isn't blank by surprise.
  return "both";
}

function renderForecast() {
  if (forecastState.accountIds === null) {
    forecastState.accountIds = activeAccounts().filter(a => !a.isInvestment && a.includeInNetWorth !== false).map(a => a.id);
  }
  return `
  <h2>Forecast</h2>
  <div class="forecast-row" id="forecastRow">
    <div class="card forecast-controls">
      <div>
        <h3>Profiles</h3>
        <div style="display:flex;gap:6px;flex-wrap:wrap;align-items:center;">
          <select id="fcProfile" style="flex:1;min-width:140px;padding:6px 8px;background:var(--bg-3);color:var(--text);border:1px solid var(--border);border-radius:6px;">
            <option value="">— ${data.forecastProfiles.length ? 'Pick a profile' : 'No saved profiles'} —</option>
            ${data.forecastProfiles.map(p =>
              `<option value="${p.id}" ${forecastState.selectedProfileId === p.id ? 'selected' : ''}>${data.defaultForecastProfileId === p.id ? '★ ' : ''}${esc(p.name)}</option>`
            ).join('')}
          </select>
          <button class="btn sm" id="fcProfileSaveAs" title="Save current settings as a new profile">Save as…</button>
          <button class="btn sm" id="fcProfileUpdate" title="${forecastState.profileDirty ? 'You have unsaved changes — click to overwrite the profile' : 'Overwrite the selected profile with current settings'}" ${forecastState.selectedProfileId ? '' : 'disabled'}>Update${forecastState.profileDirty ? ' •' : ''}</button>
          <button class="btn sm" id="fcProfileSetDefault" title="${data.defaultForecastProfileId === forecastState.selectedProfileId && forecastState.selectedProfileId ? 'This profile is the session default — click to clear' : 'Set the selected profile as the default for future sessions'}" ${forecastState.selectedProfileId ? '' : 'disabled'}>${data.defaultForecastProfileId === forecastState.selectedProfileId && forecastState.selectedProfileId ? '★ Default' : 'Set default'}</button>
          <button class="btn sm danger" id="fcProfileDelete" title="Delete the selected profile" aria-label="Delete selected forecast profile" ${forecastState.selectedProfileId ? '' : 'disabled'}>×</button>
        </div>
      </div>
      <div>
        <h3>Accounts to forecast</h3>
        <details class="fc-acc-picker">
          <summary>
            <span class="fc-acc-summary">${forecastState.accountIds.length} of ${activeAccounts().length} accounts selected</span>
            <span class="fc-acc-caret">▾</span>
          </summary>
          <div class="checkbox-list">
            ${activeAccounts().map(a => `
              <label>
                <input type="checkbox" data-fc-acc="${a.id}" ${forecastState.accountIds.includes(a.id)?'checked':''}>
                <span style="flex:1;">${esc(a.name)}
                  ${a.isInvestment?'<span class="badge invest">Investment</span>':''}
                </span>
                <span style="color:var(--text-dim);font-size:12px;">${fmt(accountBalance(a))}</span>
              </label>`).join('')}
          </div>
        </details>
      </div>
      <div>
        <h3>Time horizon</h3>
        <div style="display:flex;flex-wrap:wrap;gap:6px;">
          ${HORIZONS.map(h => `<button class="btn ${h.days===forecastState.days?'selected':''}" data-fc-h="${h.days}">${h.label}</button>`).join('')}
        </div>
        <div style="margin-top:14px;display:flex;flex-direction:column;gap:6px;">
          <div style="display:flex;flex-direction:column;gap:4px;">
            <span style="font-size:12px;color:var(--text-dim);text-transform:uppercase;letter-spacing:.5px;">Chart shows</span>
            <label><input type="radio" name="fcLines" value="both" ${forecastState.chartLines==='both'?'checked':''}> Per-account lines + combined total</label>
            <label><input type="radio" name="fcLines" value="total" ${forecastState.chartLines==='total'?'checked':''}> Combined total only</label>
            <label><input type="radio" name="fcLines" value="individual" ${forecastState.chartLines==='individual'?'checked':''}> Per-account lines only</label>
            <label><input type="radio" name="fcLines" value="spendable" ${forecastState.chartLines==='spendable'?'checked':''}> Spendable cash only</label>
          </div>
          <label title="Project envelope monthly budgets as smoothed daily spending. Envelopes already covered by an active recurring transaction are skipped.">
            <input type="checkbox" id="fcAllow" ${forecastState.includeAllowances?'checked':''}>
            Include envelope allowances as projected spending
            <span class="help-tip" tabindex="0" title="Projects envelope budgets as smoothed daily outflows against their spending account — even if you haven't logged the real transactions yet. Useful for an honest end-of-month forecast that includes the spending you KNOW is coming but hasn't been booked.">?</span>
          </label>
          <label title="Show the portion of your projected balance that is NOT earmarked by any envelope. Spendable = total − the envelope balances held in the selected accounts."
                 style="${forecastState.chartLines==='spendable'?'opacity:0.5;':''}">
            <input type="checkbox" id="fcSpend" ${forecastState.showSpendable||forecastState.chartLines==='spendable'?'checked':''} ${forecastState.chartLines==='spendable'?'disabled':''}>
            Show spendable cash line (total − envelopes)${forecastState.chartLines==='spendable'?' <span style="font-size:11px;color:var(--text-dim);">(implied)</span>':''}
          </label>
        </div>
      </div>
    </div>
    <div class="forecast-splitter" id="forecastSplitter" title="Drag to resize"></div>
    <div class="card forecast-chart-card">
      <div><canvas id="fcChart"></canvas></div>
    </div>
  </div>
  <div class="card" style="margin-top:14px;">
    <h3>Projected end-of-period balances</h3>
    <div id="fcSummary"></div>
  </div>
  <div class="card" id="fcAllowanceCard" style="margin-top:14px;display:none;">
    <h3>Envelope allowances in this projection</h3>
    <div id="fcAllowanceBreakdown"></div>
  </div>
  `;
}
function bindForecast() {
  document.querySelectorAll("[data-fc-acc]").forEach(c => c.onchange = e => {
    const id = e.target.dataset.fcAcc;
    if (e.target.checked && !forecastState.accountIds.includes(id)) forecastState.accountIds.push(id);
    if (!e.target.checked) forecastState.accountIds = forecastState.accountIds.filter(x => x !== id);
    const sum = document.querySelector('.fc-acc-summary');
    if (sum) sum.textContent = `${forecastState.accountIds.length} of ${activeAccounts().length} accounts selected`;
    markProfileDirty();
    drawForecast();
  });
  document.querySelectorAll("[data-fc-h]").forEach(b => b.onclick = () => {
    forecastState.days = +b.dataset.fcH;
    markProfileDirty();
    render();
  });
  document.querySelectorAll('input[name="fcLines"]').forEach(r => {
    r.onchange = e => {
      if (!e.target.checked) return;
      const prev = forecastState.chartLines;
      forecastState.chartLines = e.target.value;
      markProfileDirty();
      // Spendable-only mode disables the "Show spendable cash line" checkbox
      // and labels it "(implied)". Crossing that boundary needs a full
      // re-render so the checkbox's disabled state and label update;
      // otherwise drawForecast() alone leaves the controls stale.
      const crossing = (prev === 'spendable') !== (e.target.value === 'spendable');
      if (crossing) render(); else drawForecast();
    };
  });
  document.getElementById("fcAllow").onchange = e => {
    forecastState.includeAllowances = e.target.checked;
    markProfileDirty();
    drawForecast();
  };
  document.getElementById("fcSpend").onchange = e => {
    forecastState.showSpendable = e.target.checked;
    markProfileDirty();
    drawForecast();
  };

  // Profiles
  const profSel = document.getElementById("fcProfile");
  if (profSel) {
    profSel.onchange = e => loadForecastProfile(e.target.value || null);
  }
  const saveAsBtn = document.getElementById("fcProfileSaveAs");
  if (saveAsBtn) saveAsBtn.onclick = saveForecastProfileAs;
  const updateBtn = document.getElementById("fcProfileUpdate");
  if (updateBtn) updateBtn.onclick = updateForecastProfile;
  const setDefBtn = document.getElementById("fcProfileSetDefault");
  if (setDefBtn) setDefBtn.onclick = toggleDefaultForecastProfile;
  const delBtn = document.getElementById("fcProfileDelete");
  if (delBtn) delBtn.onclick = deleteForecastProfile;

  setupForecastSplitter();
  drawForecast();
}

// Capture currently-active forecast settings for persisting in a profile.
function currentForecastSettings() {
  return {
    accountIds: [...(forecastState.accountIds || [])],
    days: forecastState.days,
    chartLines: forecastState.chartLines,
    includeAllowances: forecastState.includeAllowances,
    showSpendable: forecastState.showSpendable
  };
}

function applyForecastSettings(s) {
  // Drop ids for accounts that no longer exist so a profile saved before an
  // account was deleted can't reintroduce an orphan id into the projection.
  forecastState.accountIds = [...(s.accountIds || [])].filter(id => accountById(id));
  forecastState.days = s.days || 90;
  // Tolerate legacy {showTotal, onlyTotal} for safety even though migrate()
  // should have rewritten saved profiles already.
  forecastState.chartLines = chartLinesFromLegacy(s);
  forecastState.includeAllowances = !!s.includeAllowances;
  forecastState.showSpendable = !!s.showSpendable;
}

function loadForecastProfile(id) {
  if (!id) {
    forecastState.selectedProfileId = null;
    forecastState.profileDirty = false;
    render();
    return;
  }
  const p = data.forecastProfiles.find(x => x.id === id);
  if (!p) return;
  applyForecastSettings(p);
  forecastState.selectedProfileId = p.id;
  forecastState.profileDirty = false;
  render();
}

function saveForecastProfileAs() {
  const name = (prompt("Name for this profile:", "") || "").trim();
  if (!name) return;
  if (data.forecastProfiles.some(p => p.name.toLowerCase() === name.toLowerCase())) {
    if (!confirm(`A profile named "${name}" already exists. Replace it?`)) return;
    data.forecastProfiles = data.forecastProfiles.filter(p => p.name.toLowerCase() !== name.toLowerCase());
  }
  const p = { id: uid(), name, ...currentForecastSettings() };
  data.forecastProfiles.push(p);
  forecastState.selectedProfileId = p.id;
  forecastState.profileDirty = false;
  saveDirty(); toast(`Saved profile "${name}"`); render();
}

function updateForecastProfile() {
  const id = forecastState.selectedProfileId;
  if (!id) return;
  const p = data.forecastProfiles.find(x => x.id === id);
  if (!p) return;
  Object.assign(p, currentForecastSettings());
  forecastState.profileDirty = false;
  saveDirty(); toast(`Updated profile "${p.name}"`); render();
}

function deleteForecastProfile() {
  const id = forecastState.selectedProfileId;
  if (!id) return;
  const p = data.forecastProfiles.find(x => x.id === id);
  if (!p) return;
  if (!confirm(`Delete forecast profile "${p.name}"?`)) return;
  data.forecastProfiles = data.forecastProfiles.filter(x => x.id !== id);
  // If the deleted profile was the persistent default, clear the default
  // pointer so future sessions don't try to apply a missing profile.
  if (data.defaultForecastProfileId === id) data.defaultForecastProfileId = null;
  forecastState.selectedProfileId = null;
  forecastState.profileDirty = false;
  saveDirty(); render();
}

// Toggle "default" status on the currently selected profile. The default
// profile is auto-applied on session start (see init at the bottom of this
// file), persists in data.defaultForecastProfileId, and only changes when the
// user clicks this button — picking a different profile from the dropdown is
// a session-only action and does NOT change the default.
function toggleDefaultForecastProfile() {
  const id = forecastState.selectedProfileId;
  if (!id) return;
  if (data.defaultForecastProfileId === id) {
    data.defaultForecastProfileId = null;
    toast("Default cleared");
  } else {
    data.defaultForecastProfileId = id;
    const p = data.forecastProfiles.find(x => x.id === id);
    toast(`Default profile: ${p ? p.name : ''}`);
  }
  saveDirty(); render();
}

// User manually changed a setting that belongs to a profile (account toggle,
// horizon, allowances, etc.). Keep the profile selected so Update / Delete /
// Set-default still target it; just flag the state as dirty so the Update
// button picks up a "•" indicator on its next render and we know there are
// pending changes to save back.
function markProfileDirty() {
  if (!forecastState.selectedProfileId) return;
  if (forecastState.profileDirty) return;
  forecastState.profileDirty = true;
  // Inline DOM update so changes that only call drawForecast() (most setting
  // toggles) still surface the indicator without a full re-render.
  const upd = document.getElementById("fcProfileUpdate");
  if (upd) {
    upd.textContent = "Update •";
    upd.title = "You have unsaved changes — click to overwrite the profile";
  }
}

function setupForecastSplitter() {
  const row = document.getElementById("forecastRow");
  const splitter = document.getElementById("forecastSplitter");
  if (!row || !splitter) return;
  // Restore saved width
  const saved = parseInt(localStorage.getItem("forecastControlsW") || "", 10);
  if (saved && saved > 280) row.style.setProperty("--forecast-controls-w", saved + "px");

  const onDown = (e) => {
    e.preventDefault();
    splitter.classList.add("dragging");
    document.body.classList.add("forecast-resizing");
    const rowRect = row.getBoundingClientRect();
    let resizeRaf = 0;
    const onMove = (ev) => {
      const x = (ev.touches ? ev.touches[0].clientX : ev.clientX) - rowRect.left;
      const min = 280;
      const max = Math.max(min + 200, rowRect.width - 360);
      const w = Math.max(min, Math.min(max, x));
      row.style.setProperty("--forecast-controls-w", w + "px");
      // Coalesce chart relayout to one call per frame. A raw resize() on every
      // mousemove redraws the (up to 730-point) chart 60-120x/sec and stutters.
      if (currentChart && !resizeRaf) {
        resizeRaf = requestAnimationFrame(() => { resizeRaf = 0; if (currentChart) currentChart.resize(); });
      }
    };
    const onUp = () => {
      splitter.classList.remove("dragging");
      document.body.classList.remove("forecast-resizing");
      const w = parseInt(getComputedStyle(row).getPropertyValue("--forecast-controls-w"), 10);
      if (w) localStorage.setItem("forecastControlsW", String(w));
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
      window.removeEventListener("touchmove", onMove);
      window.removeEventListener("touchend", onUp);
    };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
    window.addEventListener("touchmove", onMove, { passive: false });
    window.addEventListener("touchend", onUp);
  };
  splitter.addEventListener("mousedown", onDown);
  splitter.addEventListener("touchstart", onDown, { passive: false });
  // Double-click to reset to default
  splitter.addEventListener("dblclick", () => {
    row.style.removeProperty("--forecast-controls-w");
    localStorage.removeItem("forecastControlsW");
    if (currentChart) currentChart.resize();
  });
}

// Inline Chart.js plugin for the Forecast chart (decision #44): a dashed zero
// line whenever the y-range crosses zero, and a label at the featured line's
// low point ("Lowest €13,403 · 10 Sep"). The dot itself is a native point
// (pointRadius array on the dataset) so hover and tooltip work on it; only
// the text is drawn by hand. Colours come from themeColor(), never literals.
function forecastMarksPlugin(m) {
  return {
    id: 'forecastMarks',
    afterDatasetsDraw(chart) {
      const { ctx, chartArea, scales } = chart;
      if (!chartArea) return;
      const y = scales.y;
      // Zero line, only when 0 is inside the visible range (a positive-only
      // chart must not be stretched down to show it).
      if (y && y.min < 0 && y.max > 0) {
        const py = y.getPixelForValue(0);
        ctx.save();
        ctx.strokeStyle = themeColor("--text-dim", "#8e9bad");
        ctx.setLineDash([5, 4]);
        ctx.lineWidth = 1;
        ctx.beginPath(); ctx.moveTo(chartArea.left, py); ctx.lineTo(chartArea.right, py); ctx.stroke();
        ctx.restore();
      }
      if (m.featuredDatasetIdx < 0 || m.lowIdx < 0) return;
      const meta = chart.getDatasetMeta(m.featuredDatasetIdx);
      if (!meta || meta.hidden) return;
      const pt = meta.data[m.lowIdx];
      if (!pt) return;
      const label = `Lowest ${fmt(m.lowValue)} · ${fmtDate(m.lowDate)}`;
      ctx.save();
      ctx.font = `600 11px ${getComputedStyle(document.body).fontFamily}`;
      const w = ctx.measureText(label).width + 12, h = 20;
      // Above the point when it sits in the lower half of the plot, else below;
      // clamped so the box never leaves the plot area.
      let bx = Math.min(Math.max(pt.x - w / 2, chartArea.left + 2), chartArea.right - w - 2);
      let by = pt.y > (chartArea.top + chartArea.bottom) / 2 ? pt.y - h - 10 : pt.y + 10;
      by = Math.min(Math.max(by, chartArea.top + 2), chartArea.bottom - h - 2);
      ctx.fillStyle = themeColor("--bg-3", "#1e2836");
      ctx.strokeStyle = themeColor("--border", "#2c3746");
      ctx.lineWidth = 1;
      ctx.beginPath();
      if (ctx.roundRect) ctx.roundRect(bx, by, w, h, 5); else ctx.rect(bx, by, w, h);
      ctx.fill(); ctx.stroke();
      ctx.fillStyle = themeColor("--text", "#e8edf4");
      ctx.textBaseline = 'middle';
      ctx.fillText(label, bx + 6, by + h / 2);
      ctx.restore();
    }
  };
}

function drawForecast() {
  const { dates, series, total, envelopeTotal, spendable, allowanceInfo, excludedEnvelopes } = forecastAccountBalances(
    forecastState.accountIds, forecastState.days,
    { includeAllowances: forecastState.includeAllowances }
  );
  const colors = chartPalette();
  // chartLines:
  //   "both"       → per-account lines + combined total (dashed pale yellow on top)
  //   "total"      → combined total only (solid teal — looks like a single account)
  //   "individual" → per-account lines only, no combined total
  //   "spendable"  → nothing but the spendable-cash line (showSpendable is implied)
  const cl = forecastState.chartLines;
  const showIndividual = cl === "both" || cl === "individual";
  // Only chart/summarise accounts that still exist — a stale id (deleted account
  // left in the saved selection) has no series entry; indexing it would throw.
  const liveAccountIds = (forecastState.accountIds || []).filter(id => accountById(id));
  const showTotalLine = liveAccountIds.length > 0 && (cl === "both" || cl === "total");
  const totalOnly = cl === "total";
  const spendableImplied = cl === "spendable";
  const datasets = showIndividual ? liveAccountIds.map((id, i) => ({
    label: accountById(id)?.name || "?",
    data: series[id],
    borderColor: colors[i % colors.length],
    backgroundColor: colors[i % colors.length] + "33",
    tension: 0.15,
    fill: false,
    pointRadius: 0
  })) : [];
  // The featured line — the one whose low point gets marked, and whose area
  // is shaded (only when it is the sole line; several shaded areas would
  // muddle). Spendable wins whenever it is drawn, because "lowest spendable"
  // is the figure the dashboard leads with.
  const showSpendLine = (forecastState.showSpendable || spendableImplied) && liveAccountIds.length > 0;
  const featured = showSpendLine ? 'spendable' : (showTotalLine ? 'total' : null);
  const minIdx = arr => { let m = Infinity, k = 0; for (let i = 0; i < arr.length; i++) if (arr[i] < m) { m = arr[i]; k = i; } return k; };
  const lowIdx = featured === 'spendable' ? minIdx(spendable) : featured === 'total' ? minIdx(total) : -1;
  const dotAt = (n, i) => Array.from({ length: n }, (_, k) => k === i ? 4 : 0);
  const withAlpha = (hex, a) => /^#[0-9a-f]{6}$/i.test(hex) ? hex + a : hex;
  if (showTotalLine) {
    const col = totalOnly ? themeColor("--accent", "#4fc3a1") : themeColor("--chart-total", "#fff9b8");
    datasets.push({
      label: "Combined total",
      data: total,
      borderColor: col,
      backgroundColor: withAlpha(col, "22"),
      borderWidth: 2.5,
      borderDash: totalOnly ? [] : [4, 4],
      tension: 0.15,
      fill: (totalOnly && featured === 'total') ? 'origin' : false,
      pointRadius: featured === 'total' ? dotAt(total.length, lowIdx) : 0,
      pointBackgroundColor: col,
      pointBorderColor: themeColor("--bg-2", "#141c29"),
      pointBorderWidth: 2,
      pointHoverRadius: 5
    });
  }
  if (showSpendLine) {
    const col = themeColor("--warn", "#f0a64a");
    datasets.push({
      label: "Spendable (total − envelopes)",
      data: spendable,
      borderColor: col,
      backgroundColor: withAlpha(col, "22"),
      borderWidth: spendableImplied ? 2.5 : 2,
      // In spendable-only mode it's the sole line on the chart, so render it
      // solid rather than dotted — the dotted style only earns its keep when
      // overlaid on top of total/per-account lines to distinguish them.
      borderDash: spendableImplied ? [] : [2, 4],
      tension: 0.15,
      fill: spendableImplied ? 'origin' : false,
      pointRadius: dotAt(spendable.length, lowIdx),
      pointBackgroundColor: col,
      pointBorderColor: themeColor("--bg-2", "#141c29"),
      pointBorderWidth: 2,
      pointHoverRadius: 5
    });
  }
  const featuredDatasetIdx = featured ? datasets.length - 1 : -1;
  const lowValue = featured === 'spendable' ? spendable[lowIdx] : featured === 'total' ? total[lowIdx] : null;

  // Axis labels: "16 Sep" rather than a rotated ISO date; the year joins in
  // only when the horizon crosses into another year.
  const spansYears = dates.length > 1 && dates[0].slice(0, 4) !== dates[dates.length - 1].slice(0, 4);
  const axisFmt = new Intl.DateTimeFormat(data?.settings?.locale || DEFAULT_LOCALE,
    spansYears ? { day: 'numeric', month: 'short', year: '2-digit' } : { day: 'numeric', month: 'short' });

  if (currentChart) currentChart.destroy();
  const ctx = document.getElementById("fcChart").getContext("2d");
  currentChart = new Chart(ctx, {
    type: "line",
    data: { labels: dates, datasets },
    options: {
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      scales: {
        y: { ticks: { callback: v => fmt(v).replace(/[^\d\-.,€$]/g,'') },
             grid: { color: themeColor("--chart-grid", "rgba(255,255,255,.05)") } },
        x: { ticks: { maxTicksLimit: 12, maxRotation: 0, autoSkipPadding: 12,
                      callback: function (v) { const iso = this.getLabelForValue(v); return iso ? axisFmt.format(parseDate(iso)) : ''; } },
             grid: { color: themeColor("--chart-grid", "rgba(255,255,255,.05)") } }
      },
      plugins: {
        legend: { position: "bottom" },
        tooltip: { callbacks: {
          title: items => items.length ? fmtDate(items[0].label) : '',
          label: c => `${c.dataset.label}: ${fmt(c.parsed.y)}`
        } }
      }
    },
    plugins: [forecastMarksPlugin({
      featuredDatasetIdx, lowIdx, lowValue, lowDate: lowIdx >= 0 ? dates[lowIdx] : null
    })]
  });

  // Summary table
  const finalIdx = dates.length - 1;
  const rows = liveAccountIds.map(id => {
    const start = series[id][0], end = series[id][finalIdx];
    return `<tr>
      <td>${esc(accountById(id)?.name || '')}</td>
      <td class="num">${fmt(start)}</td>
      <td class="num"><strong>${fmt(end)}</strong></td>
      <td class="num ${end-start>=0?'pos':'neg'}">${end-start>=0?'+':''}${fmt(end-start)}</td>
    </tr>`;
  }).join('');
  const totS = total[0], totE = total[finalIdx];
  const envS = envelopeTotal[0], envE = envelopeTotal[finalIdx];
  const spS = spendable[0], spE = spendable[finalIdx];
  document.getElementById("fcSummary").innerHTML = `
    <table>
      <thead><tr><th>Account</th><th class="num">Today</th><th class="num">${fmtDate(dates[finalIdx])}</th><th class="num">Δ</th></tr></thead>
      <tbody>${rows}
        <tr style="border-top:2px solid var(--border)"><td><strong>Total</strong></td>
          <td class="num"><strong>${fmt(totS)}</strong></td>
          <td class="num"><strong>${fmt(totE)}</strong></td>
          <td class="num ${totE-totS>=0?'pos':'neg'}"><strong>${totE-totS>=0?'+':''}${fmt(totE-totS)}</strong></td>
        </tr>
        <tr style="color:var(--text-dim);"><td>Envelope reservations</td>
          <td class="num">${fmt(envS)}</td>
          <td class="num">${fmt(envE)}</td>
          <td class="num">${envE-envS>=0?'+':''}${fmt(envE-envS)}</td>
        </tr>
        <tr style="color:var(--warn);"><td><strong>Spendable</strong> <span class="help-tip" tabindex="0" title="Account total minus the envelope balances held in the selected accounts — money not yet earmarked for any envelope. YNAB calls this Available-to-Budget. Household envelopes always count; an envelope backed by an account outside this selection is left out, because its money is not in the total either. If you fully assign every euro to an envelope, spendable hits zero. Projected spending draws each envelope down to zero before it starts eating into spendable, so setting money aside is never charged twice.">?</span></td>
          <td class="num"><strong>${fmt(spS)}</strong></td>
          <td class="num"><strong>${fmt(spE)}</strong></td>
          <td class="num ${spE-spS>=0?'pos':'neg'}"><strong>${spE-spS>=0?'+':''}${fmt(spE-spS)}</strong></td>
        </tr>
      </tbody>
    </table>
    ${(excludedEnvelopes || []).length ? `<p class="micro" style="margin:8px 0 0;">
      Not counted here — backed by accounts outside this selection:
      ${excludedEnvelopes.map(x => `<strong>${esc(x.name)}</strong> (${esc(x.accountName)}, ${fmt(x.balance)})`).join(', ')}.
    </p>` : ''}
  `;

  // Allowance breakdown panel
  const allowCard = document.getElementById("fcAllowanceCard");
  const allowDiv = document.getElementById("fcAllowanceBreakdown");
  if (allowCard && allowDiv) {
    if (!forecastState.includeAllowances) {
      allowCard.style.display = "none";
    } else {
      allowCard.style.display = "";
      const inc = allowanceInfo.included || [];
      const skp = allowanceInfo.skipped || [];
      const una = allowanceInfo.unassigned || [];
      const incRows = inc.map(x =>
        `<tr><td>${esc(x.name)}</td><td>${esc(x.accountName)}</td><td class="num">${fmt(x.monthly)}${
          x.covered > 0.005 ? ` <span style="color:var(--text-dim);font-weight:400;font-size:11px;" title="Budget ${fmt(x.monthly + x.covered)} less ${fmt(x.covered)} already modelled by recurring entries">net of ${fmt(x.covered)}</span>` : ''
        }</td></tr>`
      ).join('');
      const skpList = skp.length
        ? `<p style="color:var(--text-dim);font-size:13px;margin:10px 0 0;">
            <strong>Skipped (fully covered by recurring):</strong> ${skp.map(x=>esc(x.name)+' ('+fmt(x.monthly)+')').join(', ')}
          </p>` : '';
      const unaList = una.length
        ? `<p style="color:var(--warn,#f0a64a);font-size:13px;margin:10px 0 0;">
            <strong>Unassigned (spending account not in this selection):</strong> ${una.map(x=>esc(x.name)+' ('+fmt(x.monthly)+')').join(', ')}
          </p>` : '';
      const incTable = inc.length
        ? `<table>
            <thead><tr><th>Envelope</th><th>Spending account</th><th class="num">Monthly</th></tr></thead>
            <tbody>${incRows}
              <tr style="border-top:2px solid var(--border)">
                <td colspan="2"><strong>Total monthly spend projected</strong></td>
                <td class="num"><strong>${fmt(allowanceInfo.totalMonthly)}</strong></td>
              </tr>
            </tbody>
          </table>
          <p style="color:var(--text-dim);font-size:12px;margin-top:8px;">
            Smoothed evenly across each calendar month, so every month drains exactly this much. Amounts
            already modelled by a recurring entry are netted out. The spending account is inferred from the
            most recent expense for each envelope. Each envelope's own balance absorbs this spending first —
            only what it can't cover reduces the spendable line.
          </p>`
        : `<p style="color:var(--text-dim);">No envelope allowances are being added to the projection. Either no envelopes have a monthly budget, or all of them are already covered by recurring transactions.</p>`;
      allowDiv.innerHTML = incTable + skpList + unaList;
    }
  }
}

//=============================================================================
// NET WORTH
//=============================================================================
function renderNetWorth() {
  return `
  <h2>Net worth over time</h2>
  <div class="grid cols-3" style="margin-bottom:14px;">
    <div class="card">
      <div class="stat-label">Current</div>
      <div class="stat">${fmt(totalNetWorth())}</div>
    </div>
    <div class="card">
      <div class="stat-label">Snapshots</div>
      <div class="stat">${data.netWorthSnapshots.length}</div>
      <div class="delta">Updated daily on app open</div>
    </div>
    <div class="card">
      <div class="stat-label">Investments</div>
      <div class="stat" style="color:var(--accent-2)">${fmt(totalInvestments())}</div>
    </div>
  </div>
  <div class="card">
    <div style="height:380px;"><canvas id="nwChart"></canvas></div>
  </div>
  <div class="card" style="margin-top:14px;">
    <h3>Manual snapshot</h3>
    <p style="color:var(--text-dim);">A snapshot is captured automatically each day. Use this to add a snapshot for a past date (useful for seeding history).</p>
    <div class="field-row">
      <div class="field"><label>Date</label><input type="date" id="nw_date" value="${todayISO()}"></div>
      <div class="field"><label>Net worth value</label><input type="number" step="0.01" id="nw_val"></div>
    </div>
    <button class="btn primary" id="nw_add">Add / replace snapshot</button>
  </div>
  `;
}
function bindNetWorth() {
  drawNetWorth();
  document.getElementById("nw_add").onclick = () => {
    const d = document.getElementById("nw_date").value;
    const v = parseFloat(document.getElementById("nw_val").value);
    if (!d || isNaN(v)) { toast("Date and value required"); return; }
    const ix = data.netWorthSnapshots.findIndex(s => s.date === d);
    if (ix >= 0) data.netWorthSnapshots[ix].value = v;
    else data.netWorthSnapshots.push({ date: d, value: v });
    data.netWorthSnapshots.sort((a,b) => a.date.localeCompare(b.date));
    saveDirty(); render(); toast("Snapshot saved");
  };
}
function drawNetWorth() {
  const snaps = data.netWorthSnapshots;
  if (currentChart) currentChart.destroy();
  const ctx = document.getElementById("nwChart").getContext("2d");
  currentChart = new Chart(ctx, {
    type: "line",
    data: {
      labels: snaps.map(s => s.date),
      datasets: [{
        label: "Net worth",
        data: snaps.map(s => s.value),
        borderColor: themeColor("--accent", "#4fc3a1"),
        backgroundColor: themeColor("--accent", "#4fc3a1") + "33",
        fill: true, tension: 0.2, pointRadius: 0
      }]
    },
    options: {
      maintainAspectRatio: false,
      scales: {
        y: { ticks: { callback: v => fmt(v).replace(/[^\d\-.,€$]/g,'') },
             grid: { color: themeColor("--chart-grid", "rgba(255,255,255,.05)") } },
        x: { ticks: { maxTicksLimit: 12 }, grid: { color: themeColor("--chart-grid", "rgba(255,255,255,.05)") } }
      },
      plugins: {
        legend: { display: false },
        tooltip: { callbacks: { label: c => fmt(c.parsed.y) } }
      }
    }
  });
}

//=============================================================================
// REPORTS
//=============================================================================
// Filter out non-cashflow txns from Income/Expense reporting:
//   accountId === null   -> envelope refill / Fund-the-month / close-out adjustment
//                           (envelope-only allocation, no real money in/out)
//   payee "Market adjustment" -> investment account revaluation (not real income/expense)
function isCashflowTx(tx) {
  if (tx.accountId == null) return false;
  if (tx.payee === 'Market adjustment') return false;
  return true;
}

// Reports cashflow (12 months) + by-envelope spend (30 days) in ONE pass over
// data.transactions. Returns months with both label variants (the table wants
// the year, the chart axis doesn't). renderReports stashes the result in
// _reportsAgg so bindReports — which runs immediately after — reuses it instead
// of re-scanning; together they now scan the tx list once, not four times.
let _reportsAgg = null;
function reportsAggregates() {
  const today = parseDate(todayISO());
  const months = [];
  for (let i = 11; i >= 0; i--) {
    const d = addMonths(today, -i);
    months.push({ key: `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`,
      labelLong: d.toLocaleDateString('en', { month: 'short', year: '2-digit' }),
      labelShort: d.toLocaleDateString('en', { month: 'short' }),
      income: 0, expense: 0, byTag: {} });
  }
  const cutoff = isoDate(addDays(today, -30));
  const byEnv = {};
  const byTag = {};
  // What the tag reports count: real expenses (isCashflowTx) plus TAGGED
  // account transfers, as outflow. A tagged transfer is money leaving for a
  // purpose — savings contributions, loan repayments, reimbursable petty cash
  // — which is exactly what those tags exist for. An untagged transfer stays
  // internal movement and is ignored. Key '' = untagged expense.
  const tagOutflow = tx => (tx.type === 'expense' && isCashflowTx(tx)) || (tx.type === 'transfer-account' && tx.tag);
  for (const tx of data.transactions) {
    if (isCashflowTx(tx)) {
      const m = months.find(x => x.key === tx.date.slice(0, 7));
      if (m) {
        if (tx.type === 'income') m.income += tx.amount;
        else if (tx.type === 'expense') m.expense += tx.amount;
      }
    }
    if (tagOutflow(tx)) {
      const k = tx.tag || '';
      const m = months.find(x => x.key === tx.date.slice(0, 7));
      if (m) m.byTag[k] = (m.byTag[k] || 0) + tx.amount;
      if (tx.date >= cutoff) byTag[k] = (byTag[k] || 0) + tx.amount;
    }
    // isCashflowTx guards this branch too, not just the 12-month totals above.
    // Envelope bookkeeping — "Return to spendable", "Close-out adjustment",
    // "Adjust current balance" — books a one-sided expense (envelopeId set,
    // accountId null) that moves no real money. Counting those as spending put
    // a 120 return + an 80 close-out reset into this chart alongside a 45
    // supermarket run and reported 245 spent on the envelope.
    if (tx.type === 'expense' && tx.date >= cutoff && isCashflowTx(tx)) {
      if (tx.splits && tx.splits.length) {
        for (const sp of tx.splits) if (sp.envelopeId) byEnv[sp.envelopeId] = (byEnv[sp.envelopeId] || 0) + Math.abs(sp.amount || 0);
      } else if (tx.envelopeId) {
        byEnv[tx.envelopeId] = (byEnv[tx.envelopeId] || 0) + tx.amount;
      }
    }
  }
  const envSpend = Object.entries(byEnv)
    .map(([id, amt]) => ({ name: envelopeById(id)?.name || '?', amt }))
    .sort((a,b) => b.amt - a.amt);
  // Slice colour = chip colour (tagColor); a stray tag gets the border grey,
  // "Untagged" the reserved --text-dim.
  const tagSpend = Object.entries(byTag)
    .map(([t, amt]) => ({ name: t || 'Untagged', amt,
      color: t ? (tagColor(t) || themeColor('--border', '#3a3f4b')) : themeColor('--text-dim', '#abb2bf') }))
    .sort((a,b) => b.amt - a.amt);
  // Table columns: only tags that carry any outflow in the window. An Income
  // tag, say, is legitimately always empty here and would just add width.
  const tagCols = allTags().filter(t => months.some(m => m.byTag[t]));
  const anyTagged = months.some(m => Object.keys(m.byTag).some(k => k));
  return { months, envSpend, tagSpend, tagCols, anyTagged };
}

// Budget vs actual for one calendar month — the standard envelope report,
// which until now existed only inside the close-out dialog. Same figures as
// close-out (envelopeMonthSummary: spent is split-aware and excludes one-sided
// bookkeeping; funded includes refills and incoming envelope transfers), so
// the two can't disagree. Rows sort most-over-budget first.
function budgetVsActualHTML(ym) {
  const rows = data.envelopes.map(env => {
    const s = envelopeMonthSummary(env, ym);
    const budget = envMonthlyEquiv(env);
    return { env, ...s, budget, variance: s.spent - budget };
  }).filter(r => !r.env.archived || Math.abs(r.spent) >= 0.005 || Math.abs(r.funded) >= 0.005)   // archived: only months it was still in use
    .sort((a, b) => b.variance - a.variance);
  if (!rows.length) return '<p style="color:var(--text-dim);">No envelopes yet.</p>';
  const tot = rows.reduce((t, r) => ({ budget: t.budget + r.budget, spent: t.spent + r.spent, funded: t.funded + r.funded, balance: t.balance + r.balance }), { budget: 0, spent: 0, funded: 0, balance: 0 });
  const varCell = v => Math.abs(v) < 0.005 ? '<span style="color:var(--text-dim);">—</span>' : `<span class="${v > 0 ? 'neg' : 'pos'}">${v > 0 ? '+' : ''}${fmt(v)}</span>`;
  return `<table>
    <thead><tr><th>Envelope</th><th class="num">Budget</th><th class="num">Spent</th><th class="num">Funded</th><th class="num">Over / under <span class="help-tip" tabindex="0" title="Spent minus budget for the month. Positive (red) = over budget. Annual envelopes count 1/12 of their yearly target as the month's budget.">?</span></th><th class="num">Balance at month end</th></tr></thead>
    <tbody>
      ${rows.map(r => `<tr>
        <td><a href="#" class="drill" data-tx-env="${r.env.id}" title="Show this envelope's transactions">${esc(r.env.name)}</a>${r.env.cadence === 'annual' ? ' <span class="badge">annual</span>' : ''}${r.env.isReserve ? ' <span class="badge">reserve</span>' : ''}${r.env.archived ? ' <span class="badge">archived</span>' : ''}</td>
        <td class="num" style="color:var(--text-dim);">${fmt(r.budget)}</td>
        <td class="num">${fmt(r.spent)}</td>
        <td class="num" style="color:var(--text-dim);">${fmt(r.funded)}</td>
        <td class="num">${varCell(r.variance)}</td>
        <td class="num ${r.balance < 0 ? 'neg' : ''}">${fmt(r.balance)}</td>
      </tr>`).join('')}
      <tr style="border-top:2px solid var(--border);"><td><strong>Total</strong></td>
        <td class="num"><strong>${fmt(tot.budget)}</strong></td>
        <td class="num"><strong>${fmt(tot.spent)}</strong></td>
        <td class="num"><strong>${fmt(tot.funded)}</strong></td>
        <td class="num"><strong>${varCell(tot.spent - tot.budget)}</strong></td>
        <td class="num ${tot.balance < 0 ? 'neg' : ''}"><strong>${fmt(tot.balance)}</strong></td>
      </tr>
    </tbody>
  </table>`;
}

function renderReports() {
  const agg = reportsAggregates();
  _reportsAgg = agg;                 // shared with bindReports (runs right after)
  const { months, envSpend, tagSpend, tagCols, anyTagged } = agg;
  const showTags = tagList().length > 0 || anyTagged;
  const cell = v => v ? fmt(v) : '<span style="color:var(--text-dim);">—</span>';
  const bvaMonth = todayISO().slice(0, 7);

  return `
  <h2>Reports</h2>
  <div class="grid cols-2">
    <div class="card" style="grid-column:1/-1;">
      <div style="display:flex;align-items:baseline;justify-content:space-between;gap:12px;flex-wrap:wrap;">
        <h3 style="margin:0 0 10px;">Budget vs actual</h3>
        <label style="display:flex;gap:8px;align-items:center;font-size:13px;color:var(--text-dim);">Month
          <input type="month" id="rpBvaMonth" value="${bvaMonth}" style="background:var(--bg-3);color:var(--text);border:1px solid var(--border);border-radius:6px;padding:5px 8px;"></label>
      </div>
      <div style="overflow:auto;" id="rpBvaTable">${budgetVsActualHTML(bvaMonth)}</div>
    </div>
    <div class="card">
      <h3>Income vs expense (12 months)</h3>
      <div style="height:280px;"><canvas id="rpCash"></canvas></div>
    </div>
    <div class="card">
      <h3>Spending by envelope (30 days)</h3>
      ${envSpend.length === 0 ? '<p style="color:var(--text-dim);">No expense transactions in last 30 days.</p>' :
        `<div style="height:280px;"><canvas id="rpEnv"></canvas></div>`}
    </div>
    ${showTags ? `
    <div class="card">
      <h3>Spending by tag (30 days)</h3>
      ${tagSpend.length === 0 ? '<p style="color:var(--text-dim);">No expense transactions in last 30 days.</p>' :
        `<div style="height:280px;"><canvas id="rpTag"></canvas></div>`}
    </div>
    <div class="card" style="grid-column:1/-1;">
      <h3>Expenses by tag (12 months)</h3>
      <div style="overflow:auto;"><table>
        <thead><tr><th>Month</th>${tagCols.map(t => `<th class="num">${tagChip(t)}</th>`).join('')}<th class="num">Untagged</th><th class="num">Total</th></tr></thead>
        <tbody>
          ${months.map(m => `<tr>
            <td>${m.labelLong}</td>
            ${tagCols.map(t => `<td class="num">${cell(m.byTag[t])}</td>`).join('')}
            <td class="num">${cell(m.byTag[''])}</td>
            <td class="num"><strong>${fmt(Object.values(m.byTag).reduce((s, v) => s + v, 0))}</strong></td>
          </tr>`).join('')}
        </tbody>
      </table></div>
      <p class="micro" style="margin:8px 0 0;">Expenses, plus account transfers that carry a tag (counted as money leaving for that purpose). Untagged transfers and envelope bookkeeping are excluded.</p>
    </div>` : ''}
    <div class="card" style="grid-column:1/-1;">
      <h3>Cash-flow detail</h3>
      <table>
        <thead><tr><th>Month</th><th class="num">Income</th><th class="num">Expense</th><th class="num">Net</th></tr></thead>
        <tbody>
          ${months.map(m => `<tr>
            <td>${m.labelLong}</td>
            <td class="num pos">+${fmt(m.income)}</td>
            <td class="num neg">-${fmt(m.expense)}</td>
            <td class="num ${m.income-m.expense>=0?'pos':'neg'}">
              <strong>${m.income-m.expense>=0?'+':''}${fmt(m.income-m.expense)}</strong></td>
          </tr>`).join('')}
        </tbody>
      </table>
    </div>
  </div>
  `;
}
function bindReports() {
  // Reuse the single-scan aggregates renderReports just computed.
  const { months, envSpend, tagSpend } = _reportsAgg || reportsAggregates();

  const bvaIn = document.getElementById("rpBvaMonth");
  if (bvaIn) bvaIn.onchange = () => {
    if (!bvaIn.value) return;
    document.getElementById("rpBvaTable").innerHTML = budgetVsActualHTML(bvaIn.value);
    wireDrillLinks();
  };
  wireDrillLinks();

  if (currentChart) currentChart.destroy();
  const ctx = document.getElementById("rpCash").getContext("2d");
  currentChart = new Chart(ctx, {
    type: "bar",
    data: {
      labels: months.map(m => m.labelShort),
      datasets: [
        { label: "Income", data: months.map(m => m.income), backgroundColor: themeColor("--good", "#56d364") + "88" },
        { label: "Expense", data: months.map(m => m.expense), backgroundColor: themeColor("--bad", "#e06c75") + "88" }
      ]
    },
    options: {
      maintainAspectRatio: false,
      scales: {
        y: { ticks: { callback: v => fmt(v).replace(/[^\d\-.,€$]/g,'') },
             grid: { color: themeColor("--chart-grid", "rgba(255,255,255,.05)") } },
        x: { grid: { color: themeColor("--chart-grid", "rgba(255,255,255,.05)") } }
      },
      plugins: { legend: { position: "bottom" } }
    }
  });

  // Doughnuts go through reportCharts so render() can destroy them (they
  // used to leak one instance per Reports visit).
  const doughnut = (canvas, labels, values, colors) => {
    if (!canvas) return;
    reportCharts.push(new Chart(canvas.getContext("2d"), {
      type: "doughnut",
      data: { labels, datasets: [{ data: values, backgroundColor: colors }] },
      options: {
        maintainAspectRatio: false,
        plugins: {
          legend: { position: "right", labels: { boxWidth: 12 } },
          tooltip: { callbacks: { label: c => `${c.label}: ${fmt(c.parsed)}` } }
        }
      }
    }));
  };
  // envelope pie — envSpend already computed in the shared aggregates above.
  const colors = [...chartPalette(), themeColor("--good", "#56d364")];
  doughnut(document.getElementById("rpEnv"), envSpend.map(x => x.name), envSpend.map(x => x.amt),
    envSpend.map((_,i) => colors[i%colors.length]));
  // tag pie — each slice carries the colour its chip uses.
  doughnut(document.getElementById("rpTag"), tagSpend.map(x => x.name), tagSpend.map(x => x.amt),
    tagSpend.map(x => x.color));
}

//=============================================================================
// SETTINGS
//=============================================================================
function renderBackupList() {
  const items = listBackups();
  if (!items.length) {
    return '<p style="color:var(--text-dim);margin:0;">No backups yet — one will be created on the next save.</p>';
  }
  const today = todayISO();
  // Show newest first in the UI; listBackups returns oldest first.
  return items.slice().reverse().map(({ date, size }) => {
    const kb = (size / 1024).toFixed(1);
    const tag = date === today ? ' <span class="pill">today</span>' : '';
    return `<div class="setting-row">
      <div><div class="label">${date}${tag}</div>
        <div class="desc">${kb} KB</div></div>
      <div style="display:flex;gap:6px;flex-wrap:wrap;">
        <button class="btn" data-bak-restore="${date}">Restore</button>
        <button class="btn ghost" data-bak-download="${date}">Download</button>
        <button class="btn ghost" data-bak-delete="${date}" aria-label="Delete backup ${date}">×</button>
      </div>
    </div>`;
  }).join('');
}
function renderTagList() {
  const list = tagList();
  if (!list.length) {
    return '<p style="color:var(--text-dim);margin:0;">No tags yet. Add a few — "Fixed costs", "Lifestyle", "Work" — and each transaction can carry one.</p>';
  }
  return list.map(t => {
    const u = tagUsage(t);
    // Names go into data-* attributes, so esc() them; dataset reads them back decoded.
    return `<div class="setting-row">
      <div><div class="label">${tagChip(t)}</div>
        <div class="desc">${plural(u.tx, 'transaction')} · ${plural(u.rec, 'recurring entry', 'recurring entries')}</div></div>
      <div style="display:flex;gap:6px;flex-wrap:wrap;">
        <button class="btn" data-tag-rename="${esc(t)}">Rename</button>
        <button class="btn ghost" data-tag-delete="${esc(t)}" aria-label="Delete tag ${esc(t)}">×</button>
      </div>
    </div>`;
  }).join('');
}
function renderSettings() {
  return `
  <h2>Settings</h2>
  <div class="card">
    <div class="setting-row">
      <div><div class="label">Currency</div>
        <div class="desc">All values displayed in this currency.</div></div>
      <input id="s_curr" value="${esc(data.settings.currency)}" style="width:80px;text-align:center;">
    </div>
    <div class="setting-row">
      <div><div class="label">Locale (number formatting)</div>
        <div class="desc">e.g. en-US for 1,234.56, de-DE or el-GR for 1.234,56</div></div>
      <input id="s_loc" value="${esc(data.settings.locale)}" style="width:120px;text-align:center;">
    </div>
    <div class="setting-row">
      <div><div class="label">Forecast warning floor</div>
        <div class="desc">The dashboard's "lowest in period" tile turns amber when the projected low dips under this amount, and red when it goes below zero. Leave empty for red-only.</div></div>
      <input id="s_fcfloor" type="text" inputmode="decimal" value="${typeof data.settings.forecastWarnBelow === 'number' ? data.settings.forecastWarnBelow : ''}" placeholder="none" style="width:120px;text-align:right;">
    </div>
    <div class="setting-row">
      <div><div class="label">Theme</div></div>
      <select id="s_theme">
        <option value="auto" ${(data.settings.theme||'auto')==='auto'?'selected':''}>Auto (system)</option>
        <option value="dark" ${data.settings.theme==='dark'?'selected':''}>Dark</option>
        <option value="light" ${data.settings.theme==='light'?'selected':''}>Light</option>
      </select>
    </div>
  </div>
  <div class="card" style="margin-top:14px;">
    <h3>Tags</h3>
    <p style="color:var(--text-dim);">One optional tag per transaction, for filtering the Transactions tab and the by-tag reports. Envelopes say what the money was for; tags are for the cross-cutting view (committed vs discretionary, work vs household). Up to ${TAG_LIMIT}.</p>
    <div id="tagList">${renderTagList()}</div>
    <button class="btn" id="btnAddTag" style="margin-top:8px;" ${tagList().length >= TAG_LIMIT ? `disabled title="Limit of ${TAG_LIMIT} tags reached"` : ''}>+ Add tag</button>
  </div>
  <div class="card" style="margin-top:14px;">
    <h3>Data file</h3>
    <p style="color:var(--text-dim);">Your data is stored server-side in
      <strong>finance-data.json</strong>, next to <code>serve.py</code> on the machine
      serving this page (status: <strong>${esc(document.getElementById("fileLabel").textContent)}</strong>).
      Auto-saves about a second after every change, and every device that opens this
      address reads and writes that one file. The server keeps the previous five
      versions as <code>finance-data.bak.0</code> … <code>.bak.4</code>.</p>
    <div style="display:flex;gap:8px;flex-wrap:wrap;">
      <button class="btn" id="btnExport">Export JSON</button>
      <button class="btn" id="btnImport">Import JSON</button>
    </div>
  </div>
  <div class="card" style="margin-top:14px;">
    <h3>Backups</h3>
    <p style="color:var(--text-dim);">
      Daily snapshots in browser storage. Up to ${BACKUP_SLOTS} slots; after a week
      of saves the oldest is overwritten. Independent of your data file — restore
      from here if the file is lost, corrupt, or you want to roll back a bad edit.
      Note: backups live in browser storage, so clearing site data wipes them.
    </p>
    <div id="backupList" style="margin-top:8px;">${renderBackupList()}</div>
  </div>
  <div class="card" style="margin-top:14px;">
    <h3>Envelope close-out</h3>
    <p style="color:var(--text-dim);">
      Last closed month: <strong style="color:var(--text);">${data.lastClosedMonth || '—'}</strong>.
      Re-open the close-out review for last month (or any prior month) to apply
      rollover/reset decisions.
    </p>
    <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center;">
      <button class="btn" id="btnCloseOut">Review last month</button>
      <input type="month" id="s_co_month" value="${prevMonthKey(todayISO())}" style="background:var(--bg-3);color:var(--text);border:1px solid var(--border);border-radius:6px;padding:6px 8px;">
      <button class="btn" id="btnCloseOutMonth">Review picked month</button>
    </div>
  </div>
  <div class="card" style="margin-top:14px;">
    <h3>Stats</h3>
    <p style="color:var(--text-dim);">
      ${data.accounts.length} accounts · ${data.envelopes.length} envelopes ·
      ${data.transactions.length} transactions · ${data.recurring.length} recurring ·
      ${data.netWorthSnapshots.length} net-worth snapshots
    </p>
  </div>
  <div class="card" style="margin-top:14px;border-color:var(--bad);">
    <h3 style="color:var(--bad);">Danger zone</h3>
    <button class="btn danger" id="btnReset">Reset all data</button>
  </div>
  `;
}
function bindSettings() {
  document.getElementById("s_curr").onchange = e => { data.settings.currency = e.target.value || "EUR"; saveDirty(); render(); };
  document.getElementById("s_loc").onchange = e => { data.settings.locale = e.target.value || DEFAULT_LOCALE; saveDirty(); render(); };
  document.getElementById("s_fcfloor").onchange = e => {
    const raw = e.target.value.trim();
    if (!raw) { delete data.settings.forecastWarnBelow; saveDirty(); render(); return; }
    const v = evalAmount(raw);
    if (isNaN(v) || v < 0) { toast("Warning floor: enter a non-negative amount, or leave it empty", 3500, 'error'); e.target.value = typeof data.settings.forecastWarnBelow === 'number' ? data.settings.forecastWarnBelow : ''; return; }
    data.settings.forecastWarnBelow = Math.round(v * 100) / 100;
    saveDirty(); render();
  };
  document.getElementById("s_theme").onchange = e => {
    data.settings.theme = e.target.value;   // 'auto' | 'dark' | 'light'
    applyTheme();
    updateThemeButton();
    saveDirty();
    render();
  };
  document.getElementById("btnExport").onclick = exportFile;
  document.getElementById("btnImport").onclick = importViaInput;
  document.getElementById("btnCloseOut").onclick = () => showCloseOut(prevMonthKey(todayISO()));
  document.getElementById("btnCloseOutMonth").onclick = () => {
    const v = document.getElementById("s_co_month").value; // YYYY-MM
    if (!v) { toast("Pick a month first"); return; }
    showCloseOut(v);
  };
  // Backup row buttons — delegate from the container so we don't re-bind
  // every time a slot changes.
  const bakList = document.getElementById("backupList");
  if (bakList) {
    bakList.addEventListener("click", e => {
      const btn = e.target.closest("button[data-bak-restore],button[data-bak-download],button[data-bak-delete]");
      if (!btn) return;
      const d = btn.dataset.bakRestore || btn.dataset.bakDownload || btn.dataset.bakDelete;
      if (btn.dataset.bakRestore) {
        if (!confirm(`Restore backup from ${d}? Current state goes onto the undo stack — Ctrl-Z to revert.`)) return;
        restoreBackup(d);
      } else if (btn.dataset.bakDownload) {
        downloadBackup(d);
      } else if (btn.dataset.bakDelete) {
        if (!confirm(`Delete backup from ${d}?`)) return;
        deleteBackup(d);
        document.getElementById("backupList").innerHTML = renderBackupList();
      }
    });
  }
  // Tag list — same delegated pattern as the backups. Add is not undoable
  // (nothing is lost); rename and delete cascade over transactions and
  // recurring entries, so both snapshot first.
  const tagListEl = document.getElementById("tagList");
  if (tagListEl) {
    tagListEl.addEventListener("click", e => {
      const btn = e.target.closest("button[data-tag-rename],button[data-tag-delete]");
      if (!btn) return;
      if (btn.dataset.tagRename !== undefined) {
        const old = btn.dataset.tagRename;
        const name = (prompt("Rename tag:", old) || "").trim();
        if (!name || name === old) return;
        const err = validateTagName(name, old);
        if (err) { toast(err, 3000, 'error'); return; }
        const u = tagUsage(old);
        pushUndo('Rename tag');
        renameTag(old, name);
        saveDirty(); render();
        toast(`Renamed "${old}" to "${name}" on ${plural(u.tx, 'transaction')} and ${plural(u.rec, 'recurring entry', 'recurring entries')}`, 3000, 'success');
      } else {
        const name = btn.dataset.tagDelete;
        const u = tagUsage(name);
        if (!confirm(`Delete tag "${name}"? ${plural(u.tx, 'transaction')} and ${plural(u.rec, 'recurring entry', 'recurring entries')} will become untagged.`)) return;
        pushUndo('Delete tag');
        deleteTag(name);
        saveDirty(); render();
        toast(`Deleted tag "${name}" (Ctrl+Z to undo)`, 4000, 'info', { label: 'Undo', onClick: performUndo });
      }
    });
  }
  document.getElementById("btnAddTag").onclick = () => {
    if (tagList().length >= TAG_LIMIT) { toast(`Limit of ${TAG_LIMIT} tags reached`, 3000, 'error'); return; }
    const name = (prompt("New tag name:") || "").trim();
    if (!name) return;
    const err = validateTagName(name);
    if (err) { toast(err, 3000, 'error'); return; }
    data.settings.tags.push(name);
    saveDirty(); render();
  };
  document.getElementById("btnReset").onclick = () => {
    if (!confirm("This will erase ALL data in the current file. Continue?")) return;
    if (!confirm("Are you absolutely sure? (Ctrl+Z restores it until you reload.)")) return;
    pushUndo('Reset all data');
    data = emptyData();
    saveDirty(); render();
    toast('All data reset', 6000, 'info', { label: 'Undo', onClick: performUndo });
  };
}

//=============================================================================
// HELP
//=============================================================================
// In-app reference for concepts, workflows, shortcuts, and an FAQ. Kept
// intentionally short — the README covers setup; this tab covers day-to-day
// "how does X work". FAQ items use native <details>/<summary> so no JS is
// needed to make them collapsible.
function renderHelp() {
  return `
  <h2>Help</h2>
  <div class="help">
    <p class="help-lead">A quick reference to how the app thinks. The README covers installation and first-run setup; this page covers concepts, workflows, and answers to questions that come up while you're using it.</p>

    <h3>Concepts</h3>
    <dl>
      <dt>Account</dt>
      <dd>A real-money holder — checking, savings, credit card, cash, investment, loan. Its balance changes only when a transaction is recorded against it.</dd>
      <dt>Envelope</dt>
      <dd>A virtual bucket you allocate money to for a specific spending category. Envelopes don't hold real cash — they're a claim against your accounts' total.</dd>
      <dt>Tag</dt>
      <dd>An optional label on any transaction (transfers included), chosen from a short list you define in Settings. Envelopes say <em>what</em> the money was for; tags give a cross-cutting view — committed vs discretionary, work vs household. The Transactions tab filters by tag, Reports breaks spending down by tag, and a recurring entry's tag is copied onto every transaction it generates.</dd>
      <dt>Split transaction</dt>
      <dd>One expense allocated across several envelopes (a supermarket run that was part groceries, part household). The account is debited once; only the envelope side splits, and the parts must add up to the total.</dd>
      <dt>Cadence</dt>
      <dd>Envelopes are either <strong>monthly</strong> (e.g. groceries, fuel) or <strong>annual</strong> (e.g. vacation, insurance). Annual envelopes still contribute to monthly burn-rate calculations as <em>amount / 12</em>.</dd>
      <dt>Rollover vs. reset</dt>
      <dd>Monthly envelopes can <strong>rollover</strong> (leftover carries to next month), <strong>reset</strong> (leftover returns to spendable cash at month close-out), or <strong>sweep</strong> (leftover moves into the reserve envelope at close-out). Annual envelopes always rollover.</dd>
      <dt>Total balance</dt>
      <dd>The sum of your accounts' real balances. This is the actual money you have.</dd>
      <dt>Spendable cash</dt>
      <dd>Total balance minus the sum of your envelope balances. This is the money <em>not yet claimed</em> by any envelope — what's free to allocate or spend on uncategorised things. When a forecast selects only some accounts, only the envelopes those accounts hold are subtracted: each envelope can name the account it is <strong>backed by</strong> (envelope dialog); one that names none is household-wide and counts everywhere.</dd>
      <dt>Allowances</dt>
      <dd>A forecasting smoothing option: subtract each envelope's monthly equivalent from accounts daily, simulating the intent to spend the budget evenly over time. Toggled on the Forecast tab.</dd>
      <dt>Headroom / "lowest in period"</dt>
      <dd>The lowest projected balance over your chosen forecast horizon — the constraint that tells you the maximum you can safely allocate today without driving the forecast underwater. Shown on the Dashboard and used by Fund-the-month.</dd>
    </dl>

    <h3>Workflows</h3>

    <p><strong>First-time setup.</strong> Add your accounts (Accounts tab), create envelopes grouped by category (Envelopes tab), set up recurring transactions for income and fixed bills (Recurring tab), then click <strong>Fund the month</strong> on the Envelopes tab to allocate the current month's budgets.</p>

    <p><strong>Funding the month.</strong> On the Envelopes tab, click <strong>Fund the month</strong>. The dialog shows your projected lowest balance and the maximum safe to allocate today. Enter funding amounts per envelope — the live preview updates the post-funding lowest point as you type. A soft confirm prompts you if you try to over-allocate.</p>

    <p><strong>Monthly close-out.</strong> At the start of each new month, the Dashboard shows a "Close out [last month]" banner. Click <strong>Review</strong> to walk through each envelope's leftover balance and pick rollover, reset or sweep. Reset envelopes return their leftover to spendable cash; rollover envelopes carry it forward; sweep moves it into the reserve envelope. If you have a reserve envelope, a "Set all" row lets you sweep every envelope's leftover in one click.</p>

    <p><strong>Logging a one-off transaction.</strong> Press <kbd>N</kbd> from anywhere, or use <strong>+ Add transaction</strong> on the Transactions tab. Pick a type (expense, income, transfer-account, transfer-envelope), an account, optionally an envelope, and an amount.</p>

    <p><strong>Applying recurring entries.</strong> When recurring entries are due, the Dashboard shows a banner with the count and a net total. Click <strong>Apply</strong> to record them all, or <strong>Review</strong> to untick or adjust amounts before applying.</p>

    <h3>Tabs at a glance</h3>
    <dl>
      <dt>Dashboard</dt>
      <dd>Net worth, forecast horizons, upcoming entries, lowest envelopes, pinned accounts, and recent transactions.</dd>
      <dt>Accounts</dt>
      <dd>Manage real-money accounts. Pin to dashboard with the 📌 icon, drag rows to reorder.</dd>
      <dt>Envelopes</dt>
      <dd>Virtual buckets grouped by category. <strong>Fund the month</strong> tops them all up at once; each envelope also has <strong>Spend</strong>, <strong>Fund</strong> (this one only) and <strong>↩ Return</strong> (un-earmark to spendable). <strong>Move funds</strong> shifts money envelope-to-envelope.</dd>
      <dt>Transactions</dt>
      <dd>Every recorded movement: expenses, income, account-to-account transfers, envelope-to-envelope transfers. Searchable and filterable by type, account, envelope and tag. An expense can be <strong>split</strong> across several envelopes, and <strong>⤓ Import CSV</strong> brings in a bank statement through a column-mapping wizard (mappings save as named profiles), with duplicate detection and a review step before anything is recorded.</dd>
      <dt>Recurring</dt>
      <dd>Templates for repeating entries (salary, rent, subscriptions). The app reminds you when occurrences are due rather than auto-applying them.</dd>
      <dt>Forecast</dt>
      <dd>Projects account and spendable balances 1 week to 2 years forward. Save view configurations as profiles for quick switching.</dd>
      <dt>Net Worth</dt>
      <dd>Historical net-worth chart. One snapshot is captured automatically per day (today's value updates as balances change); use Manual snapshot to backfill past dates.</dd>
      <dt>Reports</dt>
      <dd>Monthly cashflow (last 12 months), spending by envelope and by tag (last 30 days), and a month-by-tag table for the last 12 months.</dd>
      <dt>Settings</dt>
      <dd>Currency, locale, theme, the tag list, import/export of the whole budget as JSON, rolling daily backups (restore/download), manual envelope close-out, and a danger-zone full reset.</dd>
    </dl>

    <h3>Keyboard shortcuts</h3>
    <dl>
      <dt><kbd>N</kbd></dt>
      <dd>New transaction. Works anywhere when no input is focused and no modal is open.</dd>
      <dt><kbd>C</kbd></dt>
      <dd>Copy the transaction in the hovered row — handy on the Transactions tab and the Dashboard's recent-transactions table. Opens the editor pre-filled with the copied values so you can quickly log a similar one.</dd>
      <dt><kbd>Ctrl</kbd>/<kbd>⌘</kbd>+<kbd>Z</kbd></dt>
      <dd>Undo the last destructive change — delete, add/edit transaction, apply-recurring, close-out, or backup restore. Snapshot-based and in-memory, so it clears on reload. An Undo button also appears in the toast after a delete.</dd>
      <dt><kbd>Ctrl</kbd>/<kbd>⌘</kbd>+<kbd>K</kbd></dt>
      <dd>Command palette — jump to any tab or run any action (add, fund, transfer, import, close out, undo…) by typing a few letters.</dd>
      <dt><kbd>?</kbd></dt>
      <dd>Show the keyboard cheatsheet (works even before a file is loaded).</dd>
      <dt><kbd>Esc</kbd></dt>
      <dd>Close any open dialog.</dd>
    </dl>

    <h3>FAQ</h3>

    <details class="faq"><summary>Why doesn't my forecast match my actual balance after I fund an envelope?</summary>
    <div>Funding an envelope doesn't move real cash — it just earmarks part of your existing balance for a category. Your total balance stays the same; your <em>spendable cash</em> (total minus envelope balances) goes down, though not always one-for-one: funding an overspent envelope first fills its hole, and money put into an envelope with a monthly allowance gets spent from that envelope before it ever touches spendable. "Fund the month" re-runs the forecast with your proposal applied so you see the real effect. On the Forecast tab, toggle "spendable cash" to see the line that reflects funding effects.</div>
    </details>

    <details class="faq"><summary>What's the difference between rollover and reset envelopes?</summary>
    <div>At month close-out, a <strong>rollover</strong> envelope keeps its leftover balance — useful for irregular expenses like car maintenance where unspent money should stay reserved. A <strong>reset</strong> envelope's leftover returns to spendable cash at close-out — useful for "use it or lose it" categories like fun money or groceries where you don't want unspent budget to accumulate. A <strong>sweep</strong> envelope's leftover moves into the reserve envelope instead, so it stays set aside rather than going back into circulation. Annual envelopes always rollover regardless of policy.</div>
    </details>

    <details class="faq"><summary>How do I retire an account or envelope I no longer use?</summary>
    <div><strong>Archive</strong> it (the button on the Accounts row or the envelope card). Deleting is refused while any transaction still points at the record, and that is deliberate: dropping it would orphan history or destroy it. Archiving keeps every transaction and every figure — an archived account still counts in balances and net worth, an archived envelope keeps its balance earmarked — and only takes the record out of the way: out of the lists, the pickers, the dashboard strip and the forecast's account selection. An archived envelope also has <em>no budget</em> any more, so it drops out of Fund the month, close-out, the monthly totals and the forecast's allowances; if it still holds money you want back, click <strong>↩ Return</strong> first. Archived records sit in a collapsed list at the bottom of their tab with an <strong>Unarchive</strong> button, and Reports still shows an archived envelope for any month it was in use. You cannot archive the reserve envelope, or anything an <em>active</em> recurring entry still posts to — deactivate or reassign that first. Editing an old transaction still offers its archived account or envelope, marked "(archived)", so re-saving never loses it.</div>
    </details>

    <details class="faq"><summary>What does "Backed by account" do?</summary>
    <div>It tells the forecast which account holds an envelope's money. Nothing changes while a forecast selects all your cash accounts. But a per-person forecast profile — one partner's accounts only — used to subtract <em>every</em> envelope from that partner's total, including envelopes funded from the other partner's account, so spendable came out too low and <strong>Fund the month</strong> warned against money that was there. Set <strong>Backed by</strong> on each envelope and a filtered forecast subtracts only the envelopes its accounts hold, and drains each allowance from the right account; the summary table lists what it left out. <strong>Household</strong> (the default) keeps the old behaviour for that envelope. The field is advisory: moving money between two envelopes backed by different accounts does not move cash between the accounts, so keep the backing in step with where the money really sits. A reserve envelope is always household-wide.</div>
    </details>

    <details class="faq"><summary>What is a reserve envelope?</summary>
    <div>Tick <strong>Reserve envelope (emergency / catch-all)</strong> when editing an envelope to make it your emergency buffer. A reserve envelope has no budget and no cadence, and <strong>Fund the month</strong> never proposes funding it — it just sits holding money. You fill it at month-end close-out by choosing <strong>Sweep</strong> on the envelopes whose leftovers you want set aside, and you take money back out with <strong>Move funds</strong> whenever a real envelope needs it. Sweeping an envelope that ended the month <em>overspent</em> pulls from the reserve to bring it back to zero. Only one envelope can be the reserve; ticking the box on another moves the flag. Sweeps are envelope-to-envelope transfers, so no account is touched: sweeping a positive leftover leaves your spendable cash unchanged (the money stays earmarked, just in a different envelope), while covering an overspend from the reserve raises spendable, because reserved money fills the hole.</div>
    </details>

    <details class="faq"><summary>Why are some accounts missing from the forecast?</summary>
    <div>The Forecast tab has an account picker. By default it excludes investment accounts (their day-to-day value changes are market-driven, not transaction-driven) and any account with "Include in net worth" turned off. Open the account picker on the Forecast tab to add them back.</div>
    </details>

    <details class="faq"><summary>How does the app save my data, and what about backups?</summary>
    <div>The app saves to <code>finance-data.json</code> on the machine running <code>serve.py</code>, over HTTP — so every device that opens this address shares one file, and no browser permission is involved. Saves are debounced ~1s after you stop editing and flushed immediately when you switch tabs or close the page. The server rotates the previous five versions into <code>finance-data.bak.0</code> … <code>.bak.4</code> on disk, and the app additionally keeps <strong>rolling daily backups</strong> (last 7 days) in this browser's <code>localStorage</code> — see Settings → Backups to restore or download one. Use Export from Settings for an off-machine JSON copy any time. If two devices edit at once, the second save is refused with a conflict dialog rather than silently overwriting the first.</div>
    </details>

    <details class="faq"><summary>What if I miss a month's close-out?</summary>
    <div>The Dashboard banner only ever surfaces the most recent unreviewed month, so you won't see a multi-month catch-up. If you want to close out a specific older month manually, go to Settings → Envelope close-out and pick the month.</div>
    </details>

    <details class="faq"><summary>Why is an envelope balance negative?</summary>
    <div>You've spent more on that category than you've funded into the envelope. Either fund it from spendable cash (the envelope's <strong>Fund</strong> button), shift money in from another envelope (<strong>Move funds</strong>), or accept it and let the next month's funding catch up.</div>
    </details>

    <details class="faq"><summary>Can I edit a recurring template after I've already applied some occurrences?</summary>
    <div>Yes. Editing a recurring template changes future occurrences only — already-applied transactions stay exactly as they were recorded. If you need to edit a past occurrence, find it on the Transactions tab and edit the individual record.</div>
    </details>

    <details class="faq"><summary>What does "Lowest in period" mean on the Dashboard forecast card?</summary>
    <div>It's the lowest projected balance over the selected forecast horizon (e.g. 3 months). Treat it as a budgeting constraint — it tells you the maximum amount you can safely commit today without making the worst future point go underwater. Fund-the-month uses the same number to flag over-allocation.
    <p style="margin:8px 0 0;">The <strong>spendable</strong> version of this number is the one to watch when you're deciding how much to set aside. Projected spending for an envelope is paid out of that envelope's own balance first, and only starts reducing spendable once the envelope is empty — so money you've already funded is never counted against you twice, and topping up an envelope doesn't make your own forecast look worse.</p></div>
    </details>

    <details class="faq"><summary>Fund the month vs. Fund vs. Move funds vs. Return — which do I use?</summary>
    <div><strong>Fund the month</strong> (Envelopes toolbar) assigns one month's budget to every envelope in one go — the start-of-month action. It funds the budgeted <em>amount</em>, not the gap to the budget, so an envelope you overspent last month lands below its target and you feel the overspend this month; switch the modal to <strong>Top up to full target</strong> if you'd rather clear it in one go. A single envelope's <strong>Fund</strong> button does the same for just that envelope, mid-month, from spendable cash. <strong>Move funds</strong> shifts money from one envelope to another (no account or spendable effect). <strong>↩ Return</strong> un-earmarks money from an envelope back to spendable cash. All of these only move virtual allocations — your account totals stay the same.</div>
    </details>
  </div>
  `;
}

//=============================================================================
// EVENT WIRING
//=============================================================================
document.querySelectorAll("nav.tabs button").forEach(b => {
  b.onclick = () => { activeView = b.dataset.view; render(); };
});
// Pull the server's copy again — useful after editing on another device.
// Refuses to discard unsaved local edits without a confirmation.
document.getElementById("btnReload").onclick = () => {
  if (dirty && !confirm("You have unsaved changes in this tab. Reload the server's version and lose them?")) return;
  location.reload();
};
document.getElementById("btnSave").onclick = () => writeFile().then(ok => { if (ok) toast("Saved"); });

// Clicking the status indicator while a conflict is unresolved reopens the
// dialog — otherwise the only way back to it is an edit that retriggers a save.
document.getElementById("fileStatus").addEventListener("click", () => {
  if (conflictPending) handleConflict(serverEtag);
});
// Theme resolution: 'auto' follows the OS (prefers-color-scheme); 'dark'/'light'
// are explicit. applyTheme() writes the *resolved* value to <html data-theme>
// (CSS only knows dark/light); themeColor()/chartPalette() then read the right vars.
function resolvedTheme() {
  const set = (data && data.settings && data.settings.theme) || 'auto';
  if (set === 'dark' || set === 'light') return set;
  return window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
}
function applyTheme() { document.documentElement.dataset.theme = resolvedTheme(); }
function updateThemeButton() {
  const btn = document.getElementById("btnTheme");
  if (!btn) return;
  const mode = (data && data.settings && data.settings.theme) || 'auto';
  const label = mode === 'auto' ? 'Auto (system)' : mode[0].toUpperCase() + mode.slice(1);
  btn.title = `Theme: ${label} — click to cycle`;
  btn.setAttribute('aria-label', `Theme: ${label}. Click to cycle through dark, light and auto.`);
}

// Header toggle cycles dark → light → auto (Settings → Theme has the same control).
document.getElementById("btnTheme").onclick = () => {
  if (data) {
    const order = ['dark', 'light', 'auto'];
    const cur = data.settings.theme || 'auto';
    data.settings.theme = order[(order.indexOf(cur) + 1) % order.length];
    applyTheme();
    updateThemeButton();
    saveDirty();
    render();
  } else {
    // No file loaded yet — just flip the applied theme for the welcome screen.
    document.documentElement.dataset.theme =
      document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  }
};

// When the OS theme changes and the user is on Auto, re-resolve and re-tint live.
try {
  window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', () => {
    const set = (data && data.settings && data.settings.theme) || 'auto';
    if (set === 'auto') { applyTheme(); if (data) render(); }
  });
} catch (e) {}

window.addEventListener("beforeunload", e => {
  if (dirty) {
    e.preventDefault();
    return e.returnValue = "Unsaved changes - leave anyway?";
  }
});

// Flush on every "page is going away" signal: blur (tab/window loses focus),
// visibilitychange:hidden (tab backgrounded — often the last event mobile gives
// before evicting the tab), and pagehide (tab closing / navigating away).
// pagehide replaces the unreliable beforeunload for the actual write; the
// beforeunload handler above stays only to surface the confirm-leave prompt.
window.addEventListener("blur", flushNow);
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden") flushNow();
});
window.addEventListener("pagehide", flushNow);

// Global keyboard shortcuts:
//   'n' — opens the Add Transaction modal from any tab.
//   'c' — duplicates a transaction to today's date. The "active" row is the
//         one the user's focus is inside (Edit/⎘/× button) OR the one the
//         mouse is hovering over. Focus wins if both are set on different
//         rows. Only matches rows in the Transactions tab (tr[data-tx]) —
//         Dashboard's Recent-transactions table has no data-tx so it's safe.
//   '?' — opens the keyboard cheatsheet (works even before data is loaded so
//         new users can discover shortcuts on the welcome screen).
// Skipped while typing in any input/textarea/select, while a modal is already
// open, or (for data-dependent shortcuts) before data is loaded.
// ---- Command palette (Cmd/Ctrl-K) ---------------------------------------
function _cmdMatch(c, query) {
  const q = (query || '').trim().toLowerCase();
  if (!q) return true;
  const hay = (c.label + ' ' + (c.keywords || '')).toLowerCase();
  return q.split(/\s+/).every(tok => hay.includes(tok));
}
function _buildCommands() {
  const go = v => () => { activeView = v; render(); };
  const nav = [['Dashboard', 'dashboard'], ['Accounts', 'accounts'], ['Envelopes', 'envelopes'], ['Transactions', 'transactions'], ['Recurring', 'recurring'], ['Forecast', 'forecast'], ['Net Worth', 'networth'], ['Reports', 'reports'], ['Settings', 'settings'], ['Help', 'help']]
    .map(([label, v]) => ({ label: 'Go to ' + label, hint: 'tab', keywords: 'navigate view ' + label, run: go(v) }));
  const actions = [
    { label: 'Add transaction', hint: 'n', keywords: 'new expense income', run: () => editTransaction() },
    { label: 'Account transfer', keywords: 'move money between accounts', run: () => editTransaction(null, 'transfer-account') },
    { label: 'Move funds between envelopes', keywords: 'envelope transfer reallocate', run: () => transferEnvelopes() },
    { label: 'Import CSV…', keywords: 'bank statement import', run: () => csvImportStart() },
    { label: 'Add account', keywords: 'new account', run: () => editAccount() },
    { label: 'Add envelope', keywords: 'new envelope budget category', run: () => editEnvelope() },
    { label: 'Manage tags', keywords: 'tags tag label categorise settings', run: () => { activeView = 'settings'; render(); document.getElementById('btnAddTag')?.scrollIntoView({ block: 'center' }); } },
    { label: 'Add recurring entry', keywords: 'new recurring salary bill subscription', run: () => editRecurring() },
    { label: 'Fund the month', keywords: 'refill envelopes allocate budget', run: () => refillEnvelopes() },
    { label: 'Apply due recurring', keywords: 'apply due recurring', run: () => { const n = applyDueRecurring(); if (n > 0) toast(`Applied ${n} recurring ${n === 1 ? 'entry' : 'entries'}`, 5000, 'success', { label: 'Undo', onClick: performUndo }); else toast('Nothing due'); render(); } },
    { label: 'Review due recurring', keywords: 'review due recurring', run: () => showDueReview() },
    { label: 'Close out month', keywords: 'close out month rollover reset', run: () => showCloseOut() },
    { label: 'Export JSON', keywords: 'download export backup', run: () => exportFile() },
    { label: 'Import JSON', keywords: 'import file load replace', run: () => importViaInput() },
    { label: 'Reload from server', keywords: 'reload refresh server latest sync', run: () => document.getElementById('btnReload').click() },
    { label: 'Save now', keywords: 'save write file server', run: () => writeFile().then(ok => { if (ok) toast('Saved'); }).catch(() => {}) },
    { label: 'Undo last change', hint: 'Ctrl+Z', keywords: 'undo revert', run: () => performUndo() },
    { label: 'Redo', hint: 'Ctrl+Y', keywords: 'redo repeat restore', run: () => performRedo() },
    { label: 'Toggle theme', keywords: 'dark light auto appearance', run: () => { const b = document.getElementById('btnTheme'); if (b) b.click(); } },
  ];
  return nav.concat(actions);
}
function showCommandPalette() {
  const cmds = _buildCommands();
  let sel = 0, filtered = cmds;
  openModal(`
    <h2 style="margin-bottom:10px;">Command palette</h2>
    <input id="cmdq" placeholder="Type a command… (try: add, envelope, import, theme)" autocomplete="off" spellcheck="false" style="width:100%;padding:9px 12px;background:var(--bg);color:var(--text);border:1px solid var(--border);border-radius:7px;font-size:15px;">
    <div id="cmdlist" role="listbox" style="margin-top:10px;max-height:50vh;overflow:auto;"></div>
  `);
  const q = document.getElementById('cmdq');
  const list = document.getElementById('cmdlist');
  const paint = () => {
    [...list.querySelectorAll('.cmd-item')].forEach((el, i) => { el.style.background = i === sel ? 'var(--bg-3)' : ''; });
    const cur = list.querySelector(`.cmd-item[data-i="${sel}"]`);
    if (cur) cur.scrollIntoView({ block: 'nearest' });
  };
  const run = i => { const c = filtered[i]; if (!c) return; closeModal(); setTimeout(() => c.run(), 0); };
  const renderList = () => {
    filtered = cmds.filter(c => _cmdMatch(c, q.value));
    if (sel >= filtered.length) sel = Math.max(0, filtered.length - 1);
    list.innerHTML = filtered.length
      ? filtered.map((c, i) => `<div class="cmd-item" data-i="${i}" role="option" style="display:flex;justify-content:space-between;gap:12px;align-items:center;padding:8px 10px;border-radius:6px;cursor:pointer;${i === sel ? 'background:var(--bg-3);' : ''}"><span>${esc(c.label)}</span>${c.hint ? `<kbd>${esc(c.hint)}</kbd>` : ''}</div>`).join('')
      : '<div style="color:var(--text-dim);padding:8px 10px;">No matching command</div>';
    [...list.querySelectorAll('.cmd-item')].forEach(el => {
      el.onclick = () => run(+el.dataset.i);
      el.onmousemove = () => { const i = +el.dataset.i; if (sel !== i) { sel = i; paint(); } };
    });
  };
  q.addEventListener('input', () => { sel = 0; renderList(); });
  q.addEventListener('keydown', e => {
    if (e.key === 'ArrowDown') { e.preventDefault(); sel = Math.min(filtered.length - 1, sel + 1); paint(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); sel = Math.max(0, sel - 1); paint(); }
    else if (e.key === 'Enter') { e.preventDefault(); run(sel); }
  });
  renderList();
}

document.addEventListener("keydown", e => {
  // Command palette — Cmd/Ctrl-K from anywhere (but never stacked over another modal).
  if ((e.ctrlKey || e.metaKey) && !e.altKey && (e.key === 'k' || e.key === 'K')) {
    if (document.getElementById("modalBg")?.classList.contains("open")) return;
    e.preventDefault();
    if (data) showCommandPalette();
    return;
  }
  if (e.ctrlKey || e.metaKey || e.altKey) return;
  const t = e.target;
  if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT" || t.isContentEditable)) return;
  if (document.getElementById("modalBg")?.classList.contains("open")) return;
  // '?' is allowed before data loads — discovery beats strictness here.
  if (e.key === "?") {
    e.preventDefault();
    showShortcuts();
    return;
  }
  if (!data) return;
  if (e.key === "c" || e.key === "C") {
    let row = (t && t.closest) ? t.closest("tr[data-tx]") : null;
    if (!row) row = document.querySelector("tr[data-tx]:hover");
    if (row) {
      e.preventDefault();
      copyTransaction(row.dataset.tx);
      return;
    }
  }
  if (e.key === "n" || e.key === "N") {
    e.preventDefault();
    editTransaction();
  }
});

// Ctrl-Z / Cmd-Z: pop the last undoable mutation. Ctrl-Y or Ctrl-Shift-Z /
// Cmd-Shift-Z: redo. Suppressed inside text inputs (so browser text-undo
// still works) and while a modal is open (so Ctrl-Z inside a modal field does
// not silently wipe global state).
document.addEventListener("keydown", e => {
  if (!(e.ctrlKey || e.metaKey)) return;
  if (e.altKey) return;
  const k = e.key.toLowerCase();
  const isUndo = k === 'z' && !e.shiftKey;
  const isRedo = (k === 'z' && e.shiftKey) || (k === 'y' && !e.shiftKey);
  if (!isUndo && !isRedo) return;
  const t = e.target;
  if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) return;
  if (document.getElementById("modalBg")?.classList.contains("open")) return;
  if (!data) return;
  e.preventDefault();
  if (isUndo) performUndo(); else performRedo();
});

//=============================================================================
// DEMO / URL PARAMS
//=============================================================================
// Build a small synthetic dataset for ?demo=1 — used by README screenshots and
// by visitors who want to evaluate the app without seeding their own data.
// Generic names only — this is the public face of the project.
function demoData() {
  const today = new Date();
  const iso = d => d.toISOString().slice(0, 10);
  const daysAgo = n => { const d = new Date(today); d.setDate(d.getDate() - n); return iso(d); };
  const d = emptyData();
  d.settings = { currency: "EUR", locale: "en-IE", theme: "dark", household: ["You", "Partner"], tags: ["Essentials", "Lifestyle", "Work"] };
  d.accounts = [
    { id: "demo_a1", name: "Main Checking",  type: "checking",   openingBalance: 3200, includeInNetWorth: true, pinned: true },
    { id: "demo_a2", name: "Savings",         type: "savings",    openingBalance: 8500, includeInNetWorth: true, pinned: true },
    { id: "demo_a3", name: "Credit Card",     type: "credit",     openingBalance: -420, includeInNetWorth: true },
    { id: "demo_a4", name: "Wallet",          type: "cash",       openingBalance: 60,   includeInNetWorth: true },
    { id: "demo_a5", name: "Brokerage",       type: "investment", openingBalance: 12400, includeInNetWorth: true, isInvestment: true }
  ];
  d.envelopes = [
    { id: "demo_e1", name: "Groceries",      category: "Living", budgetAmount: 600, cadence: "monthly", rolloverPolicy: "carryover", pinned: true },
    { id: "demo_e2", name: "Rent",           category: "Living", budgetAmount: 1100, cadence: "monthly", rolloverPolicy: "reset" },
    { id: "demo_e3", name: "Utilities",      category: "Living", budgetAmount: 180, cadence: "monthly", rolloverPolicy: "carryover" },
    { id: "demo_e4", name: "Dining out",     category: "Fun",    budgetAmount: 200, cadence: "monthly", rolloverPolicy: "carryover" },
    { id: "demo_e5", name: "Entertainment",  category: "Fun",    budgetAmount: 100, cadence: "monthly", rolloverPolicy: "carryover" },
    { id: "demo_e6", name: "Holiday fund",   category: "Goals",  budgetAmount: 2400, cadence: "annual",  rolloverPolicy: "carryover" },
    { id: "demo_e7", name: "Emergency",      category: "Goals",  budgetAmount: 3000, cadence: "annual",  rolloverPolicy: "carryover" }
  ];
  d.transactions = [
    { id: "demo_t1", date: daysAgo(20), type: "income", amount: 2800, accountId: "demo_a1", envelopeId: null, payee: "Salary" },
    { id: "demo_t2", date: daysAgo(20), type: "income", amount: 2100, accountId: "demo_a1", envelopeId: null, payee: "Salary (partner)" },
    { id: "demo_r1", date: daysAgo(20), type: "income", amount: 600,  envelopeId: "demo_e1", accountId: null, payee: "Envelope refill" },
    { id: "demo_r2", date: daysAgo(20), type: "income", amount: 1100, envelopeId: "demo_e2", accountId: null, payee: "Envelope refill" },
    { id: "demo_r3", date: daysAgo(20), type: "income", amount: 180,  envelopeId: "demo_e3", accountId: null, payee: "Envelope refill" },
    { id: "demo_r4", date: daysAgo(20), type: "income", amount: 200,  envelopeId: "demo_e4", accountId: null, payee: "Envelope refill" },
    { id: "demo_r5", date: daysAgo(20), type: "income", amount: 100,  envelopeId: "demo_e5", accountId: null, payee: "Envelope refill" },
    { id: "demo_r6", date: daysAgo(20), type: "income", amount: 200,  envelopeId: "demo_e6", accountId: null, payee: "Holiday fund top-up" },
    { id: "demo_r7", date: daysAgo(20), type: "income", amount: 250,  envelopeId: "demo_e7", accountId: null, payee: "Emergency top-up" },
    { id: "demo_t3", date: daysAgo(19), type: "expense", amount: 1100, accountId: "demo_a1", envelopeId: "demo_e2", payee: "Rent" },
    { id: "demo_t4", date: daysAgo(18), type: "expense", amount: 87.40, accountId: "demo_a1", envelopeId: "demo_e1", payee: "Supermarket" },
    { id: "demo_t5", date: daysAgo(15), type: "expense", amount: 62.10, accountId: "demo_a3", envelopeId: "demo_e4", payee: "Pizza", tag: "Lifestyle" },
    { id: "demo_t5b", date: daysAgo(12), type: "transfer-account", amount: 45, fromAccountId: "demo_a1", toAccountId: "demo_a4", payee: "Client lunch, petty cash", tag: "Work" },
    { id: "demo_t6", date: daysAgo(14), type: "expense", amount: 145, accountId: "demo_a1", envelopeId: "demo_e3", payee: "Electricity" },
    { id: "demo_t7", date: daysAgo(12), type: "expense", amount: 38.50, accountId: "demo_a3", envelopeId: "demo_e1", payee: "Bakery" },
    { id: "demo_t8", date: daysAgo(10), type: "expense", amount: 24, accountId: "demo_a4", envelopeId: "demo_e5", payee: "Cinema", tag: "Lifestyle" },
    { id: "demo_t9", date: daysAgo(8),  type: "expense", amount: 104.20, accountId: "demo_a1", envelopeId: "demo_e1", payee: "Supermarket", tag: "Essentials" },
    { id: "demo_t10", date: daysAgo(5), type: "expense", amount: 48, accountId: "demo_a3", envelopeId: "demo_e4", payee: "Dinner" },
    { id: "demo_t11", date: daysAgo(3), type: "expense", amount: 22, accountId: "demo_a4", envelopeId: "demo_e1", payee: "Veggies" },
    { id: "demo_t12", date: daysAgo(1), type: "expense", amount: 75.30, accountId: "demo_a1", envelopeId: "demo_e1", payee: "Supermarket" }
  ];
  d.recurring = [
    { id: "demo_rc1", name: "Rent",      type: "expense", amount: 1100, schedule: "monthly", dayOfMonth: 1,  startDate: daysAgo(60),  accountId: "demo_a1", envelopeId: "demo_e2", active: true, lastAppliedDate: daysAgo(19) },
    { id: "demo_rc2", name: "Salary",    type: "income",  amount: 2800, schedule: "monthly", dayOfMonth: 25, startDate: daysAgo(120), accountId: "demo_a1", envelopeId: null,      active: true, lastAppliedDate: daysAgo(20) },
    { id: "demo_rc3", name: "Salary (partner)", type: "income", amount: 2100, schedule: "monthly", dayOfMonth: 25, startDate: daysAgo(120), accountId: "demo_a1", envelopeId: null, active: true, lastAppliedDate: daysAgo(20) },
    { id: "demo_rc4", name: "Streaming", type: "expense", amount: 14.99, schedule: "monthly", dayOfMonth: 5,  startDate: daysAgo(90),  accountId: "demo_a3", envelopeId: "demo_e5", active: true, lastAppliedDate: daysAgo(50), tag: "Lifestyle" }
  ];
  d.netWorthSnapshots = [];
  for (let n = 90; n >= 0; n -= 3) {
    const noise = Math.sin(n * 0.13) * 200 + Math.random() * 80;
    d.netWorthSnapshots.push({ date: daysAgo(n), value: 23700 + (90 - n) * 18 + noise });
  }
  return d;
}

// Tiny URL-param boot helper. Supports:
//   ?demo=1   load embedded demo dataset (in-memory only)
//   ?view=X   activate the named tab (dashboard | envelopes | forecast | ...)
// Both are non-destructive — they never write to finance-data.json. demoMode
// is what enforces that: writeFile() returns early before touching the server,
// so a demo session can be edited freely without ever reaching the real file.
function applyUrlParams() {
  const params = new URLSearchParams(location.search);
  let demoApplied = false;
  if (params.get("demo") === "1") {
    data = demoData();
    demoMode = true;
    dirty = false;
    demoApplied = true;
    updateFileStatus("demo data (not saved)", "no-file");
  }
  // ?view=transactions&acc=<id>&env=<id>&tag=<name>&q=…&from=YYYY-MM-DD&to=…
  // pre-fills the Transactions filter so a bookmark can land on "this
  // account, this month". Unknown ids are harmless: the select just shows
  // "All" and the filter matches nothing until cleared.
  const pf = {};
  for (const k of ['acc', 'env', 'q', 'from', 'to', 'type']) if (params.get(k)) pf[k] = params.get(k);
  if (params.get('tag')) pf.tag = params.get('tag') === 'untagged' ? 'u' : 't:' + params.get('tag');
  if (Object.keys(pf).length) txFilter = { ...txFilter, ...pf };
  return { demoApplied, view: params.get("view") };
}

//=============================================================================
// INIT
//=============================================================================
(async () => {
  const urlOpts = applyUrlParams();
  let loaded = false;
  if (!urlOpts.demoApplied) {
    loaded = await loadFromServer();
  } else {
    loaded = true;
  }
  applyTheme(); updateThemeButton();
  // Apply the persistent default forecast profile (if any) on session start so
  // both the Forecast tab and the dashboard forecast card open with the user's
  // preferred view selected. Self-heal a stale default that points to a
  // profile that was deleted in another session.
  if (loaded && data?.defaultForecastProfileId) {
    const p = data.forecastProfiles.find(x => x.id === data.defaultForecastProfileId);
    if (p) {
      applyForecastSettings(p);
      forecastState.selectedProfileId = p.id;
      forecastState.profileDirty = false;
    } else {
      data.defaultForecastProfileId = null;
      saveDirty();
    }
  }
  render();
  if (urlOpts.view) {
    const btn = document.querySelector(`nav.tabs button[data-view="${urlOpts.view}"]`);
    if (btn) btn.click();
  }
  registerServiceWorker();
})();

// Register the shell-caching service worker (see sw.js for what it does and,
// more importantly, what it deliberately does NOT cache). Requires a secure
// context: https://<host>.ts.net via `tailscale serve`, or plain localhost,
// which browsers treat as secure. Over http://<lan-ip>:8765 it silently
// no-ops — the app works, it just isn't installable.
//
// Failure here must never break the app: it is an enhancement, not a
// dependency, so everything is wrapped and only warns.
function registerServiceWorker() {
  if (!("serviceWorker" in navigator) || !window.isSecureContext) return;
  if (demoMode) return;  // don't let a demo session install anything
  navigator.serviceWorker.register("sw.js").catch(e => console.warn("sw registration failed", e));
}
</script>
</body>
</html>
