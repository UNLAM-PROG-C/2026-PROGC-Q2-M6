param(
  [int]$Port = 5000,
  [string]$ProjectName = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
  $ProjectName = "tower-defense-$Port"
}
Set-Location $PSScriptRoot
$env:HOST_PORT = $Port
docker compose --project-name $ProjectName up --build -d server
if ($LASTEXITCODE -ne 0) {
  throw "No se pudo iniciar el servidor Docker en el puerto $Port."
}
Write-Output "Servidor iniciado en 127.0.0.1:$Port"
