# Co-Tower Defense
## COTO: Yo te defiendo

## Guía rápida: Cómo instalar, jugar y desinstalar

### 1. Cómo instalar el juego
1. Ejecutá **`TowerDefenseSetup.exe`**.
2. Elegí qué programas adicionales querés instalar:
   - **Instalar Radmin VPN**: necesario para todos los jugadores.
   - **Instalar Docker Desktop**: necesario únicamente para la persona que vaya a **crear la partida** (los demás jugadores no lo necesitan).
3. Hacé clic en **Siguiente** → **Instalar** y esperá a que termine.

### 2. Cómo jugar con amigos
1. **Conectar Radmin VPN:**
   - Abrí **Radmin VPN** y encendelo (el botón de encendido debe figurar conectado).
   - Un jugador crea una red (**Red → Crear red**) y los demás se unen a esa misma red (**Red → Unirse a una red existente**).
2. **Abrir el juego:**
   - Ejecutá el acceso directo **Co-Tower Defense** en el Escritorio (o **`CoTowerDefense.exe`**).
3. **Crear o unirse a la partida:**
   - **Anfitrión (Host):** presioná **Crear partida**, esperá a que aparezca *"Servidor iniciado. Esperando otros jugadores"*, tocá **Copiar** y pasale la dirección (`IP:puerto`) a tus amigos. Cuando haya **2 o más jugadores** conectados, presioná **Iniciar partida**.
   - **Invitados:** pegá la dirección (`IP:puerto`) que te pasó tu amigo y presioná **Unirse**.
4. **Empezar las oleadas:**
   - Dentro de la partida, las oleadas empiezan cuando cualquiera de los jugadores coloca la primera torre.

### 3. Cómo desinstalar
1. Ejecutá **`DesinstalarTowerDefense.exe`** (o **Desinstalar Co-Tower Defense** desde el Menú Inicio).
2. Se eliminarán todos los datos y la carpeta del juego, y te dará la opción de elegir si también querés desinstalar **Docker Desktop** y **Radmin VPN**.

---

## Documentación técnica

El proyecto contiene un servidor TCP multihilo, un bucle de juego productor-consumidor, un cliente de red en Godot y un bot en Python para pruebas de concurrencia. El servidor TCP actúa como el proceso padre y un proceso hijo ejecutado mediante `exec` calcula patrones de oleadas deterministas a través de dos tuberías (*pipes*).

## Requisitos

* Docker Engine o Docker Desktop con Docker Compose.

* Godot 4.3 stable en el sistema anfitrión (*host*) para el editor visual.

* El contenedor de Godot utiliza la misma versión en modo *headless*.

El repositorio se monta en `/workspace` en cada servicio. Python y `pytest` se ejecutan dentro de Docker; no instales dependencias del proyecto en el sistema anfitrión.

## Configuración

Copiá `.env.example` a `.env` cuando necesites configuraciones locales personalizadas
(`GODOT_VERSION`, `SERVER_HOST` y `HOST_PORT`):

```
cp .env.example .env

```

Los valores por defecto son Godot `4.3`, host del servidor `0.0.0.0` y puerto TCP `5000`.
El contenedor siempre escucha en `5000`; `HOST_PORT` elige el puerto publicado en la PC anfitriona.

## Comandos de Docker

Construir las imágenes de desarrollo:

```
docker compose build

```

Abrir una terminal en el contenedor de desarrollo de Python:

```
docker compose run --rm dev bash

```

Ejecutar la suite de pruebas:

```
docker compose run --rm dev pytest

```

Iniciar el servidor TCP multihilo y el coordinador de procesos:

```
docker compose up server

```

En Windows con Docker Desktop, ejecutá esto desde PowerShell dentro de `TP-Integrador`:

```
.\start-server.ps1

```

El script construye la imagen del servidor si es necesario e inicia una instancia del servidor TCP escuchando en `0.0.0.0:5000`. Para cambiar el puerto:

```
$env:HOST_PORT = "5001"
docker compose up --build server

```

Conectá los clientes de Godot a `127.0.0.1` y al mismo puerto. Mantené esta terminal abierta mientras la partida esté en curso; presioná `Ctrl+C` para detener el servidor.

El botón `Crear partida` del lobby se usa únicamente en la PC anfitriona: inicia automáticamente
Radmin VPN, Docker Desktop y el servicio `server`, y muestra una dirección única con formato
`IP:puerto` para compartirla con los demás jugadores. El botón `Copiar` copia esa dirección al
portapapeles. La pantalla informa cada etapa y muestra el motivo exacto si falta
algún componente, si Docker no puede iniciar, si Compose falla o si el puerto no responde.
Esta automatización requiere Windows, Radmin VPN instalado y permisos suficientes para iniciar
Docker Desktop.

Los demás jugadores no deben crear otra partida. Deben pegar la dirección `IP:puerto` completa en
el recuadro del lobby y presionar `Unirse`; el programa inicia Radmin VPN antes de conectar y
separa automáticamente la IP y el puerto. Radmin VPN debe estar instalado y ambos jugadores
deben pertenecer a la misma red de Radmin VPN; abrir la aplicación no puede unirla
automáticamente a una red que no esté configurada.
`127.0.0.1` solo se usa internamente en la PC anfitriona.

### Instalador de Windows

La fuente reproducible del instalador está en `installer/TowerDefenseSetup.iss`. El instalador
incluye el cliente Godot, el servidor y los archivos necesarios para iniciar la partida. Docker
Desktop y Radmin VPN aparecen seleccionados por defecto y se instalan mediante `winget`; se pueden
desmarcar si ya están instalados. El instalador verifica Docker Engine y Docker Compose antes de
finalizar y crea accesos directos del juego y de Radmin VPN en el escritorio. El desinstalador
pregunta por separado si también debe quitar Docker Desktop y Radmin VPN; ambas opciones son
voluntarias y Docker puede tener datos locales que se perderán al desinstalarlo.

El instalador escribe el diagnóstico en `%ProgramData%\TowerDefense\installer.log`. El flujo de
inicio del lobby usa un archivo temporal dentro del perfil del usuario para comunicar el estado
entre Godot y PowerShell.

El registro de inicio incluye los PIDs del proceso padre y del hijo. El servidor designa al primer cliente como anfitrión; cuando el anfitrión presiona `Iniciar partida`, todos los clientes pasan al tablero y la primera oleada arranca (tras una cuenta regresiva de 3 segundos) cuando cualquier jugador coloca la primera torre. El servidor permanece activo hasta recibir `SIGINT` o `SIGTERM`.

El proceso trabajador requiere `fork()`, por lo que se ejecuta de forma nativa en Linux/macOS. En Windows, utilizá WSL. El proceso hijo se inicia con:

```
python -m servidor.wave_worker READ_FD WRITE_FD

```

El padre y el hijo intercambian mensajes JSON con un prefijo de longitud de cuatro bytes en formato *big-endian*. El padre envía `WAVE_REQUEST`, `STATS_UPDATE` y `SHUTDOWN`; el hijo envía `CHILD_READY` y `WAVE_PATTERN`.

## Protocolo

Los mensajes utilizan JSON con un prefijo de longitud de cuatro bytes en formato *big-endian*:

```
{"type": "MESSAGE_TYPE", "payload": {}}

```

La implementación en Python se encuentra en `servidor/protocol.py`; las constantes equivalentes de Godot se encuentran en `cliente_godot/scripts/protocol_constants.gd`.
