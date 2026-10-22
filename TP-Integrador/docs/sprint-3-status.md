# Sprint 3 — Estado de la iteración

**Proyecto:** Tower Defense Cooperative  
**Período:** 02/11/2026 – 08/11/2026  
**Objetivo:** sincronizar el estado compartido y cerrar el protocolo entre servidor y cliente.

## Implementación

- [x] `gold_lock` para compras, ventas y recompensas.
- [x] `base_hp_lock` para daño concurrente a la base.
- [x] `clients_lock` (`RLock`) para altas, bajas y snapshots de broadcast.
- [x] Orden de locks documentado: `gold_lock` → `base_hp_lock` → `clients_lock`.
- [x] Roster READY congelado al comenzar con 2–4 jugadores.
- [x] `threading.Barrier(n_players)` para liberar la primera oleada.
- [x] Validaciones de oro, posición, carril, tipo de torre y torre inexistente.
- [x] Eventos `WAVE_START`, `BASE_DAMAGE` y `GAME_OVER` enviados por el servidor.
- [x] Signals equivalentes implementadas en `NetworkClient` de Godot.
- [x] Enemigos inicializados con la vida configurada en `ENEMY_STATS`.

## Contrato de errores

Los errores se envían con esta forma:

```json
{
  "type": "ERROR",
  "payload": {
    "code": "INSUFFICIENT_GOLD",
    "message": "The team does not have enough gold"
  }
}
```

Códigos cubiertos: `INSUFFICIENT_GOLD`, `POSITION_OCCUPIED`, `INVALID_TOWER_TYPE`, `INVALID_LANE`, `INVALID_POSITION`, `TOWER_NOT_FOUND` y `GAME_ALREADY_STARTED`.

## Eventos de partida

Cuando un enemigo llega a la base, el servidor resta 10 HP y envía:

```json
{
  "type": "BASE_DAMAGE",
  "payload": {
    "enemy_id": 1,
    "enemy_type": "DISCOUNT_CHILD",
    "damage": 10,
    "base_hp": 90
  }
}
```

`GAME_OVER` incluye `result` (`VICTORY` o `DEFEAT`), `reason` y `wave`. La victoria se produce al limpiar la oleada 10; la derrota, cuando la vida de base llega a cero.

## Pruebas

La suite cubre framing, compras simultáneas, ventas simultáneas, recompensas concurrentes, daño concurrente, posiciones ocupadas, desconexión, mensajes desconocidos, clientes tardíos y una conexión coordinada de cuatro clientes.

Comando de validación:

```bash
docker compose run --rm dev pytest -q
docker compose run --rm godot godot --headless --path /workspace/cliente_godot --editor --quit
```

La prueba manual prolongada usa cuatro bots durante 300 segundos. Debe verificarse que el servidor continúe respondiendo y que el oro nunca sea negativo ni se duplique una devolución.

## Limitación del entorno

La validación estática realizada en este entorno pasó `git diff --check`, compilación Python y smoke tests de concurrencia del estado. La suite `pytest`, la prueba TCP y la validación headless de Godot requieren el daemon Docker y no pudieron ejecutarse porque el socket de OrbStack no estaba accesible. Deben repetirse los comandos Docker al disponer del daemon.
