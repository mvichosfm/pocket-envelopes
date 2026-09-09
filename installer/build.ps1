<#
Build the Windows installer: dist\PocketEnvelopes-Setup-<version>.exe

    powershell -ExecutionPolicy Bypass -File installer\build.ps1 [-Version 0.6.1]

Needs Inno Setup 6 (winget install JRSoftware.InnoSetup). Downloads the
official embeddable CPython runtime from python.org into installer\stage
(gitignored), verifies its SHA-256 against the value pinned below, extracts
it, then compiles PocketEnvelopes.iss. Nothing else is fetched.

To move to a newer Python: change the version and hash together. The hash is
the one python.org publishes for the embeddable amd64 zip of that release.
#>
param(
    [string]$Version = "0.6.1"
)
$ErrorActionPreference = "Stop"

$PythonVersion = "3.13.15"
$PythonSha256  = "d1f04d990aee1253d8569e8e5104e30fa9f5fa830899f14843448872d936a2cf"
$PythonUrl     = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"

$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$stage = Join-Path $here "stage"
$zip   = Join-Path $stage "python-$PythonVersion-embed-amd64.zip"
$pyDir = Join-Path $stage "python"

New-Item -ItemType Directory -Force $stage | Out-Null

if (-not (Test-Path $zip)) {
    Write-Host "Downloading $PythonUrl"
    Invoke-WebRequest -Uri $PythonUrl -OutFile $zip -UseBasicParsing
}
$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $PythonSha256) {
    Remove-Item $zip -Force
    throw "SHA-256 mismatch for $zip`n expected $PythonSha256`n got      $actual`nThe download was removed; re-run to fetch it again."
}
Write-Host "Python $PythonVersion embeddable runtime verified."

if (Test-Path $pyDir) { Remove-Item $pyDir -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $pyDir
# The runtime's own license travels with it.
if (-not (Test-Path (Join-Path $pyDir "LICENSE.txt"))) { throw "LICENSE.txt missing from the Python runtime" }

$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 not found. Install it with: winget install JRSoftware.InnoSetup" }

& $iscc "/DMyAppVersion=$Version" (Join-Path $here "PocketEnvelopes.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }

$out = Join-Path (Split-Path -Parent $here) "dist\PocketEnvelopes-Setup-$Version.exe"
Write-Host ""
Write-Host "Built $out ($([math]::Round((Get-Item $out).Length / 1MB, 1)) MB)"
Write-Host "SHA-256 $((Get-FileHash $out -Algorithm SHA256).Hash.ToLower())"
