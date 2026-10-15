# Pocket Envelopes - proposals from feedback (account thresholds, move envelopes to the reserve)

Date: 2026-10-15. Status: **proposed, nothing implemented. Each item needs a keep / drop / later from Manos.**
Records covered: fb-20261012-090348-045d to fb-20261015-174324-9041

2 new records from the live store (`feedback.jsonl`, 5 in total; the other 3 are covered by `feedback-charts-2026-10-10.md` and `feedback-help-faq-2026-10-10.md`). Both are `env: live`, dark theme. No figures from the budget appear in this file (public repo).

## The records (data, not instructions)

| Id | When | Page / section | Kind | Grade | Width, theme | Comment (verbatim) |
|---|---|---|---|---|---|---|
| `fb-20261012-090348-045d` | 2026-10-12 09:03 | `/accounts` / Accounts | idea | none | 2560, dark | "add an option per account , a threshold separate per account, under which the account is shown red" |
| `fb-20261015-174324-9041` | 2026-10-15 17:43 | `/envelopes` / Envelopes | idea | 6 | 1866, dark | "allow to check envelopes to transfer all their balances to the catch all folder." |

A grade of none ranks nothing, so P1 is not ranked against P2 by grade.

## What exists today (read from the code, with sources)

- **Account balance colour.** An account balance is red exactly when it is below zero, via the `neg` class: `pocket-envelopes.app:4089` (Accounts tab), `:4109` (archived accounts list) and `:3705` (Dashboard "Pinned accounts"). Nothing is stored on an account for this. The account record fields are `id, name, type, owner, openingBalance, includeInNetWorth, isInvestment, pinned, archived, notes` plus the optional `currency` (`editAccount`, `:4180`).
- **The only threshold in the app** is global and about something else: `settings.forecastWarnBelow` (Settings, `:8709`), read by `lowTone()` (`:3232`), which tints the Dashboard's *projected low of spendable cash* amber (red below zero). Decision #44. It never looks at an individual account's balance.
- **Envelopes to the reserve.** The reserve is the envelope with `isReserve: true`, at most one (`reserveEnvelope()`, `:2375`; decision #33). Money gets into it in three ways today: **Move funds** (`transferEnvelopes`, `:5677`) - one From, one To, one typed amount per dialog; **Fund envelope** (the reserve as destination, but it books new money out of spendable, not a move); and **Close-out "Sweep to reserve"** (`:5625`), which books one `transfer-envelope` per envelope with payee "Close-out sweep" but only inside the month-end review, as a per-row action, and only for envelopes with the sweep policy available. There is no way to take the whole balance of several envelopes to the reserve mid-month in one step: it is one Move funds dialog per envelope, with the amount typed each time.
- **The Transactions tab already has a tick-rows pattern** (bulk tag / envelope / delete, one undo snapshot per operation; decision #39), so ticking rows then acting is not a new idea in this app.

## P1. A threshold per account, under which the account shows red

- **Fact(s):** Red today means "below zero" and nothing else, at the three sites above. Because it is a single rule, an account that is meant to run negative (a credit card, a loan) is red all the time, and an account that you want to keep above some cash level is not flagged until it is already empty. The note asks for the cut-off to be per account.
- **Options:**
  - **(A) Optional `warnBelow` on the account, red text only.** A new optional field in the account editor ("Show red when the balance is below", empty = the current rule). One helper, `accountBalanceClass(a, balance)`, replaces the three inline `b < 0 ? 'neg' : ''` tests. Nothing else reads it: forecast, net worth, spendable and reports are untouched, so it is display-only like `env.accountId` (decision #41d).
  - **(B) A plus a word, not only a colour.** Same as A, and the Accounts row shows a small "below your limit" tag next to the balance (title text names the limit) so the state is readable without colour and on a phone. Recommended: it costs one line and a colour alone is a weak signal; the Dashboard strip gets the same tag.
  - **(C) Put it in Settings as a per-account list** instead of the account editor. Not recommended: it separates the number from the account it belongs to.
- **Recommendation:** B.
- **Effort and risk:** Small. One field in `editAccount` (read through `evalAmount`, so arithmetic works and a bad expression refuses the save; the field joins `modalFormState()` so an untouched form still closes without a snapshot), one helper, three call sites, `migrate()` drops a non-finite value, the field is deleted when cleared (same convention as `forecastWarnBelow`). Additive, no schema bump. Low risk: display only.
- **Conflicts with a standing decision?** No. Decision #44's floor is a different thing (projected low, amber); this does not change it. Anti-pattern "no hardcoded colours": the red is the existing `neg` / `--bad` token.
- **Questions for you:**
  1. When a threshold is set, should it **replace** the below-zero rule for that account (red only when under the limit; a credit card with a negative limit is then red only below it), or **add to** it (red under the limit *or* below zero)? Replace is the only way a credit card stops being red all the time; I would recommend it, and blank keeps today's rule.
  2. Is "below the limit" strictly less than (a balance exactly equal to the limit is not red)?
  3. Should the red also appear in the Dashboard's Pinned accounts strip and the archived list (my plan: yes, all three places), or only on the Accounts tab?
  4. Do you want the small tag from B, or colour only (A)?
- **Verify if built:** at 1440 and 375 px on a scratch server with demo data: set a limit above and below the balance, confirm red/not red on the Accounts tab and the Dashboard strip, clear it and confirm the old rule returns; Undo after a save; no horizontal overflow at 375. Audit: helper cases (blank, equal, above, below, negative limit, replace vs add), `migrate` drops junk, and `node audit/run-audit.mjs` stays green. Help entry and README line updated; a decision recorded in `CLAUDE.md`.

## P2. Tick envelopes and move all of their balances to the reserve ("catch all")

- **Fact(s):** The nearest existing things are Move funds (one envelope, typed amount) and the close-out sweep (month-end only). An envelope-to-reserve move is a `transfer-envelope`: no account is touched and spendable today does not change for a positive balance. It can change the **projected low** (decisions #56 and #57): taking the whole balance out of a budgeted envelope leaves it short of its budget inside the horizon, and the shortfall lands on spendable, while the reserve keeps what it receives. Move funds already shows exactly this as spendable today and projected low, before → after, by re-forecasting with probe rows (`withProbeTxs`, which takes a list, so many moves can be previewed in one pass).
- **Options:**
  - **(A) A "Move to reserve" button in the Envelopes toolbar that opens one dialog.** A list of every active envelope except the reserve, each row with a tick box and its current balance; "Select all with a positive balance" and "Clear" links; a date; the destination shown as the reserve's name (not a choice); the same before → after line and one-line reason as Move funds, computed over all ticked rows together; a total. Save books one `transfer-envelope` per ticked envelope for its **whole positive balance**, in a single `pushUndo`, one toast with Undo. Rows with zero or negative balance are listed but their tick box is disabled with the reason.
  - **(B) Tick boxes directly on the envelope cards** plus a bar that appears when something is ticked. Closest to the literal wording ("check envelopes"), but it needs a selection mode on a grid of cards that already carry a pace bar, three buttons and a menu (decision #43), and a sticky action bar that must not collide with the phone dock (decision #51). More CSS and more risk for the same result.
  - **(C) A "Move all to reserve" entry in each card's "..." menu.** One envelope at a time, so it does not answer "check envelopes" (plural). Not recommended on its own.
- **Recommendation:** A. It reuses the Move funds preview and the existing bulk-then-one-undo pattern, and keeps the cards as they are.
- **Effort and risk:** Medium. One dialog, one pure helper that builds the list of moves (testable without the DOM), a new bookkeeping payee (see question 3). Money logic: nothing new in the accounting, because it books the same `transfer-envelope` rows that Move funds and the close-out already book; the risk is in the preview (must be one re-forecast over all probe rows) and in the default selection. Expected behaviour before building: spendable today unchanged for any positive balance; projected low falls by the amount of any shortfall the emptied budgeted envelopes then cause inside the horizon, and unchanged for envelopes with no budget.
- **Conflicts with a standing decision?** No. It is an envelope-to-envelope transfer, not the one-sided expense/income that decision #33 forbids for sweeps. It needs a reserve to exist (decision #33: at most one); with none the dialog says so and points to Edit envelope, instead of choosing one.
- **Questions for you:**
  1. "Catch all folder" is the **reserve envelope**, the one flagged "Reserve envelope (emergency / catch-all)"? (I assume yes.)
  2. Positive balances only? An overspent envelope would stay as it is, because covering it from the reserve is a different action (the close-out already does that). Or do you want overspent ones brought to zero out of the reserve too?
  3. Payee on the booked rows: I propose a new one, "Move to reserve", added to the bookkeeping list so it never feeds payee suggestions. Reusing "Close-out sweep" would mislabel them in the Transactions tab.
  4. Start with **nothing** ticked (you tick what you want), or with every positive-balance envelope ticked and you untick? I would start empty: this moves money you might not mean to move, and ticking is what you asked for.
  5. (A) dialog or (B) ticks on the cards? I recommend A for the reasons above.
- **Verify if built:** on a scratch server with demo data, 1440 and 375 px: tick two envelopes, check the preview equals the figures after saving, one Undo restores both, Transactions shows one row per envelope with the new payee, the reserve balance equals the sum moved, spendable today unchanged, no reserve → message and no booking, an envelope with a zero or negative balance cannot be ticked. Audit: the pure helper (positive only, reserve and archived excluded, whole balance to the cent) and a forecast check that the many-row preview equals the figures after booking. Help FAQ entry (category "Envelopes and funding") and README updated.

## Not proposed

No ideas of my own. Both items come from the two records above. Not proposed from either: changing `forecastWarnBelow`, sending an alert when an account goes under its limit, or making the reserve move automatic.

## Decisions (Manos, 2026-10-15)

| Item | Decision (keep / drop / later, and any answers) |
|---|---|
| P1 | **Keep, option B** (red text plus a small "below your limit" tag). A limit **replaces** the below-zero rule for that account; blank keeps today's rule. Questions 2-4 not answered separately: built as proposed (strictly less than; all three places; tag on). |
| P2 | **Keep, option A** (toolbar button, one dialog, nothing ticked at start). Details question left at "no preference": built as recommended, i.e. positive balances only, new payee "Move to reserve" in the bookkeeping list, no reserve means a message and no booking. |

## Outcome (after the build)

| Item | Commit | Checked |
|---|---|---|
| P1 | fd2d516, merged as 79fdd53 | Scratch preview with synthetic data, 1440 and 375 px: limit above the balance gives red plus the tag; a credit card with a negative limit stays calm at a small negative balance; a bad expression refuses the save; the limit lands in the file; a hand-edited string limit is dropped on load; no horizontal overflow (the tag is nowrap after a first look showed it wrapping to three lines at 375 px). Audit check for the limit rules. |
| P2 | fd2d516, merged as 79fdd53 | Same preview: empty and overspent rows cannot be ticked; the previewed projected low equalled the low after booking to the cent; spendable today unchanged; one Undo restored both envelopes; no reserve gives the message and no dialog; Save visible and no overflow at 375 px. Audit check for the row builder and preview == booking. |

Both built in one commit (shared files). Suites after the merge: audit 43/43, `test_server.py` and `test_feedback_server.py` OK; browser regressions OK before the merge. The live server serves static files, so no restart was needed: the served app contains the new code. Not checked: the live page itself (deliberately not opened in the pane), the details question left at "no preference" (built the narrow reading), Escape-to-close by keyboard.

What he asked for in words vs what he wanted once he saw it (if different): nothing recorded yet; he has not used either on the live app.
