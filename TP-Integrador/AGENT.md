# AGENT.md — Guía de iteración

## Fuente de verdad

Este archivo resume las reglas que deben respetarse en cada cambio. Para el alcance completo, el calendario de sprints y el checklist de entrega, consultar [`plan.md`](plan.md). Si una decisión nueva contradice el plan, detenerse y explicitar la decisión antes de implementarla.

## Contexto del proyecto

TP integrador de Programación Concurrente (UNLaM): juego cooperativo de defensa de torres para 2 a 4 jugadores en LAN.

- Servidor: Python 3.11+, única fuente de verdad de la partida.
- Cliente: Godot 4.x/GDScript; solo envía acciones y renderiza el estado recibido.
- Red: TCP + JSON con framing `[4 bytes big-endian][cuerpo UTF-8]`.
- Concurrencia: `threading`, `queue` y locks en el servidor.
- Procesos: proceso padre y proceso hijo para patrones de oleadas/estadísticas, comunicados por pipe.
- Pruebas: `pytest` y `tools/bot_client.py`.

## Alcance cerrado

Debe incluir 3 tipos de torre, 5 tipos de enemigo, 10 oleadas fijas, oro y vida de base compartidos, pantallas de victoria/derrota y sockets TCP directos.

No agregar guardado, perfiles, progresión, matchmaking, reconexión, más mapas, dificultad procedural ni ENet/RPC sin una decisión explícita del equipo. Evitar feature creep.

## Arquitectura que se debe preservar

- `acceptor_thread` acepta conexiones y crea un `client_thread` por jugador.
- Cada `client_thread` lee mensajes y los encola como comandos; no modifica directamente el estado de la partida.
- `spawner_thread` produce enemigos en una `queue.Queue`.
- `game_loop_thread` consume comandos/enemigos, ejecuta el tick a 20 Hz y hace broadcast.
- El proceso hijo calcula el patrón de la próxima oleada y estadísticas; el padre coordina y espera su finalización ordenada.
- Godot mantiene `network_client.gd` como Autoload y aplica `STATE_UPDATE` en `game_view.gd`.

### Estado compartido y sincronización

- Oro: `gold_lock` para compras, ventas y recompensas.
- Vida de base: `base_hp_lock` para aplicar daño sin perder actualizaciones.
- Clientes: `clients_lock` (`RLock`) en conexión, desconexión y broadcast.
- Cola de enemigos: siempre `queue.Queue`; no reemplazarla por una lista compartida sin sincronización.
- Inicio de oleada: `threading.Barrier(n_players)` cuando corresponda.
- Orden global obligatorio para adquirir más de un lock: `gold_lock` → `base_hp_lock` → `clients_lock`.
- Nunca mantener un lock mientras se espera una operación de red bloqueante si puede evitarse.

## Contrato de protocolo

Todos los mensajes tienen esta forma:

```json
{"type": "MESSAGE_TYPE", "payload": {}}
```

Los nombres deben ser idénticos en `servidor/protocol.py` y `cliente_godot/scripts/protocol_constants.gd`.

- Cliente → servidor: `HELLO`, `READY`, `BUY_TOWER`, `SELL_TOWER`, `PING`.
- Servidor → cliente: `WELCOME`, `STATE_UPDATE`, `WAVE_START`, `BASE_DAMAGE`, `GAME_OVER`, `ERROR`.

Toda lectura TCP debe soportar lecturas parciales y mensajes pegados. Los mensajes inválidos o desconocidos deben producir `ERROR` o descartarse de forma segura, nunca tumbar el servidor.

## Reglas de código

- Python y GDScript: 2 espacios, sin tabs.
- Funciones de menos de 15 líneas; extraer helpers si crecen.
- Todo el código, nombres de nodos, funciones, señales, comentarios y commits en inglés.
- Sin números mágicos: usar `servidor/constants.py`, `servidor/protocol.py` o `const` en GDScript.
- Seguir Google Style Guide para Python y la guía oficial de estilo de GDScript.
- Mantener los patrones definidos en el plan: Factory, Strategy, Observer, Singleton acotado y Producer-Consumer.
- No mezclar lógica de juego autoritativa con lógica visual del cliente.

## Flujo de trabajo

- `main`: estable y entregable; solo recibe merges desde `develop` mediante PR revisado.
- `develop`: integración diaria.
- `feature/<nombre>`: una funcionalidad acotada; nace de `develop` y vuelve por PR.
- `release/ap1-parteN`: congelamiento de cada entrega incremental, con tag.
- Commits cortos, imperativos y en inglés.
- El autor no mergea su propio PR; cada PR requiere al menos una revisión.
- Antes de modificar código, revisar el estado de Git y preservar cambios no relacionados.
- Preferir cambios pequeños, verificables y fáciles de revertir.

## Criterios de terminado por iteración

Antes de considerar una tarea terminada:

1. Verificar que el cambio respeta el alcance y la arquitectura.
2. Agregar o actualizar tests, especialmente para framing, protocolo y concurrencia.
3. Ejecutar las pruebas relevantes y documentar cualquier limitación.
4. Probar errores de entrada, desconexiones y mensajes desconocidos cuando el cambio los afecte.
5. Comprobar que no haya oro negativo, doble gasto, pérdida de daño ni deadlocks.
6. Revisar formato, nombres en inglés, funciones cortas y ausencia de números mágicos.
7. Actualizar README o documentación si cambió la forma de ejecutar, configurar o entender el sistema.

## Casos de prueba prioritarios

- Framing con header/cuerpo partidos y varios mensajes en un mismo `recv`.
- Dos o más bots comprando simultáneamente: el oro nunca puede quedar negativo ni gastarse dos veces.
- Cuatro bots durante al menos 5 minutos: el servidor debe seguir respondiendo y no bloquearse.
- Desconexión de un cliente a mitad de partida: los demás deben continuar.
- Mensajes inválidos/desconocidos: el servidor debe mantenerse activo.
- Integración con 2, 3 y 4 bots, y una partida completa con al menos dos clientes Godot.

## Restricciones de entorno

El desarrollo del servidor, las pruebas y las herramientas se ejecuta dentro de Docker. Godot 4.3 stable se valida en modo headless dentro de Docker; el editor visual se ejecuta en el host. `os.fork()` requiere Linux/macOS. En Windows se debe usar WSL o `multiprocessing.Process`, documentándolo en README.

## Prioridad actual

Al 17/10/2026 Sprint 2 está implementado: servidor con hilos, colas, spawner, game loop a 20 Hz, cliente Godot conectado y bot de pruebas. La validación Docker queda pendiente hasta disponer del daemon. La vinculación con GitHub y la rama/tag `release/ap1-parte2` se realizan manualmente fuera del entorno actual. El objetivo recomendado del proyecto es la entrega del 25/11; el 02/12 queda como colchón.
