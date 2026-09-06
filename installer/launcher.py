"""Start Pocket Envelopes from an installed copy (Windows installer).

Run by the bundled ``python\\pythonw.exe`` so no console window appears:

    pythonw launcher.py                 start the server if needed, open the app
    pythonw launcher.py --no-browser    start the server only (sign-in autostart)
    pythonw launcher.py --always-on     never idle-shutdown (with the above)

What it does, in order:
  1. Points the server at a per-user data folder (%LOCALAPPDATA%\\PocketEnvelopes)
     unless DATA_DIR is already set. The program folder stays read-only.
  2. If something already answers on the port, just opens the browser: the
     server is already running (an earlier launch, or the sign-in autostart).
  3. Otherwise runs serve.py in this process, opening the browser as soon as
     the port accepts connections.
  4. pythonw has no stdout/stderr; both go to server.log in the data folder
     (truncated on each start), so a failure leaves a trace.

Nothing here is Windows-specific except the LOCALAPPDATA default; the same
file works with any Python and any platform's ``python launcher.py``.
"""
import os
import runpy
import socket
import sys
import threading
import time
import webbrowser

HERE = os.path.dirname(os.path.abspath(__file__))
SERVE = os.path.join(HERE, "serve.py")
PORT = int(os.environ.get("PORT", "8765"))
URL = f"http://localhost:{PORT}/"

no_browser = "--no-browser" in sys.argv
always_on = "--always-on" in sys.argv

data_dir = os.environ.get("DATA_DIR") or os.path.join(
    os.environ.get("LOCALAPPDATA") or os.path.expanduser("~"), "PocketEnvelopes")
os.environ["DATA_DIR"] = data_dir
os.environ.setdefault("BIND", "127.0.0.1")
if always_on:
    os.environ["IDLE_TIMEOUT"] = "0"
os.makedirs(data_dir, exist_ok=True)

if sys.stdout is None or sys.stderr is None:
    log = open(os.path.join(data_dir, "server.log"), "w", encoding="utf-8", buffering=1)
    sys.stdout = sys.stderr = log


def port_open(timeout=0.3):
    try:
        with socket.create_connection(("127.0.0.1", PORT), timeout=timeout):
            return True
    except OSError:
        return False


if port_open():
    # Already running: this launch just brings the app up.
    if not no_browser:
        webbrowser.open(URL)
    sys.exit(0)


def open_when_ready():
    for _ in range(100):          # up to ~10 s
        if port_open():
            webbrowser.open(URL)
            return
        time.sleep(0.1)


if not no_browser:
    threading.Thread(target=open_when_ready, daemon=True).start()

os.chdir(HERE)
sys.argv = [SERVE]
runpy.run_path(SERVE, run_name="__main__")
