[CmdletBinding()]
param(
  [int]$Port = 5000,
  [Parameter(Mandatory = $true)][string]$StatusPath,
  [switch]$OnlyVpn,
  [switch]$SkipVpn
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$statusDirectory = Split-Path -Parent $StatusPath

function Test-Wsl {
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & wsl.exe --status 2>$null 1>$null
    return $LASTEXITCODE -eq 0
  } finally {
    $ErrorActionPreference = $previousPreference
  }
}

function Set-Status {
  param(
    [string]$Stage,
    [string]$State,
    [string]$Message
  )

  $status = @{
    stage = $Stage
    state = $State
    message = $Message
    timestamp = (Get-Date).ToString("o")
  } | ConvertTo-Json -Compress
  New-Item -ItemType Directory -Force -Path $statusDirectory | Out-Null
  $temporaryPath = "$StatusPath.$PID.tmp"
  [System.IO.File]::WriteAllText($temporaryPath, $status, [System.Text.UTF8Encoding]::new($false))
  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    try {
      Move-Item -LiteralPath $temporaryPath -Destination $StatusPath -Force
      return
    } catch {
      if ($attempt -eq 19) {
        throw "No se pudo actualizar el estado de inicio porque el archivo está bloqueado: $StatusPath. Detalle: $($_.Exception.Message)"
      }
      Start-Sleep -Milliseconds 100
    }
  }
}

function Find-RadminVpn {
  $candidates = @(
    "$env:ProgramFiles\Radmin VPN\RvRvpnGui.exe",
    "${env:ProgramFiles(x86)}\Radmin VPN\RvRvpnGui.exe",
    "$env:ProgramFiles\Radmin VPN\RvGuiStarter.exe",
    "${env:ProgramFiles(x86)}\Radmin VPN\RvGuiStarter.exe",
    "$env:ProgramFiles\Radmin VPN\RadminVPN.exe",
    "${env:ProgramFiles(x86)}\Radmin VPN\RadminVPN.exe"
  )
  $path = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($path) {
    return $path
  }
  $installed = Get-ItemProperty @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  ) -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*Radmin VPN*" } |
    Select-Object -First 1
  return $installed.InstallLocation | ForEach-Object {
    $installDirectory = $_
    @("RvRvpnGui.exe", "RvGuiStarter.exe", "RadminVPN.exe") | ForEach-Object {
      Join-Path $installDirectory $_
    }
  } | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Test-RadminPowerOn {
  $reg = Get-ItemProperty @(
    "HKLM:\SOFTWARE\WOW6432Node\Famatech\RadminVPN\1.0",
    "HKLM:\SOFTWARE\Famatech\RadminVPN\1.0"
  ) -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($reg -and ($reg.PSObject.Properties.Name -contains "PowerOn")) {
    return ($reg.PowerOn -eq 1)
  }
  return $false
}

function Initialize-Win32Window {
  try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Window {
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue
  } catch {
  }
}

function Show-RadminVpnWindow {
  $path = Find-RadminVpn
  if (-not $path) {
    throw "Error en Radmin VPN: No está instalado. Instalalo y reintentá."
  }
  Initialize-Win32Window
  Start-Process -FilePath $path -ArgumentList "/show" -WindowStyle Normal
  Start-Sleep -Milliseconds 1000
  try {
    $procs = Get-Process -Name "RvRvpnGui", "RvGuiStarter", "RadminVPN" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
      if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32Window]::ShowWindowAsync($p.MainWindowHandle, 9) | Out-Null
        [Win32Window]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
      }
    }
  } catch {
  }
}

function Hide-DockerDesktopWindows {
  Initialize-Win32Window
  try {
    $procs = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
      if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32Window]::ShowWindowAsync($p.MainWindowHandle, 0) | Out-Null
      }
    }
  } catch {
  }
}

function Disable-DockerStartupUi {
  foreach ($fileName in @("settings-store.json", "settings.json")) {
    $settingsPath = Join-Path $env:APPDATA "Docker\$fileName"
    if (Test-Path $settingsPath) {
      try {
        $raw = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
        $json = $raw | ConvertFrom-Json
        if ($null -ne $json) {
          $json | Add-Member -NotePropertyName "OpenUIOnStartupDisabled" -NotePropertyValue $true -Force
          $updated = $json | ConvertTo-Json -Depth 10
          [System.IO.File]::WriteAllText($settingsPath, $updated, [System.Text.UTF8Encoding]::new($false))
        }
      } catch {
      }
    }
  }
}

function Ensure-RadminVpn {
  Set-Status "vpn" "running" "Verificando Radmin VPN..."
  $vpnService = Get-Service -Name "RvControlSvc" -ErrorAction SilentlyContinue
  if (-not $vpnService) {
    throw "Error en Radmin VPN: No se encontró el servicio RvControlSvc. Reinstalá Radmin VPN."
  }
  if ($vpnService.Status -ne "Running") {
    Set-Status "vpn" "running" "Iniciando servicio de Radmin VPN..."
    try {
      Start-Service -Name "RvControlSvc" -ErrorAction Stop
      $vpnService.WaitForStatus("Running", [TimeSpan]::FromSeconds(15))
    } catch {
      throw "Error en Radmin VPN: No se pudo iniciar el servicio RvControlSvc. Detalle: $($_.Exception.Message)"
    }
  }

  $process = Get-Process -Name "RvRvpnGui", "RvGuiStarter", "RadminVPN" -ErrorAction SilentlyContinue
  $wasRunning = [bool]$process
  $isPoweredOn = Test-RadminPowerOn

  if (-not $wasRunning -or -not $isPoweredOn) {
    Set-Status "vpn" "running" "Abriendo Radmin VPN en pantalla..."
    Show-RadminVpnWindow
  }

  if (-not (Test-RadminPowerOn)) {
    Set-Status "vpn" "vpn_needs_activation" "Radmin VPN está desconectado. Por favor conecte el VPN y vuelva a intentar."
    return $false
  }

  $vpnIp = Get-RadminVpnIp
  Set-Status "vpn" "vpn_ready" "Radmin VPN está conectado."
  return $true
}

function Ensure-Docker {
  Set-Status "docker" "running" "Verificando Docker Desktop..."
  $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
  if (-not $dockerCommand) {
    throw "Error en Docker: Docker no está instalado. Ejecutá el instalador y seleccioná Docker Desktop."
  }

  $daemonReady = Test-DockerDaemon
  $startedByScript = $false
  if (-not $daemonReady) {
    if (-not (Test-Wsl)) {
      throw "Error en Docker: WSL no está instalado o no está habilitado. Ejecutá como administrador: wsl --install --no-distribution; luego reiniciá Windows."
    }
    $dockerDesktop = Find-DockerDesktop
    if (-not $dockerDesktop) {
      throw "Error en Docker: Docker Desktop está instalado, pero no se encontró su ejecutable para iniciarlo."
    }
    Set-Status "docker" "running" "Iniciando Docker Desktop en segundo plano y esperando al daemon..."
    Disable-DockerStartupUi
    Start-Process -FilePath $dockerDesktop `
      -WorkingDirectory (Split-Path -Parent $dockerDesktop) `
      -WindowStyle Hidden
    $startedByScript = $true
  }

  $deadline = (Get-Date).AddSeconds(120)
  do {
    if ($startedByScript) {
      Hide-DockerDesktopWindows
    }
    if (Test-DockerDaemon) {
      $daemonReady = $true
      break
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  if ($startedByScript) {
    Hide-DockerDesktopWindows
  }
  if (-not $daemonReady) {
    throw "Error en Docker: Docker Desktop no pudo iniciar el daemon. Abrí Docker Desktop y esperá a que indique que está listo."
  }
  if (-not (Test-DockerCompose)) {
    throw "Error en Docker: Docker Compose no está disponible."
  }
  Set-Status "docker" "ok" "Docker Desktop y Compose están disponibles."
}

function Find-DockerDesktop {
  $candidates = @(
    "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
    "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
    "$env:LOCALAPPDATA\Programs\Docker\Docker\Docker Desktop.exe",
    "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe"
  )
  return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Test-DockerDaemon {
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & docker version --format "{{.Server.Version}}" 2>$null 1>$null
    return $LASTEXITCODE -eq 0
  } finally {
    $ErrorActionPreference = $previousPreference
  }
}

function Test-DockerCompose {
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & docker compose version 2>$null 1>$null
    return $LASTEXITCODE -eq 0
  } finally {
    $ErrorActionPreference = $previousPreference
  }
}

function Start-Server {
  Set-Status "server" "running" "Verificando el servidor existente..."
  Push-Location $root
  try {
    $existingContainer = (& docker compose ps -q server 2>$null | Select-Object -First 1)
    if ($existingContainer) {
      $existingContainer = ([string]$existingContainer).Trim()
    }
    if ($existingContainer) {
      $running = (& docker inspect --format "{{.State.Running}}" $existingContainer 2>$null).Trim()
      if ($running -eq "true" -and (Test-NetConnection -ComputerName "127.0.0.1" -Port $Port -InformationLevel Quiet)) {
        Set-Status "server" "running" "El servidor ya está iniciado. Se reutiliza el contenedor existente."
      } else {
        Set-Status "server" "running" "El servidor existe, pero no está listo. Iniciándolo..."
        & docker compose start server 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
          throw "Error en el servidor: No se pudo iniciar el contenedor existente."
        }
      }
    } else {
      Set-Status "server" "running" "El servidor no existe. Creándolo e iniciándolo..."
      $composeExitCode = 1
      $composeOutput = @()
      $composeDeadline = (Get-Date).AddSeconds(30)
      do {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
          $composeOutput = & docker compose up -d server 2>&1
          $composeExitCode = $LASTEXITCODE
        } finally {
          $ErrorActionPreference = $previousPreference
        }
        if ($composeExitCode -ne 0) {
          Start-Sleep -Seconds 2
        }
      } while ($composeExitCode -ne 0 -and (Get-Date) -lt $composeDeadline)
      if ($composeExitCode -ne 0) {
        $detail = ($composeOutput | Out-String).Trim()
        throw "Error en el servidor: Docker Compose no pudo crear el servidor. $detail"
      }
    }

    $deadline = (Get-Date).AddSeconds(30)
    do {
      if (Test-NetConnection -ComputerName "127.0.0.1" -Port $Port -InformationLevel Quiet) {
        break
      }
      Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
  } finally {
    Pop-Location
  }

  $ready = Test-NetConnection -ComputerName "127.0.0.1" -Port $Port -InformationLevel Quiet
  if (-not $ready) {
    throw "Error en el servidor: No respondió en el puerto $Port."
  }
  $vpnIp = Get-RadminVpnIp
  if (-not $vpnIp) {
    throw "Error en Radmin VPN: Radmin VPN está iniciado, pero no se pudo obtener su IP."
  }
  Set-Status "server" "ready" "Partida creada. IP para tus amigos: $vpnIp | Puerto: $Port"
}

function Get-RadminVpnIp {
  $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
      $_.IPAddress -like "26.*" -and
      $_.IPAddress -ne "26.0.0.1"
    } |
    Select-Object -ExpandProperty IPAddress
  return $addresses | Select-Object -First 1
}

try {
  if ($OnlyVpn) {
    Ensure-RadminVpn | Out-Null
    exit 0
  }
  if (-not $SkipVpn) {
    $vpnOk = Ensure-RadminVpn
    if (-not $vpnOk) {
      exit 0
    }
  } elseif (-not (Test-RadminPowerOn)) {
    Show-RadminVpnWindow
    Set-Status "vpn" "vpn_needs_activation" "Radmin VPN está desconectado. Por favor conecte el VPN y vuelva a intentar."
    exit 0
  }
  Ensure-Docker
  Start-Server
} catch {
  try {
    Set-Status "error" "error" $_.Exception.Message
  } catch {
    Write-Error $_.Exception.Message
  }
  exit 1
}
