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

## `fonts/` — Caprasimo and Figtree (Organic theme)

- **Files**: `caprasimo-400.woff2` (Caprasimo Regular, v6) and
  `figtree-variable.woff2` (Figtree variable, weight 300–900, v9). Both are the
  **latin** subset only, so Greek and other non-latin text falls back to
  `system-ui`.
- **Upstream**: https://github.com/docrepair-fonts/caprasimo-fonts and
  https://github.com/erikdkennedy/figtree
- **License**: SIL Open Font License 1.1 — full texts in `fonts/OFL.txt`
- **Source**: fetched 2026-10-18 from Google Fonts (the `latin` blocks of
  `https://fonts.googleapis.com/css2?family=Caprasimo&family=Figtree:wght@300..900`,
  files under `https://fonts.gstatic.com/s/caprasimo/v6/` and
  `https://fonts.gstatic.com/s/figtree/v9/`)
- **Loaded from**: the `@font-face` rules at the top of the main `<style>`
  in the app file, by relative path. Both files are also in `sw.js`'s `SHELL`
  list so the installed PWA renders correctly offline.

## Updating

Replace the file with a newer release from the same path
(`chart.js@<version>/dist/chart.umd.min.js`), update the version in this
file and the copyright years in `chart.js-LICENSE.txt` if they changed, bump
`CACHE_NAME` in `sw.js` so installed clients drop the old shell, and test the
Forecast, Net Worth and Reports tabs.
