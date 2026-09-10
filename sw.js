/* Pocket Envelopes service worker.
 *
 * Scope: make the app *launch* when the server is unreachable — not make it
 * usable offline. Two rules follow from that, and they are the whole design:
 *
 *   1. /data is NEVER cached or intercepted. The server is the single source
 *      of truth (see CLAUDE.md decision #29). A cached budget would let the
 *      app render stale figures that look authoritative, and queued offline
 *      writes would come back as a pile of 409 conflicts against a stale
 *      ETag — the conflict dialog is built for "two devices occasionally",
 *      not for a day of replayed edits. Real offline editing needs a merge
 *      layer; that is a different project. Requests to /data fall straight
 *      through to the network, so the app's own "server unreachable" toast
 *      is what the user sees.
 *
 *   2. The shell is network-FIRST, cache only as fallback. Cache-first would
 *      resurrect the stale-app-code bug that the no-store headers in serve.py
 *      were added to kill (commit 4c19de1): edit the .app file, reload, still
 *      run yesterday's code. Against a LAN/tailnet server the network hop is
 *      a millisecond or two, so there is nothing to win by going cache-first.
 *
 * Bump CACHE_NAME to force every client to drop its old shell.
 */
const CACHE_NAME = "pocket-envelopes-shell-v4";

// Kept deliberately small: the app is one file, plus Chart.js and the icons.
const SHELL = [
  "./",
  "./vendor/chart.umd.min.js",
  "./manifest.webmanifest",
  "./icons/icon-192.png",
  "./icons/icon-512.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    // `reload` bypasses the HTTP cache so we precache what the server has
    // right now, not whatever the browser happens to be holding.
    await Promise.all(SHELL.map(async (url) => {
      try {
        const res = await fetch(new Request(url, { cache: "reload" }));
        if (res.ok) await cache.put(url, res);
      } catch (e) {
        // A missing optional asset must not abort the whole install.
        console.warn("sw: could not precache", url, e);
      }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter(n => n !== CACHE_NAME).map(n => caches.delete(n)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;                    // PUT /data → untouched

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;     // never proxy third parties
  if (url.pathname.replace(/\/+$/, "").endsWith("/data")) return;  // rule 1

  event.respondWith((async () => {
    // Cached copy for this request, else the shell entry for a navigation.
    const fallback = async () => {
      const hit = await caches.match(req, { ignoreSearch: true });
      if (hit) return hit;
      if (req.mode === "navigate") return caches.match("./", { ignoreSearch: true });
      return undefined;
    };

    try {
      const fresh = await fetch(req);
      // Only cache complete, same-origin successes. Opaque/partial responses
      // would poison the fallback with something we cannot verify.
      if (fresh && fresh.ok && fresh.type === "basic") {
        const cache = await caches.open(CACHE_NAME);
        cache.put(req, fresh.clone());
        return fresh;
      }
      // A reachable-but-broken server. This is the COMMON failure here, not an
      // exotic one: `tailscale serve` stays up and answers 502 when serve.py is
      // stopped or the host is asleep, so fetch() resolves rather than throws.
      // Only the throw path would have fallen back, which meant the browser's
      // own error page won and the cached shell was never used. Prefer a good
      // cached copy over any non-ok response; if we have none, return the real
      // response so genuine 404s still surface as 404s.
      if (!fresh.ok) return (await fallback()) || fresh;
      return fresh;
    } catch (e) {
      // True network failure: offline, DNS gone, off the tailnet.
      const hit = await fallback();
      if (hit) return hit;
      throw e;
    }
  })());
});
