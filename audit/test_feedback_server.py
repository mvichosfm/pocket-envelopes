"""The optional feedback card's server half; python audit/test_feedback_server.py (stdlib only).

Real HTTP against a scratch server, plus the store's own functions against a temporary folder. Nothing here reads a
real budget or a real feedback file.
"""
import datetime
import http.client
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from scratch_server import ROOT, scratch_server

HEADER = {"X-Requested-With": "pocket-envelopes", "Content-Type": "application/json"}
CID = "cid-12345678"


def request(port, method="GET", path="/feedback", body=None, headers=None):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        connection.request(method, path, body, headers or {})
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()


def post(port, record, headers=HEADER):
    return request(port, "POST", "/feedback", json.dumps(record).encode("utf-8"), headers)


def good(**changes):
    record = {"page": "dashboard", "section": "Spendable today", "grade": 7, "kind": "look",
              "comment": "the figure is hard to read at night", "width": 1440, "theme": "dark", "about": None, "cid": CID}
    record.update(changes)
    return record


def load_module(folder):
    """serve.py loaded fresh with its feedback files in `folder`, for the store's own functions."""
    spec = importlib.util.spec_from_file_location("feedback_serve", ROOT / "serve.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.DATA_DIR = str(folder)
    module.FEEDBACK_FILE = str(Path(folder) / "feedback.jsonl")
    module.FEEDBACK_STARTED = str(Path(folder) / "feedback-started.txt")
    module.FEEDBACK_HANDLED = str(Path(folder) / "feedback-handled.json")
    return module


class OffByDefault(unittest.TestCase):
    def test_no_route_and_no_file_served_when_not_enabled(self):
        with scratch_server() as (port, folder):
            self.assertEqual(request(port)[0], 404)
            self.assertEqual(post(port, good())[0], 501)                       # what the stdlib handler always said
            (folder / "feedback.jsonl").write_text('{"id": "x"}\n', encoding="utf-8")
            self.assertEqual(request(port, path="/feedback.jsonl")[0], 404)


class Route(unittest.TestCase):
    def test_needs_the_custom_header(self):
        with scratch_server(feedback=True) as (port, folder):
            status, _ = post(port, good(), headers={"Content-Type": "application/json"})
            self.assertEqual(status, 403)
            self.assertFalse((folder / "feedback.jsonl").exists())

    def test_a_record_is_stored_read_back_and_never_served_as_a_file(self):
        with scratch_server(feedback=True) as (port, folder):
            status, raw = post(port, good())
            self.assertEqual(status, 201)
            record = json.loads(raw)["record"]
            self.assertEqual(record["env"], "live")
            self.assertEqual(record["comment"], "the figure is hard to read at night")
            self.assertTrue(record["id"].startswith("fb-"))
            lines = (folder / "feedback.jsonl").read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 1)
            self.assertEqual(json.loads(lines[0])["cid"], CID)
            status, raw = request(port)
            info = json.loads(raw)
            self.assertEqual((status, info["enabled"], info["count"]), (200, True, 1))
            self.assertEqual(info["recent"][0]["id"], record["id"])
            for name in ("feedback.jsonl", "feedback-started.txt", "feedback.jsonl.bak"):
                self.assertEqual(request(port, path="/" + name)[0], 404, name)
            self.assertEqual(request(port, path="/%66eedback.jsonl")[0], 404)  # percent-encoded name

    def test_a_retried_send_is_not_stored_twice(self):
        with scratch_server(feedback=True) as (port, folder):
            first = post(port, good())
            second = post(port, good(comment="a retry that arrives with the same client id"))
            self.assertEqual((first[0], second[0]), (201, 200))
            self.assertTrue(json.loads(second[1])["record"]["duplicate"])
            self.assertEqual(len((folder / "feedback.jsonl").read_text(encoding="utf-8").splitlines()), 1)

    def test_bad_records_are_refused_without_echoing_the_comment(self):
        secret = "SECRET-NOTE-9931"
        bad = [good(kind="bogus", comment=secret), good(grade=11, comment=secret), good(grade=True, comment=secret),
               good(grade="7", comment=secret), good(page="../data", comment=secret), good(cid="x", comment=secret),
               good(theme="blue", comment=secret), good(about="two words", comment=secret),
               good(comment=secret + "\x00"), good(width=0, comment=secret), {**good(comment=secret), "extra": 1},
               good(comment="   "), good(comment="x" * 2001)]
        with scratch_server(feedback=True) as (port, folder):
            for record in bad:
                status, raw = post(port, record)
                self.assertEqual(status, 400, record)
                self.assertNotIn(secret.encode(), raw)
            self.assertEqual(post(port, [1, 2])[0], 400)
            self.assertEqual(request(port, "POST", "/feedback", b"not json", HEADER)[0], 400)
            self.assertFalse((folder / "feedback.jsonl").exists())

    def test_oversize_and_empty_bodies(self):
        with scratch_server(feedback=True) as (port, _):
            self.assertEqual(request(port, "POST", "/feedback", b"x" * (16 * 1024 + 1), HEADER)[0], 413)
            self.assertEqual(request(port, "POST", "/feedback", b"", HEADER)[0], 400)

    def test_the_comment_text_never_reaches_the_request_log(self):
        lines = []
        with scratch_server(feedback=True, log=lines) as (port, _):
            post(port, good(comment="PRIVATE-FIGURES-4471 are wrong"))
            request(port)
        self.assertTrue(lines)
        self.assertFalse([line for line in lines if "PRIVATE-FIGURES" in line])

    def test_budget_routes_are_unchanged_with_feedback_on(self):
        with scratch_server(feedback=True) as (port, folder):
            self.assertEqual(request(port, path="/data")[0], 200)
            self.assertEqual(request(port, "PUT", "/feedback", b"{}", HEADER)[0], 405)


class Store(unittest.TestCase):
    NOW = datetime.datetime(2026, 10, 9, 12, 0, tzinfo=datetime.timezone.utc)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.m = load_module(self.tmp.name)

    def add(self, cid, now=None, **changes):
        return self.m._fb_add(good(cid=cid, **changes), "live", now or self.NOW)

    def test_a_preview_server_is_told_apart(self):
        self.assertEqual(self.m._fb_add(good(), "preview", self.NOW)["env"], "preview")

    def test_switches_itself_off_after_thirty_quiet_days(self):
        self.add("cid-aaaaaaaa")
        later = self.NOW + datetime.timedelta(days=29)
        self.assertTrue(self.m._fb_status(later)["enabled"])
        gone = self.NOW + datetime.timedelta(days=31)
        self.assertFalse(self.m._fb_status(gone)["enabled"])
        with self.assertRaises(self.m.FeedbackOff):
            self.add("cid-bbbbbbbb", now=gone)

    def test_the_clock_runs_from_the_later_of_the_last_record_and_the_start_marker(self):
        self.assertTrue(self.m._fb_status(self.NOW)["enabled"])               # first use writes the marker
        self.assertTrue(Path(self.m.FEEDBACK_STARTED).exists())
        self.assertFalse(self.m._fb_status(self.NOW + datetime.timedelta(days=31))["enabled"])
        Path(self.m.FEEDBACK_STARTED).unlink()                                 # deleting it restarts the clock
        self.assertTrue(self.m._fb_status(self.NOW + datetime.timedelta(days=31))["enabled"])

    def test_a_torn_last_line_is_skipped_and_closed_off(self):
        self.add("cid-aaaaaaaa")
        with open(self.m.FEEDBACK_FILE, "ab") as fh:
            fh.write(b'{"id": "fb-torn", "comment": "half a rec')
        self.assertEqual(len(self.m._fb_records()), 1)
        record = self.add("cid-bbbbbbbb")
        lines = Path(self.m.FEEDBACK_FILE).read_bytes().split(b"\n")
        self.assertEqual(json.loads(lines[-2])["id"], record["id"])           # on its own line, not glued to the torn one
        self.assertEqual([r["cid"] for r in self.m._fb_records()], ["cid-aaaaaaaa", "cid-bbbbbbbb"])

    def test_the_file_is_capped(self):
        self.add("cid-aaaaaaaa")
        self.m.FEEDBACK_MAX_BYTES = 10
        with self.assertRaises(self.m.FeedbackFull):
            self.add("cid-bbbbbbbb")

    def test_records_are_only_ever_appended(self):
        first = self.add("cid-aaaaaaaa", comment="first")
        before = Path(self.m.FEEDBACK_FILE).read_bytes()
        second = self.add("cid-bbbbbbbb", comment="second")
        after = Path(self.m.FEEDBACK_FILE).read_bytes()
        self.assertTrue(after.startswith(before))
        self.assertEqual([r["id"] for r in self.m._fb_records()], [first["id"], second["id"]])

    def test_recent_notes_carry_their_processing_status_from_the_sidecar(self):
        a = self.add("cid-aaaaaaaa", comment="first")
        b = self.add("cid-bbbbbbbb", comment="second")
        c = self.add("cid-cccccccc", comment="third")
        status = {r["id"]: (r["status"], r["ref"]) for r in self.m._fb_status(self.NOW)["recent"]}
        self.assertEqual(set(status.values()), {("new", "")})                  # no sidecar: everything is new
        Path(self.m.FEEDBACK_HANDLED).write_text(json.dumps({
            a["id"]: {"status": "built", "ref": "abc1234 " + "x" * 300},
            b["id"]: {"status": "bogus", "ref": "ignored"},
            "unknown-id": {"status": "dropped"}}), encoding="utf-8")
        status = {r["id"]: (r["status"], r["ref"]) for r in self.m._fb_status(self.NOW)["recent"]}
        self.assertEqual(status[a["id"]][0], "built")
        self.assertEqual(len(status[a["id"]][1]), 120)                         # ref is capped
        self.assertEqual(status[b["id"]], ("new", ""))                         # an unknown status is not trusted
        self.assertEqual(status[c["id"]], ("new", ""))
        before = Path(self.m.FEEDBACK_FILE).read_bytes()
        Path(self.m.FEEDBACK_HANDLED).write_text("not json", encoding="utf-8")  # malformed sidecar: not fatal
        self.assertEqual(len(self.m._fb_status(self.NOW)["recent"]), 3)
        self.assertEqual(Path(self.m.FEEDBACK_FILE).read_bytes(), before)      # the store is never touched

    def test_private_names_are_refused_by_the_static_handler(self):
        for path in ("/feedback.jsonl", "/feedback-started.txt", "/feedback-handled.json", "/x/feedback.jsonl", "/notes.jsonl"):
            self.assertTrue(self.m._is_private_url(path), path)
        self.assertFalse(self.m._is_private_url("/pocket-envelopes.app"))


if __name__ == "__main__":
    unittest.main()
