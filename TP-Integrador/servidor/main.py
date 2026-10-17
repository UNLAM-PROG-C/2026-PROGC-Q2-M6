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
  worker = None
  stop_event = threading.Event()

  def request_shutdown(_signum: int, _frame: object) -> None:
    stop_event.set()

  signal.signal(signal.SIGINT, request_shutdown)
  signal.signal(signal.SIGTERM, request_shutdown)
  try:
    worker = start_wave_worker()
    game_loop = build_game_loop(
      server,
      GameState(),
      queue.Queue(),
      stop_event,
    )
    spawner = EnemySpawner(
      game_loop.enemy_queue,
      worker,
      game_loop.ready_event,
      game_loop.wave_complete_event,
      stop_event,
    )
    print(f"Server listening on {server.address[0]}:{server.address[1]}", flush=True)
    print(f"Parent PID: {os.getpid()}", flush=True)
    print(f"Child PID: {worker.pid}", flush=True)
    server.start()
    game_loop.start()
    spawner.start()
    stop_event.wait()
    print("Shutdown requested", flush=True)
  finally:
    stop_event.set()
    if 'spawner' in locals():
      spawner.join()
    if 'game_loop' in locals():
      game_loop.join()
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
