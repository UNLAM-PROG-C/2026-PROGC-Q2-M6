# Sprint 0 — Estado de la iteración

**Proyecto:** Tower Defense Cooperative  
**Período:** 12/10/2026 – 18/10/2026  
**Objetivo:** preparar un entorno reproducible de desarrollo con Docker y dejar listas las bases del protocolo, el framing TCP y el cliente Godot inicial.

## Items realizados

### Entorno y Docker

- [x] `Dockerfile` basado en Python 3.11.
- [x] `Dockerfile.godot` con Godot 4.3 stable headless.
- [x] `docker-compose.yml` con servicios `dev`, `server` y `godot`.
- [x] Volumen compartido `/workspace` para trabajar sobre el código del repositorio.
- [x] Puerto TCP configurable mediante `SERVER_PORT`.
- [x] `.gitignore` para archivos generados, cachés, logs y entornos locales.
- [x] `.dockerignore` para reducir el contexto de construcción.
- [x] `.env.example` con versión de Godot, host y puerto.
- [x] `.editorconfig` con indentación de dos espacios.
- [x] `requirements-dev.txt` con pytest fijado.

### Servidor Python

- [x] Paquete `servidor` inicializado.
- [x] `servidor/constants.py` con valores iniciales del juego.
- [x] `servidor/main.py` con servidor TCP mínimo y cierre mediante `KeyboardInterrupt`.
- [x] Lectura de `SERVER_HOST` y `SERVER_PORT` desde variables de entorno.

### Protocolo y framing

- [x] Mensajes de cliente y servidor definidos en `servidor/protocol.py`.
- [x] Framing con encabezado de 4 bytes en orden big-endian.
- [x] Serialización y deserialización JSON.
- [x] Soporte para lecturas parciales.
- [x] Soporte para varios mensajes consecutivos en el mismo stream.
- [x] Validación de tamaño, tipo y payload de los mensajes.
- [x] Manejo de JSON inválido mediante `ProtocolError`.
- [x] Constantes equivalentes en `protocol_constants.gd`.

### Cliente Godot

- [x] Proyecto Godot 4.3 stable creado.
- [x] `Lobby.tscn` con campos de host y puerto.
- [x] Botón de conexión con validación básica.
- [x] `network_client.gd` configurado como Autoload.
- [x] Validación headless preparada para ejecutarse dentro de Docker.

### Pruebas y documentación

- [x] Tests de framing con header y body fragmentados.
- [x] Test de varios mensajes en un único stream.
- [x] Test de envío de mensajes con `send_message()`.
- [x] Tests de JSON inválido y payload incorrecto.
- [x] Test de equivalencia entre constantes Python y GDScript.
- [x] `README.md` con instalación y comandos Docker.
- [x] `plan.md` y `AGENT.md` actualizados al flujo con Docker.

## Validaciones ejecutadas

Estas comprobaciones ya se realizaron sin modificar el proyecto:

- `docker compose config --quiet`: correcto.
- Compilación sintáctica de Python: correcta.
- Smoke test de framing con socket real: correcto.
- Smoke test de lectura fragmentada: correcto.
- Verificación de equivalencia de constantes Python/GDScript: correcta.

## Validaciones pendientes

La ejecución completa dentro de Docker queda pendiente de iniciar Docker Desktop u OrbStack en el equipo:

- `docker compose build`.
- Tests completos con pytest dentro del contenedor.
- Validación de Godot headless dentro del contenedor.
- Prueba del servidor TCP dentro del contenedor.

El host utilizado durante la implementación no tenía el daemon Docker accesible, por lo que no corresponde marcar esas pruebas como aprobadas todavía.

## Cómo probar esta iteración

### 1. Iniciar Docker

Iniciar Docker Desktop u OrbStack y comprobar que el daemon responde:

```bash
docker info
```

Si el comando muestra la información del servidor Docker, continuar con las pruebas.

### 2. Preparar configuración local

Desde la raíz del proyecto:

```bash
cp .env.example .env
```

El archivo `.env` es local y está excluido por `.gitignore`.

### 3. Construir las imágenes

```bash
docker compose build
```

Este comando construye la imagen Python y la imagen de Godot headless.

### 4. Ejecutar los tests Python

```bash
docker compose run --rm dev pytest -q
```

La ejecución debe finalizar sin errores. Los tests cubren framing, lecturas fragmentadas, mensajes consecutivos, errores JSON y equivalencia de constantes.

### 5. Validar el proyecto Godot

```bash
docker compose run --rm godot godot --headless --path /workspace/cliente_godot --editor --quit
```

El comando debe terminar con código de salida `0` y sin errores de parseo de escenas o scripts.

### 6. Levantar el servidor

En una terminal:

```bash
docker compose up server
```

Debe aparecer un mensaje similar a:

```text
Server listening on 0.0.0.0:5000
```

En otra terminal, comprobar que el puerto está accesible desde otro contenedor:

```bash
docker compose run --rm dev python -c 'import socket; socket.create_connection(("server", 5000), timeout=3).close(); print("TCP connection passed")'
```

### 7. Abrir el lobby visual

Con Godot 4.3 stable instalado en el host:

```bash
godot --editor --path cliente_godot
```

Ejecutar `Lobby.tscn` y comprobar:

- el host aparece como `127.0.0.1`;
- el puerto aparece como `5000`;
- un puerto inválido muestra un mensaje de validación;
- un host válido muestra el estado de solicitud de conexión.

En este sprint el botón todavía no establece una conexión TCP real: prepara la interfaz y emite la señal para la implementación de red del Sprint 2.

### 8. Detener el entorno

```bash
docker compose down
```

## Resultado esperado

El Sprint 0 queda aprobado cuando la construcción Docker, los tests Python, la validación headless de Godot y la prueba de disponibilidad TCP finalizan correctamente.

La lógica de procesos, hilos, locks, oleadas y gameplay queda reservada para los siguientes sprints.
