; Script de instalacao profissional do PapoCall utilizando Inno Setup
#define MyAppName "PapoCall"
#define MyAppVersion "1.0.0c"
#define MyAppPublisher "PapoCall"
#define MyAppURL "https://papocall.vercel.app"
#define MyAppExeName "PapoCall.exe"

[Setup]
; Identificador exclusivo da aplicacao
AppId={{E58E6629-8B94-4F58-9C21-6D59A111F3E2}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DisableProgramGroupPage=yes
; Instalacao por usuario (sem necessidade de permissoes de administrador / sem popup UAC)
PrivilegesRequired=lowest
OutputDir=..\public\downloads
OutputBaseFilename=PapoCall-Setup
SetupIconFile=..\assets\icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion=1.0.0.3
VersionInfoCompany=PapoCall
VersionInfoDescription=PapoCall v1.0.0c - Aplicativo Desktop Nativo
VersionInfoCopyright=Copyright (C) 2026 PapoCall

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startupicon"; Description: "Iniciar o PapoCall automaticamente com o Windows"; GroupDescription: "Outras opções:"; Flags: unchecked

[Files]
; Flutter Release Binaries (100% Nativo Windows - Zero WebView2 / Zero Browser Engine)
Source: "..\flutter_app\build\windows\x64\runner\Release\papocall.exe"; DestName: "{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\flutter_app\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\flutter_app\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\assets\icon.ico"; DestDir: "{app}\assets"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\assets\icon.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\assets\icon.ico"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\assets\icon.ico"; Tasks: startupicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
