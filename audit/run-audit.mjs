// Pocket Envelopes — mechanical audit.
//
// Run from the project root:
//
//     node audit/run-audit.mjs
//
// Node built-ins only; nothing to install. Exits non-zero when any check FAILs.
// It never reads finance-data.json — every unit check seeds its own synthetic data.
//
// What it checks:
//
//   1. pocket-envelopes.app — every inline <script> compiles (syntax only).
//   2. pocket-envelopes.app stays single-file and locally vendored: Chart.js is
//      loaded from vendor/, and no <script>/<link>/<img> points at an http(s) URL.
//   3. The accounting engine, extracted from the app by name into a bare `vm`
//      context and exercised against synthetic fixtures:
//        - evalAmount rejects executable input and division by zero
//        - account / split-envelope deltas route correctly
//        - recurring dates stay end-of-month anchored; custom months are sorted
//        - recurring monthly equivalents and recurring→transaction routing
//        - validateData rejects malformed collections
//        - forecast floors overspent envelopes (spendable is not inflated)
//        - a funded monthly allowance is charged once, not twice
//        - "fund one month" assigns the budget, not the overspend gap
//        - envelope-only adjustments are not cashflow
//   4. sw.js compiles, never intercepts /data, and keeps the shell network-first.
//   5. serve.py compiles under the local Python (py -3 on Windows, python3 elsewhere).
//      Skipped with a WARN if no Python is found.
//
// PASS / WARN / FAIL per check, then a one-line summary. A FAIL means a stated
// invariant of the app is broken; a WARN is something a human should look at.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const auditDir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(auditDir, "..");
const appPath = path.join(root, "pocket-envelopes.app");
const app = readFileSync(appPath, "utf8");

const results = [];
const pass = (name, detail = "") => results.push({ level: "PASS", name, detail });
const warn = (name, detail = "") => results.push({ level: "WARN", name, detail });
const fail = (name, detail = "") => results.push({ level: "FAIL", name, detail });

function check(name, fn) {
  try {
    fn();
    pass(name);
  } catch (error) {
    fail(name, error?.message || String(error));
  }
}

function inlineScripts(html) {
  return [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);
}

function mainInlineScript(html) {
  const scripts = inlineScripts(html).filter((body) => body.trim());
  if (!scripts.length) throw new Error("No inline application script found");
  return scripts.at(-1);
}

// Slice `function <name>(...) { ... }` out of the source by brace matching,
// skipping braces inside strings, template literals and comments.
function extractFunction(source, name) {
  const match = new RegExp(`(?:async\\s+)?function\\*?\\s+${name}\\s*\\(`).exec(source);
  if (!match) throw new Error(`Function ${name} not found`);
  const start = match.index;
  const open = source.indexOf("{", start);
  let depth = 0;
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;

  for (let i = open; i < source.length; i++) {
    const ch = source[i];
    const next = source[i + 1];
    if (lineComment) {
      if (ch === "\n") lineComment = false;
      continue;
    }
    if (blockComment) {
      if (ch === "*" && next === "/") { blockComment = false; i++; }
      continue;
    }
    if (quote) {
      if (escaped) { escaped = false; continue; }
      if (ch === "\\") { escaped = true; continue; }
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === "/" && next === "/") { lineComment = true; i++; continue; }
    if (ch === "/" && next === "*") { blockComment = true; i++; continue; }
    if (ch === '"' || ch === "'" || ch === "`") { quote = ch; continue; }
    if (ch === "{") depth++;
    if (ch === "}") {
      depth--;
      if (depth === 0) return source.slice(start, i + 1);
    }
  }
  throw new Error(`Function ${name} is not balanced`);
}

// ---------------------------------------------------------------- 1. syntax

try {
  const scripts = inlineScripts(app);
  for (const body of scripts) if (body.trim()) new Function(body);
  pass("App JavaScript syntax", `${scripts.length} inline scripts compiled`);
} catch (error) {
  fail("App JavaScript syntax", error.message);
}

// ------------------------------------------------- 2. single-file invariants

check("App stays single-file and locally vendored", () => {
  assert.match(app, /<script src="vendor\/chart\.umd\.min\.js"><\/script>/,
    "Chart.js must be loaded from vendor/chart.umd.min.js");
  assert.doesNotMatch(app, /<script[^>]+src=["']https?:\/\//i, "no remote <script src>");
  assert.doesNotMatch(app, /<(?:link|img)[^>]+(?:href|src)=["']https?:\/\//i, "no remote <link>/<img>");
});

// ------------------------------------------------ 3. accounting-engine tests

function logicApi() {
  const source = mainInlineScript(app);
  const names = [
    "parseDate", "addDays", "addMonths", "addMonthsAnchored", "isoDate",
    "todayISO", "daysBetween", "validateData", "evalAmount", "txAccountDelta",
    "txEnvelopePortion", "txEnvelopeDelta", "accountById", "envelopeById",
    "accountBalance", "envelopeBalance", "envMonthlyEquiv", "recurringOccurrences",
    "dueRecurringOccurrences", "recurringToTx", "recurringResumeDate",
    "recurringMonthlyEquiv", "recurringMonthlyForEnvelope",
    "envelopeSpendingAccount", "forecastAccountBalances", "spendableLow",
    "spendableMinAfterFunding", "envelopeFundSuggestion", "isCashflowTx",
  ];
  const bundle = [
    "var data = null;",
    "const uid = () => 'audit-id';",
    ...names.map((name) => extractFunction(source, name)),
    `globalThis.__auditApi = {
      ${names.join(",")},
      setData(value) { data = value; },
      getData() { return data; }
    };`,
  ].join("\n\n");
  const context = vm.createContext({ console, Date, Math, isFinite, isNaN });
  vm.runInContext(bundle, context, { filename: "pocket-envelopes-logic.js" });
  return context.__auditApi;
}

let api;
try { api = logicApi(); pass("Logic harness loads the app's accounting functions"); }
catch (error) { fail("Logic harness loads the app's accounting functions", error.message); }

if (api) {
  check("Amount expressions reject executable input", () => {
    assert.equal(api.evalAmount("2380,50 - 100"), 2280.5);
    assert.equal(api.evalAmount("(10+5)*2"), 30);
    assert.ok(Number.isNaN(api.evalAmount("alert(1)")));
    assert.ok(Number.isNaN(api.evalAmount("1/0")));
  });

  check("Account and split-envelope deltas conserve routing", () => {
    const transfer = { type: "transfer-account", amount: 75, fromAccountId: "a", toAccountId: "b" };
    assert.equal(api.txAccountDelta(transfer, "a"), -75);
    assert.equal(api.txAccountDelta(transfer, "b"), 75);
    assert.equal(api.txAccountDelta(transfer, "c"), 0);
    const split = { type: "expense", amount: 100, splits: [
      { envelopeId: "food", amount: 60 }, { envelopeId: "fun", amount: 40 },
    ] };
    assert.equal(api.txEnvelopeDelta(split, "food"), -60);
    assert.equal(api.txEnvelopeDelta(split, "fun"), -40);
  });

  check("Recurring dates stay anchored and custom months are chronological", () => {
    const monthly = [...api.recurringOccurrences(
      { schedule: "monthly", startDate: "2026-01-31" },
      api.parseDate("2026-01-01"), api.parseDate("2026-04-30"),
    )];
    assert.deepEqual(Array.from(monthly), ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"]);
    const custom = [...api.recurringOccurrences(
      { schedule: "custom-months", startDate: "2026-01-15", months: [12, 4] },
      api.parseDate("2026-01-01"), api.parseDate("2026-12-31"),
    )];
    assert.deepEqual(Array.from(custom), ["2026-04-15", "2026-12-15"]);
  });

  check("Recurring monthly equivalents and transaction routing", () => {
    assert.equal(api.recurringMonthlyEquiv({ amount: 120, schedule: "yearly" }), 10);
    assert.equal(api.recurringMonthlyEquiv({ amount: 10, schedule: "weekly" }), 10 * 52 / 12);
    const tx = api.recurringToTx({
      id: "r", name: "Move", type: "transfer-envelope", amount: 50,
      fromEnvelopeId: "a", toEnvelopeId: "b",
    }, "2026-08-15", 50);
    assert.equal(tx.fromEnvelopeId, "a");
    assert.equal(tx.toEnvelopeId, "b");
    assert.equal(tx.fromRecurringId, "r");
  });

  check("Schema guard rejects malformed financial collections", () => {
    assert.ok(api.validateData(null).length > 0);
    assert.ok(api.validateData({ transactions: {} }).length > 0);
    assert.ok(api.validateData({ accounts: [null] }).length > 0);
    assert.deepEqual(Array.from(api.validateData({ accounts: [], transactions: [] })), []);
  });

  check("Forecast floors overspent envelopes instead of inflating spendable cash", () => {
    api.setData({
      accounts: [{ id: "cash", openingBalance: 1000, includeInNetWorth: true }],
      envelopes: [{ id: "overspent", openingBalance: -100, budgetAmount: 0, cadence: "monthly" }],
      transactions: [], recurring: [],
    });
    const fc = api.forecastAccountBalances(["cash"], 1, { includeAllowances: false });
    assert.equal(fc.envelopeTotal[0], 0);
    assert.equal(fc.spendable[0], 1000);
  });

  check("A funded allowance is charged once, not twice", () => {
    api.setData({
      accounts: [{ id: "cash", openingBalance: 5000, includeInNetWorth: true }],
      envelopes: [{ id: "living", openingBalance: 300, budgetAmount: 300, cadence: "monthly" }],
      transactions: [], recurring: [],
    });
    // Forecast through this month-end. Calendar-anchored smoothing drains one
    // monthly allowance. Because the envelope already holds that allowance,
    // account and reserved-envelope deltas cancel in spendable cash.
    const now = new Date();
    const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0);
    const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const daysToMonthEnd = Math.round((monthEnd - midnight) / 86400000);
    const fc = api.forecastAccountBalances(["cash"], daysToMonthEnd, { includeAllowances: true });
    const expected = 5000 - 300;
    assert.ok(Math.abs(fc.spendable.at(-1) - expected) < 0.05,
      `Expected ${expected}, got ${fc.spendable.at(-1)}`);
  });

  check("Fund-one-month does not silently repay overspending", () => {
    api.setData({
      accounts: [], recurring: [], transactions: [],
      envelopes: [{ id: "food", openingBalance: -735, budgetAmount: 1000, cadence: "monthly" }],
    });
    const suggestion = api.envelopeFundSuggestion(api.getData().envelopes[0], "month");
    assert.equal(suggestion.suggested, 1000);
  });

  check("Envelope-only adjustments are excluded from cashflow", () => {
    assert.equal(api.isCashflowTx({ type: "expense", accountId: null, amount: 10 }), false);
    assert.equal(api.isCashflowTx({ type: "expense", accountId: "cash", amount: 10 }), true);
    assert.equal(api.isCashflowTx({ type: "income", accountId: "invest", payee: "Market adjustment" }), false);
  });
}

// ------------------------------------------------------- 4. service worker

check("Service worker compiles, skips /data, and is network-first", () => {
  const sw = readFileSync(path.join(root, "sw.js"), "utf8");
  new Function(sw);
  assert.match(sw, /endsWith\("\/data"\)\)\s*return/, "/data requests must fall through untouched");
  // Network-first: the fetch handler must go to the network and treat the cache
  // as a fallback — including for a *resolved* non-ok response, because a
  // stopped backend behind a reverse proxy answers 502 rather than throwing.
  const at = sw.indexOf('addEventListener("fetch"');
  assert.ok(at >= 0, "fetch handler not found");
  const handler = sw.slice(at);
  assert.match(handler, /await fetch\(/, "fetch handler never calls fetch()");
  assert.match(handler, /!fresh\.ok/, "a non-ok response must fall back to the cached shell");
  assert.match(sw, /const CACHE_NAME\s*=\s*["'][^"']+["']/, "CACHE_NAME must be a literal (bump it to roll the shell)");
});

// ---------------------------------------------------------- 5. serve.py

{
  const candidates = process.platform === "win32"
    ? [["py", ["-3", "-m", "py_compile", "serve.py"]], ["python", ["-m", "py_compile", "serve.py"]]]
    : [["python3", ["-m", "py_compile", "serve.py"]], ["python", ["-m", "py_compile", "serve.py"]]];
  let ran = false;
  for (const [cmd, args] of candidates) {
    const r = spawnSync(cmd, args, { cwd: root, encoding: "utf8" });
    if (r.error) continue;                       // interpreter not on PATH; try the next
    ran = true;
    if (r.status === 0) pass("Local server Python syntax", `${cmd} ${args.join(" ")}`);
    else fail("Local server Python syntax", (r.stderr || r.stdout || "compile failed").trim());
    break;
  }
  if (!ran) warn("Local server Python syntax", "no Python interpreter found on PATH; serve.py not compiled");
}

// ---------------------------------------------------------------- report

console.log("\nPocket Envelopes audit\n");
for (const result of results) {
  const detail = result.detail ? ` — ${result.detail}` : "";
  console.log(`[${result.level}] ${result.name}${detail}`);
}
const counts = Object.fromEntries(["PASS", "WARN", "FAIL"].map(
  (level) => [level, results.filter((item) => item.level === level).length],
));
console.log(`\nSummary: ${counts.PASS} passed, ${counts.WARN} warnings, ${counts.FAIL} failed.`);
process.exitCode = counts.FAIL ? 1 : 0;
