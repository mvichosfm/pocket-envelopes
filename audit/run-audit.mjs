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
//        - backed envelopes: a full account selection forecasts exactly as before,
//          a filtered one subtracts only the envelopes its accounts hold
//        - archived envelopes keep their balance but carry no budget; pickers keep
//          an archived record only while the edited entry still names it
//        - the per-render balance cache never returns a stale figure: a push, a
//          swapped array or closing the cache all force a recompute
//        - a hand-logged transaction matches a due occurrence only on type, account,
//          exact amount and a 3-day window, never one generated from a recurring
//        - "fund one month" assigns the budget, not the overspend gap
//        - the Fund-envelope solver lands the projected low at zero to the cent,
//          absorbs an overspend for free, and returns null for an envelope the
//          selected accounts do not hold
//        - envelope-only adjustments are not cashflow
//        - one occurrence of a recurring can carry its own amount or be skipped: every
//          reader (pending, due, forecast, hand-log matching) honours it, the template and
//          its allowance netting do not move, resolved dates are pruned, bad entries sanitised
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
  let parameters = 1;
  let depth = 0;
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;

  for (let i = start + match[0].length; i < source.length; i++) {
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
    // Destructured/default parameters can contain braces before the body.
    if (parameters) {
      if (ch === "(") parameters++;
      if (ch === ")") parameters--;
      continue;
    }
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
    "balanceCacheBegin", "balanceCacheEnd", "_balCacheLive", "findHandLoggedMatch",
    "accountBalance", "envelopeBalance", "envMonthlyEquiv", "recurringOccurrences",
    "dueRecurringOccurrences", "isSkippedOccurrence", "firstPendingOccurrence", "occurrenceAmount",
    "setOccurrenceOverride", "setOccurrenceSkipped", "pruneResolvedOccurrences", "sanitizeRecurringOverrides",
    "validISODate", "recurringToTx", "recurringResumeDate",
    "recurringMonthlyEquiv", "recurringMonthlyForEnvelope", "recurringCoversEnvelope", "recurringCoversAllowanceOf",
    "withProbeTxs", "isReturnTx",
    "envelopeBackingAccount", "envelopeCountsFor", "activeAccounts", "activeEnvelopes", "pickerList",
    "envelopeSpendingAccount", "forecastAccountBalances", "spendableLow",
    "spendableMinAfterFunding", "envelopeFundSuggestion", "isCashflowTx",
    "spendableToday", "fundingToZeroLow",
    "lastDayOfMonthKey", "envelopeMonthSummary", "envelopeMonthSpendMap", "reportsAggregates",
  ];
  const bundle = [
    "var data = null;",
    "let _balCache = null;",
    "const HAND_LOG_WINDOW_DAYS = 3;",
    "const RETURN_PAYEE = 'Return to spendable';",
    "const uid = () => 'audit-id';",
    "const tagColor = () => 'grey', themeColor = () => 'grey';",
    "const allTags = () => data.settings?.tags || [];",
    ...names.map((name) => extractFunction(source, name)),
    `globalThis.__auditApi = {
      ${names.join(",")},
      setData(value) { data = value; },
      setToday(value) { todayISO = () => value; },
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
    // ids and types are interpolated into markup unescaped: constrain them here (decision #50)
    assert.ok(api.validateData({ envelopes: [{ id: 'e1" onmouseover="x' }] }).length > 0, "hostile id refused");
    assert.ok(api.validateData({ transactions: [{ id: "t1", type: "expense<img>" }] }).length > 0, "hostile type refused");
    assert.ok(api.validateData({ recurring: [{ id: "r1", type: "weird" }] }).length > 0, "unknown recurring type refused");
    assert.deepEqual(Array.from(api.validateData({ transactions: [{ id: "demo_t1", type: "transfer-envelope" }], envelopes: [{ id: "__fundProbe" }] })), []);
  });

  check("A one-off or ended recurring does not net the envelope allowance", () => {
    const env = { id: "living", name: "Living", openingBalance: 0, budgetAmount: 300, cadence: "monthly" };
    const t = new Date();
    const lastMonthEnd = new Date(t.getFullYear(), t.getMonth(), 0);
    const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    const mk = (over) => ({ id: "r", type: "expense", amount: 300, schedule: "monthly", startDate: "2020-01-01", envelopeId: "living", active: true, ...over });
    api.setData({ accounts: [], envelopes: [env], transactions: [], recurring: [mk({})] });
    assert.equal(api.recurringMonthlyForEnvelope(env), 300, "a live monthly nets its amount");
    api.setData({ accounts: [], envelopes: [env], transactions: [], recurring: [mk({ schedule: "once", amount: 5000 })] });
    assert.equal(api.recurringMonthlyForEnvelope(env), 0, "a one-off is an event, not a stream");
    api.setData({ accounts: [], envelopes: [env], transactions: [], recurring: [mk({ endDate: iso(lastMonthEnd) })] });
    assert.equal(api.recurringMonthlyForEnvelope(env), 0, "ended last month → no longer nets");
    api.setData({ accounts: [], envelopes: [env], transactions: [], recurring: [mk({ endDate: iso(new Date(t.getFullYear(), t.getMonth() + 2, 1)) })] });
    assert.equal(api.recurringMonthlyForEnvelope(env), 300, "ending in a future month still nets this month");
    assert.equal(api.recurringCoversEnvelope(mk({ active: false })), false);
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

  // Arrays built inside the vm context have a foreign Array prototype, so
  // strict deepEqual on them fails; copy them into this realm first.
  const arr = (x) => Array.from(x);

  check("Backed envelopes: selecting every account forecasts exactly as before", () => {
    const fixture = (withBacking) => ({
      accounts: [
        { id: "mine", name: "Mine", openingBalance: 500, includeInNetWorth: true },
        { id: "theirs", name: "Theirs", openingBalance: 1000, includeInNetWorth: true },
      ],
      envelopes: [
        { id: "shared", name: "Shared", openingBalance: 120, budgetAmount: 0, cadence: "monthly" },
        { id: "rent", name: "Rent", openingBalance: 300, budgetAmount: 0, cadence: "monthly", ...(withBacking ? { accountId: "theirs" } : {}) },
        { id: "fuel", name: "Fuel", openingBalance: 80, budgetAmount: 0, cadence: "monthly", ...(withBacking ? { accountId: "mine" } : {}) },
      ],
      transactions: [], recurring: [],
    });
    api.setData(fixture(false));
    const before = api.forecastAccountBalances(["mine", "theirs"], 30, { includeAllowances: false });
    api.setData(fixture(true));
    const after = api.forecastAccountBalances(["mine", "theirs"], 30, { includeAllowances: false });
    assert.deepEqual(arr(after.spendable), arr(before.spendable));
    assert.deepEqual(arr(after.envelopeTotal), arr(before.envelopeTotal));
    assert.equal(after.spendable[0], 1500 - 500);
    assert.equal(after.excludedEnvelopes.length, 0);
  });

  check("Backed envelopes: a filtered forecast subtracts only the envelopes its accounts hold", () => {
    api.setData({
      accounts: [
        { id: "mine", name: "Mine", openingBalance: 500, includeInNetWorth: true },
        { id: "theirs", name: "Theirs", openingBalance: 1000, includeInNetWorth: true },
      ],
      envelopes: [
        { id: "shared", name: "Shared", openingBalance: 120, budgetAmount: 0, cadence: "monthly" },          // household: counts everywhere
        { id: "rent", name: "Rent", openingBalance: 300, budgetAmount: 0, cadence: "monthly", accountId: "theirs" },
        { id: "fuel", name: "Fuel", openingBalance: 80, budgetAmount: 0, cadence: "monthly", accountId: "mine" },
        { id: "gone", name: "Gone", openingBalance: 50, budgetAmount: 0, cadence: "monthly", accountId: "deleted" }, // dangling → household
      ],
      transactions: [], recurring: [],
    });
    const mine = api.forecastAccountBalances(["mine"], 7, { includeAllowances: false });
    assert.equal(mine.spendable[0], 500 - 120 - 80 - 50);
    assert.deepEqual(arr(mine.excludedEnvelopes).map((x) => `${x.name}@${x.accountName}`), ["Rent@Theirs"]);
    const theirs = api.forecastAccountBalances(["theirs"], 7, { includeAllowances: false });
    assert.equal(theirs.spendable[0], 1000 - 120 - 300 - 50);
    assert.deepEqual(arr(theirs.excludedEnvelopes).map((x) => x.name), ["Fuel"]);
    // The old rule charged every envelope against the single selected account.
    assert.notEqual(mine.spendable[0], 500 - 120 - 300 - 80 - 50);
  });

  check("Backed envelopes: the allowance drains from the backing account, or not at all", () => {
    const now = new Date();
    const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0);
    const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const daysToMonthEnd = Math.round((monthEnd - midnight) / 86400000);
    api.setData({
      accounts: [
        { id: "mine", name: "Mine", openingBalance: 2000, includeInNetWorth: true },
        { id: "theirs", name: "Theirs", openingBalance: 2000, includeInNetWorth: true },
      ],
      envelopes: [{ id: "rent", name: "Rent", openingBalance: 0, budgetAmount: 300, cadence: "monthly", accountId: "theirs" }],
      // Spending history says "mine"; the explicit backing account must win.
      transactions: [{ id: "t1", date: "2020-01-05", type: "expense", amount: 10, accountId: "mine", envelopeId: "rent" }],
      recurring: [],
    });
    const both = api.forecastAccountBalances(["mine", "theirs"], daysToMonthEnd, { includeAllowances: true });
    assert.deepEqual(arr(both.allowanceInfo.included).map((x) => x.accountName), ["Theirs"]);
    assert.ok(Math.abs(both.series.mine.at(-1) - 1990) < 0.005, "mine must not be drained (2000 less the posted 10)");
    const onlyMine = api.forecastAccountBalances(["mine"], daysToMonthEnd, { includeAllowances: true });
    assert.equal(onlyMine.allowanceInfo.included.length, 0);
    assert.deepEqual(arr(onlyMine.allowanceInfo.unassigned).map((x) => x.name), ["Rent"]);
    assert.ok(Math.abs(onlyMine.total.at(-1) - 1990) < 0.005, "a forecast without the backing account sees no drain");
  });

  check("Archived envelopes keep their balance but carry no budget", () => {
    const now = new Date();
    const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0);
    const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const daysToMonthEnd = Math.round((monthEnd - midnight) / 86400000);
    api.setData({
      accounts: [
        { id: "cash", name: "Cash", openingBalance: 1000, includeInNetWorth: true },
        { id: "old", name: "Old", openingBalance: 25, includeInNetWorth: true, archived: true },
      ],
      envelopes: [
        { id: "live", name: "Live", openingBalance: 0, budgetAmount: 300, cadence: "monthly" },
        { id: "gone", name: "Gone", openingBalance: 100, budgetAmount: 300, cadence: "monthly", archived: true },
      ],
      transactions: [], recurring: [],
    });
    assert.equal(api.envMonthlyEquiv(api.getData().envelopes[1]), 0);
    const fc = api.forecastAccountBalances(["cash"], daysToMonthEnd, { includeAllowances: true });
    assert.equal(fc.envelopeTotal[0], 100, "an archived envelope's balance is still earmarked");
    assert.equal(fc.spendable[0], 900);
    assert.deepEqual(arr(fc.allowanceInfo.included).map((x) => x.name), ["Live"], "no allowance drains from an archived envelope");
    // The archived account keeps counting wherever balances are summed …
    assert.equal(api.accountBalance(api.getData().accounts[1]), 25);
    // … but it is not an "active" account, and a picker only keeps it while selected.
    assert.deepEqual(arr(api.activeAccounts()).map((a) => a.id), ["cash"]);
    assert.deepEqual(arr(api.activeEnvelopes()).map((e) => e.id), ["live"]);
    assert.deepEqual(arr(api.pickerList(api.getData().accounts, "old")).map((a) => a.id), ["cash", "old"]);
    assert.deepEqual(arr(api.pickerList(api.getData().accounts, null)).map((a) => a.id), ["cash"]);
    assert.deepEqual(arr(api.pickerList(api.getData().envelopes, ["gone", "live"])).map((e) => e.id), ["live", "gone"]);
  });

  check("Balance cache: same figures as a fresh scan, never stale", () => {
    api.setData({
      accounts: [{ id: "cash", name: "Cash", openingBalance: 1000, includeInNetWorth: true }],
      envelopes: [{ id: "food", name: "Food", openingBalance: 100, budgetAmount: 0, cadence: "monthly" }],
      transactions: [{ id: "t1", date: "2020-01-05", type: "expense", amount: 40, accountId: "cash", envelopeId: "food" }],
      recurring: [],
    });
    const d = api.getData();
    const fresh = api.accountBalance(d.accounts[0]);
    api.balanceCacheBegin();
    assert.equal(api.accountBalance(d.accounts[0]), fresh);
    assert.equal(api.envelopeBalance(d.envelopes[0]), 60);
    // a push inside the pass changes the array length → recompute, not the cached value
    d.transactions.push({ id: "t2", date: "2020-01-06", type: "expense", amount: 10, accountId: "cash", envelopeId: "food" });
    assert.equal(api.accountBalance(d.accounts[0]), 950);
    assert.equal(api.envelopeBalance(d.envelopes[0]), 50);
    // a swapped array (the Fund modal's probe copy) bypasses the cache too
    const original = d.transactions;
    d.transactions = original.concat([{ id: "p", date: "2020-01-07", type: "expense", amount: 5, accountId: "cash", envelopeId: "food" }]);
    assert.equal(api.accountBalance(d.accounts[0]), 945);
    d.transactions = original;
    assert.equal(api.accountBalance(d.accounts[0]), 950);
    api.balanceCacheEnd();
    assert.equal(api._balCacheLive(), null);
    assert.equal(api.accountBalance(d.accounts[0]), 950);
  });

  check("Hand-logged match: type, account, exact amount, 3-day window, never a generated tx", () => {
    const rec = { id: "r1", name: "Rent", type: "expense", amount: 1100, accountId: "cash", envelopeId: "rent" };
    const base = { accounts: [], envelopes: [], recurring: [] };
    const tx = (over) => ({ id: "x", date: "2026-09-01", type: "expense", amount: 1100, accountId: "cash", envelopeId: "rent", ...over });
    const find = (t, taken) => { api.setData({ ...base, transactions: [t] }); return api.findHandLoggedMatch(rec, "2026-09-03", taken || new Set()); };
    assert.equal(find(tx())?.id, "x", "two days early, same account and amount → match");
    assert.equal(find(tx({ envelopeId: "other" }))?.id, "x", "a different envelope is still the same payment");
    assert.equal(find(tx({ date: "2026-08-29" })), null, "five days away → no");
    assert.equal(find(tx({ amount: 1099.99 })), null, "a cent off → no");
    assert.equal(find(tx({ accountId: "savings" })), null, "another account → no");
    assert.equal(find(tx({ type: "income" })), null, "another type → no");
    assert.equal(find(tx({ fromRecurringId: "r1" })), null, "already generated from a recurring → no");
    assert.equal(find(tx(), new Set(["x"])), null, "claimed by another due row → no");
    // closest date wins
    api.setData({ ...base, transactions: [tx({ id: "far", date: "2026-09-01" }), tx({ id: "near", date: "2026-09-04" })] });
    assert.equal(api.findHandLoggedMatch(rec, "2026-09-03", new Set()).id, "near");
    // transfers match on the from/to pair
    const trec = { id: "r2", type: "transfer-account", amount: 200, fromAccountId: "cash", toAccountId: "savings" };
    api.setData({ ...base, transactions: [{ id: "t", date: "2026-09-02", type: "transfer-account", amount: 200, fromAccountId: "cash", toAccountId: "savings" }] });
    assert.equal(api.findHandLoggedMatch(trec, "2026-09-01", new Set())?.id, "t");
    api.setData({ ...base, transactions: [{ id: "t", date: "2026-09-02", type: "transfer-account", amount: 200, fromAccountId: "savings", toAccountId: "cash" }] });
    assert.equal(api.findHandLoggedMatch(trec, "2026-09-01", new Set()), null, "reversed direction → no");
  });

  check("Fund-one-month does not silently repay overspending", () => {
    api.setData({
      accounts: [], recurring: [], transactions: [],
      envelopes: [{ id: "food", openingBalance: -735, budgetAmount: 1000, cadence: "monthly" }],
    });
    const suggestion = api.envelopeFundSuggestion(api.getData().envelopes[0], "month");
    assert.equal(suggestion.suggested, 1000);
  });

  check("Fund envelope: the projected-low solver lands the low at zero, fills a hole for free, and knows when it cannot help", () => {
    const today = api.todayISO();
    api.setData({
      accounts: [
        { id: "cash", openingBalance: 1000, includeInNetWorth: true },
        { id: "other", openingBalance: 500, includeInNetWorth: true },
      ],
      envelopes: [
        { id: "reserve", isReserve: true, openingBalance: 200, budgetAmount: 0, cadence: "monthly" },
        { id: "living", openingBalance: 300, budgetAmount: 300, cadence: "monthly" },
        { id: "hole", openingBalance: -100, budgetAmount: 0, cadence: "monthly" },
        { id: "theirs", accountId: "other", openingBalance: 50, budgetAmount: 0, cadence: "monthly" },
      ],
      transactions: [], recurring: [],
    });
    const opts = { includeAllowances: false };
    // cash 1000 less 200 + 300 reserved: the hole is floored at zero and
    // "theirs" sits in the other account, so neither counts here.
    const base = api.spendableLow(api.forecastAccountBalances(["cash"], 30, opts));
    assert.ok(Math.abs(base.min - 500) < 0.005, `base low ${base.min}`);
    assert.equal(api.spendableToday(["cash"]), 500);
    // The reserve has no allowance and a positive balance: the answer is the low itself,
    // and funding it lands the low at zero.
    const z = api.fundingToZeroLow("reserve", ["cash"], 30, opts, today);
    assert.equal(z, 500);
    const after = api.spendableMinAfterFunding(["cash"], 30, opts, [{ envelopeId: "reserve", amount: z, date: today }]);
    assert.ok(Math.abs(after.min) < 0.005, `low after funding ${after.min}`);
    // An overspent envelope absorbs its overspend before it costs spendable anything.
    assert.equal(api.fundingToZeroLow("hole", ["cash"], 30, opts, today), 600);
    // Backed by an account outside the selection: no amount moves this low.
    assert.equal(api.fundingToZeroLow("theirs", ["cash"], 30, opts, today), null);
    // Over both accounts it counts, and the low is 1500 - 550.
    assert.equal(api.fundingToZeroLow("theirs", ["cash", "other"], 30, opts, today), 950);
    // Already below zero: nothing can be set aside.
    api.getData().accounts[0].openingBalance = 400;
    assert.equal(api.fundingToZeroLow("reserve", ["cash"], 30, opts, today), 0);
  });

  check("Only expense recurrings cover an allowance; transfers and income move or add cash, never stand in for it", () => {
    api.setToday("2026-09-16");
    const fixture = (rec) => ({
      accounts: [{ id: "cash", openingBalance: 5000, includeInNetWorth: true }],
      envelopes: [
        { id: "food", name: "Food", openingBalance: 200, budgetAmount: 300, cadence: "monthly" },
        { id: "reserve", name: "Reserve", openingBalance: 1000, budgetAmount: 0, cadence: "monthly", isReserve: true },
      ],
      transactions: [], recurring: rec ? [rec] : [],
    });
    const stream = { id: "r1", schedule: "monthly", startDate: "2026-01-01", active: true, lastAppliedDate: "2026-09-01", amount: 100 };
    const food = () => api.getData().envelopes[0];
    // An expense on the envelope models 100 of its 300: the allowance drains the other 200.
    api.setData(fixture({ ...stream, type: "expense", accountId: "cash", envelopeId: "food" }));
    assert.equal(api.recurringMonthlyForEnvelope(food()), 100);
    // A recurring top-up from the reserve moves no cash: Food still spends 300 from the account.
    api.setData(fixture({ ...stream, type: "transfer-envelope", fromEnvelopeId: "reserve", toEnvelopeId: "food" }));
    assert.equal(api.recurringMonthlyForEnvelope(food()), 0);
    const withTransfer = api.forecastAccountBalances(["cash"], 90, { includeAllowances: true });
    api.setData(fixture(null));
    const bare = api.forecastAccountBalances(["cash"], 90, { includeAllowances: true });
    assert.ok(Math.abs(withTransfer.total[90] - bare.total[90]) < 0.005,
      `a recurring envelope transfer must not change the projected cash total (${withTransfer.total[90]} vs ${bare.total[90]})`);
    // Income onto the envelope adds cash; it does not also reduce the projected drain.
    api.setData(fixture({ ...stream, type: "income", accountId: "cash", envelopeId: "food" }));
    assert.equal(api.recurringMonthlyForEnvelope(food()), 0);
    const withIncome = api.forecastAccountBalances(["cash"], 90, { includeAllowances: true });
    // Oct 1, Nov 1, Dec 1 fall inside the 90 days from 2026-09-16: exactly three occurrences of 100.
    assert.ok(Math.abs((withIncome.total[90] - bare.total[90]) - 300) < 0.005,
      `income recurring should add its occurrences and nothing else (${withIncome.total[90] - bare.total[90]})`);
    // A one-off and an ended template still cover nothing (decision #50).
    api.setData(fixture({ ...stream, type: "expense", accountId: "cash", envelopeId: "food", schedule: "once" }));
    assert.equal(api.recurringMonthlyForEnvelope(food()), 0);
  });

  check("Fund the month is assumed: budgeted envelopes are refilled on the 1st, reset envelopes release at month end", () => {
    api.setToday("2026-09-16");
    const fixture = (extra) => ({
      accounts: [{ id: "cash", openingBalance: 1000, includeInNetWorth: true }],
      envelopes: [{ id: "food", name: "Food", openingBalance: 300, budgetAmount: 300, cadence: "monthly", rolloverPolicy: "rollover", ...extra }],
      transactions: [], recurring: [],
    });
    // Decision #22's example, 60 days from 16 Sep: cash 1000, Food holds 300, 300 a month.
    api.setData(fixture());
    const spent = api.forecastAccountBalances(["cash"], 60, { includeAllowances: true, assumeRefill: false });
    const refilled = api.forecastAccountBalances(["cash"], 60, { includeAllowances: true });
    // Cash drains identically in both readings: 300 in September, 300 in October, 15/30 of November.
    assert.ok(Math.abs(spent.total[60] - refilled.total[60]) < 0.005, "refills never touch cash");
    // Each month's budget is spent over its first 28 days (decision #58): September's
    // remainder by the 28th, all of October's by the 28th, 15/28 of November's by the 15th.
    assert.ok(Math.abs(refilled.total[60] - (1000 - 300 - 300 - 300 * 15 / 28)) < 0.05, `cash at day 60: ${refilled.total[60]}`);
    const oct29 = refilled.dates.indexOf("2026-10-29"), oct31 = refilled.dates.indexOf("2026-10-31");
    assert.ok(Math.abs(refilled.total[oct31] - refilled.total[oct29 - 1]) < 0.005, "nothing is spent on the 29th–31st");
    assert.ok(Math.abs(refilled.total[oct31] - (1000 - 300 - 300)) < 0.05, "and October has spent exactly one month's budget by then");
    // Spent down: Food's 300 is consumed, so the low is cash at the horizon — 239.29
    // (1000 less September's 300, October's 300 and 15/28 of November's).
    assert.ok(Math.abs(api.spendableLow(spent).min - (1000 - 300 - 300 - 300 * 15 / 28)) < 0.05, `spent-down low ${api.spendableLow(spent).min}`);
    // Refilled: on 1 Nov, after funding the month, cash is 400 and Food holds 300 — unallocated 100.
    const low = api.spendableLow(refilled);
    assert.ok(Math.abs(low.min - 100) < 0.05, `refill low ${low.min}`);
    assert.equal(low.date, "2026-11-01");
    const nov1 = refilled.dates.indexOf("2026-11-01");
    // The 1st carries the refill and that day's own drain (300 over November's 30 days).
    assert.ok(Math.abs(refilled.envelopeTotal[nov1] - (300 - 300 / 28)) < 0.05, `Food is back at its budget on the 1st (${refilled.envelopeTotal[nov1]})`);
    assert.ok(Math.abs(refilled.envelopeTotal[nov1 - 1]) < 0.05, "and empty the day before");
    assert.equal(refilled.allowanceInfo.assumeRefill, true);
    assert.equal(spent.allowanceInfo.assumeRefill, false);
    // A reset envelope hands its leftover back at month end: 500 held, 300 budget,
    // so 200 returns to spendable on 30 Sep, then the 1st refills 300.
    api.setData(fixture({ openingBalance: 500, rolloverPolicy: "reset" }));
    const reset = api.forecastAccountBalances(["cash"], 60, { includeAllowances: true });
    const sep30 = reset.dates.indexOf("2026-09-30"), oct1 = sep30 + 1;
    assert.ok(Math.abs(reset.envelopeTotal[sep30]) < 0.05, `reset leftover released at month end (${reset.envelopeTotal[sep30]})`);
    assert.ok(Math.abs(reset.envelopeTotal[oct1] - (300 - 300 / 28)) < 0.05, `and refilled on the 1st, net of that day's drain (${reset.envelopeTotal[oct1]})`);
    assert.ok(Math.abs(reset.spendable[sep30] - (1000 - 300)) < 0.05, "the released 200 is spendable again");
    // An envelope whose spending is not in this forecast is neither drained nor refilled.
    api.setData({
      accounts: [{ id: "mine", openingBalance: 1000, includeInNetWorth: true }, { id: "theirs", openingBalance: 1000, includeInNetWorth: true }],
      envelopes: [{ id: "rent", name: "Rent", openingBalance: 100, budgetAmount: 300, cadence: "monthly", accountId: "theirs" }],
      transactions: [], recurring: [],
    });
    const mine = api.forecastAccountBalances(["mine"], 60, { includeAllowances: true });
    assert.deepEqual(Array.from(mine.allowanceInfo.unassigned).map(x => x.name), ["Rent"]);
    assert.ok(Math.abs(mine.total[60] - 1000) < 0.005);
    assert.ok(Math.abs(mine.spendable[60] - 1000) < 0.005, "an excluded backed envelope is not refilled into this forecast");
    // Allowances off: the refill flag is inert.
    api.setData(fixture());
    const off = api.forecastAccountBalances(["cash"], 60, { includeAllowances: false });
    assert.ok(Math.abs(api.spendableLow(off).min - 700) < 0.005);
    assert.equal(off.allowanceInfo.assumeRefill, false);
  });

  check("Returning money from an envelope also removes it from this month's projected spending", () => {
    api.setToday("2026-09-16");
    const fixture = (balance, extraTx = []) => ({
      accounts: [{ id: "cash", openingBalance: 1000, includeInNetWorth: true }],
      envelopes: [{ id: "food", name: "Food", openingBalance: balance, budgetAmount: 300, cadence: "monthly" }],
      transactions: extraTx, recurring: [],
    });
    const ret = (amount, date = "2026-09-16", payee = "Return to spendable") =>
      ({ id: "r-" + amount + date, date, type: "expense", amount, accountId: null, envelopeId: "food", payee });
    const low = () => api.spendableLow(api.forecastAccountBalances(["cash"], 60, { includeAllowances: true })).min;
    const anchor = () => api.forecastAccountBalances(["cash"], 60, { includeAllowances: true }).allowanceInfo.calendarAnchor;
    // Food holds exactly its budget, nothing spent yet: returning all of it raises today AND the low by 300.
    api.setData(fixture(300));
    const base = { today: api.spendableToday(["cash"]), low: low() };
    api.setData(fixture(300, [ret(300)]));
    assert.equal(api.spendableToday(["cash"]) - base.today, 300);
    assert.ok(Math.abs(low() - base.low - 300) < 0.005, `return of the whole budget: low +300, got ${low() - base.low}`);
    // Returning a surplus above the budget still only cancels this month's projection (floored at zero)
    // and every returned euro reaches the low.
    api.setData(fixture(500));
    const surplus = low();
    api.setData(fixture(500, [ret(500)]));
    assert.ok(Math.abs(low() - surplus - 500) < 0.005, `return above the budget: low +500, got ${low() - surplus}`);
    // A return dated last month, or a balance adjustment, does not touch this month's projection:
    // the low rises only by the reservation the envelope would have carried at the low date.
    api.setData(fixture(300));
    const plain = low();
    api.setData(fixture(300, [ret(300, "2026-08-20")]));
    assert.ok(low() - plain < 300 - 0.005, "last month's return is not this month's signal");
    api.setData(fixture(300, [ret(300, "2026-09-16", "Balance adjustment")]));
    assert.ok(low() - plain < 300 - 0.005, "a balance adjustment is not a return");
    assert.equal(anchor().smoothDays, 28);
  });

  check("One occurrence can carry its own amount or be skipped; every reader honours it, the template does not move", () => {
    api.setToday("2026-09-16");
    // 1. the accessor: an override for that date only, unreadable values fall back
    const yearly = { id: "xmas", name: "Xmas", type: "expense", amount: 2500, schedule: "yearly", startDate: "2025-12-20", accountId: "cash", envelopeId: "gifts", active: true, lastAppliedDate: "2025-12-20" };
    assert.equal(api.occurrenceAmount(yearly, "2026-12-20"), 2500);
    yearly.overrides = { "2026-12-20": { amount: 2000 } };
    assert.equal(api.occurrenceAmount(yearly, "2026-12-20"), 2000);
    assert.equal(api.occurrenceAmount(yearly, "2027-12-20"), 2500, "later years keep the template amount");
    assert.equal(api.occurrenceAmount({ amount: 9, overrides: { d: { amount: 0 } } }, "d"), 9);
    assert.equal(api.occurrenceAmount({ amount: 9, overrides: { d: { amount: "x" } } }, "d"), 9);
    // 2. set / clear: equal to the template (to the cent) removes the entry, empty map deleted
    const r = { amount: 2500 };
    assert.equal(api.setOccurrenceOverride(r, "d", 2000), true);
    assert.equal(r.overrides.d.amount, 2000);
    assert.equal(api.setOccurrenceOverride(r, "d", 2000.004), false, "same amount to the cent is no change");
    assert.equal(api.setOccurrenceOverride(r, "d", 2500), true);
    assert.equal(r.overrides, undefined, "back to the template removes the entry and the map");
    assert.equal(api.setOccurrenceOverride(r, "d", 2500.004), false);
    assert.equal(api.setOccurrenceOverride(r, "d", NaN), false);
    // 3. skip / unskip one date; the pending, due and FORECAST readers all leave it out
    api.setData({
      accounts: [{ id: "cash", openingBalance: 1000, includeInNetWorth: true }],
      envelopes: [{ id: "gifts", name: "Gifts", budgetAmount: 0, cadence: "monthly" }],
      transactions: [], recurring: [yearly],
    });
    const dec20 = 14 + 31 + 30 + 20;   // 2026-12-20 is day 95 from 2026-09-16
    let fc = api.forecastAccountBalances(["cash"], 120, { includeAllowances: false });
    assert.equal(fc.dates[dec20], "2026-12-20");
    assert.ok(Math.abs(fc.total[dec20 - 1] - 1000) < 0.005);
    assert.ok(Math.abs(fc.total[dec20] - (1000 - 2000)) < 0.005, "the future loop books the date's own amount");
    delete yearly.overrides;
    fc = api.forecastAccountBalances(["cash"], 120, { includeAllowances: false });
    assert.ok(Math.abs(fc.total[dec20] - (1000 - 2500)) < 0.005, "without an override the template amount is booked");
    assert.equal(api.setOccurrenceSkipped(yearly, "2026-12-20", true), true);
    assert.equal(api.setOccurrenceSkipped(yearly, "2026-12-20", true), false);
    assert.equal(api.firstPendingOccurrence(yearly), "2027-12-20", "the pending scan steps over a skipped future date");
    fc = api.forecastAccountBalances(["cash"], 120, { includeAllowances: false });
    assert.ok(Math.abs(fc.total[120] - 1000) < 0.005, "a skipped future occurrence leaves the projection");
    assert.equal(api.setOccurrenceSkipped(yearly, "2026-12-20", false), true);
    assert.equal(yearly.skippedDates, undefined);
    // 4. due rows carry the date's own amount and the idx-0 fold books it
    const monthly = { id: "gym", name: "Gym", type: "expense", amount: 100, schedule: "monthly", startDate: "2026-01-05", accountId: "cash", active: true, lastAppliedDate: "2026-08-05", overrides: { "2026-09-05": { amount: 80 } } };
    api.setData({ accounts: [{ id: "cash", openingBalance: 1000, includeInNetWorth: true }], envelopes: [], transactions: [], recurring: [monthly] });
    const due = Array.from(api.dueRecurringOccurrences());
    assert.equal(due.length, 1);
    assert.equal(due[0].date, "2026-09-05");
    assert.equal(due[0].amount, 80);
    assert.ok(Math.abs(api.forecastAccountBalances(["cash"], 30, { includeAllowances: false }).total[0] - 920) < 0.005);
    api.setOccurrenceSkipped(monthly, "2026-09-05", true);
    assert.equal(api.dueRecurringOccurrences().length, 0, "a skipped due date is not offered");
    api.setOccurrenceSkipped(monthly, "2026-09-05", false);
    // 5. a hand-logged transaction is matched against the date's own amount
    api.getData().transactions.push({ id: "h1", date: "2026-09-04", type: "expense", amount: 80, accountId: "cash" });
    assert.equal(api.findHandLoggedMatch(monthly, "2026-09-05", new Set()).id, "h1");
    api.getData().transactions[0].amount = 100;
    assert.equal(api.findHandLoggedMatch(monthly, "2026-09-05", new Set()), null, "the template amount no longer matches an overridden date");
    // 6. the prune: everything at or below the watermark goes, containers deleted when empty
    const p = { amount: 100, lastAppliedDate: "2026-09-05", skippedDates: ["2026-08-05", "2026-10-05"], overrides: { "2026-08-05": { amount: 1 }, "2026-10-05": { amount: 2 } } };
    api.pruneResolvedOccurrences(p);
    assert.deepEqual(Array.from(p.skippedDates), ["2026-10-05"]);
    assert.deepEqual(Object.keys(p.overrides), ["2026-10-05"]);
    p.lastAppliedDate = "2026-10-05";
    api.pruneResolvedOccurrences(p);
    assert.equal(p.skippedDates, undefined);
    assert.equal(p.overrides, undefined);
    // 7. migrate's sanitiser drops what cannot be read and keeps what can, even behind the watermark
    const s = { amount: 100, lastAppliedDate: "2026-09-05", overrides: { "2026-2-3": { amount: 5 }, nope: { amount: 5 }, "2026-10-05": { amount: -5 }, "2026-11-05": { amount: "x" }, "2026-12-05": null, "2026-08-05": { amount: 7 } } };
    api.sanitizeRecurringOverrides(s);
    assert.deepEqual(Object.keys(s.overrides), ["2026-08-05"]);
    const t = { amount: 100, overrides: [1, 2] };
    api.sanitizeRecurringOverrides(t);
    assert.equal(t.overrides, undefined);
    // 8. allowance netting still uses the template's monthly rate
    api.setData({ accounts: [], envelopes: [{ id: "gifts", name: "Gifts", budgetAmount: 300, cadence: "monthly" }], transactions: [],
      recurring: [{ ...yearly, overrides: { "2026-12-20": { amount: 2000 } } }] });
    assert.ok(Math.abs(api.recurringMonthlyForEnvelope(api.getData().envelopes[0]) - 2500 / 12) < 0.005);
  });

  check("Move funds probe: transfers leave data untouched and move spendable only across the zero floor", () => {
    api.setToday("2026-09-16");
    api.setData({
      accounts: [{ id: "cash", openingBalance: 4720, includeInNetWorth: true }],
      envelopes: [
        { id: "food", name: "Food", openingBalance: 200, budgetAmount: 300, cadence: "monthly" },
        { id: "fun", name: "Fun", openingBalance: -80, budgetAmount: 100, cadence: "monthly" },
        { id: "reserve", name: "Reserve", openingBalance: 1000, budgetAmount: 0, cadence: "monthly", isReserve: true },
      ],
      transactions: [], recurring: [],
    });
    const saved = api.getData().transactions;
    const probe = (from, to, amount) => ({ id: "__moveProbe", date: "2026-09-16", type: "transfer-envelope", amount, fromEnvelopeId: from, toEnvelopeId: to });
    const today = () => api.spendableToday(["cash"]);
    const low = (refill) => api.spendableLow(api.forecastAccountBalances(["cash"], 90, { includeAllowances: true, assumeRefill: refill })).min;
    assert.equal(today(), 3520, "fun's overspend has already come out of spendable");
    // Covering the overspend from the reserve gives that 80 back; the probe never lands in the data.
    assert.equal(api.withProbeTxs([probe("reserve", "fun", 80)], today), 3600);
    assert.equal(api.getData().transactions, saved);
    assert.equal(api.getData().transactions.length, 0);
    // Overdrawing the source lowers today by the shortfall only.
    assert.equal(api.withProbeTxs([probe("food", "reserve", 250)], today), 3470);
    // Both stay positive: today is unchanged either way.
    assert.equal(api.withProbeTxs([probe("reserve", "food", 300)], today), 3520);
    // With Fund the month assumed (the default) the projected low does not move either —
    // a budgeted envelope's money is as kept as the reserve's (decision #57) — provided the
    // envelope never runs out inside the horizon. Food at 200 with 300 still to spend this
    // month would cross zero (and that shortfall rightly lands on spendable), so give it
    // more than it spends: 600 today, never below 150 after any of these moves.
    api.getData().envelopes[0].openingBalance = 600;
    const refillLow = low(true);
    assert.ok(Math.abs(api.withProbeTxs([probe("reserve", "food", 300)], () => low(true)) - refillLow) < 0.005, "refill: reserve → Food leaves the low alone");
    assert.ok(Math.abs(api.withProbeTxs([probe("food", "reserve", 150)], () => low(true)) - refillLow) < 0.005, "refill: Food → reserve leaves the low alone");
    // With refills off, Food spends its budget either way, so money moved into it is spent
    // inside the horizon and the low rises by the full amount; out of it, the low falls.
    const baseLow = low(false);
    assert.ok(Math.abs(api.withProbeTxs([probe("reserve", "food", 300)], () => low(false)) - (baseLow + 300)) < 0.005);
    assert.ok(Math.abs(api.withProbeTxs([probe("food", "reserve", 150)], () => low(false)) - (baseLow - 150)) < 0.005);
    // The restore runs even when the probe throws.
    assert.throws(() => api.withProbeTxs([probe("food", "reserve", 1)], () => { throw new Error("boom"); }), /boom/);
    assert.equal(api.getData().transactions, saved);
  });

  check("Envelope-only adjustments are excluded from cashflow", () => {
    assert.equal(api.isCashflowTx({ type: "expense", accountId: null, amount: 10 }), false);
    assert.equal(api.isCashflowTx({ type: "expense", accountId: "cash", amount: 10 }), true);
    assert.equal(api.isCashflowTx({ type: "income", accountId: "invest", payee: "Market adjustment" }), false);
  });
}

if (api) {
  check("Reports retain twelve distinct months on month-end and leap dates", () => {
    api.setData({ transactions: [], envelopes: [], settings: {} });
    for (const date of ["2026-03-29", "2026-03-30", "2026-03-31", "2024-02-29", "2026-01-31"]) {
      api.setToday(date);
      const keys = Array.from(api.reportsAggregates().months, m => m.key);
      assert.equal(new Set(keys).size, 12, date);
      assert.equal(keys[11], date.slice(0, 7));
      for (let i = 1; i < keys.length; i++) {
        const serial = k => Number(k.slice(0, 4)) * 12 + Number(k.slice(5));
        assert.equal(serial(keys[i]) - serial(keys[i - 1]), 1);
      }
    }
  });
  check("Cards, close-out and reports count actual spending, excluding future rows and reallocations", () => {
    api.setToday("2026-09-10");
    const food = { id: "food", name: "Food", openingBalance: 300 };
    api.setData({ envelopes: [food, { id: "fun", name: "Fun" }], settings: { tags: ["Bills"] }, transactions: [
      { date: "2026-09-01", type: "expense", amount: 250, accountId: "cash", envelopeId: "food" },
      { date: "2026-09-02", type: "expense", amount: 30, accountId: "cash", splits: [{ envelopeId: "food", amount: 20 }, { envelopeId: "fun", amount: 10 }] },
      { date: "2026-09-03", type: "transfer-envelope", amount: 15, fromEnvelopeId: "food", toEnvelopeId: "fun", payee: "Close-out sweep" },
      { date: "2026-09-04", type: "transfer-envelope", amount: 5, fromEnvelopeId: "food", toEnvelopeId: "fun", payee: "Move funds" },
      { date: "2026-09-05", type: "income", amount: 40, envelopeId: "food", accountId: null },
      { date: "2026-09-06", type: "expense", amount: 3, envelopeId: "food", accountId: null },
      { date: "2026-09-10", type: "transfer-account", amount: 7, fromAccountId: "cash", toAccountId: "savings", tag: "Bills" },
      { date: "2026-09-25", type: "expense", amount: 100, accountId: "cash", envelopeId: "food", tag: "Bills" },
      { date: "2026-09-25", type: "income", amount: 200, accountId: "cash", envelopeId: "food" },
    ] });
    assert.equal(api.envelopeMonthSpendMap("2026-09").food, 270);
    const summary = api.envelopeMonthSummary(food, "2026-09");
    assert.equal(summary.spent, 270);
    assert.equal(summary.funded, 40);
    assert.equal(summary.balance, 147, "month-end balance still includes scheduled rows and reallocations");
    const report = api.reportsAggregates();
    assert.equal(report.months[11].expense, 280);
    assert.equal(report.months[11].income, 0);
    assert.equal(report.envSpend.find(e => e.name === "Food").amt, 270);
    assert.equal(report.tagSpend.find(t => t.name === "Bills").amt, 7, "tagged account transfers retain their meaning");
    api.setToday("2026-10-01");
    assert.equal(api.envelopeMonthSummary(food, "2026-09").spent, 370, "past months include all actual rows");
  });
}

// Drive the real persistence functions with delayed responses, never a budget file.
function persistenceApi() {
  const requests = [], statuses = [];
  const context = vm.createContext({
    console: { error() {} }, TextEncoder,
    setTimeout: () => 1, clearTimeout() {},
    fetch(url, options) { return new Promise(resolve => requests.push({ options, resolve })); },
    recordStatus: value => statuses.push(value),
  });
  const names = ["writeFile", "persistData", "saveDirty", "flushNow", "loadFromServer"];
  vm.runInContext(`
    let data = { value: 'A' }, dirty = true, demoMode = false, conflictPending = false;
    let serverEtag = 'initial', saveInFlight = null, saveKeepaliveRequested = false, saveTimer = null, loadState = 'loaded';
    const DATA_URL = '/data';
    function setStatus(s) { recordStatus(s); }
    function updateFileStatus(s) { recordStatus(s); }
    function toast() {} function ensureDailyBackup() {}
    function safeParseData(text) { return JSON.parse(text); }
    function handleConflict() { conflictPending = true; dirty = true; recordStatus('conflict'); }
    ${names.map(n => extractFunction(mainInlineScript(app), n)).join("\n")}
    globalThis.api = { ${names.join(",")},
      edit(value) { data = value; saveDirty(); },
      demo() { demoMode = true; },
      state() { return { dirty, conflictPending, serverEtag, loadState, data }; }
    };
  `, context);
  return { ...context.api, requests, statuses };
}
function respond(request, status = 204, tag = 'saved', text = async () => '{}') {
  request.resolve({ status, ok: status >= 200 && status < 300, headers: { get: k => k === 'ETag' ? tag : null }, text });
}
async function until(predicate) {
  for (let i = 0; i < 30; i++) { if (predicate()) return; await Promise.resolve(); }
  assert.ok(predicate(), "expected asynchronous progress");
}
async function asyncCheck(name, fn) {
  try { await fn(); pass(name); } catch (error) { fail(name, error.message); }
}
await asyncCheck("Delayed saves drain newer edits with a fresh ETag and no self-conflict", async () => {
  const p = persistenceApi();
  const first = p.writeFile();
  p.edit({ value: 'B' });
  p.flushNow();
  const joined = p.writeFile();
  assert.equal(p.requests.length, 1);
  respond(p.requests[0], 204, 'A-tag');
  await until(() => p.requests.length === 2);
  assert.equal(p.state().dirty, true);
  assert.ok(!p.statuses.includes('finance-data.json'), "must not label newer edits saved early");
  assert.equal(JSON.parse(p.requests[1].options.body).value, 'B');
  assert.equal(p.requests[1].options.headers['If-Match'], 'A-tag');
  assert.equal(p.requests[1].options.keepalive, true);
  respond(p.requests[1]);
  assert.equal(await first, true);
  assert.equal(await joined, true);
  assert.equal(p.requests.length, 2);
  assert.equal(p.state().dirty, false);
});
await asyncCheck("Real conflicts pause saving until an explicit overwrite; failures preserve dirty state", async () => {
  const p = persistenceApi();
  const first = p.writeFile();
  respond(p.requests[0], 409, 'other-device');
  assert.equal(await first, false);
  assert.equal(await p.writeFile(), false);
  assert.equal(p.requests.length, 1);
  assert.equal(p.state().dirty, true);
  const forced = p.writeFile({ force: true });
  assert.equal(p.requests[1].options.headers['If-Match'], undefined);
  respond(p.requests[1], 503);
  assert.equal(await forced, false);
  assert.equal(p.state().dirty, true);
  const retry = p.writeFile({ force: true });
  respond(p.requests[2]);
  assert.equal(await retry, true);
  assert.equal(p.state().conflictPending, false);
});
await asyncCheck("Keepalive measures UTF-8 bytes, and demo edits never send requests", async () => {
  for (const [value, expected] of [['x'.repeat(40000), true], ['α'.repeat(40000), false]]) {
    const p = persistenceApi(); p.edit({ value });
    const saving = p.writeFile({ keepalive: true });
    assert.equal(p.requests[0].options.keepalive, expected);
    respond(p.requests[0]); await saving;
  }
  const p = persistenceApi(); p.demo();
  assert.equal(await p.writeFile(), true);
  assert.equal(p.requests.length, 0);
});
await asyncCheck("A failed response-body read leaves the existing budget and failed-load guard intact", async () => {
  const p = persistenceApi();
  const loading = p.loadFromServer();
  respond(p.requests[0], 200, 'new-tag', async () => { throw Error('connection reset'); });
  assert.equal(await loading, false);
  assert.equal(p.state().loadState, 'failed');
  assert.equal(p.state().data.value, 'A');
});

// ------------------------------------------------------- 3b. serve.py guards
{
  const script = [
    "import importlib.util, sys",
    "spec = importlib.util.spec_from_file_location('serve', 'serve.py'); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)",
    "priv = ['/finance-data.json', '/finance%2Ddata.json', '/finance%252Ddata.json', '/finance-data.bak.0', '/finance%2Ddata.bak.0', '/.git/config', '/%2Egit/config', '/serve-daemon%2Elog', '/icons/../finance-data.json', '/.claude/launch.json']",
    "pub = ['/', '/pocket-envelopes.app', '/sw.js', '/manifest.webmanifest', '/icons/icon-192.png', '/vendor/chart.umd.min.js']",
    "bad = [p for p in priv if not m._is_private_url(p)] + [p for p in pub if m._is_private_url(p)]",
    "hosts_ok = ['localhost:8765', '127.0.0.1:8765', '[::1]:8765', '192.168.1.20:8765', 'mini-pc.tail1234.ts.net', None, '']",
    "hosts_bad = ['attacker.example:8765', 'evil.com', 'localhost.evil.com:8765']",
    "bad += [h for h in hosts_ok if not m._host_allowed_name(h)] + [h for h in hosts_bad if m._host_allowed_name(h)]",
    "print('OK' if not bad else 'BAD ' + repr(bad))",
  ].join("\n");
  const candidates = process.platform === "win32"
    ? [["py", ["-3", "-c", script]], ["python", ["-c", script]]]
    : [["python3", ["-c", script]], ["python", ["-c", script]]];
  let ran = false;
  for (const [cmd, args] of candidates) {
    const r = spawnSync(cmd, args, { cwd: root, encoding: "utf8" });
    if (r.error) continue;
    ran = true;
    const out = (r.stdout || "").trim();
    if (r.status === 0 && out === "OK") pass("serve.py refuses private paths after decoding, and foreign Host headers");
    else fail("serve.py refuses private paths after decoding, and foreign Host headers", out || r.stderr);
    break;
  }
  if (!ran) warn("serve.py guard checks skipped", "no Python found");
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
