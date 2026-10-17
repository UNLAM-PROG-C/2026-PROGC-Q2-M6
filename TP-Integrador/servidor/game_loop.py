"""Authoritative 20 Hz game loop for Sprint 2."""

from __future__ import annotations

import queue
import threading
import time
from typing import Any

from servidor.constants import GAME_TICK_SECONDS, MIN_PLAYERS
from servidor.game_state import GameState
from servidor.network import (
  CONNECT,
  DISCONNECT,
  INVALID,
  MESSAGE,
  ClientCommand,
  ClientConnection,
  GameServer,
)
from servidor.protocol import (
  BUY_TOWER,
  ERROR,
  PING,
  READY,
  SELL_TOWER,
  STATE_UPDATE,
  WAVE_START,
  WELCOME,
  HELLO,
)
from servidor.spawner import WaveStart


class GameLoop:
  """Consume client and enemy queues and broadcast authoritative state."""

  def __init__(
    self,
    server: GameServer,
    state: GameState,
    enemy_queue: queue.Queue,
    stop_event: threading.Event,
  ) -> None:
    self.server = server
    self.state = state
    self.enemy_queue = enemy_queue
    self.stop_event = stop_event
    self.ready_players: set[int] = set()
    self.clients: dict[int, ClientConnection] = {}
    self.ready_event = threading.Event()
    self.wave_complete_event = threading.Event()
    self.thread = threading.Thread(
      target=self.run,
      name="game_loop_thread",
      daemon=True,
    )

  def start(self) -> None:
    """Start the game loop."""
    self.thread.start()

  def join(self, timeout: float = 2.0) -> None:
    """Wait for the game loop."""
    self.thread.join(timeout)

  def run(self) -> None:
    """Run ticks until the shared stop event is set."""
    next_tick = time.monotonic()
    while not self.stop_event.is_set():
      self._drain_commands()
      self._drain_enemies()
      self.state.advance_enemies(GAME_TICK_SECONDS)
      self._complete_wave_if_idle()
      self._broadcast_state()
      next_tick += GAME_TICK_SECONDS
      self.stop_event.wait(max(0.0, next_tick - time.monotonic()))

  def _drain_commands(self) -> None:
    while True:
      try:
        command = self.server.command_queue.get_nowait()
      except queue.Empty:
        return
      self._handle_command(command)

  def _handle_command(self, command: ClientCommand) -> None:
    if command.kind == CONNECT:
      self.clients[command.client.player_id] = command.client
      return
    if command.kind == DISCONNECT:
      self._remove_client(command.client)
      return
    if command.kind == INVALID:
      self._send_error(command.client, "INVALID_MESSAGE", self._error_text(command))
      return
    if command.kind == MESSAGE and command.message is not None:
      self._handle_message(command.client, command.message)

  def _handle_message(self, client: ClientConnection, message: dict[str, Any]) -> None:
    message_type = message["type"]
    payload = message["payload"]
    handlers = {
      HELLO: self._handle_hello,
      READY: self._handle_ready,
      BUY_TOWER: self._handle_buy,
      SELL_TOWER: self._handle_sell,
      PING: self._handle_ping,
    }
    handler = handlers.get(message_type)
    if handler is None:
      self._send_error(client, "UNKNOWN_MESSAGE", "Unknown client message")
      return
    try:
      handler(client, payload)
    except (KeyError, TypeError, ValueError) as error:
      self._send_error(client, str(error), "Invalid message payload")

  def _handle_hello(self, client: ClientConnection, payload: dict) -> None:
    name = payload.get("name", f"player-{client.player_id}")
    if not isinstance(name, str) or not name.strip():
      raise ValueError("INVALID_NAME")
    client.name = name.strip()
    self.server.send(client, WELCOME, {
      "player_id": client.player_id,
      "players": len(self.clients),
      "min_players": MIN_PLAYERS,
    })

  def _handle_ready(self, client: ClientConnection, _payload: dict) -> None:
    self.ready_players.add(client.player_id)
    if len(self.ready_players) >= MIN_PLAYERS:
      self.ready_event.set()

  def _handle_buy(self, client: ClientConnection, payload: dict) -> None:
    tower_type = payload["tower_type"]
    lane = payload["lane"]
    position = tuple(payload["pos"])
    self.state.buy_tower(tower_type, lane, position)

  def _handle_sell(self, client: ClientConnection, payload: dict) -> None:
    self.state.sell_tower(payload["tower_id"])

  def _handle_ping(self, _client: ClientConnection, _payload: dict) -> None:
    return

  def _drain_enemies(self) -> None:
    while True:
      try:
        event = self.enemy_queue.get_nowait()
      except queue.Empty:
        return
      if isinstance(event, WaveStart):
        self.state.current_wave = event.wave
        self.server.broadcast(WAVE_START, {
          "wave": event.wave,
          "enemies": event.pattern,
        }, self.clients)
      else:
        self.state.add_enemy(event)

  def _broadcast_state(self) -> None:
    if self.clients:
      self.server.broadcast(STATE_UPDATE, self.state.snapshot(), self.clients)

  def _complete_wave_if_idle(self) -> None:
    if self.state.current_wave and not self.state.enemies and self.enemy_queue.empty():
      self.wave_complete_event.set()

  def _remove_client(self, client: ClientConnection) -> None:
    self.clients.pop(client.player_id, None)
    self.ready_players.discard(client.player_id)
    self.server.close_connection(client)

  def _send_error(self, client: ClientConnection, code: str, message: str) -> None:
    self.server.send(client, ERROR, {"code": code, "message": message})

  @staticmethod
  def _error_text(command: ClientCommand) -> str:
    if command.message is None:
      return "Invalid protocol frame"
    return command.message.get("error", "Invalid client message")


def build_game_loop(
  server: GameServer,
  state: GameState,
  enemy_queue: queue.Queue,
  stop_event: threading.Event,
) -> GameLoop:
  """Build a game loop with explicit queues for integration tests."""
  return GameLoop(server, state, enemy_queue, stop_event)
