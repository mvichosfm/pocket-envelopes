"""Tiny static file server + JSON data API with idle auto-shutdown.

Serves the directory this file lives in on http://localhost:8765 (override
via $PORT) and exits if no HTTP request arrives within IDLE_TIMEOUT seconds
(default 1800 = 30 min, override via $IDLE_TIMEOUT; set 0 to never shut down).
Launched by launch.bat but works standalone too: `python serve.py`.

Why this exists: the app keeps its state in `finance-data.json` next to this
file, and reaches it over HTTP rather than through the browser. That makes the
server the single source of truth, so any device that can reach this host --
including Tailscale peers, see BIND below -- sees the same data.

Endpoints beyond the static files:

  GET /data   -> the current finance-data.json verbatim (application/json).
                 If the file does not exist yet, returns `{}` plus a
                 `X-Data-New: 1` header so the client can tell "first ever
                 run" from "a file that happens to be empty".
                 Always carries an `ETag` = sha256 of the bytes served.

  PUT /data   -> replace finance-data.json with the request body.
                 400 if the body is not valid JSON.
                 409 if `If-Match` is sent and does not match the current
                 ETag (someone else wrote in between); the response carries
                 the current ETag so the client can warn about a stale write.
                 Omitting `If-Match` forces the write -- this is a
                 single-user app, an explicit overwrite is allowed.
                 204 on success, with the new ETag.

Durability: writes go to finance-data.json.tmp, are fsync'd, then os.replace'd
over the real file, so a crash mid-write can never leave a torn file. The
previous contents rotate into finance-data.bak.0 (newest) .. .bak.4 (oldest).

BIND defaults to 127.0.0.1 (this machine only). There is NO authentication --
anyone who can open the port can read and overwrite your finances -- so
widening it is a deliberate choice: set $BIND=0.0.0.0 to listen on every
interface, and only do that on a network you trust (a Tailscale tailnet, a
firewalled LAN). The README's multi-device section keeps the loopback bind and
puts `tailscale serve` in front instead.

Static files: the app, its icons, the manifest, the service worker and
vendor/ are served from this directory. The data file, its backups, logs,
dotfiles (.git, .claude) and directory listings are refused (404) so the
budget can only be reached through the /data API above.

Stdlib only -- no pip install. Python 3.8 or newer.
"""

import hashlib
import http.server
import json
import mimetypes
import os
import shutil
import socketserver
import sys
import threading
import time

PORT = int(os.environ.get("PORT", "8765"))
BIND = os.environ.get("BIND", "127.0.0.1")
IDLE_TIMEOUT = int(os.environ.get("IDLE_TIMEOUT", "1800"))

# The app file deliberately uses a non-.html extension so double-clicking it in
# Explorer does not open it under file:// (which has no persistent origin, so
# localStorage-backed UI preferences would live in a separate storage bucket).
APP_FILE = "pocket-envelopes.app"


def _is_private_path(path_only: str) -> bool:
    """True for URL paths the static handler must never serve.

    Matches the data file and its rotation/staging siblings, log files, and
    any path component starting with a dot (.git, .claude, .env ...).
    """
    parts = [p for p in path_only.split("/") if p]
    if any(p.startswith(".") for p in parts):
        return True
    name = parts[-1].lower() if parts else ""
    if name.startswith("finance-data"):
        return True
    return name.endswith((".log", ".tmp", ".bak"))
mimetypes.add_type("text/html", ".app")
# PWA assets. Windows' registry-backed mimetypes module reports .js as
# text/plain on some machines, which makes the browser refuse to register the
# service worker ("unsupported MIME type") — so pin both explicitly rather
# than trusting the host.
mimetypes.add_type("application/manifest+json", ".webmanifest")
mimetypes.add_type("text/javascript", ".js")

DATA_FILE = "finance-data.json"
TMP_FILE = DATA_FILE + ".tmp"
BAK_PREFIX = "finance-data.bak."
BAK_SLOTS = 5          # .bak.0 (newest) .. .bak.4 (oldest)
MAX_BODY = 64 * 1024 * 1024   # refuse absurd bodies rather than buffering them

# Serialises PUTs against each other and against GET, so a reader can never
# observe the rotate/replace sequence halfway through.
_data_lock = threading.Lock()


def _etag(payload: bytes) -> str:
    """Strong ETag for a body: quoted sha256 hex, per RFC 7232."""
    return '"' + hashlib.sha256(payload).hexdigest() + '"'


def _etag_matches(header_value: str, current: str) -> bool:
    """Compare an If-Match header against our current ETag.

    Lenient on purpose: curl users paste the tag back with or without its
    quotes, and `*` means "any existing representation".
    """
    if header_value is None:
        return True                       # no If-Match -> caller accepts the risk
    for candidate in header_value.split(","):
        candidate = candidate.strip()
        if candidate == "*":
            return True
        if candidate.startswith("W/"):    # we only issue strong tags, but be tolerant
            candidate = candidate[2:]
        if candidate.strip('"') == current.strip('"'):
            return True
    return False


def _read_data():
    """Return (bytes, is_new). Missing file reads as an empty JSON object."""
    try:
        with open(DATA_FILE, "rb") as fh:
            return fh.read(), False
    except FileNotFoundError:
        return b"{}", True


def _rotate_backups():
    """Shift finance-data.bak.N down one slot, then snapshot the live file.

    Copies (rather than moves) the live file into .bak.0 so finance-data.json
    is never briefly absent -- a concurrent GET must always find a whole file.
    """
    oldest = BAK_PREFIX + str(BAK_SLOTS - 1)
    if os.path.exists(oldest):
        os.remove(oldest)
    for slot in range(BAK_SLOTS - 2, -1, -1):
        src = BAK_PREFIX + str(slot)
        if os.path.exists(src):
            os.replace(src, BAK_PREFIX + str(slot + 1))
    if os.path.exists(DATA_FILE):
        shutil.copy2(DATA_FILE, BAK_PREFIX + "0")


def _write_data(payload: bytes):
    """Atomically replace DATA_FILE with payload, after rotating backups."""
    _rotate_backups()
    with open(TMP_FILE, "wb") as fh:
        fh.write(payload)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(TMP_FILE, DATA_FILE)


class Handler(http.server.SimpleHTTPRequestHandler):
    last_request = time.monotonic()

    # -- helpers ------------------------------------------------------------
    def _touch(self):
        Handler.last_request = time.monotonic()

    def _route(self):
        return self.path.split("?", 1)[0].split("#", 1)[0]

    def _send_json(self, code, payload: bytes, extra_headers=()):
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        for key, value in extra_headers:
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)

    def _send_error_json(self, code, message, extra_headers=()):
        body = json.dumps({"error": message}).encode("utf-8")
        self._send_json(code, body, extra_headers)

    # -- routing ------------------------------------------------------------
    def send_head(self):
        # Strip the query string before deciding what to serve so URLs like
        # /?demo=1 still route to the app file. SimpleHTTPRequestHandler keeps
        # the rest of self.path intact, and the browser keeps the query in
        # location.search either way.
        path_only = self._route()
        if path_only in ("/", "/envelope-budget.html", "/pocket-envelopes.html"):
            self.path = "/" + APP_FILE + self.path[len(path_only):]
            path_only = "/" + APP_FILE
        # The data file and everything around it must not be fetchable by
        # name: SimpleHTTPRequestHandler would happily serve
        # finance-data.json, the .bak rotation, logs and .git/ to anyone who
        # can reach the port, bypassing the /data API entirely. Directory
        # listings go for the same reason.
        if _is_private_path(path_only):
            self.send_error(404, "Not found")
            return None
        return super().send_head()

    def list_directory(self, path):
        self.send_error(404, "Not found")
        return None

    def do_GET(self):
        self._touch()
        if self._route() == "/data":
            return self._get_data()
        return super().do_GET()

    def do_HEAD(self):
        self._touch()
        if self._route() == "/data":
            return self._get_data()
        return super().do_HEAD()

    def do_PUT(self):
        self._touch()
        if self._route() == "/data":
            return self._put_data()
        self._send_error_json(405, "PUT is only supported on /data")

    # -- /data --------------------------------------------------------------
    def _get_data(self):
        with _data_lock:
            payload, is_new = _read_data()
        headers = [("ETag", _etag(payload))]
        if is_new:
            headers.append(("X-Data-New", "1"))
        self._send_json(200, payload, headers)

    def _put_data(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self._send_error_json(400, "invalid Content-Length")
        if length <= 0:
            return self._send_error_json(400, "empty body")
        if length > MAX_BODY:
            return self._send_error_json(413, "body too large")

        body = self.rfile.read(length)
        try:
            json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, ValueError, RecursionError) as exc:
            # RecursionError: a pathologically nested body ([[[[...]]]]) is
            # invalid input, not a server fault -- answer 400, don't unwind.
            return self._send_error_json(400, "body is not valid JSON: %s" % exc)

        if_match = self.headers.get("If-Match")
        with _data_lock:
            current, _ = _read_data()
            current_tag = _etag(current)
            if not _etag_matches(if_match, current_tag):
                # Someone (another tab/device) wrote since this client loaded.
                # Hand back the live tag so the client can offer a reload or a
                # deliberate force-overwrite (a PUT with no If-Match).
                return self._send_error_json(
                    409,
                    "data changed on the server since your last load",
                    [("ETag", current_tag)],
                )
            _write_data(body)
            new_tag = _etag(body)

        self.send_response(204)
        self.send_header("ETag", new_tag)
        self.end_headers()

    # -- shared -------------------------------------------------------------
    def end_headers(self):
        # Local single-user app: never let the browser serve a stale cached
        # copy. We send Last-Modified but no Cache-Control, so browsers apply
        # *heuristic* caching to our 200 responses — after the app file changes,
        # a plain reload (or relaunching via launch.bat) can still run the OLD
        # code because Chrome reuses its cache without revalidating. Forcing
        # no-store/no-cache makes every request refetch the current file.
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, fmt, *args):
        Handler.last_request = time.monotonic()
        super().log_message(fmt, *args)


def idle_watchdog(httpd):
    while True:
        time.sleep(30)
        idle = time.monotonic() - Handler.last_request
        if idle >= IDLE_TIMEOUT:
            print(f"\nNo requests for {int(idle)}s - shutting down.")
            httpd.shutdown()
            return


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    try:
        httpd = socketserver.ThreadingTCPServer((BIND, PORT), Handler)
    except OSError as e:
        print(f"Could not bind to {BIND}:{PORT} - {e}")
        print("Is another copy of the server already running? Close it, or set PORT to a free port.")
        sys.exit(1)
    Handler.last_request = time.monotonic()
    if IDLE_TIMEOUT > 0:
        threading.Thread(target=idle_watchdog, args=(httpd,), daemon=True).start()
        shutdown_note = f"auto-shutdown after {IDLE_TIMEOUT}s idle"
    else:
        shutdown_note = "no idle shutdown"
    # Always print localhost: that is what the person sitting at this machine
    # should click, whatever interface we listen on.
    print(f"Serving http://localhost:{PORT}/  ({shutdown_note})")
    if BIND == "0.0.0.0":
        print(f"WARNING: BIND=0.0.0.0 -- reachable from every device on this machine's networks, port {PORT}, with no authentication.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nInterrupted - shutting down.")
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
