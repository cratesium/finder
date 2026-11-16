; Inno Setup 6 script for the Finder Windows installer.
;
; Build the app first (with bundled yt-dlp + FFmpeg):
;   dart run tool/fetch_dependencies.dart --platform windows --arch x64
;   flutter build windows --release
; Then (version comes from pubspec.yaml; tool/package_windows.ps1 does all of this):
;   iscc /DAppVersion=3.0.0 /DAppBuild=3 packaging\windows\finder.iss
;
; Output: build\release\Finder-<version>-windows-x64-setup.exe
;
; The user picks a per-user install (no admin rights) or an install for all
; users. The AppId never changes, so a newer installer upgrades in place.

#ifndef AppVersion
  #error Pass /DAppVersion=<x.y.z> (see tool/package_windows.ps1)
#endif
#ifndef AppBuild
  #define AppBuild "0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

#define AppName "Finder"
#define AppExe "finder.exe"
#define AppPublisher "Cratesium"

[Setup]
; Stable identity: do not change, or upgrades become side-by-side installs.
AppId={{6F3B2C1E-8A4D-4C7B-9E21-C7A5D3F0B9E4}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}.{#AppBuild}
AppPublisher={#AppPublisher}
AppPublisherURL=https://cratesium.app
AppCopyright=Copyright (C) 2026 Cratesium
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17134
OutputDir=..\..\build\release
OutputBaseFilename=Finder-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
; Close a running Finder (and its yt-dlp/FFmpeg children) before upgrading.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Replace the bundled tools wholesale on upgrade so no stale files remain.
Type: filesandordirs; Name: "{app}\bin"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; User data (history, settings, logs in %APPDATA%\Finder) is kept on
; uninstall so a reinstall picks up where the user left off.
