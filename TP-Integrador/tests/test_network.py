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
  BUY_TOWER,
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


@pytest.mark.parametrize("client_count", [2, 3, 4])
def test_ready_client_counts_receive_authoritative_updates(
  running_game,
  client_count: int,
) -> None:
  clients = []
  for index in range(client_count):
    client = socket.create_connection(running_game.address, timeout=2)
    send_message(client, HELLO, {"name": f"player-{index}"})
    assert recv_message(client)["type"] == WELCOME
    clients.append(client)
  for client in clients:
    send_message(client, READY, {})
  try:
    for client in clients:
      state = _read_type(client, STATE_UPDATE)
      assert state["payload"]["current_wave"] >= 0
  finally:
    for client in clients:
      client.close()


def test_late_ready_client_is_rejected(running_game) -> None:
  first = _connect(running_game, "first")
  second = _connect(running_game, "second")
  late = socket.create_connection(running_game.address, timeout=2)
  try:
    assert recv_message(late)["type"] == WELCOME
    send_message(late, READY, {})
    error = _read_type(late, ERROR)
    assert error["payload"]["code"] == "GAME_ALREADY_STARTED"
  finally:
    first.close()
    second.close()
    late.close()


def test_invalid_tower_returns_specific_error(running_game) -> None:
  first = _connect(running_game, "first")
  second = _connect(running_game, "second")
  try:
    send_message(first, BUY_TOWER, {
      "tower_type": "INVALID",
      "lane": 0,
      "pos": [10, 20],
    })
    error = _read_type(first, ERROR)
    assert error["payload"]["code"] == "INVALID_TOWER_TYPE"
  finally:
    first.close()
    second.close()


def test_two_clients_receive_shared_tower_state(running_game) -> None:
  first = _connect(running_game, "first")
  second = _connect(running_game, "second")
  try:
    send_message(first, BUY_TOWER, {
      "tower_type": "MOPPER",
      "lane": 0,
      "pos": [20.0, 0.0],
    })
    state = _read_type(second, STATE_UPDATE)
    towers = state["payload"].get("towers", [])
    assert towers[0]["tower_type"] == "MOPPER"
  finally:
    first.close()
    second.close()
