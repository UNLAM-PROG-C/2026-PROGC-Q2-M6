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
OutputBaseFilename=TowerDefenseSetup
UninstallDisplayName={#AppName}
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
DisableProgramGroupPage=yes

[Tasks]
Name: "docker"; Description: "Instalar Docker Desktop (necesario para crear partidas)"; Flags: checkedonce
Name: "radminvpn"; Description: "Instalar Radmin VPN (necesario para jugar en red con amigos)"; Flags: checkedonce

[Files]
Source: "install-prerequisites.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "uninstall-prerequisites.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "output\DesinstalarTowerDefense.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CoTowerDefense.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CoTowerDefense.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "payload\Godot_v4.3-stable_win64.exe"; DestDir: "{app}\Godot"; Flags: ignoreversion
Source: "..\cliente_godot\*"; DestDir: "{app}\game"; Excludes: ".godot\*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\servidor\*"; DestDir: "{app}\servidor"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\docker-compose.yml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Dockerfile"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\requirements-dev.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\start-stack.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install-prerequisites.ps1"" {code:InstallArguments}"; \
  StatusMsg: "Configurando el juego e instalando los componentes seleccionados..."; \
  Flags: waituntilterminated

[Icons]
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\CoTowerDefense.exe"; WorkingDir: "{app}"; Comment: "{#AppName}"
Name: "{group}\{#AppName}"; Filename: "{app}\CoTowerDefense.exe"; WorkingDir: "{app}"; Comment: "{#AppName}"
Name: "{group}\Desinstalar {#AppName}"; Filename: "{app}\DesinstalarTowerDefense.exe"; WorkingDir: "{app}"; Comment: "Desinstalar {#AppName}"

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\Godot\app_userdata\Tower Defense Cooperative"
Type: filesandordirs; Name: "{userappdata}\Godot\app_userdata\Co-Tower Defense"
Type: filesandordirs; Name: "{commonappdata}\TowerDefense"
Type: filesandordirs; Name: "{app}"

[Code]
function InstallArguments(Param: String): String;
begin
  Result := '';
  if WizardIsTaskSelected('docker') then
    Result := Result + '-InstallDocker ';
  if WizardIsTaskSelected('radminvpn') then
    Result := Result + '-InstallRadminVpn';
end;

function InitializeUninstall(): Boolean;
var
  PsParams: String;
  ScriptPath: String;
  ResultCode: Integer;
begin
  Result := True;
  PsParams := ' -InstallRoot "' + ExpandConstant('{app}') + '"';

  if not UninstallSilent then
  begin
    if MsgBox('¿También querés desinstalar Docker Desktop?', mbConfirmation, MB_YESNO) = idYes then
      PsParams := PsParams + ' -RemoveDocker';

    if MsgBox('¿También querés desinstalar Radmin VPN?', mbConfirmation, MB_YESNO) = idYes then
      PsParams := PsParams + ' -RemoveRadminVpn';
  end;

  ScriptPath := ExpandConstant('{app}\uninstall-prerequisites.ps1');
  if FileExists(ScriptPath) then
  begin
    Exec(
      'powershell.exe',
      '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"' + PsParams,
      ExpandConstant('{app}'),
      SW_HIDE,
      ewWaitUntilTerminated,
      ResultCode
    );
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DelTree(ExpandConstant('{userappdata}\Godot\app_userdata\Tower Defense Cooperative'), True, True, True);
    DelTree(ExpandConstant('{userappdata}\Godot\app_userdata\Co-Tower Defense'), True, True, True);
    DelTree(ExpandConstant('{commonappdata}\TowerDefense'), True, True, True);
    DelTree(ExpandConstant('{app}'), True, True, True);
  end;
end;
