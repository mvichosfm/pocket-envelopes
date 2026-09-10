"""Real HTTP/disk persistence checks; python audit/test_server.py (stdlib only)."""
from concurrent.futures import ThreadPoolExecutor
import http.client
import json
from pathlib import Path
import shutil
import socket
import tempfile
import unittest

from scratch_server import scratch_server


def request(port, method="GET", path="/data", body=None, headers=None):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        connection.request(method, path, body, headers or {})
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), response.read()
    finally:
        connection.close()


def budget(value):
    return json.dumps({"version": 2, "accounts": [], "envelopes": [],
                       "transactions": [], "recurring": [], "settings": {},
                       "test_value": value}).encode("utf-8")


class PersistenceTests(unittest.TestCase):
    def test_first_run_save_reload_and_static_privacy(self):
        with scratch_server() as (port, folder):
            status, headers, body = request(port)
            self.assertEqual(status, 200)
            self.assertEqual(headers.get("X-Data-New"), "1")
            self.assertFalse((folder / "finance-data.json").exists())
            payload = budget("synthetic")
            status, saved, _ = request(port, "PUT", body=payload, headers={"If-Match": headers["ETag"]})
            self.assertEqual(status, 204)
            status, loaded, body = request(port)
            self.assertEqual(body, payload)
            self.assertEqual(loaded["ETag"], saved["ETag"])
            self.assertNotIn("X-Data-New", loaded)
            self.assertEqual((folder / "finance-data.json").read_bytes(), payload)
            self.assertFalse((folder / "finance-data.json.tmp").exists())
            for path in ("/finance-data.json", "/finance%2Ddata.json", "/finance-data.bak.0", "/.git/config"):
                self.assertEqual(request(port, path=path)[0], 404, path)
            self.assertEqual(request(port, headers={"Host": "attacker.example"})[0], 421)
            status, headers, _ = request(port, path="/")
            self.assertEqual(status, 200)
            self.assertIn("text/html", next(v for k, v in headers.items() if k.lower() == "content-type"))

    def test_concurrent_clients_cannot_silently_overwrite(self):
        with scratch_server() as (port, folder):
            initial = request(port)[1]["ETag"]
            def write(value):
                return request(port, "PUT", body=budget(value), headers={"If-Match": initial})
            with ThreadPoolExecutor(max_workers=2) as pool:
                replies = list(pool.map(write, ("A", "B")))
            self.assertEqual(sorted(r[0] for r in replies), [204, 409])
            winner = "A" if replies[0][0] == 204 else "B"
            self.assertEqual(request(port)[2], budget(winner))
            # Explicit overwrite preserves the replaced version on disk.
            self.assertEqual(request(port, "PUT", body=budget("chosen"))[0], 204)
            self.assertEqual((folder / "finance-data.bak.0").read_bytes(), budget(winner))

    def test_invalid_writes_preserve_budget_and_backups(self):
        with scratch_server() as (port, folder):
            request(port, "PUT", body=budget("A"))
            request(port, "PUT", body=budget("B"))
            for payload in (b"{broken", b"\xff", b""):
                self.assertEqual(request(port, "PUT", body=payload)[0], 400)
            self.assertEqual(request(port, "PUT", body=b"x", headers={"Content-Length": str(65 * 1024 * 1024)})[0], 413)
            self.assertEqual(request(port)[2], budget("B"))
            self.assertEqual((folder / "finance-data.bak.0").read_bytes(), budget("A"))

    def test_rotating_backups_restore_after_restart(self):
        with tempfile.TemporaryDirectory(prefix="pocket-restore-") as directory:
            with scratch_server(directory) as (port, folder):
                for value in range(7):
                    self.assertEqual(request(port, "PUT", body=budget(value))[0], 204)
                for slot in range(5):
                    self.assertEqual((folder / ("finance-data.bak." + str(slot))).read_bytes(), budget(5 - slot))
                self.assertFalse((folder / "finance-data.bak.5").exists())
            # Follow the documented recovery: stop, copy a backup, restart.
            shutil.copy2(Path(directory) / "finance-data.bak.2", Path(directory) / "finance-data.json")
            with scratch_server(directory) as (port, folder):
                self.assertEqual(request(port)[2], budget(3))
                tag = request(port)[1]["ETag"]
                self.assertEqual(request(port, "PUT", body=budget("after restore"), headers={"If-Match": tag})[0], 204)

    def test_stalled_upload_times_out_without_changing_disk(self):
        with scratch_server(timeout=0.25) as (port, folder):
            request(port, "PUT", body=budget("safe"))
            with socket.create_connection(("127.0.0.1", port), timeout=3) as client:
                client.sendall(b"PUT /data HTTP/1.0\r\nHost: localhost\r\nContent-Length: 100\r\n\r\n{")
                self.assertEqual(client.recv(1024), b"", "stalled request must terminate")
            self.assertEqual(request(port)[2], budget("safe"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
