param(
  [switch]$RemoveDocker,
  [switch]$RemoveRadmin
)

$ErrorActionPreference = "SilentlyContinue"

# Remove firewall rules
& netsh advfirewall firewall delete rule name="Tower Defense Local" 2>$null | Out-Null
& netsh advfirewall firewall delete rule name="Tower Defense Tailscale" 2>$null | Out-Null

function Uninstall-Application([string]$DisplayName, [string]$PackageId) {
  Write-Host "Buscando desinstalador para $DisplayName..."
  $regKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  $installed = Get-ItemProperty $regKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and ($_.DisplayName -like "*$DisplayName*") } |
    Select-Object -First 1

  if ($installed) {
    if ($installed.QuietUninstallString) {
      Write-Host "Ejecutando desinstalador silencioso de $DisplayName..."
      Start-Process "cmd.exe" -ArgumentList "/c `"$($installed.QuietUninstallString)`"" -Wait -WindowStyle Hidden
      return
    } elseif ($installed.UninstallString) {
      Write-Host "Ejecutando desinstalador de $DisplayName..."
      Start-Process "cmd.exe" -ArgumentList "/c `"$($installed.UninstallString)`"" -Wait -WindowStyle Hidden
      return
    }
  }

  $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
  if ($winget) {
    Write-Host "Ejecutando winget uninstall para $PackageId..."
    Start-Process $winget.Source -ArgumentList "uninstall --id $PackageId --silent --accept-source-agreements" -Wait -WindowStyle Hidden
  }
}

if ($RemoveDocker) {
  Uninstall-Application "Docker Desktop" "Docker.DockerDesktop"
}

if ($RemoveRadmin) {
  Uninstall-Application "Radmin VPN" "Famatech.RadminVPN"
}
