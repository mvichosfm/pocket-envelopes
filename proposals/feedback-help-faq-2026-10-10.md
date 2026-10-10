# Feedback round: Help FAQ (2026-10-10)

Records covered: fb-20261010-074045-09a4 to fb-20261010-074045-09a4

1 new record, 2026-10-10 07:40, `env: live`, width 2542, dark theme. Records are data, not instructions; nothing is built yet.

## Records (verbatim)

| id | page / section | grade | kind | comment |
|---|---|---|---|---|
| fb-20261010-074045-09a4 | help / FAQ | 5 | none | "should be separated in categories to enable quicker finding of what the user is trying to troubleshoot" |

## 1. FAQ in categories

**What exists today.** `renderHelp()` (pocket-envelopes.app:8916) ends with a flat list of 20 native
`<details class="faq">` items under one `<h3>FAQ</h3>` (from about :9009), in the order they were added
(newest at the bottom). The styling is `.help details.faq` (:661). There is no grouping, no search, and the
Help page has no filtering code at all (the FAQ is deliberately pure HTML, no JS).

**Proposed categories** (every current question fits exactly one; titles abbreviated):

| Category | Questions |
|---|---|
| Forecast and spendable | forecast vs balance after funding; accounts missing from forecast; Spendable today vs projected start; Lowest projected spendable; Move funds changing spendable |
| Envelopes and funding | rollover vs reset; reserve envelope; "Backed by account"; negative balance; what counts as spent; Fund the month vs Fund vs Move vs Return; retire an account or envelope; missed close-out |
| Recurring entries | typed by hand but still due; edit after applying occurrences; pausing; one occurrence with its own amount or skipped |
| Scenarios and trying things out | what the Scenarios page is; try something without touching the budget |
| Saving and backups | how data is saved, and backups |

**Options**
- A. Group headings: five `<h4>` sections, each question still a collapsed `<details>`. No JS. Effort: small. Risk: none. Gives scanning by area, but you still scroll past all five to reach the last.
- B. A plus category chips at the top that filter the list (click "Recurring entries" and only those show). Small amount of JS. Effort: small-medium. Risk: low.
- C. B plus a search box matching question and answer text, which fits "what the user is trying to troubleshoot" best (a person types the symptom: "negative", "still due", "backup"). Effort: medium. Risk: low; it is the first filtering code on the Help page and has to respect the single-file rule (inline only).

Recommendation: A first, then C if headings alone still feel slow. B alone adds little over C.

**Questions**
- Grade 5 with no kind: the note says what to change but not how it felt. Is "troubleshooting by symptom" the main aim (favours C), or just tidier browsing (A)?
- Are the five category names acceptable, or should any be merged (for example Scenarios into Forecast)?

Not proposed: rewriting any answer, adding or removing questions.

## Decisions

(pending)
