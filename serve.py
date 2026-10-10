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

  GET / POST /feedback -> only when the server is started with FEEDBACK=1: the
                 optional feedback card's store (see the FEEDBACK section
                 below). Off by default; without it the card does not exist.

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
budget can only be reached through the /data API above. The check runs on
the percent-DECODED, normalised path: `/finance%2Ddata.json` used to slip
past it.

Host check: every request's Host header must name this machine -- localhost,
a literal IP address, this host's own name, a Tailscale `*.ts.net` name, or
an entry in $ALLOWED_HOSTS (comma-separated). Anything else is answered 421.
This is what stops a DNS-rebinding page (a hostname the attacker re-points at
127.0.0.1 after the page has loaded) from reading or overwriting /data through
the loopback bind; it is not authentication.

Stdlib only -- no pip install. Python 3.8 or newer.
"""

import datetime
import hashlib
import http.server
import ipaddress
import json
import mimetypes
import os
import posixpath
import re
import shutil
import socket
import socketserver
import sys
import threading
import time
import urllib.parse

PORT = int(os.environ.get("PORT", "8765"))
BIND = os.environ.get("BIND", "127.0.0.1")
IDLE_TIMEOUT = int(os.environ.get("IDLE_TIMEOUT", "1800"))
# Extra hostnames the Host check accepts, e.g. a reverse-proxy name that is not
# a *.ts.net one. Comma-separated, case-insensitive, without the port.
ALLOWED_HOSTS = {h.strip().lower() for h in os.environ.get("ALLOWED_HOSTS", "").split(",") if h.strip()}

# The app file deliberately uses a non-.html extension so double-clicking it in
# Explorer does not open it under file:// (which has no persistent origin, so
# localStorage-backed UI preferences would live in a separate storage bucket).
APP_FILE = "pocket-envelopes.app"


def _is_private_path(path_only: str) -> bool:
    """True for URL paths the static handler must never serve.

    Matches the data file and its rotation/staging siblings, the feedback
    card's store, log files, and any path component starting with a dot
    (.git, .claude, .env ...).
    Call it on a DECODED path (see _is_private_url).
    """
    parts = [p for p in path_only.split("/") if p]
    if any(p.startswith(".") for p in parts):
        return True
    name = parts[-1].lower() if parts else ""
    if name.startswith("finance-data"):
        return True
    # The optional feedback card's store and its start marker (see FEEDBACK below). With the default DATA_DIR they sit
    # next to this file, so the static handler must refuse them by name like the budget itself.
    if name.startswith("feedback") or name.endswith(".jsonl"):
        return True
    return name.endswith((".log", ".tmp", ".bak", ".bak.0", ".bak.1", ".bak.2", ".bak.3", ".bak.4"))


def _is_private_url(path_only: str) -> bool:
    """_is_private_path on the percent-decoded, normalised URL path.

    SimpleHTTPRequestHandler.translate_path unquotes AFTER our check, so the
    check must see what the file system will see: `/finance%2Ddata.json`,
    `/%2Egit/config` and `/x/../finance-data.json` all decode or collapse to a
    private path. Decoding twice is deliberate: a doubly-encoded path is
    refused too rather than reasoned about.
    """
    decoded = urllib.parse.unquote(urllib.parse.unquote(path_only))
    normalised = posixpath.normpath("/" + decoded.replace("\\", "/"))
    return _is_private_path(decoded) or _is_private_path(normalised)


_LOCAL_NAMES = {"localhost", "127.0.0.1", "::1", "[::1]"}


def _host_allowed_name(host_header) -> bool:
    """Is this Host header value one of ours? (See the module docstring.)

    Accepts: no Host at all (HTTP/1.0 clients), localhost and loopback
    addresses, any literal IP address (DNS rebinding needs a NAME that can be
    re-pointed; a literal IP cannot), this machine's own hostname, Tailscale
    `*.ts.net` names, and $ALLOWED_HOSTS. Everything else is refused.
    """
    if not host_header:
        return True
    host = host_header.strip().lower()
    if host.startswith("["):                      # [ipv6]:port
        host = host.split("]", 1)[0] + "]"
        host = host.strip("[]")
    elif host.count(":") == 1:                    # name:port or v4:port
        host = host.rsplit(":", 1)[0]
    host = host.rstrip(".")
    if host in _LOCAL_NAMES:
        return True
    try:
        ipaddress.ip_address(host)
        return True
    except ValueError:
        pass
    if host.endswith(".ts.net"):
        return True
    own = socket.gethostname().lower()
    if host in (own, own + ".local", own.split(".")[0]):
        return True
    return host in ALLOWED_HOSTS
# Content types the stdlib would get wrong. Windows' registry-backed
# mimetypes module reports .js as text/plain on some machines, which makes the
# browser refuse to register the service worker ("unsupported MIME type") — so
# pin all three explicitly rather than trusting the host.
_STATIC_TYPES = {
    ".app": "text/html",
    ".webmanifest": "application/manifest+json",
    ".js": "text/javascript",
}
for _ext, _mime in _STATIC_TYPES.items():
    mimetypes.add_type(_mime, _ext)

# Where the budget lives. Default: next to this file, which is what a
# checkout expects. The Windows installer sets DATA_DIR to a per-user folder
# (%LOCALAPPDATA%\PocketEnvelopes) because the program folder is not a place
# to keep, or write, personal data. Static files always come from this
# file's own directory regardless.
DATA_DIR = os.path.abspath(os.environ.get("DATA_DIR") or os.path.dirname(os.path.abspath(__file__)))
DATA_FILE = os.path.join(DATA_DIR, "finance-data.json")
TMP_FILE = DATA_FILE + ".tmp"
BAK_PREFIX = os.path.join(DATA_DIR, "finance-data.bak.")
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
    os.makedirs(DATA_DIR, exist_ok=True)
    _rotate_backups()
    with open(TMP_FILE, "wb") as fh:
        fh.write(payload)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(TMP_FILE, DATA_FILE)


# ----------------------------------------------------------------- feedback --
# The optional feedback card. Opt-in: it exists only when the server is started with FEEDBACK=1, so an ordinary install
# has no such route and no button. A grade and a comment left inside the app are appended, one JSON line per record, to
# feedback.jsonl in DATA_DIR. Append-only: nothing here edits or deletes a record. It is a store of its own, separate
# from the budget, so it deliberately does not go through _write_data(); nothing leaves this machine.
#
#   GET  /feedback -> {"enabled", "count", "quiet_days", "last", "recent": [...]}   (404 when FEEDBACK is off)
#   POST /feedback -> 201 {"record": {...}}, or 200 with "duplicate": true for a client id already stored. Needs the
#                     X-Requested-With: pocket-envelopes header, which a cross-site page cannot send without a CORS
#                     preflight this server never grants (the Host check alone does not stop a cross-site form post).
#
# The card switches itself off after FEEDBACK_QUIET_DAYS without a record, counted from the later of the newest record
# and feedback-started.txt (created on first use; delete the file to restart the clock).
FEEDBACK_ENABLED = os.environ.get("FEEDBACK", "").strip().lower() in ("1", "true", "yes", "on")
DEFAULT_PORT = 8765
FEEDBACK_FILE = os.path.join(DATA_DIR, "feedback.jsonl")
FEEDBACK_STARTED = os.path.join(DATA_DIR, "feedback-started.txt")
# What happened to each note, written by the person processing the feedback (never by this server, never by the app):
# {"<record id>": {"status": "kept|built|dropped|later", "ref": "short text"}}. Read-only here; feedback.jsonl stays
# append-only and untouched. A note with no entry is "new". The name starts with "feedback", so it is already private.
FEEDBACK_HANDLED = os.path.join(DATA_DIR, "feedback-handled.json")
FEEDBACK_STATUSES = ("kept", "built", "dropped", "later")
FEEDBACK_MAX_BYTES = 5 * 1024 * 1024
FEEDBACK_BODY_MAX = 16 * 1024
FEEDBACK_QUIET_DAYS = 30
FEEDBACK_KINDS = ("look", "logic", "section", "idea")
FEEDBACK_HEADER = ("X-Requested-With", "pocket-envelopes")
_feedback_lock = threading.Lock()

_FB_PAGE = re.compile(r"^[a-z][a-z0-9-]{0,29}$")
_FB_ABOUT = re.compile(r"^[A-Za-z0-9._#/-]{1,40}$")
_FB_CID = re.compile(r"^[A-Za-z0-9-]{8,40}$")
_FB_FIELDS = {"page", "section", "grade", "kind", "comment", "width", "theme", "about", "cid"}


class FeedbackOff(Exception):
    """The card has switched itself off: no record for FEEDBACK_QUIET_DAYS days."""


class FeedbackFull(Exception):
    """feedback.jsonl has reached FEEDBACK_MAX_BYTES."""


def _fb_now():
    return datetime.datetime.now().astimezone()


def _fb_int(value, low, high, what):
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise ValueError("%s must be a whole number from %d to %d" % (what, low, high))
    return value


def _fb_text(value, limit, what, newlines=False):
    if not isinstance(value, str):
        raise ValueError("%s must be text" % what)
    text = value.strip()
    if not text or len(text) > limit:
        raise ValueError("%s must be 1 to %d characters" % (what, limit))
    allowed = "\n\r\t" if newlines else ""
    if any((ord(c) < 32 and c not in allowed) or ord(c) == 127 for c in text):
        raise ValueError("%s has control characters" % what)
    return text


def _fb_clean(body):
    """The record a request body describes, or ValueError. Messages name fields, never echo their values."""
    if not isinstance(body, dict):
        raise ValueError("body must be an object")
    if set(body) - _FB_FIELDS:
        raise ValueError("unknown field")
    page = body.get("page")
    if not isinstance(page, str) or not _FB_PAGE.match(page):
        raise ValueError("page must be a view name")
    section = body.get("section")
    section = None if section in (None, "") else _fb_text(section, 80, "section")
    kind = body.get("kind")
    if kind is not None and kind not in FEEDBACK_KINDS:
        raise ValueError("kind must be one of %s" % ", ".join(FEEDBACK_KINDS))
    theme = body.get("theme")
    if theme is not None and theme not in ("dark", "light"):
        raise ValueError("theme must be dark or light")
    about = body.get("about")
    if about in (None, ""):
        about = None
    elif not isinstance(about, str) or not _FB_ABOUT.match(about):
        raise ValueError("about must be a short reference such as a commit or a note id")
    cid = body.get("cid")
    if not isinstance(cid, str) or not _FB_CID.match(cid):
        raise ValueError("cid must be 8 to 40 letters, digits or dashes")
    return {"page": page, "section": section, "grade": _fb_int(body.get("grade"), 1, 10, "grade"), "kind": kind,
            "comment": _fb_text(body.get("comment"), 2000, "comment", newlines=True),
            "width": _fb_int(body.get("width"), 1, 20000, "width"), "theme": theme, "about": about, "cid": cid}


def _fb_records():
    """Every readable record, oldest first. A torn last line (a crash mid-append) is skipped, never fatal."""
    try:
        with open(FEEDBACK_FILE, "rb") as fh:
            raw = fh.read()
    except FileNotFoundError:
        return []
    out = []
    for line in raw.split(b"\n"):
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line.decode("utf-8"))
        except (UnicodeDecodeError, ValueError, RecursionError):
            continue
        if isinstance(rec, dict) and isinstance(rec.get("id"), str):
            out.append(rec)
    return out


def _fb_handled():
    """The processing sidecar as a dict; a missing, unreadable or malformed file reads as 'nothing processed yet'."""
    try:
        with open(FEEDBACK_HANDLED, "rb") as fh:
            obj = json.loads(fh.read().decode("utf-8"))
    except (OSError, UnicodeDecodeError, ValueError, RecursionError):
        return {}
    return obj if isinstance(obj, dict) else {}


def _fb_note_state(entry):
    """{"status", "ref"} for one note: an unknown or missing status is 'new'; ref is short plain text."""
    if not isinstance(entry, dict) or entry.get("status") not in FEEDBACK_STATUSES:
        return {"status": "new", "ref": ""}
    ref = entry.get("ref")
    return {"status": entry["status"], "ref": ref[:120] if isinstance(ref, str) else ""}


def _fb_time(text, fallback=None):
    try:
        t = datetime.datetime.fromisoformat(str(text).strip())
    except ValueError:
        return fallback
    return t if t.tzinfo else t.astimezone()      # a hand-edited naive time is read as local


def _fb_started(now):
    """When the card was first used; written now if the marker is missing or unreadable."""
    try:
        with open(FEEDBACK_STARTED, "r", encoding="utf-8") as fh:
            t = _fb_time(fh.read())
        if t:
            return t
    except OSError:
        pass
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(FEEDBACK_STARTED, "w", encoding="utf-8") as fh:
        fh.write(now.isoformat(timespec="seconds"))
    return now


def _fb_quiet(records, started, now):
    last = started
    for r in records:
        t = _fb_time(r.get("at"))
        if t and t > last:
            last = t
    return last, now - last >= datetime.timedelta(days=FEEDBACK_QUIET_DAYS)


def _fb_status(now=None):
    now = now or _fb_now()
    with _feedback_lock:
        records = _fb_records()
        last, quiet = _fb_quiet(records, _fb_started(now), now)
    handled = _fb_handled()
    recent = [{"id": r.get("id"), "at": r.get("at"), "page": r.get("page"), "section": r.get("section"),
               "grade": r.get("grade"), "kind": r.get("kind"), "comment": str(r.get("comment") or "")[:200],
               **_fb_note_state(handled.get(r.get("id")))}
              for r in records[-5:]][::-1]
    return {"enabled": not quiet, "count": len(records), "quiet_days": FEEDBACK_QUIET_DAYS,
            "last": last.isoformat(timespec="seconds"), "recent": recent}


def _fb_add(body, env, now=None):
    """Validate and append one record; returns it (with duplicate=True for a client id that is already stored)."""
    rec = _fb_clean(body)
    now = now or _fb_now()
    with _feedback_lock:
        records = _fb_records()
        for r in records:
            if r.get("cid") == rec["cid"]:
                return dict(r, duplicate=True)
        if _fb_quiet(records, _fb_started(now), now)[1]:
            raise FeedbackOff()
        try:
            size = os.path.getsize(FEEDBACK_FILE)
        except OSError:
            size = 0
        if size >= FEEDBACK_MAX_BYTES:
            raise FeedbackFull()
        record = {"id": "fb-%s-%s" % (now.strftime("%Y%m%d-%H%M%S"), os.urandom(2).hex()),
                  "at": now.isoformat(timespec="seconds"), "env": env, **rec}
        line = (json.dumps(record, ensure_ascii=False) + "\n").encode("utf-8")
        if size:                                   # close off a torn last line so the new record starts on its own line
            with open(FEEDBACK_FILE, "rb") as fh:
                fh.seek(-1, os.SEEK_END)
                if fh.read(1) != b"\n":
                    line = b"\n" + line
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(FEEDBACK_FILE, "ab") as fh:
            fh.write(line)
            fh.flush()
            os.fsync(fh.fileno())
        return record


class Handler(http.server.SimpleHTTPRequestHandler):
    # Python 3.8's handler never consults the mimetypes registry: it reads only
    # this table, copied at import time, so the registrations above must be
    # mirrored here or the app is served as application/octet-stream (a
    # download prompt instead of a page). 3.9+ falls through to mimetypes and
    # ignores the duplicate.
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, **_STATIC_TYPES}
    # A sleeping phone or interrupted upload must not strand a handler forever.
    timeout = 30
    last_request = time.monotonic()

    # -- helpers ------------------------------------------------------------
    def _touch(self):
        Handler.last_request = time.monotonic()

    def _route(self):
        return self.path.split("?", 1)[0].split("#", 1)[0]

    def _host_ok(self) -> bool:
        if _host_allowed_name(self.headers.get("Host")):
            return True
        self._send_error_json(
            421,
            "this server only answers requests addressed to this machine "
            "(localhost, its IP, its hostname, a *.ts.net name, or $ALLOWED_HOSTS)",
        )
        return False

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
        if _is_private_url(path_only):
            self.send_error(404, "Not found")
            return None
        return super().send_head()

    def list_directory(self, path):
        self.send_error(404, "Not found")
        return None

    def do_GET(self):
        self._touch()
        if not self._host_ok():
            return None
        if self._route() == "/data":
            return self._get_data()
        if FEEDBACK_ENABLED and self._route() == "/feedback":
            return self._get_feedback()
        return super().do_GET()

    def do_HEAD(self):
        self._touch()
        if not self._host_ok():
            return None
        if self._route() == "/data":
            return self._get_data()
        return super().do_HEAD()

    def do_PUT(self):
        self._touch()
        if not self._host_ok():
            return None
        if self._route() == "/data":
            return self._put_data()
        self._send_error_json(405, "PUT is only supported on /data")

    def do_POST(self):
        self._touch()
        if not self._host_ok():
            return None
        if FEEDBACK_ENABLED and self._route() == "/feedback":
            return self._post_feedback()
        # Without FEEDBACK=1 this is what the stdlib handler has always answered to a POST.
        self.send_error(501, "Unsupported method ('POST')")

    # -- /feedback (opt-in, see FEEDBACK above) -------------------------------
    def _get_feedback(self):
        self._send_json(200, json.dumps(_fb_status(), ensure_ascii=False).encode("utf-8"))

    def _post_feedback(self):
        if self.headers.get(FEEDBACK_HEADER[0]) != FEEDBACK_HEADER[1]:
            return self._send_error_json(403, "missing the %s header" % FEEDBACK_HEADER[0])
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self._send_error_json(400, "invalid Content-Length")
        if length <= 0:
            return self._send_error_json(400, "empty body")
        if length > FEEDBACK_BODY_MAX:
            return self._send_error_json(413, "body too large")
        try:
            body = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, ValueError, RecursionError):
            return self._send_error_json(400, "body is not valid JSON")
        # live = the normal port; anything else is a scratch copy (a preview), so its records can be told apart
        env = "live" if PORT == DEFAULT_PORT else "preview"
        try:
            record = _fb_add(body, env)
        except ValueError as exc:
            return self._send_error_json(400, str(exc))
        except FeedbackOff:
            return self._send_error_json(403, "feedback is switched off: no record for %d days (delete "
                                              "feedback-started.txt to start again)" % FEEDBACK_QUIET_DAYS)
        except FeedbackFull:
            return self._send_error_json(507, "the feedback file is full")
        self._send_json(200 if record.get("duplicate") else 201,
                        json.dumps({"record": record}, ensure_ascii=False).encode("utf-8"))

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
    print(f"Data file: {DATA_FILE}")
    if FEEDBACK_ENABLED:
        print(f"Feedback card: ON, records go to {FEEDBACK_FILE}")
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
