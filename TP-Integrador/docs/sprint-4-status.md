# Sprint 4 — Estado de la iteración

## Implementación

- [x] Catálogo de torres y enemigos migrado al concepto de supermercado.
- [x] Fábricas de torres y enemigos.
- [x] Estrategias de ataque para mopeador, repositor y sistema de paging.
- [x] Daño, cadencia, recompensas y aturdimiento resueltos por el servidor.
- [x] Observer para enemigos derrotados, daño a base y oleadas completadas.
- [x] Escenas Godot `Main`, `GameView`, `Hud`, `Tower`, `Enemy` y `GameOver`.
- [x] Colocación y venta de torres desde el cliente.
- [x] HUD, errores y pantallas de victoria/derrota.
- [x] Sprites SVG originales con fondo transparente para los ocho tipos de personaje.

## Catálogo visual

Las torres representan al personal de COTO: mopeador, repositor con zorra de carga y sistema de paging. Los enemigos representan cazadores de descuentos: niño, abuela con carrito, niño en monopatín, abuela blindada y jefe del carro de oro.

Los identificadores de red permanecen en inglés para respetar el estándar del repositorio; las etiquetas visibles están en español.

## Validación

```bash
docker compose run --rm dev pytest -q
docker compose run --rm godot godot --headless --path /workspace/cliente_godot --editor --quit
```

La validación manual requiere dos clientes Godot conectados al mismo servidor. Ambos deben observar el mismo oro, vida de base, oleada, torres y enemigos. Una torre derrotando enemigos debe aumentar el oro compartido; una base en cero debe mostrar derrota y limpiar la partida; limpiar la oleada 10 debe mostrar victoria.

La prueba Python local de humo fue ejecutada correctamente. La suite completa y la validación headless de Godot quedan preparadas para ejecutarse dentro de Docker porque el host no tiene `pytest` ni Godot disponibles.
