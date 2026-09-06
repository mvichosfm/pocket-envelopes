# Pocket Envelopes audit workflow

The repeatable review process for `pocket-envelopes.app`, the single-file local
application, and the small server that carries it (`serve.py`, `sw.js`).

The workflow is **report-first**: it identifies and ranks changes, it does not
silently alter financial behaviour. A logic change is implemented only after its
expected accounting outcome has been written down and covered by a test.

The audit has two halves:

- **Mechanical** — `node audit/run-audit.mjs` from the project folder (Node
  built-ins only, nothing to install). It compiles every inline script, extracts
  the accounting functions into a bare `vm` context and unit-tests them against
  synthetic fixtures, checks the single-file / locally-vendored invariants,
  checks that `sw.js` never intercepts `/data` and stays network-first, and
  compiles `serve.py`. It never reads `finance-data.json`. A FAIL means a stated
  invariant is broken (exit code 1); a WARN is something a human should look at.
- **Manual** — reading `pocket-envelopes.app` along the money flows and boundary
  cases below. This is where real findings come from; the script only keeps the
  known invariants from regressing.

## Phases

### 1. Baseline

Read `CLAUDE.md` (architecture invariants and the numbered decisions) and recent
git history. Note the current `SCHEMA_VERSION`. A finding that contradicts a
recorded decision must argue with the decision, not just the code.

### 2. Mechanical checks

Run `node audit/run-audit.mjs`. Fix nothing yet; paste the output into the report.

### 3. Logic, by money flow

Trace every transaction type through all of its consumers:

| Money flow | Account effect | Envelope effect | Review consumers |
|---|---:|---:|---|
| Expense | decreases | decreases | balances, reports, forecast, close-out |
| Income | increases | increases | balances, reports, forecast |
| Account transfer | net zero overall | none | account balances, forecast |
| Envelope transfer | none | net zero overall | envelope balances, forecast, sweeps |
| Split expense/income | one account total | multiple portions | reports, forecast, orphan guards |
| Envelope-only adjustment | none | changes | balances, but never cashflow spending |

For each flow review creation, editing, deletion, recurring materialisation,
forecast projection, reporting, undo, backup and CSV import. Amounts must go
through `txAccountDelta` / `txEnvelopePortion`, never a raw `tx.envelopeId`.

### 4. Time-based behaviour

Use boundary cases, not average dates:

- Month ends: 28/29 February and 30/31-day months; end-of-month anchoring.
- Unsorted custom months such as `[12, 4]`.
- Overdue recurring entries, and partial application across a gap.
- Future one-off transactions and due occurrences folded into forecast day 0.
- Annual envelopes, the reserve envelope, overspent envelopes, balances crossing zero.
- The current month draining budget-minus-spent while every future month drains
  exactly one month's allowance.
- Month close-out, calendar-year rollover, daylight-saving boundaries.

### 5. Storage and recovery

What is held in browser memory versus persisted in browser storage; what crosses
the network (only `GET`/`PUT /data` to the local server); and how a `409`
conflict, a corrupt file, an interrupted save and a stopped server are surfaced
and recovered (`.bak.N` rotation, dated backups, the conflict dialog).
Never use real financial data in tests — synthetic fixtures only.

### 6. Ranking

- **P0 — Critical:** unrecoverable silent corruption or loss of the budget file. Stop.
- **P1 — High:** realistic data-loss risk, or a figure the user acts on is wrong.
- **P2 — Medium:** incorrect edge behaviour, missing recovery, or a material test gap.
- **P3 — Low:** polish or measured performance work without present user harm.

Every proposal states its evidence, the invariant affected, the smallest safe
change, the regression test, and any migration or compatibility effect.

### 7. Close

Write the dated report and re-run `node audit/run-audit.mjs` after approved
fixes. Add a numbered decision to `CLAUDE.md` when a fix must not be undone
later. Keep deferred items explicit; do not re-propose optimisations already
measured as negligible.
