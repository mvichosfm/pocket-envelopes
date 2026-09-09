; Inno Setup script for the Pocket Envelopes Windows installer.
; Build with installer\build.ps1, which stages the embeddable Python runtime
; into installer\stage\python before calling ISCC on this file.

#define MyAppName "Pocket Envelopes"
#ifndef MyAppVersion
  #define MyAppVersion "0.6.1"
#endif
#define MyAppPublisher "Manos Vichos"
#define MyAppURL "https://github.com/mvichosfm/pocket-envelopes"
#define MyPython "python\pythonw.exe"

[Setup]
AppId={{7E1D4E2A-5C1B-4B0E-9A4C-2F3E8B6D1A57}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
; Per-user install: no admin prompt, and nothing is written under Program Files.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=PocketEnvelopes-Setup-{#MyAppVersion}
SetupIconFile=pocket-envelopes.ico
UninstallDisplayIcon={app}\pocket-envelopes.ico
UninstallDisplayName={#MyAppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; A running server holds pythonw.exe open; let Restart Manager close it on upgrade.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; Flags: unchecked
Name: "autostart"; Description: "Start the server when I sign in (keeps it running for phone and installed-app use; it shuts itself down when idle otherwise)"; Flags: unchecked

[Files]
Source: "..\pocket-envelopes.app"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\serve.py"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\sw.js"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\manifest.webmanifest"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\icons\*"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "..\vendor\*"; DestDir: "{app}\vendor"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "launcher.py"; DestDir: "{app}"; Flags: ignoreversion
Source: "pocket-envelopes.ico"; DestDir: "{app}"; Flags: ignoreversion
; The embeddable CPython runtime, staged by build.ps1 (its own LICENSE.txt included).
Source: "stage\python\*"; DestDir: "{app}\python"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyPython}"; Parameters: """{app}\launcher.py"""; WorkingDir: "{app}"; IconFilename: "{app}\pocket-envelopes.ico"; Comment: "Start the budget server and open the app"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyPython}"; Parameters: """{app}\launcher.py"""; WorkingDir: "{app}"; IconFilename: "{app}\pocket-envelopes.ico"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName} server"; Filename: "{app}\{#MyPython}"; Parameters: """{app}\launcher.py"" --no-browser --always-on"; WorkingDir: "{app}"; IconFilename: "{app}\pocket-envelopes.ico"; Tasks: autostart

[Run]
Filename: "{app}\{#MyPython}"; Parameters: """{app}\launcher.py"""; WorkingDir: "{app}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\{#MyPython}"; Parameters: """{app}\launcher.py"" --no-browser --always-on"; WorkingDir: "{app}"; Flags: nowait runhidden; Tasks: autostart

[Code]
// Stop any server started from this install folder, so files can be replaced
// (upgrade) or removed (uninstall). Matches on the launcher path, so other
// Python processes on the machine are left alone.
procedure StopServer();
var
  ResultCode: Integer;
  Cmd: String;
begin
  Cmd := '-NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process -Filter ''Name = ''''pythonw.exe'''' OR Name = ''''python.exe'''''' | Where-Object { $_.CommandLine -like ''*' + ExpandConstant('{app}') + '\launcher.py*'' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"';
  Exec('powershell.exe', Cmd, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopServer();
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  StopServer();
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and not UninstallSilent then
    MsgBox('Pocket Envelopes was removed. Your budget was kept at:' + #13#10 + #13#10 +
           ExpandConstant('{localappdata}\PocketEnvelopes') + #13#10 + #13#10 +
           'Delete that folder yourself if you no longer want it.', mbInformation, MB_OK);
end;
