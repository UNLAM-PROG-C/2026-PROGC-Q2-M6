# Sprint 2 — Estado de la iteración

**Proyecto:** Tower Defense Cooperative  
**Período:** 26/10/2026 – 01/11/2026  
**Objetivo:** implementar hilos del servidor y el primer contacto funcional con el cliente Godot.

## Implementación

- [x] `acceptor_thread` y un `client_thread` por conexión.
- [x] Lectura de frames parciales y mensajes consecutivos mediante el protocolo TCP existente.
- [x] Cola de comandos entre los hilos de cliente y el game loop.
- [x] `spawner_thread` productor de eventos de oleada y enemigos.
- [x] `game_loop_thread` consumidor a 20 Hz.
- [x] Integración del spawner con el proceso hijo de Sprint 1.
- [x] `WELCOME`, `READY`, `STATE_UPDATE`, compras, ventas, `PING` y `ERROR`.
- [x] Cliente Godot con `StreamPeerTCP`, framing big-endian y buffer de recepción.
- [x] Bot Python con handshake, compras aleatorias, logs y cierre abrupto opcional.
- [x] Desconexión de clientes sin detener el servidor.
- [x] Mensajes desconocidos o inválidos tratados como errores de protocolo.
- [x] Sin locks, de forma intencional, para dejar la evidencia previa al Sprint 3.

## Validación

Desde la raíz del proyecto, con Docker disponible:

```bash
docker compose build
docker compose run --rm dev pytest -q
docker compose run --rm godot godot --headless --path /workspace/cliente_godot --editor --quit
```

Para una prueba manual:

```bash
docker compose up server
docker compose run --rm dev python -m tools.bot_client --name bot-1 --duration 30
docker compose run --rm dev python -m tools.bot_client --name bot-2 --duration 30 --seed 2
```

El servidor espera dos clientes `READY`, comienza la primera oleada y envía `STATE_UPDATE` periódicos. Si un bot se desconecta, el otro continúa recibiendo actualizaciones.

## Evidencia de la condición de carrera

`tests/test_game_state.py::test_unsynchronized_purchase_race_is_reproducible` sincroniza dos hilos justo después de comprobar el oro y antes de descontarlo. Con 50 de oro y dos torres de 50, ambas compras se aceptan y el saldo queda en `-50`.

Esto es deliberado para AP1 Parte 2. En Sprint 3 se agregará `gold_lock` y se repetirá el caso esperando una única compra válida y ningún saldo negativo.

## Alcance excluido

Este sprint no incluye locks, renderizado de torres o enemigos, HUD, combate visual, reconexión, persistencia, matchmaking ni ENet/RPC. Esos componentes pertenecen a los sprints posteriores.

La creación de la rama y el tag `release/ap1-parte2` queda pendiente de realizar manualmente cuando la metadata Git esté disponible en el entorno.
