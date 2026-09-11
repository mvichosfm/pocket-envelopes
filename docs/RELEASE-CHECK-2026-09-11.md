# Focused 1.0 release check — 2026-09-11

**Working-tree follow-up: R1–R4 are repaired and verified.** The four defect groups
found in the initial check below are fixed, along with the related focus, labels,
hidden Undo action and blocked Forecast storage issues. Candidate installation,
independent user trials and GitHub checks on the repaired commit remain outstanding.

## Repair verification — 2026-09-11

- Recurring edits preserve resolved history even when start/cadence changes;
  Duplicate retains its separate fresh-history behavior. Malformed legacy history
  is corrected explicitly in the editor rather than guessed on load.
- Account/envelope saves validate drafts before replacing records or changing the
  reserve. The affected add/edit/move/value/pause actions snapshot exactly once;
  rejected or unchanged forms do not consume Undo.
- Invalid locale input is rejected inline. Existing invalid saved/imported locales
  use a safe display fallback, including transaction labels and forecast axes.
- Settings labels, row focus after mutation/deletion, inert hidden toast actions,
  synchronous modal focus and guarded Forecast storage access are fixed.
- **Validation:** 28 core checks, all 5 server tests, the 108-check Edge visual suite
  and its persistence scenarios passed. The **12 new permanent regression tests**
  (with multiple transaction/form cases) passed in Edge, Firefox and WebKit.
  These regressions now run from `audit/run_browser.py`, including in its CI job.
- Application changes are local and uncommitted at this verification point. No
  real budget was read or changed; no release was published. A previous green
  GitHub run is not a claim that this new working tree has run on GitHub yet.

The evidence JSON retains the initial failed observations and includes a separate
`repair_verification` section with the tested application hash and final results.

## Initial check (historical snapshot)

**Initial verdict: hold 1.0.** The normal budgeting, persistence and recovery paths
passed, but four reproduced defect groups required repair. Adding more features
was unnecessary. The findings and source lines below refer to that initial build.

Examined commit: `126021e2b1da2ad1054cb2b514214c2b081fa697` on `main`.
This is a focused release check, not a new exhaustive audit or a claim that
every historical finding has been closed. No production budget was read or
modified, and no application code, tag, release or repository setting was changed.

## Evidence that passed

| Area | Result |
| --- | --- |
| Local core audit | 28 passed, 0 warnings, 0 failures: syntax, accounting, forecast invariants, reporting, save races, corrupt-load guard, Host/private-path guards and service-worker invariants. |
| Local server integration | All 5 passed: first run, save/load, stale-write rejection, invalid writes, backup rotation/recovery, stalled-upload timeout. |
| Existing Edge browser suite | 108 visual checks passed across 80 viewport/theme/view combinations; browser create/save/conflict/explicit overwrite/reload/backup restore/corrupt-load checks also passed. |
| GitHub, this exact commit | All five jobs passed: Python 3.12 on Windows/macOS/Linux, Python 3.8 on Linux, Chromium browser checks on Linux. [Run 34561431169](https://github.com/mvichosfm/pocket-envelopes/actions/runs/34561431169). |
| Additional browser journeys | Edge 152.0.4191.66, Firefox 151.0 and Playwright WebKit 26.5 all passed the first-budget, disk reload and exact export/import round trip described below, without browser exceptions. |
| Additional responsive checks | All 10 views fit at 1280, 390 and 320 CSS pixels in each of those three engines (90 view/width/engine combinations). |
| Installed launcher components | Staged CPython 3.13.15 archive matches the build script's pinned SHA-256. The actual launcher, current app/server and staged runtime passed first start, asset content types, save to isolated DATA_DIR, second launch and restart with saved data intact. |

The first-budget journey used the app's forms: create a checking account with
1,000; create a groceries envelope with a monthly budget of 100; Fund the month;
record a 25 purchase. Each browser produced **975 account balance, 75 envelope
balance and 900 unreserved cash**. After export, a deliberate temporary change
was saved, then Import restored a budget exactly equal to the exported JSON.

Buttons were activated with Enter and controls filled through browser automation.
This establishes keyboard activation, not a complete unaided keyboard-only or
screen-reader usability pass. WebKit on Windows is not Safari on an Apple device;
the README's minimum browser versions were not separately exercised.

## Repair before 1.0

### R1 — P1: saving an unchanged recurring entry reopens paid occurrences

Source: `pocket-envelopes.app:6163`–`6166`, inside `editRecurring`.

Reproduction: use a monthly entry starting July 1, with July/August/September
already recorded and `lastAppliedDate = 2026-09-01`. Click Edit, change nothing,
then Save. The watermark changes to `2026-06-30`; due count changes from **0 to
3**, while all three original transactions remain. The reset tests whether the
start predates the watermark, not whether the user changed the start date.

Impact: the app offers already-paid occurrences again and can book duplicates
if the user applies them. The pending forecast is also wrong immediately after
the edit. This is an existing edit-path defect, not the new copy's intended
fresh history.

Acceptance: no-op, name, notes and amount edits preserve the watermark and due
count. An actual backdated schedule change must have deliberate, tested semantics.
Add a regression with real linked transactions, rather than only a fresh recurring.

### R2 — P1: Undo can remove an earlier purchase instead of only the latest action

Sources: `pocket-envelopes.app:3705`, `3796`, `4246`, `4970`, `6158`, `6186`.

All six probed actions created **zero undo snapshots**: Move funds, Update
investment value, Edit account, Edit recurring, Pause recurring, and switching
the reserve envelope without a balance adjustment. A concrete sequence of
"record purchase, Move funds, Undo" removed the preceding purchase as well.
Snapshot restore jumps back past both actions because the transfer has no entry.

There is a second related hazard at `pocket-envelopes.app:1655`: a dismissed
toast retains its Undo button. After the fade, its opacity was 0, visibility
remained visible, and keyboard focus could still land on the hidden button.

Acceptance: each successful budget mutation snapshots exactly once after
validation and before mutation; Undo reverses only that action and Redo restores
it. Invalid/no-op saves must not insert stray snapshots. Dismissed toast actions
must leave the keyboard focus order and cannot trigger an unrelated later Undo.

### R3 — P1: an invalid formatting locale persists and blanks the dashboard

Sources: `pocket-envelopes.app:7290` and formatting helpers at `1547` onward.

Reproduction: in Settings enter `el_GR` as Locale and leave the field. The value
is saved. After reload, the dashboard is empty and the browser reports
`Invalid language tag: el_GR`. This was verified against the scratch server's
saved JSON, not just in-memory state. Settings remains reachable; changing the
value to `en-GB` restores the dashboard, which was also verified.

Acceptance: trim and validate locale input before mutation; reject invalid tags
with a clear field message. Formatter fallbacks must also recover from an invalid
locale already present in an imported or saved file.

### R4 — P2, release gate: form validation does not protect the saved model

Sources: `pocket-envelopes.app:3706`, `4250` and the recurring save handler at
`6117` onward, including watermark initialization at `6157`.

- Edit an account's name and enter `100+` for opening balance. Save rejects the
  expression, but Cancel leaves the changed name in `data.accounts`.
- Edit an envelope's name and enter `100+` for its budget. Save rejects it, but
  Cancel leaves the changed name in `data.envelopes`.
- Add a recurring entry with a name and amount but clear Start/on. It is accepted
  with `startDate: ""` and `lastAppliedDate: "NaN-NaN-NaN"`.

The rejected-edit observations are model mutations; they can be included in a
subsequent save. They are not claims that the rejected Save itself wrote to disk.
Correcting the blank recurring start did restore a pending date in this build,
but left the malformed watermark. This narrows the older audit's assertion that
delete-and-recreate is always required.

Acceptance: collect and validate all proposed fields before modifying live
records or the undo stack. Refused Save followed by Cancel must leave a byte-for-byte
equivalent budget. Require a valid start date and valid end/start ordering; never
create a malformed watermark, and repair legacy malformed values deliberately.

## Other findings and scope limits

| Finding | Current triage |
| --- | --- |
| Editing a recurring row drops focus to BODY; five Settings controls lack explicit accessible labels | Reproduced. Fix these small accessibility gaps with the release repairs; no broad accessibility conformance claim is justified. Add-button/forecast-control focus preservation already exists, so the older claim that every render loses focus is too broad. |
| Forecast when browser storage is blocked | Reproduced by making Storage.getItem throw SecurityError: Forecast render throws and no chart is created. Harden the saved-width read before broad browser/privacy-mode support claims. Ordinary browser storage passed in all three engines. |
| Older performance, structural and cosmetic findings | Do not block 1.0 merely for formatter caching, code duplication or cosmetic refinements. Not comprehensively re-audited here; the historical backlog remains open. |
| Existing fixed high/security/save/report groups | Current core/server/browser checks passed. No regression observed in the covered cases. This is not a penetration-test claim. |
| Unsaved edits during abrupt tab/process closure | Existing documented limit remains. Waiting for the saved indicator is part of the present persistence contract; full offline editing/durable queues are separate work. |

## Release preparation still outstanding

- **Branch protection:** GitHub reported `main.protected = false`. Successful CI
  is verified; required checks are not enforced. Configure them as a release
  maintenance measure, without treating green CI as proof of the untested cases.
- **Installer:** the latest public installer is still
  [v0.10.0](https://github.com/mvichosfm/pocket-envelopes/releases/tag/v0.10.0),
  with an EXE and SHA-256 asset. No Inno Setup compiler was available locally.
  Component startup was tested, but a current-build clean installation,
  upgrade preserving a sample budget, and uninstall preserving it still need
  a candidate-installer trial. No installer was published during this check.
- **Version/cache/notes:** the build defaults and latest versioned changelog
  section still say 0.10.0. Finalize the chosen release version and notes and
  bump the service-worker shell cache per CONTRIBUTING.md during preparation.
  The network-first worker passed its checks; this is release hygiene, not a
  reproduced online stale-shell bug.
- **If using a release candidate:** the installer workflow currently publishes
  every `v*` tag with `--draft=false --latest` and no prerelease flag
  (`.github/workflows/installer.yml:164`). Adjust that before publishing an RC,
  so an RC is explicitly a prerelease and does not replace the stable latest.
- **Human trials:** the roadmap's independent household setup/recovery trials,
  walkthrough with worked numbers, and public synthetic demo remain outstanding.
  Automated journeys do not count as independent user trials.

## Minimum next pass

1. Repair R1–R4 and the small focus/label/hidden-action gaps; add focused
   regressions for the reproduced failures.
2. Run the existing core/server/browser suites plus those regressions on the
   repaired commit, and confirm its GitHub jobs pass.
3. Build a correctly marked candidate, exercise installation/upgrade/recovery,
   and finish the independent setup checks before promoting to 1.0.

Detailed synthetic probe observations are in
[`release-check-2026-09-11-results.json`](release-check-2026-09-11-results.json).
The disposable local probes are retained under ignored `build/release-check/`;
they do not run against the user's budget or change the CI suite.
