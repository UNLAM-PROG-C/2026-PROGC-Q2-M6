[CmdletBinding()]
param(
  [switch]$RemoveDocker,
  [Alias("RemoveRadmin")][switch]$RemoveRadminVpn,
  [string]$InstallRoot = ""
)

$ErrorActionPreference = "SilentlyContinue"
$rootDir = if ($InstallRoot) { $InstallRoot } else { $PSScriptRoot }

# 1. Detener procesos del juego si están abiertos
$gameProcesses = @(
  "CoTowerDefense",
  "TowerDefense",
  "Godot_v4.3-stable_win64",
  "Godot_v4.3-stable_win64_console"
)
foreach ($procName in $gameProcesses) {
  Get-Process -Name $procName -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
}

# 2. Detener y eliminar contenedores/datos de Docker del juego si el daemon está activo
try {
  $composeFile = Join-Path $rootDir "docker-compose.yml"
  if (-not (Test-Path $composeFile)) {
    $parentCompose = Join-Path (Split-Path -Parent $rootDir) "docker-compose.yml"
    if (Test-Path $parentCompose) {
      $composeFile = $parentCompose
    }
  }
  if ((Test-Path $composeFile) -and (Get-Command docker -ErrorAction SilentlyContinue)) {
    & docker version --format "{{.Server.Version}}" 2>$null 1>$null
    if ($LASTEXITCODE -eq 0) {
      Push-Location (Split-Path -Parent $composeFile)
      & docker compose down --rmi local --volumes --remove-orphans 2>$null 1>$null
      Pop-Location
    }
  }
} catch {
}

# 3. Eliminar reglas de Firewall
& netsh advfirewall firewall delete rule name="Tower Defense Local" 2>$null | Out-Null
& netsh advfirewall firewall delete rule name="Tower Defense Tailscale" 2>$null | Out-Null

# 4. Eliminar todos los datos de usuario, logs y temporales del juego
$dataPaths = @(
  (Join-Path $env:APPDATA "Godot\app_userdata\Tower Defense Cooperative"),
  (Join-Path $env:APPDATA "Godot\app_userdata\Co-Tower Defense"),
  (Join-Path $env:APPDATA "Godot\app_userdata\CoTowerDefense"),
  (Join-Path $env:LOCALAPPDATA "Godot\app_userdata\Tower Defense Cooperative"),
  (Join-Path $env:LOCALAPPDATA "Godot\app_userdata\Co-Tower Defense"),
  (Join-Path $env:TEMP "tower-defense-installer"),
  "$env:ProgramData\TowerDefense"
)
foreach ($path in $dataPaths) {
  if ($path -and (Test-Path -LiteralPath $path)) {
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# 5. Eliminar accesos directos del juego en el escritorio
$desktopFolders = @(
  [Environment]::GetFolderPath("CommonDesktopDirectory"),
  [Environment]::GetFolderPath("Desktop")
)
foreach ($desk in $desktopFolders) {
  if ($desk) {
    foreach ($lnk in @("Co-Tower Defense.lnk", "Tower Defense Cooperative.lnk")) {
      $shortcut = Join-Path $desk $lnk
      if (Test-Path -LiteralPath $shortcut) {
        Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
      }
    }
  }
}

function Uninstall-Application {
  param(
    [Parameter(Mandatory = $true)][string]$DisplayName,
    [Parameter(Mandatory = $true)][string]$PackageId,
    [string]$SilentArgs = ""
  )

  $regKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  $installed = Get-ItemProperty $regKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and ($_.DisplayName -like "*$DisplayName*") } |
    Select-Object -First 1

  if ($installed) {
    if ($installed.QuietUninstallString) {
      Start-Process "cmd.exe" -ArgumentList "/c $($installed.QuietUninstallString)" -Wait -WindowStyle Hidden
      return
    }
    if ($installed.UninstallString) {
      $cmd = $installed.UninstallString
      if ($SilentArgs -and ($cmd -notmatch [regex]::Escape($SilentArgs))) {
        $cmd = "$cmd $SilentArgs"
      }
      Start-Process "cmd.exe" -ArgumentList "/c $cmd" -Wait -WindowStyle Hidden
      return
    }
  }

  $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
  if ($winget) {
    Start-Process $winget.Source -ArgumentList "uninstall --id $PackageId --exact --silent --accept-source-agreements" -Wait -WindowStyle Hidden
  }
}

# 6. Desinstalación opcional de Docker Desktop y Radmin VPN
if ($RemoveDocker) {
  Get-Process -Name "Docker Desktop", "com.docker.backend", "com.docker.service" -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
  Uninstall-Application -DisplayName "Docker Desktop" -PackageId "Docker.DockerDesktop" -SilentArgs "uninstall --quiet"
}

if ($RemoveRadminVpn) {
  Get-Process -Name "RvRvpnGui", "RvGuiStarter", "RadminVPN" -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
  Uninstall-Application -DisplayName "Radmin VPN" -PackageId "Famatech.RadminVPN" -SilentArgs "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
  $radminShortcut = "$env:PUBLIC\Desktop\Radmin VPN.lnk"
  if (Test-Path -LiteralPath $radminShortcut) {
    Remove-Item -LiteralPath $radminShortcut -Force -ErrorAction SilentlyContinue
  }
}
