; Builds FlyyLink-Setup-<version>.exe from the published app in windows\publish\Aproid.
; iscc /DAppVersion=1.2.3 installer\Aproid.iss
; Installs for the current user only, so it needs no administrator rights and can update itself silently.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

#define AppName "FlyyLink"
#define AppExe "FlyyLink.exe"
#define Publish "..\publish\Aproid"

[Setup]
AppId={{2DEE6FF4-680A-4AC7-8BBD-B8C93D408B04}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Toneflix
AppPublisherURL=https://aproid.toneflix.com
AppUpdatesURL=https://aproid.toneflix.com/#download
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\{#AppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=..\publish
OutputBaseFilename=FlyyLink-Setup-{#AppVersion}
SetupIconFile=..\src\Aproid\Assets\Aproid.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
CloseApplications=force
RestartApplications=no

[Tasks]
Name: "startup"; Description: "Start FlyyLink when I sign in to Windows"

[Files]
Source: "{#Publish}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; A fresh copy of the app each time, so files a newer version dropped don't linger.
Type: filesandordirs; Name: "{app}\*"
; The Start menu shortcut from before the app was renamed.
Type: files; Name: "{userprograms}\Aproid.lnk"

[Icons]
Name: "{userprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; Comment: "Your Android phone on this PC"

[Run]
; Also runs after a silent update, which starts FlyyLink again.
Filename: "{app}\{#AppExe}"; Description: "Open FlyyLink"; Flags: nowait postinstall

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/im {#AppExe} /f"; Flags: runhidden; RunOnceId: "StopAproid"

[Registry]
; FlyyLink writes these itself on launch. Listed here so uninstalling removes them.
Root: HKCU; Subkey: "Software\Classes\*\shell\Aproid.Send"; Flags: uninsdeletekey dontcreatekey
Root: HKCU; Subkey: "Software\Classes\Aproid.tel"; Flags: uninsdeletekey dontcreatekey
Root: HKCU; Subkey: "Software\Aproid"; Flags: uninsdeletekey dontcreatekey
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: none; ValueName: "Aproid"; Flags: uninsdeletevalue dontcreatekey
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "Aproid"; Flags: uninsdeletevalue dontcreatekey
; Same value the app's "Start with Windows" setting writes.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Aproid"; ValueData: """{app}\{#AppExe}"" --background"; Tasks: startup
