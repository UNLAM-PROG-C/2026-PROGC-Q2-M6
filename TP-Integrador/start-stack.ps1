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

function Ensure-RadminVpn {
  Set-Status "vpn" "running" "Verificando Radmin VPN..."
  $vpnService = Get-Service -Name "RvControlSvc" -ErrorAction SilentlyContinue
  if (-not $vpnService) {
    throw "No se encontró el servicio de Radmin VPN (RvControlSvc). Reinstalá Radmin VPN."
  }
  if ($vpnService.Status -ne "Running") {
    Set-Status "vpn" "running" "Encendiendo Radmin VPN..."
    try {
      Start-Service -Name "RvControlSvc" -ErrorAction Stop
      $vpnService.WaitForStatus("Running", [TimeSpan]::FromSeconds(15))
    } catch {
      throw "Radmin VPN no pudo encenderse. Verificá permisos de administrador y el servicio RvControlSvc. Detalle: $($_.Exception.Message)"
    }
  }
  $vpnIp = Get-RadminVpnIp
  if ($vpnIp) {
    Set-Status "vpn" "vpn_ready" "Radmin VPN ya está activo."
    return
  }
  $process = Get-Process -Name "RvRvpnGui", "RvGuiStarter", "RadminVPN" -ErrorAction SilentlyContinue
  if (-not $process) {
    $path = Find-RadminVpn
    if (-not $path) {
      throw "Radmin VPN no está instalado. Instalalo desde el instalador y reintentá."
    }
    Start-Process -FilePath $path -WindowStyle Normal
    Start-Sleep -Seconds 2
  } else {
    $path = Find-RadminVpn
    if ($path) {
      Start-Process -FilePath $path -WindowStyle Normal
    }
  }
  if (-not (Get-Process -Name "RvRvpnGui", "RvGuiStarter", "RadminVPN" -ErrorAction SilentlyContinue)) {
    throw "Radmin VPN no pudo iniciarse."
  }
  $vpnIp = Get-RadminVpnIp
  if ($vpnIp) {
    Set-Status "vpn" "vpn_ready" "Radmin VPN ya está activo."
    return
  }
  Set-Status "vpn" "vpn_needs_activation" "Radmin VPN está abierto, pero figura desconectado. Activá el botón de encendido y reintentá."
}

function Ensure-Docker {
  Set-Status "docker" "running" "Verificando Docker Desktop..."
  $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
  if (-not $dockerCommand) {
    throw "Docker no está instalado. Ejecutá el instalador y seleccioná Docker Desktop."
  }

  $daemonReady = Test-DockerDaemon
  if (-not $daemonReady) {
    if (-not (Test-Wsl)) {
      throw "WSL no está instalado o no está habilitado. Ejecutá como administrador: wsl --install --no-distribution; luego reiniciá Windows."
    }
    $dockerDesktop = Find-DockerDesktop
    if (-not $dockerDesktop) {
      throw "Docker Desktop está instalado, pero no se encontró su aplicación para iniciarla."
    }
    Set-Status "docker" "running" "Abriendo Docker Desktop y esperando al daemon..."
    Start-Process -FilePath $dockerDesktop `
      -WorkingDirectory (Split-Path -Parent $dockerDesktop) `
      -WindowStyle Hidden
  }

  $deadline = (Get-Date).AddSeconds(120)
  do {
    if (Test-DockerDaemon) {
      $daemonReady = $true
      break
    }
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)
  if (-not $daemonReady) {
    throw "Docker Desktop no pudo iniciar el daemon. Abrí Docker Desktop y esperá a que indique que está listo."
  }
  if (-not (Test-DockerCompose)) {
    throw "Docker Compose no está disponible."
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
          throw "No se pudo iniciar el contenedor existente del servidor."
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
        throw "Docker Compose no pudo crear el servidor. $detail"
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
    throw "El servidor no respondió en el puerto $Port."
  }
  $vpnIp = Get-RadminVpnIp
  if (-not $vpnIp) {
    throw "Radmin VPN está iniciado, pero no se pudo obtener su IP."
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
    Ensure-RadminVpn
    exit 0
  }
  if (-not $SkipVpn) {
    Ensure-RadminVpn
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
