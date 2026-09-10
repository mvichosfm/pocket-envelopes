"""Disposable loopback server for integration/browser checks. Stdlib only.

Only public app assets are copied; a real finance-data.json is never read.
"""
from contextlib import contextmanager
from functools import partial
import importlib.util
from pathlib import Path
import shutil
import socketserver
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]


@contextmanager
def scratch_server(directory=None, timeout=30):
    with tempfile.TemporaryDirectory(prefix="pocket-audit-") as temporary:
        folder = Path(directory or temporary).resolve()
        folder.mkdir(parents=True, exist_ok=True)
        for name in ("pocket-envelopes.app", "sw.js", "manifest.webmanifest"):
            shutil.copy2(ROOT / name, folder / name)
        for name in ("vendor", "icons"):
            if not (folder / name).exists():
                shutil.copytree(ROOT / name, folder / name)
        spec = importlib.util.spec_from_file_location("scratch_serve", ROOT / "serve.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.DATA_DIR = str(folder)
        module.DATA_FILE = str(folder / "finance-data.json")
        module.TMP_FILE = module.DATA_FILE + ".tmp"
        module.BAK_PREFIX = str(folder / "finance-data.bak.")

        class QuietHandler(module.Handler):
            def log_message(self, *args):
                pass

        QuietHandler.timeout = timeout
        with socketserver.ThreadingTCPServer(
            ("127.0.0.1", 0), partial(QuietHandler, directory=str(folder))
        ) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                yield server.server_address[1], folder
            finally:
                server.shutdown()
                thread.join(timeout=5)
