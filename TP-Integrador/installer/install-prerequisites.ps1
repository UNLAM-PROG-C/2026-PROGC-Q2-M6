[CmdletBinding()]
param(
  [switch]$InstallDocker,
  [switch]$InstallRadminVpn,
  [string]$LogPath = "$env:ProgramData\TowerDefense\installer.log"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$temporaryRoot = Join-Path $env:TEMP "tower-defense-installer"
New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null

function Write-Step {
  param([string]$Message)
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[$timestamp] $Message"
  Add-Content -Path $LogPath -Value "[$timestamp] $Message"
}

function Download-File {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$Destination
  )
  if ((Test-Path $Destination) -and ((Get-Item $Destination).Length -gt 1048576)) {
    Write-Step "Archivo en caché encontrado: $Destination"
    return
  }
  Write-Step "Descargando $Url..."
  $webClient = New-Object System.Net.WebClient
  $webClient.DownloadFile($Url, $Destination)
  Write-Step "Descarga completada."
}

function Ensure-Wsl {
  Write-Step "Verificando Windows Subsystem for Linux (WSL)..."
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & wsl.exe --status 2>$null 1>$null
    if ($LASTEXITCODE -eq 0) {
      Write-Step "WSL ya está instalado."
      return
    }
  } finally {
    $ErrorActionPreference = $previousPreference
  }

  Write-Step "WSL no está instalado. Iniciando instalación de WSL..."
  & wsl.exe --install --no-distribution
  if ($LASTEXITCODE -ne 0) {
    throw "No se pudo instalar WSL automáticamente. Ejecutá como administrador: wsl --install --no-distribution"
  }
  Write-Step "WSL fue instalado. Puede requerir reiniciar Windows antes de iniciar Docker Desktop."
}

function Try-InstallWingetPackage {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$Name
  )
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) {
    return $false
  }
  Write-Step "Instalando $Name mediante winget..."
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
      Write-Step "$Name instalado mediante winget."
      return $true
    }
  } catch {
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  return $false
}

function Get-RadminVpnPath {
  $candidates = @(
    "$env:ProgramFiles\Radmin VPN\RvRvpnGui.exe",
    "${env:ProgramFiles(x86)}\Radmin VPN\RvRvpnGui.exe",
    "$env:ProgramFiles\Radmin VPN\RvGuiStarter.exe",
    "${env:ProgramFiles(x86)}\Radmin VPN\RvGuiStarter.exe",
    "$env:ProgramFiles\Radmin VPN\RadminVPN.exe",
    "${env:ProgramFiles(x86)}\Radmin VPN\RadminVPN.exe",
    "$env:LOCALAPPDATA\Programs\Radmin VPN\RadminVPN.exe"
  )
  return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Install-RadminVpnDirect {
  $radminInstaller = Join-Path $temporaryRoot "Radmin_VPN.exe"
  Download-File `
    -Url "https://download.radmin-vpn.com/download/files/Radmin_VPN_2.1.4951.1.exe" `
    -Destination $radminInstaller
  Write-Step "Ejecutando instalador oficial de Radmin VPN..."
  Start-Process -FilePath $radminInstaller -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-" -Wait
}

function New-RadminShortcut {
  $path = $null
  $deadline = (Get-Date).AddSeconds(30)
  do {
    $path = Get-RadminVpnPath
    if (-not $path) {
      Start-Sleep -Seconds 2
    }
  } while (-not $path -and (Get-Date) -lt $deadline)
  if (-not $path) {
    Write-Step "Radmin VPN se instaló, pero todavía no se encontró su ejecutable para crear el acceso directo."
    return
  }
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut("$env:PUBLIC\Desktop\Radmin VPN.lnk")
  $shortcut.TargetPath = $path
  $shortcut.Arguments = "/show"
  $shortcut.WorkingDirectory = Split-Path -Parent $path
  $shortcut.Save()
  Write-Step "Acceso directo de Radmin VPN creado en el escritorio público."
}

function Get-DockerDesktopPath {
  $candidates = @(
    "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
    "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
    "$env:LOCALAPPDATA\Programs\Docker\Docker\Docker Desktop.exe",
    "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe"
  )
  return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Test-DockerDesktopInstalled {
  if (Get-DockerDesktopPath) {
    return $true
  }

  $appx = Get-AppxPackage -Name "*DockerDesktop*" -ErrorAction SilentlyContinue
  if ($appx) {
    return $true
  }

  $registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  $installed = Get-ItemProperty $registryPaths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*Docker Desktop*" }
  return [bool]$installed
}

function Install-DockerDesktopDirect {
  $dockerInstaller = Join-Path $temporaryRoot "DockerDesktopInstaller.exe"
  Download-File `
    -Url "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" `
    -Destination $dockerInstaller
  Write-Step "Ejecutando instalador oficial de Docker Desktop..."
  Start-Process -FilePath $dockerInstaller -ArgumentList "install", "--quiet" -Wait
}

function Ensure-FirewallRule {
  Write-Step "Configurando regla de Firewall de Windows (TCP 5000-5100)..."
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & netsh advfirewall firewall delete rule name="Tower Defense Local" 2>$null | Out-Null
    & netsh advfirewall firewall add rule name="Tower Defense Local" dir=in action=allow protocol=TCP localport=5000-5100 profile=any | Out-Null
    Write-Step "Regla de Firewall configurada."
  } finally {
    $ErrorActionPreference = $previousPreference
  }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
Write-Step "Iniciando configuración e instalación de componentes..."

Ensure-FirewallRule

if ($InstallRadminVpn) {
  if (Get-RadminVpnPath) {
    Write-Step "Radmin VPN ya está instalado. Se omite la instalación."
  } else {
    $ok = Try-InstallWingetPackage -Id "Famatech.RadminVPN" -Name "Radmin VPN"
    if (-not $ok -and -not (Get-RadminVpnPath)) {
      Install-RadminVpnDirect
    }
  }
  New-RadminShortcut
}

if ($InstallDocker) {
  Ensure-Wsl
  if (Test-DockerDesktopInstalled) {
    Write-Step "Docker Desktop ya está instalado. Se omite la instalación."
  } else {
    $ok = Try-InstallWingetPackage -Id "Docker.DockerDesktop" -Name "Docker Desktop"
    if (-not $ok -and -not (Test-DockerDesktopInstalled)) {
      Install-DockerDesktopDirect
    }
  }
}

Write-Step "Instalación finalizada correctamente."
