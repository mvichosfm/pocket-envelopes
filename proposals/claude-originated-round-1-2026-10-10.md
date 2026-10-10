# Pocket Envelopes - Claude-originated proposals, round 1

Date: 2026-10-10. Status: **proposed, nothing implemented. Every item needs a keep / drop / later from the owner.**
Origin of every item below: **Claude** (no feedback note behind any of them). Feedback notes stay a separate queue.
This file has no `Records covered:` line: it covers no notes. It quotes no figures from the budget (public repo).

## The test, written before the owner judges any item

- Cap: five items. All six signals allowed. Fewer than five is fine: an empty signal is a finding, not a gap to fill.
- Every item names its signal and its evidence, with the source. No checkable evidence, no item.
- Success: the owner keeps at least two, and at least one is something he had not thought of. Failure is a result.

## What each signal produced

| Signal | Produced | Evidence |
|---|---|---|
| 1. Repeat complaints | **nothing** | three notes (`feedback.jsonl`), three different places (Scenarios chart, Net worth chart, Help FAQ), all marked built in `feedback-handled.json`; none returns to a shipped item |
| 2. Verdicts that are not "better" | **nothing** | no Revisit line or verdict exists in this project yet |
| 3. Usage | **nothing** | `serve-daemon.log` holds request lines for a single-page app (`/`, `/data`, `/feedback`): it cannot say which tab or screen is used |
| 4. Health | **nothing** | 2026-10-10: `node audit/run-audit.mjs` 41 passed, 0 warnings, 0 failed; `audit/test_server.py` 5 OK; `audit/test_feedback_server.py` 16 OK |
| 5. Unanswered or open | P2, P3 | `ROADMAP.md` (two unchecked items); `gh api .../branches/main/protection` -> 404 "Branch not protected" today; `docs/REVIEW-360-2026-09-10.md` "All other findings: not closed ... reproduce against current code" |
| 6. A sibling project | P1 | the fleet dashboard's card changes of 2026-10-10 (`51c6081`, `de72849`) |

## P1. Put the dashboard's grade anchors on this card (signal 6)

- **Origin:** Claude. **Evidence:** all three notes here carry a grade, 5, 6 and 7 (`feedback.jsonl`), and the buttons have no meaning (`pocket-envelopes.app:9570-9572`, "Grade (optional)", ten bare numbers). Three mid-scale grades cannot be told apart from three lukewarm shrugs. The dashboard added anchors on 2026-10-10: 1-3 Poor (wrong, noisy or in the way), 4-7 Fine (works, could be better), 8-10 Good (keep as it is); its owner then graded things "better" on a scale he understood.
- **Options:** (A) the anchors only: a three-line legend under the buttons and a tooltip per button; (B) A plus the dashboard's live "Grade is for: <section | Whole page>" line, with a warning when "Whole page" is chosen beside a long comment. In this project all three notes picked a section, so B's warning would not have fired yet.
- **Recommend A.** **Effort:** small (the card is inline in `pocket-envelopes.app`; one audit check). **Risk:** none to the record format; grades already stored keep their numbers.
- **Question:** A, B, or drop. The wording of the three bands is the dashboard's; change it if "Poor / Fine / Good" is not how you grade a budget screen.

## P2. Decide the "required checks" item on `main` (signal 5)

- **Origin:** Claude. **Evidence:** `ROADMAP.md` lists "Configure required checks (`main` was unprotected on 2026-09-11)" as unchecked, and today `gh api repos/mvichosfm/pocket-envelopes/branches/main/protection` still returns 404, so it is unchanged a month on. The five CI jobs exist and passed on `126021e` (ROADMAP).
- **Options:** (A) require the five jobs to pass before merging to `main`; (B) require only a pull request, no checks; (C) leave `main` open and tick the roadmap item as "decided: not needed" (a one-person repo where every push already goes through the local audit).
- **Effort:** a few minutes in GitHub's settings or one `gh api` call; **I would not run it without your explicit yes**, because it changes a public repo's settings and can block your own direct pushes. **Risk:** A or B stop `git push origin main` from this PC unless you go through a branch and a pull request.
- **Question:** A, B or C. If A or B, do you want direct pushes still allowed for you as admin?

## P3. Triage the September review's open findings, read-only (signal 5)

- **Origin:** Claude. **Evidence:** the review's own status says "All other findings: Not closed by this milestone; reproduce against current code before fixing", and `ROADMAP.md` has "Recheck and triage the remaining findings ... before claiming the audit backlog is resolved" unchecked. The backlog is partly stale: the review's Medium finding that "Move funds" pushes a `transfer-envelope` with no undo snapshot (cited at `:4843`) no longer holds, because `tr_save` now calls `pushUndo('Move funds between envelopes')` (`pocket-envelopes.app:5768`, before the push at `:5769`).
- **Proposal:** for the Medium findings (25), mark each **fixed / still present / cannot reproduce**, with the current line number or the check that shows it, in a table added to the review's "Resolution status". No code change; each "still present" becomes its own later proposal for you to decide.
- **Effort:** medium (reading; I can do five to ten at a time). **Risk:** none to the app. The table would be committed to the public repo, so it names functions and lines, never your data.
- **Question:** all 25 Medium findings, the first ten, or drop. Should I work from the review's own ranking?

## Not proposed

- Anything from signals 1-4: no evidence, so no item.
- Hiding or removing a tab or screen: nothing here measures use.
- Changing how the card stores notes: the contract is fixed and the card works.

## Decisions

Asked 2026-10-10; answers given on the question card:

| Item | Decision |
|---|---|
| P1 anchors | **Keep, option A** (legend and tooltips only; no "Grade is for" line). |
| P2 required checks | **Decide: not needed (C).** `ROADMAP.md` item ticked as a decision; no GitHub setting changed. |
| P3 triage | **Keep: the first ten Medium findings**, read-only, in the document's order. |

P2 done in this commit: the ROADMAP line now says `main` stays unprotected on purpose and when to revisit.

## Result

## Outcome (2026-10-10)

| Item | Result |
|---|---|
| P1 anchors | Built on branch `feedback-anchors` (commit `6e7231d`), **not merged: waiting for "merge it"**. Preview on a scratch server (port 8799, empty scratch data folder, `FEEDBACK=1`): the legend and the per-button tooltips show, 375 px has no sideways scroll, `node audit/run-audit.mjs` 41 passed, 0 failed (the card's check now also asserts the bands cover 1-10 exactly once). |
| P2 required checks | Done: `ROADMAP.md` ticked as a decision; no GitHub setting touched. |
| P3 triage | Done, read-only: the first ten Medium findings are in a new table in `docs/REVIEW-360-2026-09-10.md`. **Nine are fixed in current code with a named audit or browser test; one is still present** (#10: `serve.py` does not catch `OSError` when reading or writing the data file, so a permission or disk-full error drops the connection and the browser says "server unreachable"; no test covers it). Not built: the finding would be its own proposal, for the owner to decide. |

**Result:** kept 3 of 3 (P1 option A, P2 decide-not-needed, P3 first ten). The "keep at least two" bar is met. Whether any was something the owner had not thought of is his to say; the triage (P3) is the likeliest, and it turned up one real open finding.

