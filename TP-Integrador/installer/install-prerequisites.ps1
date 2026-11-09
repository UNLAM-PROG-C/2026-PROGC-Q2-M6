[CmdletBinding()]
param(
  [switch]$InstallDocker,
  [switch]$InstallRadminVpn,
  [string]$LogPath = "$env:ProgramData\TowerDefense\installer.log"
)

$ErrorActionPreference = "Stop"

function Ensure-Wsl {
  Write-Step "Verificando Windows Subsystem for Linux (WSL)..."
  $statusOutput = & wsl.exe --status 2>&1
  if ($LASTEXITCODE -eq 0) {
    Write-Step "WSL ya está instalado."
    return
  }

  Write-Step "WSL no está instalado. Iniciando instalación de WSL..."
  & wsl.exe --install --no-distribution
  if ($LASTEXITCODE -ne 0) {
    throw "No se pudo instalar WSL automáticamente. Ejecutá como administrador: wsl --install --no-distribution"
  }
  throw "WSL fue instalado, pero Windows debe reiniciarse antes de usar Docker Desktop. Reiniciá y ejecutá nuevamente el instalador."
}

function Write-Step {
  param([string]$Message)
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[$timestamp] $Message"
  Add-Content -Path $LogPath -Value "[$timestamp] $Message"
}

function Install-WingetPackage {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$Name
  )

  Write-Step "Instalando $Name..."
  & winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    throw "No se pudo instalar $Name mediante winget. Código: $LASTEXITCODE."
  }
  Write-Step "$Name instalado."
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

function Start-And-Verify-Docker {
  Write-Step "Verificando Docker Desktop..."
  & docker info *> $null
  if ($LASTEXITCODE -ne 0) {
    $dockerDesktop = Get-DockerDesktopPath
    if ($dockerDesktop) {
      Write-Step "Iniciando Docker Desktop..."
      Start-Process -FilePath $dockerDesktop
    } else {
      $appx = Get-AppxPackage -Name "*DockerDesktop*" -ErrorAction SilentlyContinue |
        Select-Object -First 1
      if ($appx) {
        Write-Step "Iniciando Docker Desktop desde Microsoft Store..."
        Start-Process "shell:AppsFolder\$($appx.PackageFamilyName)!App"
      } else {
        throw "Docker Desktop está instalado, pero no se pudo localizar para iniciarlo."
      }
    }
  }

  $deadline = (Get-Date).AddSeconds(120)
  do {
    Start-Sleep -Seconds 2
    & docker info *> $null
  } while ($LASTEXITCODE -ne 0 -and (Get-Date) -lt $deadline)
  if ($LASTEXITCODE -ne 0) {
    throw "Docker Desktop se instaló, pero el daemon no inició dentro de 120 segundos."
  }
  & docker compose version *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "Docker Compose no está disponible después de instalar Docker Desktop."
  }
  Write-Step "Docker Desktop y Compose están operativos."
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
Write-Step "Iniciando instalación de requisitos."

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "Windows Package Manager (winget) no está disponible."
}

if ($InstallDocker) {
  Ensure-Wsl
  if (Test-DockerDesktopInstalled) {
    Write-Step "Docker Desktop ya está instalado. Se omite la instalación."
  } else {
    Install-WingetPackage -Id "Docker.DockerDesktop" -Name "Docker Desktop"
  }
  Start-And-Verify-Docker
}

if ($InstallRadminVpn) {
  $radminInstalled = Get-RadminVpnPath
  if ($radminInstalled) {
    Write-Step "Radmin VPN ya está instalado. Se omite la instalación."
  } else {
    Install-WingetPackage -Id "Famatech.RadminVPN" -Name "Radmin VPN"
  }
  New-RadminShortcut
}

Write-Step "Instalación finalizada correctamente."
