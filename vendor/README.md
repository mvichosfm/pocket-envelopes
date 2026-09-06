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

## Updating

Replace the file with a newer release from the same path
(`chart.js@<version>/dist/chart.umd.min.js`), update the version in this
file and the copyright years in `chart.js-LICENSE.txt` if they changed, bump
`CACHE_NAME` in `sw.js` so installed clients drop the old shell, and test the
Forecast, Net Worth and Reports tabs.
