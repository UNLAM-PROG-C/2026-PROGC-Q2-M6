param(
  [Parameter(Mandatory = $true)]
  [string]$InstallRoot
)

$ErrorActionPreference = "Stop"
$temporaryRoot = Join-Path $env:TEMP "tower-defense-installer"
New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
$step = 0

function Write-Step([string]$Message) {
  $script:step++
  Write-Host ""
  Write-Host "[$script:step/5] $Message" -ForegroundColor Cyan
}

function Download-File([string]$Url, [string]$Destination) {
  Write-Host "  Descargando desde el sitio oficial..."
  Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
  Write-Host "  Descarga completada." -ForegroundColor Green
}

Write-Host "Tower Defense Cooperative - configurando dependencias" -ForegroundColor Green
Write-Host "No cierres esta ventana hasta que aparezca el mensaje final."

Write-Step "Comprobando e instalando Godot 4.3"
$godotPath = Join-Path $InstallRoot "Godot\Godot_v4.3-stable_win64.exe"
if (-not (Test-Path $godotPath)) {
  $godotDir = Split-Path -Parent $godotPath
  New-Item -ItemType Directory -Force -Path $godotDir | Out-Null
  $godotZip = Join-Path $temporaryRoot "godot.zip"
  Download-File `
    "https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_win64.exe.zip" `
    $godotZip
  Expand-Archive -Path $godotZip -DestinationPath $godotDir -Force
  Write-Host "  Godot instalado." -ForegroundColor Green
} else {
  Write-Host "  Godot ya estaba instalado." -ForegroundColor Yellow
}

$gamePath = Join-Path $InstallRoot "TowerDefense.exe"
Copy-Item $godotPath $gamePath -Force
Write-Host "  Ejecutable del juego preparado." -ForegroundColor Green

Write-Step "Comprobando e instalando Tailscale"
$tailscalePath = Join-Path $env:ProgramFiles "Tailscale\tailscale.exe"
if (-not (Test-Path $tailscalePath)) {
  $tailscaleInstaller = Join-Path $temporaryRoot "tailscale-setup.exe"
  Download-File `
    "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe" `
    $tailscaleInstaller
  Start-Process $tailscaleInstaller -ArgumentList "/S" -Wait
  Write-Host "  Tailscale instalado." -ForegroundColor Green
} else {
  Write-Host "  Tailscale ya estaba instalado." -ForegroundColor Yellow
}

Write-Step "Comprobando Docker Desktop"
if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
  $dockerInstaller = Join-Path $temporaryRoot "DockerDesktopInstaller.exe"
  Download-File `
    "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" `
    $dockerInstaller
  Start-Process $dockerInstaller -ArgumentList "install", "--quiet" -Wait
  Write-Host "  Docker Desktop fue instalado." -ForegroundColor Green
} else {
  Write-Host "  Docker Desktop ya estaba instalado." -ForegroundColor Yellow
}

Write-Step "Configurando el Firewall de Windows"
if ($null -eq (Get-NetFirewallRule -DisplayName "Tower Defense Tailscale" `
    -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule `
    -DisplayName "Tower Defense Tailscale" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 5001-5100 `
    -Action Allow `
    -Profile Private | Out-Null
  Write-Host "  Regla TCP 5001-5100 creada." -ForegroundColor Green
} else {
  Write-Host "  La regla del Firewall ya existía." -ForegroundColor Yellow
}

Write-Step "Creando acceso directo del juego"
$desktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
$shortcutPath = Join-Path $desktop "Tower Defense Cooperative.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $gamePath
$shortcut.Arguments = "--path `"$InstallRoot\cliente_godot`""
$shortcut.WorkingDirectory = $InstallRoot
$shortcut.Save()

Write-Host ""
Write-Host "Configuración finalizada correctamente." -ForegroundColor Green
Write-Host "Tailscale requiere inicio de sesión manual y la misma tailnet para todos."
