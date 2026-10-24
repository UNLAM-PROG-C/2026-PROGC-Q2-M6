# Instalador online para Windows

El instalador final para distribuir es `TowerDefenseSetup.exe`. Se genera
compilando `TowerDefense.iss` con Inno Setup.

También se puede ejecutar PowerShell como Administrador desde la carpeta
`TP-Integrador`:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\installer\install-game.ps1
```

El instalador:

- Copia el cliente Godot y el servidor local.
- Muestra una consola con el progreso de cada dependencia.
- Prepara `TowerDefense.exe` y crea accesos directos que no abren PowerShell.
- Descarga Godot 4.3 si no está en la instalación.
- Descarga e instala Tailscale si no está instalado.
- Detecta Docker Desktop y ofrece instalarlo si falta.
- Abre los puertos TCP 5001-5100 en el perfil de red privada.
- Crea un acceso directo en el escritorio.

Tailscale no inicia sesión automáticamente. Cada usuario debe iniciar sesión
manualmente y unirse a la misma tailnet. El instalador no contiene claves de
autenticación.

El acceso directo abre `TowerDefense.exe` directamente; el usuario final no
necesita conocer Python ni abrir PowerShell. PowerShell se usa internamente
solo cuando el botón `Crear partida` inicia Docker.

Docker Desktop puede requerir reiniciar Windows y aceptar sus términos de
licencia. El instalador necesita conexión a Internet.

Este instalador es para Windows x64. macOS y Linux requieren exportaciones y
paquetes propios de cada sistema operativo.

Para compilar el `.exe`, instalá Inno Setup 6 y ejecutá:

```powershell
ISCC.exe .\installer\TowerDefense.iss
```

El resultado queda en `installer\output\TowerDefenseSetup.exe`.
