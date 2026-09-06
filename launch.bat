@echo off
REM Launches the Pocket Envelopes app via a local http server. The server owns
REM finance-data.json and serves it over /data, so it is the storage layer, not
REM just a way to get an http:// origin. The app file is named
REM pocket-envelopes.app (no .html) so double-clicking it in Explorer cannot
REM accidentally open it under file://, which would have no server to talk to.
REM
REM Closing this window stops the server.

setlocal
set PORT=8765
set URL=http://localhost:%PORT%/

REM Loopback only. Remote access is meant to go through `tailscale serve`,
REM which proxies https://<host>.ts.net -> 127.0.0.1:8765 and restricts
REM reachability to your tailnet. Binding 0.0.0.0 here instead would ALSO
REM expose the app, unauthenticated, to every device on the local network.
REM Set BIND=0.0.0.0 deliberately if that is what you want.
set BIND=127.0.0.1

cd /d "%~dp0"

REM --- Detect Python: try the `py -3` launcher first, then plain `python`. ---
py -3 --version >nul 2>nul
if not errorlevel 1 (
    set PYTHON_CMD=py -3
    goto :have_python
)
python --version >nul 2>nul
if not errorlevel 1 (
    set PYTHON_CMD=python
    goto :have_python
)

REM --- No Python found: show install hint and keep the window open. ---
echo.
echo ============================================================
echo  Python 3 is required but was not found on this PC.
echo ============================================================
echo.
echo  This project ships a tiny built-in Python web server
echo  (serve.py). The server IS the storage layer: it keeps your budget
echo  in finance-data.json next to it and every device reads and writes
echo  through it, so the app cannot run from a plain file:// page.
echo.
echo  Install Python 3 (one-time, ~30 MB) by either:
echo.
echo    1. winget:           winget install Python.Python.3.12
echo    2. Microsoft Store:  search "Python 3.12" and click Install
echo    3. Manual download:  https://www.python.org/downloads/
echo.
echo  After installing, close this window and double-click
echo  launch.bat again. No PC restart required.
echo.
pause
exit /b 1

:have_python
echo Starting local server on port %PORT% using %PYTHON_CMD%...
echo Project folder: %CD%
echo Opening %URL% in your default browser.
echo.
echo *** Server will auto-shut down after 30 minutes of inactivity. ***
echo Close this window or press Ctrl+C to stop it sooner.
echo.

REM Open the page first, then run the server in the foreground.
start "" "%URL%"

%PYTHON_CMD% "%~dp0serve.py"

if errorlevel 1 (
    echo.
    echo Server exited with an error. Press any key to close this window.
    pause >nul
)

endlocal
