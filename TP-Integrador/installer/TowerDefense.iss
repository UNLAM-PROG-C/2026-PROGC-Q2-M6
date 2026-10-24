#define AppName "Tower Defense Cooperative"
#define AppVersion "1.0.0"
#define Publisher "UNLAM-PROG-C"
#define InstallDirName "TowerDefenseCooperative"

[Setup]
AppId={{9D7C3C18-36F3-4C89-8E99-5AAB2A1BD8B1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#Publisher}
DefaultDirName={autopf}\{#InstallDirName}
DefaultGroupName={#AppName}
OutputDir=output
OutputBaseFilename=TowerDefenseSetup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern
UninstallDisplayName={#AppName}

[Files]
Source: "..\cliente_godot\*"; DestDir: "{app}\cliente_godot"; Flags: recursesubdirs ignoreversion
Source: "..\servidor\*"; DestDir: "{app}\servidor"; Flags: recursesubdirs ignoreversion
Source: "..\docker-compose.yml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Dockerfile"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\requirements-dev.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\start-server.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "install-dependencies.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion

[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\install-dependencies.ps1"" -InstallRoot ""{app}"""; \
  StatusMsg: "Descargando e instalando Godot, Tailscale y Docker Desktop..."; \
  Flags: waituntilterminated

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\TowerDefense.exe"; \
  Parameters: "--path ""{app}\cliente_godot"""
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\TowerDefense.exe"; \
  Parameters: "--path ""{app}\cliente_godot"""
