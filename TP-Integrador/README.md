# Co-Tower Defense
## COTO: Yo te defiendo

## Guía rápida: Cómo instalar, jugar y desinstalar

### 1. Cómo instalar el juego
1. Descargá o cloná este repositorio.
2. Instalá los programas necesarios:
   - **Godot 4.3 o superior**: necesario para todos los jugadores (el juego se ejecuta desde el editor).
   - **Radmin VPN**: necesario para todos los jugadores.
   - **Docker Desktop** (con WSL habilitado): necesario únicamente para la persona que vaya a **crear la partida** (los demás jugadores no lo necesitan).

### 2. Cómo jugar con amigos
1. **Conectar Radmin VPN:**
   - Abrí **Radmin VPN** y encendelo (el botón de encendido debe figurar conectado).
   - Un jugador crea una red (**Red → Crear red**) y los demás se unen a esa misma red (**Red → Unirse a una red existente**).
2. **Abrir el juego:**
   - Abrí Godot, importá `cliente_godot/project.godot` y ejecutá el proyecto (**F5**).
3. **Crear o unirse a la partida:**
   - **Anfitrión (Host):** presioná **Crear partida**, esperá a que aparezca *"Servidor iniciado. Esperando otros jugadores"*, tocá **Copiar** y pasale la dirección (`IP:puerto`) a tus amigos. Cuando haya **2 o más jugadores** conectados (máximo 4), presioná **Iniciar partida**.
   - **Invitados:** pegá la dirección (`IP:puerto`) que te pasó tu amigo y presioná **Unirse**.
4. **Empezar las oleadas:**
   - Dentro de la partida, las oleadas empiezan (tras una cuenta regresiva de 3 segundos) cuando cualquiera de los jugadores coloca la primera torre.

### 3. Cómo desinstalar
1. Si creaste partidas, eliminá el contenedor y la imagen del servidor desde la carpeta `TP-Integrador`: `docker compose down --rmi local`.
2. Borrá la carpeta del repositorio.
3. Si ya no los necesitás, desinstalá **Docker Desktop**, **Radmin VPN** y **Godot** desde la configuración de Windows.

---

## Documentación técnica

El proyecto contiene un servidor TCP multihilo, un bucle de juego productor-consumidor, un cliente de red en Godot y un bot en Python para pruebas de concurrencia. El servidor TCP actúa como el proceso padre y un proceso hijo ejecutado mediante `exec` calcula patrones de oleadas deterministas a través de dos tuberías (*pipes*).

### Hilo de sonido del cliente

El cliente Godot reproduce la música en un hilo concurrente propio, implementado en el Autoload `SoundManager` (`cliente_godot/scripts/sound_manager.gd`):

* El hilo principal solo encola comandos (`play_music()`, `stop_music()`) en una cola protegida por un `Mutex` (productor).
* El hilo de audio (consumidor) vacía la cola. En Godot 4.4 o superior decodifica `assets/audio/two_left_socks.ogg` con `AudioStreamPlayback.mix_audio()` y empuja las muestras a un `AudioStreamGenerator` que lee el mezclador del motor.
* En versiones anteriores a 4.4 (por ejemplo, la 4.3 del contenedor *headless*) `mix_audio()` no existe: el hilo sigue consumiendo los comandos, pero delega la reproducción en un `AudioStreamPlayer` mediante `call_deferred`, porque el árbol de escena no es seguro entre hilos. El modo se detecta automáticamente al iniciar.
* Con la música detenida, el hilo se bloquea en un `Semaphore` en lugar de hacer espera activa; al cerrar el juego se encola `QUIT` y se espera su finalización con `wait_to_finish()`.

## Requisitos

* Docker Engine o Docker Desktop con Docker Compose.

* Godot 4.3 o superior en el sistema anfitrión (*host*) para el editor visual. El proyecto fue guardado por última vez con Godot 4.7 (`config/features` en `cliente_godot/project.godot`); abrirlo con una versión anterior muestra una advertencia.

* El contenedor de Godot usa por defecto Godot 4.3 en modo *headless* (configurable con `GODOT_VERSION`).

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

El script construye la imagen del servidor si es necesario e inicia el servidor TCP en segundo
plano (`docker compose up --build -d`) escuchando en `0.0.0.0:5000`, con el nombre de proyecto
Compose `tower-defense-<puerto>`. Para cambiar el puerto:

```
.\start-server.ps1 -Port 5001

```

Conectá los clientes de Godot a `127.0.0.1` y al mismo puerto. Como el contenedor queda
corriendo en segundo plano, no hace falta mantener la terminal abierta. Para detenerlo:

```
docker compose --project-name tower-defense-5000 down

```

El botón `Crear partida` del lobby se usa únicamente en la PC anfitriona: ejecuta en segundo plano
`start-stack.ps1`, que inicia automáticamente Radmin VPN, Docker Desktop (verificando antes que WSL
esté habilitado) y el servicio `server`, y muestra una dirección única con formato
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

El flujo de inicio del lobby usa un archivo de estado en `user://` (dentro del perfil del
usuario) para comunicar el estado entre Godot y PowerShell.

### Servidor y proceso trabajador

El registro de inicio incluye los PIDs del proceso padre y del hijo. El servidor designa al primer cliente como anfitrión; cuando el anfitrión presiona `Iniciar partida`, todos los clientes pasan al tablero y la primera oleada arranca (tras una cuenta regresiva de 3 segundos) cuando cualquier jugador coloca la primera torre. El servidor permanece activo hasta recibir `SIGINT` o `SIGTERM`.

El proceso trabajador requiere `fork()`, por lo que solo funciona en Linux/macOS. En Windows el servidor corre dentro del contenedor Docker (Linux), así que no hace falta configurar nada extra; para ejecutarlo fuera de Docker, usá WSL. El proceso hijo se inicia con:

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
