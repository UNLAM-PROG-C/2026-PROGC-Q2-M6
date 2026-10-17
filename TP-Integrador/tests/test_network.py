"""Integration tests for threaded TCP clients and the game loop."""

import queue
import socket
import threading
import time

import pytest

from servidor.game_loop import build_game_loop
from servidor.game_state import GameState
from servidor.network import GameServer
from servidor.process_manager import shutdown_worker, start_wave_worker
from servidor.protocol import (
  ERROR,
  HELLO,
  READY,
  STATE_UPDATE,
  WELCOME,
  encode_message,
  recv_message,
  send_message,
)
from servidor.spawner import EnemySpawner


@pytest.fixture
def running_game():
  stop_event = threading.Event()
  server = GameServer("127.0.0.1", 0)
  worker = start_wave_worker()
  loop = build_game_loop(server, GameState(), queue.Queue(), stop_event)
  spawner = EnemySpawner(
    loop.enemy_queue,
    worker,
    loop.ready_event,
    loop.wave_complete_event,
    stop_event,
  )
  server.start()
  loop.start()
  spawner.start()
  yield server
  stop_event.set()
  spawner.join()
  loop.join()
  server.stop()
  server.join()
  shutdown_worker(worker)


def _connect(server: GameServer, name: str) -> socket.socket:
  client = socket.create_connection(server.address, timeout=2)
  send_message(client, HELLO, {"name": name})
  assert recv_message(client)["type"] == WELCOME
  send_message(client, READY, {})
  return client


def _read_type(client: socket.socket, message_type: str, timeout: float = 3) -> dict:
  client.settimeout(0.2)
  deadline = time.monotonic() + timeout
  while time.monotonic() < deadline:
    try:
      message = recv_message(client)
    except socket.timeout:
      continue
    if message and message["type"] == message_type:
      return message
  pytest.fail(f"Did not receive {message_type}")


def test_two_clients_receive_state_and_survive_disconnect(running_game) -> None:
  first = _connect(running_game, "first")
  second = _connect(running_game, "second")
  try:
    state = _read_type(second, STATE_UPDATE)
    assert "gold" in state["payload"]
    first.close()
    state_after_disconnect = _read_type(second, STATE_UPDATE)
    assert "base_hp" in state_after_disconnect["payload"]
  finally:
    second.close()


def test_unknown_client_message_returns_error(running_game) -> None:
  client = socket.create_connection(running_game.address, timeout=2)
  try:
    client.sendall(encode_message("UNKNOWN", {}))
    error = _read_type(client, ERROR)
    assert error["payload"]["code"] == "INVALID_MESSAGE"
  finally:
    client.close()
