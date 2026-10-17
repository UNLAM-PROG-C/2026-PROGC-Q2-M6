# Tower Defense Cooperative

Sprint 2 adds the threaded TCP server, the producer-consumer game loop, the first working Godot network client and a Python bot for concurrent testing. The TCP server remains the parent process and an exec'ed child calculates deterministic wave patterns through two pipes.

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

Run the bot from another terminal after the server is running:

```bash
docker compose run --rm dev python -m tools.bot_client --name bot-1 --duration 30
```

Run two bots to exercise concurrent connections and purchases:

```bash
docker compose run --rm dev python -m tools.bot_client --name bot-1 --seed 1
docker compose run --rm dev python -m tools.bot_client --name bot-2 --seed 2
```

The Godot client can be opened on the host with:

```bash
godot --editor --path cliente_godot
```

Run `Lobby.tscn`, enter the server host and port, and press `Connect`. The lobby logs the connection, `WELCOME`, `STATE_UPDATE` and protocol errors. It does not render gameplay yet.

The Sprint 2 server uses an acceptor thread, one client thread per socket, a producer queue for enemies and a 20 Hz game-loop consumer. Locks are intentionally not used until Sprint 3. The isolated race test demonstrates why the shared gold must be protected:

```bash
docker compose run --rm dev pytest -q tests/test_game_state.py -k race
```

That test is evidence of the pre-lock state: two synchronized purchases can both pass the gold check and leave the balance negative. The live server still applies commands in the game loop, so socket handlers never mutate the state directly.

Run the Sprint 1 tests locally with:

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

The host editor is intentionally outside Docker because the Sprint 0 setup does not configure graphical display forwarding. The project itself is shared through the repository mount and is validated with the Godot container.

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
