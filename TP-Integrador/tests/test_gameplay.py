"""Tests for Sprint 4 game-over and observer behavior."""

import queue
import threading

from servidor.constants import TOTAL_WAVES
from servidor.game_loop import build_game_loop
from servidor.game_state import Enemy, GameState
from servidor.protocol import GAME_OVER


class RecordingServer:
  """Minimal server double for game-loop event tests."""

  def __init__(self) -> None:
    self.clients_lock = threading.RLock()
    self.messages: list[tuple[str, dict]] = []

  def broadcast(self, message_type, payload, _clients) -> None:
    self.messages.append((message_type, payload))

  def send(self, _client, _message_type, _payload) -> bool:
    return True

  def unregister(self, _client) -> None:
    return

  def close_connection(self, _client) -> None:
    return


def test_clearing_final_wave_publishes_victory() -> None:
  server = RecordingServer()
  stop_event = threading.Event()
  state = GameState(current_wave=TOTAL_WAVES)
  loop = build_game_loop(server, state, queue.Queue(), stop_event)

  loop._complete_wave_if_idle()

  assert server.messages[-1] == (
    GAME_OVER,
    {"result": "VICTORY", "reason": "ALL_WAVES_CLEARED", "wave": 10},
  )
  assert stop_event.is_set()


def test_base_zero_publishes_defeat() -> None:
  server = RecordingServer()
  stop_event = threading.Event()
  state = GameState(base_hp=10)
  loop = build_game_loop(server, state, queue.Queue(), stop_event)

  loop._handle_reached_enemies([
    Enemy(1, "DISCOUNT_CHILD", 30, 0, (100.0, 0.0)),
  ])

  assert server.messages[-1] == (
    GAME_OVER,
    {"result": "DEFEAT", "reason": "BASE_DESTROYED", "wave": 0},
  )
  assert stop_event.is_set()
