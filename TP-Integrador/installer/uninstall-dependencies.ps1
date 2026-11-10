[CmdletBinding()]
param(
  [switch]$RemoveDocker,
  [Alias("RemoveRadmin")][switch]$RemoveRadminVpn,
  [string]$InstallRoot = ""
)

$prereqScript = Join-Path $PSScriptRoot "uninstall-prerequisites.ps1"
if (Test-Path -LiteralPath $prereqScript) {
  & $prereqScript -RemoveDocker:$RemoveDocker -RemoveRadminVpn:$RemoveRadminVpn -InstallRoot $InstallRoot
}
