@echo off
setlocal
for /f "tokens=2,*" %%A in ('reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\{9D7C3C18-36F3-4C89-8E99-5AAB2A1BD8B1}_is1" /v UninstallString 2^>nul') do set "UNINSTALLER=%%B"
if not exist "%UNINSTALLER%" (
  echo No se encontro la instalacion registrada de Tower Defense.
  pause
  exit /b 1
)
start "" %UNINSTALLER%
endlocal
