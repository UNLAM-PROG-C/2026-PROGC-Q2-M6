param(
  [Parameter(Mandatory = $true)]
  [string]$InstallRoot,
  [switch]$InstallDocker,
  [switch]$InstallRadmin
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'
$temporaryRoot = Join-Path $env:TEMP "tower-defense-installer"
New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
$step = 0

function Write-Step([string]$Message) {
  $script:step++
  Write-Host ""
  Write-Host "[$script:step/5] $Message" -ForegroundColor Cyan
}

function Download-File([string]$Url, [string]$Destination) {
  if ((Test-Path $Destination) -and ((Get-Item $Destination).Length -gt 1048576)) {
    Write-Host "  Archivo en caché listo." -ForegroundColor Yellow
    return
  }
  Write-Host "  Descargando desde el sitio oficial..."
  $webClient = New-Object System.Net.WebClient
  $webClient.DownloadFile($Url, $Destination)
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

function Get-RadminEntry {
  Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", `
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*Radmin VPN*" } |
    Select-Object -First 1
}

$radminInstalledByGame = $false
Write-Step "Comprobando e instalando Radmin VPN"
if ($null -ne (Get-RadminEntry)) {
  Write-Host "  Radmin VPN ya estaba instalado." -ForegroundColor Yellow
} elseif ($InstallRadmin) {
  $radminInstaller = Join-Path $temporaryRoot "Radmin_VPN.exe"
  Download-File `
    "https://download.radmin-vpn.com/download/files/Radmin_VPN_2.1.4951.1.exe" `
    $radminInstaller
  Start-Process $radminInstaller -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-" -Wait
  if ($null -ne (Get-RadminEntry)) {
    Write-Host "  Radmin VPN instalado." -ForegroundColor Green
    $radminInstalledByGame = $true
  } else {
    Write-Host "  No se pudo instalar Radmin VPN automáticamente." -ForegroundColor Red
    Write-Host "  Abriendo el instalador para que lo completes a mano..." -ForegroundColor Yellow
    Start-Process $radminInstaller -Wait
    $radminInstalledByGame = $null -ne (Get-RadminEntry)
  }
} else {
  Write-Host "  Radmin VPN omitido por selección del usuario." -ForegroundColor Yellow
}

$dockerInstalledByGame = $false

Write-Step "Comprobando Docker Desktop"
if ($InstallDocker -and $null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
  $dockerInstaller = Join-Path $temporaryRoot "DockerDesktopInstaller.exe"
  Download-File `
    "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" `
    $dockerInstaller
  Start-Process $dockerInstaller -ArgumentList "install", "--quiet" -Wait
  Write-Host "  Docker Desktop fue instalado." -ForegroundColor Green
  $dockerInstalledByGame = $true
} elseif ($null -ne (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Host "  Docker Desktop ya estaba instalado." -ForegroundColor Yellow
} else {
  Write-Host "  Docker omitido por selección del usuario." -ForegroundColor Yellow
}

$manifestDir = Join-Path $InstallRoot "installer"
New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
$manifestPath = Join-Path $manifestDir "installed-manifest.ini"
Set-Content -Path $manifestPath -Value @"
[InstalledByGame]
Docker=$($dockerInstalledByGame.ToString().ToLower())
Radmin=$($radminInstalledByGame.ToString().ToLower())
"@

Write-Step "Configurando el Firewall de Windows"
$existingRule = & netsh advfirewall firewall show rule name="Tower Defense Local" 2>$null
if ($LASTEXITCODE -ne 0 -or -not ($existingRule -match "Tower Defense Local")) {
  & netsh advfirewall firewall add rule name="Tower Defense Local" dir=in action=allow protocol=TCP localport=5001-5100 profile=any | Out-Null
  Write-Host "  Regla TCP 5001-5100 creada en el Firewall." -ForegroundColor Green
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
Write-Host "Docker solo se necesita en la computadora que presione 'Crear partida'."
Write-Host ""
Write-Host "PARA JUGAR (se hace una sola vez):" -ForegroundColor Cyan
Write-Host "  1. En Radmin VPN: Red > Unirse a una red existente"
Write-Host "  2. Nombre de red: TowerDefense-UNLAM" -ForegroundColor White
Write-Host "  3. Clave:         1234" -ForegroundColor White

$radminEntry = Get-RadminEntry
if ($null -ne $radminEntry -and $radminEntry.InstallLocation) {
  $radminApp = Get-ChildItem -Path $radminEntry.InstallLocation -Filter "RvRvpnGui.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $radminApp) {
    $radminApp = Get-ChildItem -Path $radminEntry.InstallLocation -Filter "*.exe" -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notlike "unins*" -and $_.Name -like "*Gui*" } | Select-Object -First 1
  }
  if ($null -ne $radminApp) {
    Start-Process $radminApp.FullName
  }
}

Write-Host ""
Write-Host "Completando instalación..." -ForegroundColor Cyan
Start-Sleep -Seconds 2
