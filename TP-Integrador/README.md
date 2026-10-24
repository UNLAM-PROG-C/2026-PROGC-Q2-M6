# Co-Tower Defense
## COTO: Yo te defiendo

El proyecto contiene un servidor TCP multihilo, un bucle de juego productor-consumidor, un cliente de red en Godot y un bot en Python para pruebas de concurrencia. El servidor TCP actúa como el proceso padre y un proceso hijo ejecutado mediante `exec` calcula patrones de oleadas deterministas a través de dos tuberías (*pipes*).

## Requisitos

* Docker Engine o Docker Desktop con Docker Compose.

* Godot 4.3 stable en el sistema anfitrión (*host*) para el editor visual.

* El contenedor de Godot utiliza la misma versión en modo *headless*.

El repositorio se monta en `/workspace` en cada servicio. Python y `pytest` se ejecutan dentro de Docker; no instales dependencias del proyecto en el sistema anfitrión.

## Configuración

Copiá `.env.example` a `.env` cuando necesites configuraciones locales personalizadas:

```
cp .env.example .env

```

Los valores por defecto son Godot `4.3`, host del servidor `0.0.0.0` y puerto TCP `5000`.

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
$env:SERVER_PORT = "5001"
docker compose up --build server

```

Conectá los clientes de Godot a `127.0.0.1` y al mismo puerto. Mantené esta terminal abierta mientras la partida esté en curso; presioná `Ctrl+C` para detener el servidor.

El registro de inicio incluye los PIDs del proceso padre y del hijo. El servidor espera a que dos clientes estén listos (`READY`) antes de que el generador (*spawner*) inicie la primera oleada, y permanece activo hasta recibir `SIGINT` o `SIGTERM`.

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
