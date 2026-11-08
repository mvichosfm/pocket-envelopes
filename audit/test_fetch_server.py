"""The optional statement-fetch trigger's server half (FETCH_TASK); python audit/test_fetch_server.py (stdlib only).

Real HTTP against a scratch server. Task Scheduler is replaced by a fake: nothing here starts a real task.
"""
import datetime
import http.client
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from scratch_server import ROOT, scratch_server

HEADER = {"X-Requested-With": "pocket-envelopes"}


def request(port, method="GET", path="/fetch", headers=None):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        connection.request(method, path, None, headers or {})
        response = connection.getresponse()
        return response.status, response.read(), dict(response.getheaders())
    finally:
        connection.close()


def now_plus(seconds=0):
    return (datetime.datetime.now().astimezone() + datetime.timedelta(seconds=seconds)).isoformat()


class Fake:
    def __init__(self, code=0):
        self.calls, self.code = [], code

    def __call__(self, args, **kwargs):
        self.calls.append(list(args))
        return mock.Mock(returncode=self.code, stdout="", stderr="")


class Env:
    """Environment variables for one scratch server (serve.py reads them at import)."""
    def __init__(self, **values):
        self.values = values

    def __enter__(self):
        self.old = {k: os.environ.get(k) for k in self.values}
        os.environ.update(self.values)

    def __exit__(self, *exc):
        for k, v in self.old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


class OffByDefault(unittest.TestCase):
    def test_no_route_when_not_enabled(self):
        with Env(FETCH_TASK=""), scratch_server() as (port, _):
            self.assertEqual(request(port)[0], 404)
            self.assertEqual(request(port, "POST", headers=HEADER)[0], 501)       # what the stdlib handler always said

    def test_a_bad_task_name_stops_the_server_from_starting(self):
        for bad in ["a&b", "x" * 61, "task\\evil", "t;calc"]:
            with Env(FETCH_TASK=bad):
                spec = importlib.util.spec_from_file_location("fetch_serve_bad", ROOT / "serve.py")
                module = importlib.util.module_from_spec(spec)
                with self.assertRaises(SystemExit, msg=bad):
                    spec.loader.exec_module(module)


class Enabled(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.status = Path(self.tmp.name) / "fetch-status.json"

    def tearDown(self):
        self.tmp.cleanup()

    def server(self, cooldown="300"):
        return Env(FETCH_TASK="Test Task", FETCH_STATUS_FILE=str(self.status), FETCH_COOLDOWN=cooldown)

    def test_guards_and_a_fixed_command(self):
        with self.server(), scratch_server() as (port, _):
            self.assertEqual(request(port)[0], 200)
            status, body, _ = request(port)
            self.assertEqual(json.loads(body)["status"]["state"], "idle")
            self.assertEqual(request(port, "POST")[0], 403, "no custom header: refused")
            self.assertEqual(request(port, "POST", headers={**HEADER, "Host": "evil.example"})[0], 421, "foreign Host: refused")
            fake = Fake()
            with mock.patch("subprocess.run", fake):
                code, body, _ = request(port, "POST", headers=HEADER)
                self.assertEqual(code, 202)
                self.assertEqual(json.loads(body)["state"], "starting")
                self.assertEqual(len(fake.calls), 1)
                self.assertTrue(fake.calls[0][0].lower().endswith("schtasks.exe"))
                self.assertEqual(fake.calls[0][1:], ["/Run", "/TN", "Test Task"], "the one fixed command, nothing from the request")
                # a second start while the first has not reported: refused
                self.assertEqual(request(port, "POST", headers=HEADER)[0], 409)
                self.assertEqual(len(fake.calls), 1)

    def test_status_is_whitelisted_and_gates_the_next_start(self):
        with self.server(), scratch_server() as (port, _):
            fake = Fake()
            with mock.patch("subprocess.run", fake):
                self.assertEqual(request(port, "POST", headers=HEADER)[0], 202)
                self.status.write_text(json.dumps({"state": "downloading", "message": "cash", "at": now_plus(1),
                                                   "secret": "x"}), encoding="utf-8")
                status = json.loads(request(port)[1])["status"]
                self.assertEqual(status["state"], "downloading")
                self.assertNotIn("secret", status)
                self.assertEqual(request(port, "POST", headers=HEADER)[0], 409, "still running")
                self.status.write_text(json.dumps({"state": "done", "message": "ok", "at": now_plus(2),
                                                   "summary": {"booked": 2, "queued": 3, "gap": -1.5, "evil": 9, "lines": True, "unexplained": "x"}}),
                                       encoding="utf-8")
                status = json.loads(request(port)[1])["status"]
                self.assertEqual(status["state"], "done")
                self.assertEqual(status["summary"], {"booked": 2, "queued": 3, "gap": -1.5}, "only numeric whitelisted keys survive")
                code, body, headers = request(port, "POST", headers=HEADER)
                self.assertEqual(code, 429, "inside the cooldown")
                self.assertIn("Retry-After", headers)
                self.assertEqual(len(fake.calls), 1)

    def test_cooldown_over_allows_another_run(self):
        with self.server(cooldown="0"), scratch_server() as (port, _):
            fake = Fake()
            with mock.patch("subprocess.run", fake):
                self.assertEqual(request(port, "POST", headers=HEADER)[0], 202)
                self.status.write_text(json.dumps({"state": "done", "message": "", "at": now_plus(1)}), encoding="utf-8")
                self.assertEqual(request(port, "POST", headers=HEADER)[0], 202)
                self.assertEqual(len(fake.calls), 2)

    def test_a_dead_run_and_bad_files_do_not_block_or_leak(self):
        with self.server(cooldown="0"), scratch_server() as (port, folder):
            old = (datetime.datetime.now().astimezone() - datetime.timedelta(hours=1)).isoformat()
            self.status.write_text(json.dumps({"state": "waiting-approval", "message": "x", "at": old}), encoding="utf-8")
            self.assertEqual(json.loads(request(port)[1])["status"]["state"], "stopped", "an active state that old means the run died")
            with mock.patch("subprocess.run", Fake()):
                self.assertEqual(request(port, "POST", headers=HEADER)[0], 202, "so a new run may start")
            for junk in ["not json", "[1,2]", json.dumps({"state": "rm -rf"}), "x" * 20000]:
                self.status.write_text(junk, encoding="utf-8")
                self.assertIn(json.loads(request(port)[1])["status"]["state"], ("idle", "starting"), junk[:20])
            (folder / "fetch-status.json").write_text("{}", encoding="utf-8")
            self.assertEqual(request(port, path="/fetch-status.json")[0], 404, "the progress file is never served as a static file")

    def test_a_task_that_will_not_start_is_reported_and_not_remembered(self):
        with self.server(cooldown="300"), scratch_server() as (port, _):
            with mock.patch("subprocess.run", Fake(code=1)):
                self.assertEqual(request(port, "POST", headers=HEADER)[0], 502)
            with mock.patch("subprocess.run", Fake(code=0)):
                self.assertEqual(request(port, "POST", headers=HEADER)[0], 202, "a failed start does not trigger the cooldown")


class Silent(unittest.TestCase):
    """A task that starts but never reports must not leave the server saying 'starting' for ever."""

    def test_a_started_task_that_never_reports_stops_blocking(self):
        with tempfile.TemporaryDirectory() as t, Env(FETCH_TASK="Test Task", FETCH_STATUS_FILE=str(Path(t) / "fetch-status.json"), FETCH_COOLDOWN="0"):
            spec = importlib.util.spec_from_file_location("fetch_serve_silent", ROOT / "serve.py")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            with mock.patch("subprocess.run", Fake()):
                self.assertEqual(module._fetch_start()[0], 202)
                self.assertEqual(module._fetch_status()["state"], "starting")
                self.assertEqual(module._fetch_start()[0], 409, "inside the grace period it is still starting")
                module._fetch_started_at = datetime.datetime.now().astimezone() - datetime.timedelta(seconds=module.FETCH_START_GRACE_SECONDS + 5)
                st = module._fetch_status()
                self.assertEqual(st["state"], "stopped")
                self.assertIn("did not report", st["message"])
                self.assertEqual(module._fetch_start()[0], 202, "so the next press starts a new run (cooldown is 0)")


if __name__ == "__main__":
    unittest.main()
