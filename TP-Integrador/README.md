# Tower Defense Cooperative

The project contains a threaded TCP server, a producer-consumer game loop, a Godot network client and a Python bot for concurrent testing. The TCP server remains the parent process and an exec'ed child calculates deterministic wave patterns through two pipes.

## Requirements

- Docker Engine or Docker Desktop with Docker Compose.
- Godot 4.3 stable on the host for the visual editor.
- The Godot container uses the same version in headless mode.

The repository is mounted at `/workspace` in every service. Python and pytest are executed inside Docker; do not install project dependencies on the host.

## Configuration

Copy `.env.example` to `.env` when local overrides are needed:

```bash
cp .env.example .env
```

The default values are Godot `4.3`, server host `0.0.0.0` and TCP port `5000`.

## Docker commands

Build the development images:

```bash
docker compose build
```

Open a shell in the Python development container:

```bash
docker compose run --rm dev bash
```

Run the test suite:

```bash
docker compose run --rm dev pytest
```

Start the threaded TCP server and process coordinator:

```bash
docker compose up server
```

The startup log includes the parent and child PIDs. The server waits for two ready clients before the spawner starts the first wave and remains alive until `SIGINT` or `SIGTERM`.

The process worker requires `fork()`, so it runs natively on Linux/macOS. On Windows, use WSL. The child is launched with:

```text
python -m servidor.wave_worker READ_FD WRITE_FD
```

The parent and child exchange four-byte big-endian length-prefixed JSON messages. The parent sends `WAVE_REQUEST`, `STATS_UPDATE` and `SHUTDOWN`; the child sends `CHILD_READY` and `WAVE_PATTERN`.

## Sprint 2: threaded server and clients

Run the bot from another terminal after the server is running. From a Docker container, use `server` as the host name:

```bash
docker compose run --rm dev python -m tools.bot_client --host server --port 5000 --name bot-1 --duration 30
```

Run two bots to exercise concurrent connections and purchases:

```bash
docker compose run --rm dev python -m tools.bot_client --host server --port 5000 --name bot-1 --seed 1
docker compose run --rm dev python -m tools.bot_client --host server --port 5000 --name bot-2 --seed 2
```

The Godot client can be opened on the host with:

```bash
godot --editor --path cliente_godot
```

Run `Main.tscn`, enter the server host and port, and press `Connect`. After two clients send `READY`, the lobby changes to the supermarket board and renders the authoritative state.

The Sprint 2 server uses an acceptor thread, one client thread per socket, a producer queue for enemies and a 20 Hz game-loop consumer. The historical race evidence is documented in `docs/sprint-2-status.md`; Sprint 3 now protects the shared state with locks.

```bash
docker compose run --rm dev pytest -q tests/test_game_state.py -k race
```

The live server applies commands in the game loop, so socket handlers never mutate the state directly.

## Sprint 3: synchronized state and complete protocol

**Status:** implementation completed; Docker bot connectivity confirmed using the `server` service hostname. Full automated integration and Godot headless validation remain the final acceptance checks.

Implemented in this sprint:

- `gold_lock`, `base_hp_lock` and shared `clients_lock` (`RLock`), with no socket I/O while locks are held.
- Atomic tower purchases, sales, enemy rewards and base damage; no negative gold or double refunds.
- READY roster freeze for 2–4 players using `threading.Barrier(n_players)`.
- Server validation errors for invalid towers, lanes, positions, occupied slots, insufficient gold and late players.
- Complete server/Godot handling for `WAVE_START`, `BASE_DAMAGE`, `GAME_OVER`, `STATE_UPDATE` and `ERROR`.
- Concurrent state, network, spawner and four-client integration tests.
- Bot support for both random tower purchases and sales.

The server protects purchases, sales and enemy rewards with `gold_lock`, base damage with `base_hp_lock`, and client registration/broadcast snapshots with a shared `clients_lock` (`RLock`). Locks are never held while sending on a socket. When at least two clients send `READY`, the current READY roster (2–4 players) is frozen and released through a `threading.Barrier`; later clients cannot join that match.

The server emits `WAVE_START`, `BASE_DAMAGE`, `GAME_OVER`, `STATE_UPDATE` and `ERROR`. Godot exposes matching signals from `NetworkClient`. A tower position is occupied when its lane and exact position match an existing tower. An enemy reaching the base deals 10 damage, and base HP is clamped at zero.

Run the Sprint 3 unit and integration tests with:

```bash
docker compose run --rm dev pytest -q
```

For a manual concurrency run, start the server and launch four bots from separate terminals:

```bash
docker compose up server
docker compose run --rm dev python -m tools.bot_client --host server --port 5000 --name bot-1 --duration 300 --seed 1
docker compose run --rm dev python -m tools.bot_client --host server --port 5000 --name bot-2 --duration 300 --seed 2
docker compose run --rm dev python -m tools.bot_client --host server --port 5000 --name bot-3 --duration 300 --seed 3
docker compose run --rm dev python -m tools.bot_client --host server --port 5000 --name bot-4 --duration 300 --seed 4
```

Launch the four bot commands from separate terminals, as soon as possible after starting the server, so they can join the same roster. The expected result is no negative gold, no duplicate refunds, no lost base damage and no server deadlock. The detailed checklist and validation evidence are in [`docs/sprint-3-status.md`](docs/sprint-3-status.md).

Run the full suite locally when `pytest` is installed with:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q
```

Validate the Godot project in headless mode:

```bash
docker compose run --rm godot godot --headless --path /workspace/cliente_godot --editor --quit
```

Open the visual editor on the host:

```bash
godot --editor --path cliente_godot
```

Configure the Godot script editor to use tabs for GDScript indentation, as recommended by the Godot style guide. The repository `.editorconfig` applies this rule only to `cliente_godot/**/*.gd`; Python and other project files keep their existing formatting rules.

The host editor is intentionally outside Docker because the Sprint 0 setup does not configure graphical display forwarding. The project itself is shared through the repository mount and is validated with the Godot container.

## Sprint 4: playable supermarket defense

The current client uses the supermarket concept from section 3.7 of `plan.md`:

- Towers: `MOPPER`, `STOCK_REPLENISHER` and `AUDIO_TOWER`.
- Enemies: `DISCOUNT_CHILD`, `SHOPPING_GRANDMA`, `SKATEBOARD_CHILD`, `ARMORED_GRANDMA` and `GOLD_CART_BOSS`.
- Tower attacks, enemy health, rewards, movement and game-over conditions are resolved by the server.
- Godot renders three lanes, the HUD, character sprites, puddle/sonic effects, errors and victory/defeat overlays.

Controls:

1. Select a tower from the top-right buttons.
2. Click a lane position to send `BUY_TOWER`.
3. Click an existing tower to send `SELL_TOWER` and receive half its cost back.

The character artwork is original project artwork stored in `cliente_godot/assets/characters/`; the attached images are visual references only.

For a complete local match, start the server and open `cliente_godot/scenes/Main.tscn` from two Godot clients. Enter the server address, press `Connect` in both clients, select towers and defend all ten waves.

## Protocol

Messages use JSON with a four-byte big-endian length prefix:

```json
{"type": "MESSAGE_TYPE", "payload": {}}
```

The Python implementation lives in `servidor/protocol.py`; the matching Godot constants live in `cliente_godot/scripts/protocol_constants.gd`.

## Sprint 0

The completed items and the full validation procedure are documented in [`docs/sprint-0-status.md`](docs/sprint-0-status.md).

## Sprint 1

The implementation status and reproducible process validation are documented in [`docs/sprint-1-status.md`](docs/sprint-1-status.md).

## Sprint 2

The implementation status, test coverage and known pre-lock race are documented in [`docs/sprint-2-status.md`](docs/sprint-2-status.md).
