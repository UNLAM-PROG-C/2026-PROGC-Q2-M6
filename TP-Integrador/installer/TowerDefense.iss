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

[Tasks]
Name: "installdocker"; Description: "Instalar Docker Desktop (necesario únicamente para crear partidas)"; Flags: checkedonce
Name: "installradmin"; Description: "Instalar Radmin VPN (para jugar por Internet con amigos sin configurar el router)"; Flags: checkedonce

[Files]
Source: "..\cliente_godot\*"; DestDir: "{app}\cliente_godot"; Flags: recursesubdirs ignoreversion
Source: "..\servidor\*"; DestDir: "{app}\servidor"; Flags: recursesubdirs ignoreversion
Source: "..\docker-compose.yml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Dockerfile"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\requirements-dev.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\start-server.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\tools\*"; DestDir: "{app}\tools"; Flags: recursesubdirs ignoreversion
Source: "install-dependencies.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "uninstall-dependencies.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "output\DesinstalarTowerDefense.exe"; DestDir: "{app}\installer"; Flags: ignoreversion

[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\install-dependencies.ps1"" -InstallRoot ""{app}"" {code:DependencyParameters}"; \
  StatusMsg: "Descargando e instalando dependencias (Godot, Radmin VPN)..."; \
  Flags: waituntilterminated

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\TowerDefense.exe"; \
  Parameters: "--path ""{app}\cliente_godot"""
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\TowerDefense.exe"; \
  Parameters: "--path ""{app}\cliente_godot"""
Name: "{group}\Desinstalar {#AppName}"; Filename: "{app}\installer\DesinstalarTowerDefense.exe"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\Godot"
Type: filesandordirs; Name: "{app}\cliente_godot"
Type: files; Name: "{app}\TowerDefense.exe"
Type: filesandordirs; Name: "{app}"

[Code]
function DependencyParameters(Param: String): String;
begin
  Result := '';
  if WizardIsTaskSelected('installdocker') then
    Result := Result + ' -InstallDocker';
  if WizardIsTaskSelected('installradmin') then
    Result := Result + ' -InstallRadmin';
end;

function InitializeUninstall(): Boolean;
var
  ManifestPath: String;
  DockerWasInstalled: Boolean;
  RadminWasInstalled: Boolean;
  RemoveDocker: Integer;
  RemoveRadmin: Integer;
  PsParams: String;
  ResultCode: Integer;
  ScriptPath: String;
begin
  Result := True;

  if not UninstallSilent then
  begin
    ManifestPath := ExpandConstant('{app}\installer\installed-manifest.ini');
    DockerWasInstalled := GetIniBool('InstalledByGame', 'Docker', False, ManifestPath);
    RadminWasInstalled := GetIniBool('InstalledByGame', 'Radmin', False, ManifestPath);

    PsParams := '';

    if DockerWasInstalled then
    begin
      RemoveDocker := MsgBox('¿También querés desinstalar Docker Desktop?', mbConfirmation, MB_YESNO);
      if RemoveDocker = idYes then
        PsParams := PsParams + ' -RemoveDocker';
    end;

    if RadminWasInstalled then
    begin
      RemoveRadmin := MsgBox('¿También querés desinstalar Radmin VPN?', mbConfirmation, MB_YESNO);
      if RemoveRadmin = idYes then
        PsParams := PsParams + ' -RemoveRadmin';
    end;

    ScriptPath := ExpandConstant('{app}\installer\uninstall-dependencies.ps1');
    if FileExists(ScriptPath) then
    begin
      Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"' + PsParams, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end
    else
    begin
      Exec('cmd.exe', '/c netsh advfirewall firewall delete rule name="Tower Defense Local"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DelTree(ExpandConstant('{app}'), True, True, True);
  end;
end;
