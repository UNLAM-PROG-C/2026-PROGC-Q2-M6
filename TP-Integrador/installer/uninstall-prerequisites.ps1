[CmdletBinding()]
param(
  [switch]$RemoveDocker,
  [switch]$RemoveRadminVpn,
  [string]$LogPath = "$env:ProgramData\TowerDefense\uninstaller.log"
)

$ErrorActionPreference = "Stop"
$appDataPath = Join-Path $env:APPDATA "Godot\app_userdata\Tower Defense Cooperative"

function Write-Step {
  param([string]$Message)
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[$timestamp] $Message"
  Add-Content -Path $LogPath -Value "[$timestamp] $Message"
}

function Uninstall-WingetPackage {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$Name
  )

  Write-Step "Desinstalando $Name..."
  & winget uninstall --id $Id --exact --silent --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    throw "No se pudo desinstalar $Name mediante winget. Código: $LASTEXITCODE."
  }
  Write-Step "$Name desinstalado."
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
Write-Step "Iniciando desinstalación opcional de componentes."

Get-Process -Name "Godot_v4.3-stable_win64" -ErrorAction SilentlyContinue |
  ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

if (Test-Path -LiteralPath $appDataPath) {
  Remove-Item -LiteralPath $appDataPath -Recurse -Force
  Write-Step "Archivos de usuario del juego eliminados."
}

if (($RemoveDocker -or $RemoveRadminVpn) -and
    -not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "Windows Package Manager (winget) no está disponible."
}

if ($RemoveDocker) {
  Uninstall-WingetPackage -Id "Docker.DockerDesktop" -Name "Docker Desktop"
}

if ($RemoveRadminVpn) {
  Uninstall-WingetPackage -Id "Famatech.RadminVPN" -Name "Radmin VPN"
}

Write-Step "Desinstalación finalizada correctamente."
