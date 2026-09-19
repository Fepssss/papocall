; Script de instalacao profissional do PapoCall utilizando Inno Setup
#define MyAppName "PapoCall"
#define MyAppVersion "1.0.0k"
#define MyAppPublisher "PapoCall"
#define MyAppURL "https://papocall.vercel.app"
#define MyAppExeName "PapoCall.exe"
#define MyAppAssocName MyAppName + " File"
#define MyAppAssocExt ".papocall"
#define MyAppAssocKey StringChange(MyAppAssocName, " ", "") + MyAppAssocExt

[Setup]
; Identificador exclusivo da aplicacao (gerado via GUID)
AppId={{C4712F85-6EE6-4B39-8671-5DFEAC66023F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
ChangesAssociations=yes
DisableProgramGroupPage=yes
; Nao exige privilégios de administrador obrigatórios para permitir instalacao por usuario
PrivilegesRequired=lowest
OutputDir=..\public\downloads
OutputBaseFilename=PapoCall-Setup
SetupIconFile=..\flutter_app\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion=1.0.0.11
VersionInfoCompany=PapoCall
VersionInfoDescription=PapoCall v1.0.0k - Aplicativo Desktop Nativo
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
