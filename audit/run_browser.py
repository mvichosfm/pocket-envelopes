"""Run browser checks with disposable assets/data and an automatically freed port."""
import os
from pathlib import Path
import subprocess
import sys

from scratch_server import scratch_server

with scratch_server() as (port, _):
    environment = dict(os.environ, SERVER="http://127.0.0.1:" + str(port), POCKET_AUDIT_SCRATCH="1")
    for script in ("visual-smoke.py", "browser_persistence.py"):
        result = subprocess.run([sys.executable, str(Path(__file__).with_name(script))], env=environment)
        if result.returncode:
            break
sys.exit(result.returncode)
