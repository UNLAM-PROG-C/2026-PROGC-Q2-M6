# Plan de proyecto — Torre de Defensa Cooperativa

TP Integrador · Programación Concurrente (UNLaM) · 2° Cuatrimestre 2026

Servidor en **Python** + cliente gráfico en **Godot 4.x (GDScript)** · 2 a 4 jugadores cooperativos

---

## 1. Visión general

Juego cooperativo de defensa de torres. De 2 a 4 jugadores defienden juntos una base contra 10 oleadas fijas de enemigos, compartiendo **oro** y **vida de base**. El servidor es la única fuente de verdad: concentra toda la lógica de juego y de concurrencia. El cliente Godot solo envía acciones del jugador y renderiza el estado que recibe.

**Por qué este diseño:** la concurrencia resuelve un problema real del juego (varios jugadores accediendo al mismo oro y a la misma vida de base a la vez), y cada etapa de la cátedra (procesos → hilos → comunicación y concurrencia) queda en una capa identificable del código.

### Alcance cerrado

| Incluye | No incluye |
|---|---|
| 2–4 jugadores en LAN/IP conocida | Guardado, perfiles, progresión |
| 3 tipos de torre, 5 tipos de enemigo | Más de un mapa |
| 10 oleadas fijas | Dificultad dinámica / oleadas procedurales |
| Oro y vida de base compartidos | Reconexión de clientes caídos |
| Pantallas de victoria y derrota | Matchmaking por internet |
| Cliente Godot con sockets TCP directos | API multijugador nativa de Godot (ENet/RPC) |

---

## 2. Stack tecnológico

| Capa | Tecnología | Notas |
|---|---|---|
| Servidor | Python 3.11+ | `threading`, `queue`, `socket`, `struct`, `json`, `os.fork` / `multiprocessing` |
| Cliente | Godot Engine 4.x | GDScript, `StreamPeerTCP`, Autoload, Signals |
| Protocolo | TCP + JSON | Framing por longitud: 4 bytes big-endian + cuerpo UTF-8 |
| IPC interno | `os.pipe` / `multiprocessing.Pipe` | Padre ↔ proceso hijo de estadísticas/IA de oleadas |
| Testing | `pytest` + bot cliente en Python | El bot permite probar concurrencia sin abrir varios Godot |
| Control de versiones | Git + GitHub | GitFlow simplificado (sección 8) |
| Docs | Markdown + PDF final | README.md, manual de usuario, conclusiones |

**Requisitos de entorno:** `os.fork()` solo existe en Linux/macOS. En Windows usar WSL o `multiprocessing.Process`. Definir esto en el README.

---

## 3. Arquitectura

### 3.1 Vista general

```
 ┌────────────────┐        TCP + JSON (framing)        ┌──────────────────────────────┐
 │ Cliente Godot  │ ◄────────────────────────────────► │ Servidor Python (proceso     │
 │ (1 por jugador)│  BUY_TOWER, READY ... STATE_UPDATE │ padre)                       │
 └────────────────┘                                    │                              │
 ┌────────────────┐                                    │  acceptor_thread             │
 │ Cliente Godot  │ ◄────────────────────────────────► │  client_thread  x N          │
 └────────────────┘                                    │  spawner_thread  (productor) │
                                                       │  game_loop_thread(consumidor)│
                                                       │            │ pipe            │
                                                       │            ▼                 │
                                                       │  Proceso hijo (fork):        │
                                                       │  patrón de oleadas + stats   │
                                                       └──────────────────────────────┘
```

### 3.2 Estructura del repositorio

```
tower-defense/
├── README.md
├── plan.md
├── servidor/
│   ├── main.py                  # arranca el servidor
│   ├── process_manager.py       # fork() del hijo + pipe + wait()
│   ├── game_state.py            # oro, vida de base, torres, enemigos + locks
│   ├── network.py               # acceptor + client threads + framing
│   ├── spawner.py               # hilo productor de enemigos
│   ├── game_loop.py             # hilo consumidor, tick a 20 Hz
│   ├── protocol.py              # tipos de mensaje y constantes
│   ├── constants.py             # costos, daños, tiempos (sin números mágicos)
│   └── patterns/
│       ├── tower_factory.py
│       ├── enemy_factory.py
│       ├── attack_strategy.py
│       ├── event_publisher.py
│       └── game_state_manager.py
├── cliente_godot/
│   ├── project.godot
│   ├── scenes/   (Main, Lobby, Hud, Tower, Enemy, GameOver)
│   └── scripts/
│       ├── network_client.gd        # Autoload: StreamPeerTCP + framing + JSON
│       ├── protocol_constants.gd    # mismos nombres que protocol.py
│       ├── game_view.gd             # aplica STATE_UPDATE sobre la escena
│       └── input_handler.gd         # arma BUY_TOWER / SELL_TOWER
├── tools/
│   └── bot_client.py            # cliente bot para pruebas de carga y carreras
├── tests/
└── docs/                        # capturas, manual de usuario, informe
```

### 3.3 Hilos y procesos

| Componente | Tipo | Responsabilidad |
|---|---|---|
| Servidor (padre) | Proceso | Orquesta todo, hace `fork()` y `wait()` del hijo |
| Proceso hijo | Proceso (`fork`) | Calcula el patrón de la próxima oleada y acumula estadísticas; se comunica por pipe |
| `acceptor_thread` | Hilo | Acepta conexiones y crea un `client_thread` por jugador |
| `client_thread` (N) | Hilo | Lee mensajes de un socket y los encola como comandos |
| `spawner_thread` | Hilo (productor) | Genera enemigos en intervalos que se acortan por oleada |
| `game_loop_thread` | Hilo (consumidor) | Tick de 20 Hz: aplica comandos, mueve enemigos, resuelve daño, hace broadcast |

### 3.4 Recursos compartidos y sincronización

| Recurso | Riesgo | Mecanismo |
|---|---|---|
| Oro del equipo | Dos jugadores compran a la vez y gastan oro inexistente | `threading.Lock` (`gold_lock`) |
| Vida de la base | Actualizaciones de daño que se pisan | `threading.Lock` (`base_hp_lock`) |
| Cola de enemigos | Acceso simultáneo spawner / game loop | `queue.Queue` (thread-safe) |
| Inicio de oleada | Arrancar sin que todos estén listos | `threading.Barrier(n_players)` |
| Lista de clientes | Iterar mientras otro hilo agrega/quita | `threading.RLock` (`clients_lock`) |

**Regla anti-deadlock:** si una acción necesita más de un lock, siempre se adquieren en el mismo orden global: `gold_lock` → `base_hp_lock` → `clients_lock`. Documentarlo en el código y en el README.

### 3.5 Protocolo

Framing: `[4 bytes: longitud big-endian][JSON UTF-8]`. Todo mensaje tiene `type` y `payload`.

```json
{"type": "BUY_TOWER", "payload": {"lane": 2, "tower_type": "MAGE", "pos": [340, 220]}}
```

**Cliente → Servidor:** `HELLO`, `READY`, `BUY_TOWER`, `SELL_TOWER`, `PING`

**Servidor → Cliente:** `WELCOME`, `STATE_UPDATE` (10–20 Hz), `WAVE_START`, `BASE_DAMAGE`, `GAME_OVER`, `ERROR`

Los nombres de mensaje viven en `protocol.py` y `protocol_constants.gd`; deben mantenerse idénticos.

### 3.6 Patrones de diseño

| Patrón | Dónde | Equivalente en Godot |
|---|---|---|
| Factory Method | `tower_factory.py`, `enemy_factory.py` | `instance_tower(type)` en `game_view.gd` |
| Strategy | `attack_strategy.py` (área, single-target, ignora armadura) | Solo reproduce el efecto visual |
| Observer | `event_publisher.py` (ENEMY_KILLED, BASE_DAMAGED, WAVE_CLEARED) | Signals nativas (`game_view` → `Hud`) |
| Singleton acotado | `game_state_manager.py` (una instancia de estado por partida) | `network_client.gd` como Autoload |
| Producer-Consumer | `spawner.py` ↔ `game_loop.py` | No aplica |

### 3.7 Reglas del juego (valores iniciales, ajustables en `constants.py`)

| Torre | Costo | Daño | Cadencia | Especial |
|---|---|---|---|---|
| Arquero | 50 | 10 | 1/seg | — |
| Cañón | 120 | 40 | 1/3 seg | Daño en área chico |
| Mago | 150 | 15 | 1/2 seg | Ignora armadura |

| Enemigo | Vida | Velocidad | Recompensa | Desde oleada |
|---|---|---|---|---|
| Goblin | 30 | Normal | 5 | 1 |
| Orco | 80 | Lenta | 10 | 3 |
| Corredor | 20 | Rápida | 8 | 4 |
| Troll | 150 | Lenta | 20 | 7 |
| Jefe | 500 | Normal | 100 | 10 |

Oro inicial 200 · Vida de base inicial 100 · Victoria: superar la oleada 10 · Derrota: vida de base en 0.

---

## 4. Estándar de código (obligatorio de la cátedra)

| Regla | Python | GDScript |
|---|---|---|
| Guía de estilo | Google Style Guide | GDScript Style Guide oficial (documentar en README) |
| Indentación | 2 espacios, sin tabs | 2 espacios (configurar el editor de Godot) |
| Tamaño de función | Menos de 15 líneas | Menos de 15 líneas |
| Números mágicos | Constantes en `constants.py` / `protocol.py` | `const` en `protocol_constants.gd` |
| Idioma | Todo en inglés | Todo en inglés (nodos, señales, funciones, comentarios) |
| Patrones de diseño | Sección 3.6 | Sección 3.6 |

---

## 5. Sprints

**Fecha de hoy:** 12/10/2026. **Fechas posibles de entrega/coloquio:** 18/11, 25/11 y 02/12.
**Recomendación:** apuntar al **25/11** como fecha objetivo. El 18/11 es posible pero deja casi sin margen, y el 02/12 queda como colchón. Los sprints son semanales.

### Sprint 0 — Setup local con Docker (12/10 – 18/10)

**Objetivo:** que todo el equipo pueda desarrollar y ejecutar el servidor, las pruebas y las herramientas dentro de Docker, con una versión reproducible de Godot para validación headless.

- [ ] Crear `.gitignore`, `.dockerignore`, `Dockerfile`, `Dockerfile.godot` y `docker-compose.yml`
- [ ] Fijar Python 3.11+, Godot 4.3 stable y los comandos de desarrollo dentro de Docker
- [ ] Crear esqueleto de carpetas (sección 3.2)
- [ ] Configurar formato de 2 espacios en `.editorconfig`
- [ ] Escribir `protocol.py` y `protocol_constants.gd` con los mismos tipos de mensaje
- [ ] Escribir `constants.py` con todos los valores de la sección 3.7
- [ ] Implementar y probar `send_message` / `recv_message` con framing en Python
- [ ] Crear proyecto Godot con `Lobby.tscn` (campos IP/puerto, botón conectar)
- [ ] Validar el proyecto Godot en modo headless dentro de Docker
- [ ] Documentar instalación, ejecución y pruebas en `README.md`

La vinculación con GitHub y la creación de ramas se realizan manualmente fuera de este sprint.

**Definición de terminado:** `docker compose build`, las pruebas Python y la validación headless de Godot funcionan, y las constantes del protocolo existen en ambos lados.

### Sprint 1 — AP1 Parte 1: Procesos (19/10 – 25/10)

**Objetivo:** servidor como proceso propio con un hijo creado por `fork()`.

- [ ] `game_state.py` con clases `Tower`, `Enemy`, `GameState` (sin locks todavía)
- [ ] `main.py` levanta el servidor como proceso independiente
- [ ] `process_manager.py`: `fork()` del hijo de estadísticas/IA de oleadas
- [ ] Comunicación padre ↔ hijo por pipe (mensajes: `WAVE_REQUEST`, `WAVE_PATTERN`, `STATS_UPDATE`)
- [ ] `wait()` / `waitpid()` para cierre ordenado del hijo al terminar la partida
- [ ] Manejo de señal/cierre limpio (no dejar procesos zombie)
- [ ] Patrón de 10 oleadas definido en el hijo (cantidad y tipo de enemigos)
- [ ] Rama `release/ap1-parte1` con tag al finalizar

**Definición de terminado:** al arrancar el servidor se ve el PID del padre y del hijo, el padre le pide un patrón de oleada por pipe y lo recibe, y al cerrar no quedan procesos huérfanos.

**Pendiente a verificar:** si la cátedra pide entregar `execve` en esta parte, agregar una tarea mínima (ej. lanzar el logger de estadísticas con `execve`).

### Sprint 2 — AP1 Parte 2: Hilos (26/10 – 01/11)

**Objetivo:** hilos del servidor funcionando y primer contacto del cliente Godot. Todavía **sin locks a propósito**, para poder ver la condición de carrera antes de resolverla.

- [x] `network.py`: `acceptor_thread` + un `client_thread` por conexión
- [x] Framing completo en el servidor (lectura de header + cuerpo, manejo de lecturas parciales)
- [x] `spawner.py`: `spawner_thread` que encola enemigos
- [x] `game_loop.py`: `game_loop_thread` a 20 Hz consumiendo la cola
- [x] `network_client.gd` como Autoload: conecta con `StreamPeerTCP`, arma y parsea frames
- [x] El cliente Godot recibe `WELCOME` y `STATE_UPDATE` y los loggea (sin render todavía)
- [x] Script `tools/bot_client.py`: conecta, manda `HELLO`/`READY`, compra torres al azar
- [x] Caso borde resuelto temprano: desconexión de un cliente (se captura el error de socket y la partida sigue)
- [ ] Rama `release/ap1-parte2` con tag

**Definición de terminado:** con el servidor corriendo, un cliente Godot y un bot conectados ven `STATE_UPDATE` periódicos; matar un cliente no tira el servidor.

**Entregable didáctico:** dejar documentada (log o test) una condición de carrera real provocada con dos bots comprando a la vez. Va al informe como evidencia del "antes".

### Sprint 3 — AP1 Parte 3: Comunicación y Concurrencia (02/11 – 08/11)

**Objetivo:** resolver toda la sincronización y cerrar el protocolo.

- [ ] `gold_lock` en compra/venta de torres y en recompensas por enemigo derrotado
- [ ] `base_hp_lock` para el daño a la base
- [ ] `clients_lock` (`RLock`) en connect/disconnect/broadcast
- [ ] `threading.Barrier(n_players)` para el inicio sincronizado de oleada
- [ ] Orden global de locks documentado y respetado
- [ ] Protocolo completo implementado en ambos lados (todos los mensajes de 3.5)
- [ ] Validaciones del servidor: oro insuficiente, posición ocupada, tipo inválido → `ERROR`
- [ ] Repetir el test de carrera del Sprint 2: ahora el oro nunca queda negativo ni se gasta dos veces
- [ ] Test con 2, 3 y 4 bots simultáneos
- [ ] Rama `release/ap1-parte3` con tag

**Definición de terminado:** 4 bots comprando y vendiendo a la vez durante varios minutos sin inconsistencias de oro ni de vida, y sin deadlocks.

### Sprint 4 — Cliente Godot jugable + patrones (09/11 – 15/11)

**Objetivo:** juego completo de punta a punta con 2+ personas reales.

- [ ] `Hud.tscn`: oro, vida de base, número de oleada
- [ ] `Tower.tscn` y `Enemy.tscn`; `game_view.gd` los instancia, mueve y libera según `STATE_UPDATE`
- [ ] `input_handler.gd`: selección de torre y colocación en carriles, envío de `BUY_TOWER` / `SELL_TOWER`
- [ ] Pantallas `GameOver` (victoria y derrota)
- [ ] Mostrar mensajes `ERROR` al jugador (ej. "oro insuficiente")
- [ ] Refactor con patrones: Factory (torres/enemigos), Strategy (ataques), Observer (eventos), Singleton acotado, Autoload
- [ ] Revisión de estándar de código: funciones < 15 líneas, sin números mágicos, todo en inglés
- [ ] Balanceo básico de las 10 oleadas jugando partidas reales
- [ ] Partida completa de punta a punta con 2 personas en máquinas distintas

**Definición de terminado:** una partida de 10 oleadas jugable, con victoria y derrota funcionando, en red local.

### Sprint 5 — Documentación, pulido y coloquio (16/11 – 22/11)

**Objetivo:** dejar listo el informe y estar preparados para defender.

- [ ] `README.md`: finalidad, lenguajes, frameworks, requisitos de hardware/SO, cómo correr servidor y cliente
- [ ] Manual de usuario con capturas o video (link en el documento)
- [ ] Sección de conclusiones: dificultades reales (carrera detectada, framing, deadlocks evitados)
- [ ] Informe en PDF `TP_Integrador_NumerodelGrupo.pdf` con carátula, link al repo, descripción, manual y conclusiones
- [ ] Subir el PDF a Miel
- [ ] Ensayo de coloquio: cada integrante explica un módulo que **no** escribió
- [ ] Revisión final del repo (sin archivos basura, ramas limpias, tags de entregas)

**Definición de terminado:** repo y PDF entregados, y todos pueden explicar cualquier módulo.

### Colchón y opcional (23/11 – 02/12)

Esta franja es margen para imprevistos y para entregar el 02/12 si hace falta. Solo si sobra tiempo:

- [ ] **AP2 opcional (OpenMP/MPI):** paralelizar el cálculo de daño en área o la actualización de muchos enemigos por tick, y medir el speedup. Nota honesta: con carriles fijos el pathfinding es trivial, así que conviene paralelizar el daño en área o la simulación de muchos enemigos, que sí escalan.
- [ ] Documentar GPU como "trabajo futuro" si no se implementa.

---

## 6. Estrategia de branching

| Rama | Propósito | Regla |
|---|---|---|
| `main` | Código estable para entregar y mostrar | Solo recibe merges desde `develop` por PR revisado por otro integrante |
| `develop` | Integración diaria | Rama de trabajo del equipo |
| `feature/<nombre>` | Una funcionalidad (ej. `feature/gold-lock`, `feature/godot-hud`) | Sale de `develop`, vuelve por PR, se borra al mergear |
| `release/ap1-parteN` | Congela cada entrega incremental | Tag + rama al cerrar cada sprint de AP1 |

**Commits:** en inglés, modo imperativo, cortos. Ej.: `add gold lock to prevent double spend`, `add godot hud scene`.

**Pull Requests:** mínimo 1 revisión de otro integrante; el autor no mergea su propio PR. Servidor y cliente conviven en el mismo repo.

---

## 7. Estrategia de testing

| Qué | Cómo |
|---|---|
| Framing | Test unitario: mensajes partidos y pegados se reconstruyen bien |
| Condición de carrera | 2+ bots comprando la misma torre/oro en simultáneo; verificar oro final consistente |
| Deadlock | Prueba larga (5+ min) con 4 bots; si el servidor deja de responder, hay un problema de orden de locks |
| Desconexión | Cerrar un cliente a mitad de partida; el resto debe seguir |
| Protocolo | Mensajes inválidos o desconocidos no deben tirar el servidor |
| Integración | Partida completa con clientes Godot reales en dos máquinas |

---

## 8. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Framing mal leído entre Python y Godot | Script mínimo en Godot que solo conecte y loggee bytes crudos, antes de armar el resto del cliente (Sprint 2) |
| Carrera no detectada en el oro | Test con bots en Sprint 2 (antes del lock) y Sprint 3 (después) |
| Deadlock por orden de locks | Orden global documentado + revisión cruzada en PR |
| `fork()` no disponible en Windows | Decidir en Sprint 0: WSL/Linux o `multiprocessing.Process` |
| Un integrante no puede explicar su parte | Rotar módulos entre sprints; nadie es "dueño" permanente de un archivo ni de un lenguaje |
| Desincronización visual por latencia | `STATE_UPDATE` periódico completo, no solo eventos |
| Feature creep | Respetar la lista de "No incluye" de la sección 1; todo agregado se discute en grupo |
| Ir justos de tiempo | Apuntar al 25/11 y usar 02/12 como colchón, no como plan base |

---

## 9. Checklist de entrega final

- [ ] Repo en GitHub con código fuente, proyecto Godot y `plan.md`
- [ ] `README.md` completo (finalidad, lenguajes, frameworks, requisitos)
- [ ] Manual de usuario (capturas o link a video)
- [ ] Conclusiones con dificultades reales
- [ ] PDF `TP_Integrador_NumerodelGrupo.pdf` con el mismo contenido que README y manual
- [ ] Entrega en Miel
- [ ] Estándar de código verificado en Python y GDScript
- [ ] Tags de las 3 entregas de AP1 en el repo
