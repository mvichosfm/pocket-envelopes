# Windows installer

Everything needed to build `PocketEnvelopes-Setup-<version>.exe`.

| File | Role |
|---|---|
| `build.ps1` | The build. Downloads the official embeddable CPython runtime from python.org into `stage/` (gitignored), verifies it against the SHA-256 pinned in the script, extracts it, then compiles the Inno Setup script. Prints the installer's own SHA-256 at the end, for the release notes. |
| `PocketEnvelopes.iss` | Inno Setup 6 script: per-user install, no administrator rights, files + bundled runtime, Start-menu shortcut, optional desktop shortcut and sign-in autostart, stop-the-server hooks for upgrade and uninstall. |
| `launcher.py` | What the shortcuts run, under the bundled `pythonw.exe`. Keeps the budget in `%LOCALAPPDATA%\PocketEnvelopes`, starts the server only if nothing already answers on the port, opens the browser when it does. |
| `make-icon.py`, `pocket-envelopes.ico` | Icon build (stdlib only) and its committed output. |

## Build

```powershell
winget install JRSoftware.InnoSetup
powershell -ExecutionPolicy Bypass -File installer\build.ps1 -Version 0.3.0
```

Output: `dist\PocketEnvelopes-Setup-0.3.0.exe` (about 11 MB, most of it the
Python runtime).

## Test it without touching your own budget

The launcher honours `PORT`, so a test can run beside a real server:

```powershell
$env:PORT = "8766"
& "$env:LOCALAPPDATA\Programs\Pocket Envelopes\python\pythonw.exe" "$env:LOCALAPPDATA\Programs\Pocket Envelopes\launcher.py"
```

Silent install / uninstall for scripted checks: `Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` and the same flags on `unins000.exe` in the install folder.

## Updating the bundled Python

Change `$PythonVersion` and `$PythonSha256` together in `build.ps1`; the hash is the one python.org publishes for `python-<version>-embed-amd64.zip`. The runtime's `LICENSE.txt` ships inside the installer under `python\`.
