; Inno Setup script for Lectern.
; Build it with installer\build-installer.ps1 (which passes AppVersion),
; or open it in the Inno Setup Compiler.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

#define AppName "Lectern"
#define AppExe "lectern.exe"
; Must match SetCurrentProcessExplicitAppUserModelID in windows\runner\main.cpp,
; so Windows' media controls show "Lectern" instead of "Unknown app".
#define AppUserModelID "Lectern.Desktop"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; Never change AppId: Windows uses it to recognise upgrades of the same app.
AppId={{53F76B52-5DD5-4E40-9C3D-188A5B29529A}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Lectern contributors
LicenseFile=..\LICENSE
VersionInfoVersion={#AppVersion}
; Per-user install into %LOCALAPPDATA%\Programs\Lectern: no admin prompt.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=output
OutputBaseFilename=Lectern-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; Close a running Lectern before upgrading it.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; The whole release build: lectern.exe, flutter_windows.dll, plugins, data\...
; It also contains the Visual C++ runtime DLLs (msvcp140.dll,
; vcruntime140.dll, ...) and the newer libmpv-2.dll, both added by the build
; (see installer\patch-windows-runner.ps1), so nothing else needs installing.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppUserModelID}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppUserModelID}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
