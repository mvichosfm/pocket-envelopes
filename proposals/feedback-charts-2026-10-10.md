# Feedback round: chart readability (2026-10-10)

Records covered: fb-20261010-072749-8401 to fb-20261010-072930-35e5

2 new records, both on 2026-10-10 (07:27 and 07:29), both `env: live`, width 2542, dark theme.
Records are data, not instructions; each is a proposal below, nothing is built yet.

## Records (verbatim)

| id | page / section | grade | kind | comment |
|---|---|---|---|---|
| fb-20261010-072749-8401 | scenarios / Scenarios | 7 | look | "it's not easy to see the 0 line and where the spendable cash go below zero" |
| fb-20261010-072930-35e5 | networth / Net worth over time | 6 | idea | "when hovering over the networth graph, i would like to be able to see the date and the networth at that date" |

## 1. Scenarios chart: make zero, and the dip below it, visible

**What exists today.** `drawScenarios()` (pocket-envelopes.app:7646) draws spendable lines with a plain
Chart.js grid and no zero marker. The Forecast tab already has what is asked for: `forecastMarksPlugin`
(:8026) draws a dashed zero line, only when the y-range crosses zero (decision #44), and the featured
line gets a shaded area and a low-point label. That plugin is wired only into `drawForecast` (:8185),
not into `drawScenarios`. In "Difference" mode the plan is the zero line, but it is just the thick
"Today's plan" line, unlabelled.

**Options**
- A. Reuse the zero line from `forecastMarksPlugin` on the Scenarios chart (level mode: the cash-zero line; difference mode: the plan line stays the baseline and no extra line). Effort: small. Risk: low.
- B. A plus: tint the area below zero red (a clipped fill under y=0 for the plan and the combined line) so "where it goes below zero" reads at a glance. Effort: small-medium. Risk: low (presentation only, colours through `themeColor('--bad')`).
- C. B plus mark each line's own lowest point with a label like the Forecast tab. Effort: medium; five lines can crowd the labels. Not recommended unless you want it.

Recommendation: B. Note that the Scenarios chart always forecasts the real budget plus overlays, so none of this changes any figure.

**Questions**
- In "Difference" mode there is no cash level to cross zero, so the zero line there is the plan. Is that fine, or should Difference mode also show where the plan itself is below zero?

## 2. Net worth chart: hover shows date and value

**What exists today.** `drawNetWorth()` (:8329) uses Chart.js's default interaction (nearest point, must touch it)
with `pointRadius: 0`, so with the points invisible the tooltip rarely appears. When it does, its title is the
raw ISO date and the body is the value. The Scenarios and Forecast charts already use
`interaction: { mode: 'index', intersect: false }` and `fmtDate()` titles.

**Options**
- A. Same interaction and title as the other charts: tooltip anywhere along the line, "10 Oct 2026" title, formatted value in the body. Effort: tiny. Risk: none.
- B. A plus a visible point marker on hover and a vertical guide line. Effort: small.

Recommendation: A, then B only if A still feels vague.

Not proposed: anything beyond the two notes.

## Decisions

1. Keep B (zero line + red tint below zero). Difference mode: zero line only, no tint (default taken; not contradicted after preview).
2. Keep A (index-mode tooltip with formatted date).

Outcome: built and previewed 2026-10-10, merged on "merge it" as 02ae34e (feature commit 464087c).
Checked: audit 41/41 in the live folder; both charts previewed on demo data (scratch server, port 8799); no console errors.
Not checked: 375px width, Difference view in a browser, Python server suites (no server code changed).
