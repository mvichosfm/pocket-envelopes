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
powershell -ExecutionPolicy Bypass -File installer\build.ps1 -Version 0.8.0
```

Output: `dist\PocketEnvelopes-Setup-0.8.0.exe` (about 11 MB, most of it the
Python runtime).

## Built on GitHub Actions for releases

`.github/workflows/installer.yml` runs this same `build.ps1` on a `windows-latest` runner (Inno Setup is preinstalled there) for every `v*` tag, uploads the installer as a workflow artifact, and attaches it plus a `.sha256` file to the GitHub release. The workflow carries a dormant code-signing job for SignPath: it runs only if the repository ever has the `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG`, `SIGNPATH_SIGNING_POLICY_SLUG` variables and the `SIGNPATH_API_TOKEN` secret, in which case the signed file is attached instead. There is no signing certificate today; the release page's SHA-256 is the verification. *Run workflow* on the Actions tab does a dry run without a tag.

## Test it without touching your own budget

The launcher honours `PORT`, so a test can run beside a real server:

```powershell
$env:PORT = "8766"
& "$env:LOCALAPPDATA\Programs\Pocket Envelopes\python\pythonw.exe" "$env:LOCALAPPDATA\Programs\Pocket Envelopes\launcher.py"
```

Silent install / uninstall for scripted checks: `Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` and the same flags on `unins000.exe` in the install folder.

## Updating the bundled Python

Change `$PythonVersion` and `$PythonSha256` together in `build.ps1`; the hash is the one python.org publishes for `python-<version>-embed-amd64.zip`. The runtime's `LICENSE.txt` ships inside the installer under `python\`.
