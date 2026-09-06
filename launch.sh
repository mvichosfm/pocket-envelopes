#!/usr/bin/env sh
# Launches the Pocket Envelopes app via a local http server. The server owns
# finance-data.json and serves it over /data, so it is the storage layer, not
# just a way to get an http:// origin. The app file is named
# pocket-envelopes.app (no .html) so double-clicking it in a file manager
# cannot accidentally open it under file://, which would have no server to
# talk to.
#
# Pair of launch.bat for Windows; identical UX. Close terminal to stop.

set -e

PORT=8765
URL="http://localhost:$PORT/"

# Loopback only. Remote access is meant to go through `tailscale serve`, which
# proxies https://<host>.ts.net -> 127.0.0.1:8765 and restricts reachability to
# your tailnet. Binding 0.0.0.0 here instead would ALSO expose the app,
# unauthenticated, to every device on the local network. Set BIND=0.0.0.0
# deliberately if that is what you want.
BIND=127.0.0.1
export BIND

# Resolve script directory (works under symlinks, bash, dash, zsh).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# --- Detect Python 3 ---
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD=python3
elif command -v python >/dev/null 2>&1; then
    # Some systems alias python -> python3; check the version.
    if python -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
        PYTHON_CMD=python
    fi
fi

if [ -z "$PYTHON_CMD" ]; then
    cat <<'EOF'

============================================================
 Python 3 is required but was not found on this system.
============================================================

 This project ships a tiny built-in Python web server
 (serve.py). The server IS the storage layer: it keeps your budget
 in finance-data.json next to it and every device reads and writes
 through it, so the app cannot run from a plain file:// page.

 Install Python 3 (one-time, ~30 MB) by:

   macOS:     brew install python
              (or download from https://www.python.org/downloads/)
   Debian/Ubuntu:
              sudo apt install python3
   Fedora:    sudo dnf install python3
   Arch:      sudo pacman -S python

 After installing, re-run this script. No reboot required.

EOF
    exit 1
fi

echo "Starting local server on port $PORT using $PYTHON_CMD..."
echo "Project folder: $SCRIPT_DIR"
echo "Opening $URL in your default browser."
echo
echo "*** Server will auto-shut down after 30 minutes of inactivity. ***"
echo "Close this window or press Ctrl+C to stop it sooner."
echo

# Open the browser in the background, then run the server in the foreground.
# xdg-open: Linux. open: macOS. Fail silently if neither is available — the
# user can paste the URL manually.
(sleep 1 && { command -v xdg-open >/dev/null 2>&1 && xdg-open "$URL"; } \
                    || { command -v open >/dev/null 2>&1 && open "$URL"; } \
                    || echo "Could not auto-open browser; visit $URL manually.") &

exec "$PYTHON_CMD" "$SCRIPT_DIR/serve.py"
