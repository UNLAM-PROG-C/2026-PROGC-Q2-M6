# Sprint 1 — Estado de la iteración

**Proyecto:** Tower Defense Cooperative  
**Período:** 19/10/2026 – 25/10/2026  
**Objetivo:** coordinar un proceso padre y un proceso hijo mediante `fork()`, `execve()`, pipes y `waitpid()`.

## Implementación

- [x] Modelos `Tower`, `Enemy` y `GameState` sin locks.
- [x] Framing independiente para pipes con longitud big-endian de cuatro bytes.
- [x] Mensajes `WAVE_REQUEST`, `STATS_UPDATE`, `SHUTDOWN`, `CHILD_READY` y `WAVE_PATTERN`.
- [x] Worker ejecutable como `python -m servidor.wave_worker`.
- [x] Tabla determinista de diez oleadas.
- [x] Señales `SIGINT` y `SIGTERM` en el proceso padre.
- [x] Cierre de pipes y recolección del hijo mediante `waitpid()`.
- [x] Tests unitarios e integración padre/hijo.

## Validación

Desde la raíz del proyecto:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q
```

Para validar el servidor completo con Docker:

```bash
docker compose build
docker compose up server
```

La salida esperada contiene líneas equivalentes a:

```text
Server listening on 0.0.0.0:5000
Parent PID: <pid>
Child PID: <pid>
Wave 1 pattern: {'wave': 1, 'enemies': [{'type': 'GOBLIN', 'count': 5}]}
```

Al detener el servicio con `Ctrl+C` o `docker compose down`, la salida debe confirmar:

```text
Shutdown requested
Child process reaped
Server stopped
```

La prueba de integración confirma el handshake `CHILD_READY`, las diez respuestas `WAVE_PATTERN`, el envío de `STATS_UPDATE`, `SHUTDOWN` y la salida exitosa del hijo.

En el entorno de desarrollo actual, la ejecución local de pytest queda pendiente porque `pytest` no está instalado en el Python del host y el daemon Docker no permite conexión desde este proceso. La integración de procesos sí fue validada directamente con Python 3 mediante pipes reales y confirmó el round-trip de las diez oleadas y la salida `0` del worker.

## Alcance excluido

Este sprint todavía no implementa clientes, acceptor threads, game loop, spawner, locks, colas, concurrencia de jugadores ni renderizado Godot. Esos componentes corresponden a los sprints siguientes.

## Limitación de plataforma

`fork()` y `execve()` se ejecutan nativamente en Linux/macOS. En Windows se debe usar WSL, tal como se documenta en el README.
