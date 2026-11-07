param(
  [string]$InstallRoot = "$env:ProgramFiles\TowerDefenseCooperative"
)

$ErrorActionPreference = "Stop"

function Test-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]$identity
  return $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
  )
}

function Download-File([string]$Url, [string]$Destination) {
  Write-Host "Descargando $Url"
  Invoke-WebRequest -Uri $Url -OutFile $Destination
}

function Add-DesktopShortcut([string]$Name, [string]$Target, [string]$Arguments) {
  $desktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
  $shortcutPath = Join-Path $desktop "$Name.lnk"
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $Target
  $shortcut.Arguments = $Arguments
  $shortcut.WorkingDirectory = $InstallRoot
  $shortcut.Save()
}

if (-not (Test-Administrator)) {
  throw "Ejecutá este instalador como Administrador."
}

$temporaryRoot = Join-Path $env:TEMP "tower-defense-installer"
New-Item -ItemType Directory -Force -Path $InstallRoot, $temporaryRoot | Out-Null

$sourceRoot = Split-Path -Parent $PSScriptRoot
Copy-Item "$sourceRoot\cliente_godot" $InstallRoot -Recurse -Force
Copy-Item "$sourceRoot\servidor" $InstallRoot -Recurse -Force
Copy-Item "$sourceRoot\docker-compose.yml" $InstallRoot -Force
Copy-Item "$sourceRoot\Dockerfile" $InstallRoot -Force
Copy-Item "$sourceRoot\requirements-dev.txt" $InstallRoot -Force
Copy-Item "$sourceRoot\start-server.ps1" $InstallRoot -Force

$godotPath = Join-Path $InstallRoot "Godot\Godot_v4.3-stable_win64.exe"
if (-not (Test-Path $godotPath)) {
  $godotZip = Join-Path $temporaryRoot "godot.zip"
  $godotDir = Split-Path -Parent $godotPath
  New-Item -ItemType Directory -Force -Path $godotDir | Out-Null
  Download-File `
    "https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_win64.exe.zip" `
    $godotZip
  Expand-Archive -Path $godotZip -DestinationPath $godotDir -Force
}
$gamePath = Join-Path $InstallRoot "TowerDefense.exe"
Copy-Item $godotPath $gamePath -Force

$tailscalePath = Join-Path $env:ProgramFiles "Tailscale\tailscale.exe"
if (-not (Test-Path $tailscalePath)) {
  $tailscaleInstaller = Join-Path $temporaryRoot "tailscale-setup.exe"
  Download-File `
    "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe" `
    $tailscaleInstaller
  Start-Process $tailscaleInstaller -ArgumentList "/S" -Wait
}

$dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
if ($null -eq $dockerCommand) {
  $answer = Read-Host "Docker Desktop no está instalado. ¿Descargarlo e instalarlo ahora? (S/N)"
  if ($answer -notmatch "^[sS]$") {
    throw "Docker Desktop es necesario para crear partidas."
  }
  $dockerInstaller = Join-Path $temporaryRoot "DockerDesktopInstaller.exe"
  Download-File `
    "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" `
    $dockerInstaller
  Start-Process $dockerInstaller -ArgumentList "install", "--quiet" -Wait
  Write-Warning "Docker Desktop puede requerir reiniciar Windows antes de crear una partida."
}

$firewallRule = Get-NetFirewallRule -DisplayName "Tower Defense Tailscale" `
  -ErrorAction SilentlyContinue
if ($null -eq $firewallRule) {
  New-NetFirewallRule `
    -DisplayName "Tower Defense Tailscale" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 5001-5100 `
    -Action Allow `
    -Profile Private | Out-Null
}

Add-DesktopShortcut `
  "Tower Defense Cooperative" `
  $gamePath `
  "--path `"$InstallRoot\cliente_godot`""

Write-Host ""
Write-Host "Instalación finalizada en $InstallRoot"
Write-Host "Abrí Tailscale, iniciá sesión y uní las computadoras a la misma tailnet."
Write-Host "Después usá el botón Crear partida dentro del juego."
