#define AppName "Co-Tower Defense"
#define AppVersion "1.0.10"
#define AppPublisher "UNLAM-PROG-C"
#define GodotExeName "Godot_v4.3-stable_win64.exe"

[Setup]
AppId={{A4F5D4B5-9D8F-4F38-8D4B-0F5B7A43F0D8}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\CoTowerDefense
DefaultGroupName={#AppName}
OutputDir=output
OutputBaseFilename=TowerDefenseSetup-1.0.10
UninstallDisplayName={#AppName}
PrivilegesRequired=admin
WizardStyle=modern
Compression=lzma
SolidCompression=yes
DisableProgramGroupPage=yes

[Tasks]
Name: "docker"; Description: "Instalar Docker Desktop"; Flags: checkedonce
Name: "radminvpn"; Description: "Instalar Radmin VPN"; Flags: checkedonce

[Files]
Source: "install-prerequisites.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "uninstall-prerequisites.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "payload\Godot_v4.3-stable_win64.exe"; DestDir: "{app}\Godot"; Flags: ignoreversion
Source: "..\cliente_godot\*"; DestDir: "{app}\game"; Excludes: ".godot\*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\servidor\*"; DestDir: "{app}\servidor"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\docker-compose.yml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Dockerfile"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\requirements-dev.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\start-stack.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install-prerequisites.ps1"" {code:InstallArguments}"; StatusMsg: "Instalando y verificando los componentes seleccionados..."; Flags: waituntilterminated; Check: HasSelectedComponents

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall-prerequisites.ps1"" {code:UninstallArguments}"; Flags: waituntilterminated; RunOnceId: "RemoveOptionalComponents"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Icons]
Name: "{autodesktop}\Co-Tower Defense"; Filename: "{app}\Godot\{#GodotExeName}"; Parameters: "--path ""{app}\game"""; WorkingDir: "{app}"; Comment: "Co-Tower Defense"
Name: "{group}\Co-Tower Defense"; Filename: "{app}\Godot\{#GodotExeName}"; Parameters: "--path ""{app}\game"""; WorkingDir: "{app}"; Comment: "Co-Tower Defense"

[Code]
var
  RemoveDocker: Boolean;
  RemoveRadminVpn: Boolean;

function HasSelectedComponents: Boolean;
begin
  Result := WizardIsTaskSelected('docker') or WizardIsTaskSelected('radminvpn');
end;

function InstallArguments(Param: String): String;
begin
  Result := '';
  if WizardIsTaskSelected('docker') then
    Result := Result + '-InstallDocker ';
  if WizardIsTaskSelected('radminvpn') then
    Result := Result + '-InstallRadminVpn';
end;

function HasUninstallComponents: Boolean;
begin
  Result := RemoveDocker or RemoveRadminVpn;
end;

function UninstallArguments(Param: String): String;
begin
  Result := '';
  if RemoveDocker then
    Result := Result + '-RemoveDocker ';
  if RemoveRadminVpn then
    Result := Result + '-RemoveRadminVpn';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep <> usUninstall then
    exit;

  RemoveDocker := MsgBox(
    '¿Querés desinstalar Docker Desktop también? Esto puede eliminar entornos y datos de Docker.',
    mbConfirmation, MB_YESNO) = idYes;
  RemoveRadminVpn := MsgBox(
    '¿Querés desinstalar Radmin VPN también?',
    mbConfirmation, MB_YESNO) = idYes;
end;
