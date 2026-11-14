"""TCP server entry point and threaded process coordinator."""

from __future__ import annotations

import os
import queue
import signal
import socket
import threading

from servidor.constants import SERVER_HOST, SERVER_PORT
from servidor.game_loop import build_game_loop
from servidor.game_state import GameState
from servidor.network import GameServer, create_listener
from servidor.process_manager import (
  ChildProcess,
  shutdown_worker,
  start_wave_worker,
)
from servidor.spawner import EnemySpawner


def create_server(host: str, port: int) -> socket.socket:
  """Keep the Sprint 0 listener factory available to callers."""
  return create_listener(host, port)


def run_server(host: str, port: int) -> None:
  """Run the threaded parent process until shutdown is requested."""
  server = GameServer(host, port)
  stop_event = threading.Event()
  _install_signal_handlers(stop_event)
  worker, threads = None, []
  try:
    worker = start_wave_worker()
    threads = _build_threads(server, worker, stop_event)
    _log_startup(server, worker)
    server.start()
    for thread in threads:
      thread.start()
    stop_event.wait()
    print("Shutdown requested", flush=True)
  finally:
    _shutdown(server, worker, threads, stop_event)


def _install_signal_handlers(stop_event: threading.Event) -> None:
  def request_shutdown(_signum: int, _frame: object) -> None:
    stop_event.set()

  signal.signal(signal.SIGINT, request_shutdown)
  signal.signal(signal.SIGTERM, request_shutdown)


def _build_threads(
  server: GameServer,
  worker: ChildProcess,
  stop_event: threading.Event,
) -> list:
  """Return [game_loop, spawner] wired to the same events."""
  game_loop = build_game_loop(server, GameState(), queue.Queue(), stop_event)
  spawner = EnemySpawner(
    game_loop.enemy_queue,
    worker,
    game_loop.ready_event,
    game_loop.wave_complete_event,
    stop_event,
    game_loop.wave_start_event,
    game_loop.match_reset_event,
    game_loop.game_over_event,
  )
  return [game_loop, spawner]


def _log_startup(server: GameServer, worker: ChildProcess) -> None:
  host, port = server.address[0], server.address[1]
  print(f"Server listening on {host}:{port}", flush=True)
  print(f"Parent PID: {os.getpid()}", flush=True)
  print(f"Child PID: {worker.pid}", flush=True)


def _shutdown(
  server: GameServer,
  worker: ChildProcess | None,
  threads: list,
  stop_event: threading.Event,
) -> None:
  stop_event.set()
  for thread in reversed(threads):
    thread.join()
  server.stop()
  server.join()
  if worker is not None:
    shutdown_worker(worker)
    print("Child process reaped", flush=True)
  print("Server stopped", flush=True)


def _environment_port() -> int:
  return int(os.getenv("SERVER_PORT", str(SERVER_PORT)))


if __name__ == "__main__":
  run_server(os.getenv("SERVER_HOST", SERVER_HOST), _environment_port())
