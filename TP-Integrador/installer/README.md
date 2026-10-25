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
- Descarga e instala Radmin VPN automáticamente para jugar por Internet sin configurar routers.
- Detecta Docker Desktop y ofrece instalarlo si falta (solo para el anfitrión).
- Abre los puertos TCP 5001-5100 en todos los perfiles del Firewall.
- Crea un acceso directo en el escritorio.

Para jugar entre dos computadoras por Internet:
1. Abrí Radmin VPN (no pide cuenta ni correo ni tarjeta).
2. Hacé clic en "Crear Red" y poné un nombre y contraseña (ej: `tower1` / `1234`).
3. Tu amigo abre Radmin VPN, hace clic en "Unirse a Red" y entra con ese nombre y contraseña.
4. En el juego presionás "Crear partida" y te va a mostrar tu IP de Radmin VPN (ej: `26.x.x.x:5001`).
5. Tu amigo pega esa IP en su juego y presiona "Conectarse a partida".

Docker Desktop solo es necesario en la computadora que presiona `Crear partida`; los invitados pueden conectarse sin Docker.

Para compilar el `.exe` del instalador con Inno Setup 6:

```powershell
ISCC.exe .\installer\TowerDefense.iss
```

El resultado queda en `installer\output\TowerDefenseSetup.exe`.
