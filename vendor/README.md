# Vendored dependencies

This folder contains the one third-party asset bundled with the project, so
the app loads with no network call, works offline, and never exposes your
IP or User-Agent to a CDN.

## `chart.umd.min.js` — Chart.js v4.4.1

- **Upstream**: https://github.com/chartjs/Chart.js
- **License**: MIT — full text in `chart.js-LICENSE.txt` (the minified bundle
  carries only the short banner, so the license accompanies it here)
- **Source**: https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js
- **Loaded from**: the `<script src="vendor/chart.umd.min.js">` tag near the
  top of `pocket-envelopes.app`

## `fonts/` — Source Serif 4 (Broadsheet theme)

- **Files**: `source-serif-4-roman-latin.woff2` (variable roman, optical size
  8–60, weight 400–700) and `source-serif-4-italic-latin.woff2` (italic, 400).
  Both are the **latin** subset only, so Greek and other non-latin text falls
  back to Georgia.
- **Upstream**: https://github.com/adobe-fonts/source-serif
- **License**: SIL Open Font License 1.1 — full text in `fonts/OFL.txt`
- **Source**: supplied with the Broadsheet skin pack (`Broadsheet.zip`,
  2026-10-18), already subset to latin; the pack does not record a download URL.
- **Loaded from**: the `@font-face` rules at the top of the main `<style>`
  in the app file, by relative path. Both files are also in `sw.js`'s `SHELL`
  list so the installed PWA renders correctly offline.
- **Replaced**: Caprasimo and Figtree (the Organic theme's faces) were removed
  on the same date; they remain in git history (commit `ccb8854`).

## Updating

Replace the file with a newer release from the same path
(`chart.js@<version>/dist/chart.umd.min.js`), update the version in this
file and the copyright years in `chart.js-LICENSE.txt` if they changed, bump
`CACHE_NAME` in `sw.js` so installed clients drop the old shell, and test the
Forecast, Net Worth and Reports tabs.
