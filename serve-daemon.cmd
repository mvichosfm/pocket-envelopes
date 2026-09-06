@echo off
REM Background launcher for always-on serving. Used by the
REM "PocketEnvelopesServer" scheduled task; safe to run by hand too.
REM
REM Differs from launch.bat in three ways:
REM   - no browser is opened (nobody is watching)
REM   - IDLE_TIMEOUT=0, so the server never shuts itself down
REM   - pythonw.exe, so there is no console window sitting in the taskbar
REM
REM BIND stays on loopback: remote devices reach the app through
REM `tailscale serve`, which proxies https://<host>.ts.net -> 127.0.0.1:8765.
REM Binding 0.0.0.0 would expose the app unauthenticated to the whole LAN.

cd /d "%~dp0"

set BIND=127.0.0.1
set IDLE_TIMEOUT=0
set PORT=8765
set LOGFILE=%~dp0serve-daemon.log

REM Run the server in the FOREGROUND, not via `start /b`. This script is the
REM task's process, so blocking here is what makes the scheduled task track
REM the server's real lifetime: the task shows Running while it serves, Stop
REM actually stops it, and a crash ends the task with an error so Task
REM Scheduler's restart policy fires. Detaching instead would make the task
REM report success a second after boot and leave the server unsupervised.
REM pythonw is windowless, so nothing appears on screen either way.
where pythonw.exe >nul 2>nul
if not errorlevel 1 (
    pythonw.exe "%~dp0serve.py" >> "%LOGFILE%" 2>&1
    exit /b %errorlevel%
)
where python.exe >nul 2>nul
if not errorlevel 1 (
    python.exe "%~dp0serve.py" >> "%LOGFILE%" 2>&1
    exit /b %errorlevel%
)

echo [%date% %time%] no python found on PATH >> "%LOGFILE%"
exit /b 1
