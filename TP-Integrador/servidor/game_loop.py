"""Authoritative 20 Hz game loop for Sprint 2."""

from __future__ import annotations

import queue
import threading
import time
from typing import Any

from servidor.constants import (
  BASE_DAMAGE_PER_ENEMY,
  GAME_TICK_SECONDS,
  MAX_PLAYERS,
  MIN_PLAYERS,
  READY_BARRIER_TIMEOUT_SECONDS,
  TOTAL_WAVES,
)
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
  BASE_DAMAGE,
  ERROR,
  GAME_OVER,
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
  """Consume queues and broadcast authoritative synchronized state."""

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
    self.clients_lock = server.clients_lock
    self.ready_players: set[int] = set()
    self.clients: dict[int, ClientConnection] = {}
    self.participants: set[int] = set()
    self.roster_locked = False
    self.start_barrier: threading.Barrier | None = None
    self.game_over_sent = False
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
      reached = self.state.advance_enemies(GAME_TICK_SECONDS)
      self._handle_reached_enemies(reached)
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
      self._add_client(command.client)
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
    except (KeyError, TypeError) as error:
      self._send_error(client, "INVALID_MESSAGE", "Invalid message payload")
    except ValueError as error:
      code = str(error)
      self._send_error(client, code, self._error_message(code))

  def _handle_hello(self, client: ClientConnection, payload: dict) -> None:
    name = payload.get("name", f"player-{client.player_id}")
    if not isinstance(name, str) or not name.strip():
      raise ValueError("INVALID_NAME")
    client.name = name.strip()
    with self.server.clients_lock:
      player_count = len(self.clients)
    self.server.send(client, WELCOME, {
      "player_id": client.player_id,
      "players": player_count,
      "min_players": MIN_PLAYERS,
      "game_started": self.roster_locked,
    })

  def _handle_ready(self, client: ClientConnection, _payload: dict) -> None:
    if self.roster_locked and client.player_id not in self.participants:
      raise ValueError("GAME_ALREADY_STARTED")
    self.ready_players.add(client.player_id)
    if len(self.ready_players) >= MIN_PLAYERS:
      self._lock_roster()

  def _handle_buy(self, client: ClientConnection, payload: dict) -> None:
    self._require_participant(client)
    tower_type = payload["tower_type"]
    lane = payload["lane"]
    raw_position = payload["pos"]
    if not isinstance(raw_position, (list, tuple)):
      raise ValueError("INVALID_POSITION")
    position = tuple(raw_position)
    self.state.buy_tower(tower_type, lane, position)

  def _handle_sell(self, client: ClientConnection, payload: dict) -> None:
    self._require_participant(client)
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

  def _handle_reached_enemies(self, enemies: list) -> None:
    for enemy in enemies:
      base_hp = self.state.damage_base(BASE_DAMAGE_PER_ENEMY)
      self.server.broadcast(BASE_DAMAGE, {
        "enemy_id": enemy.enemy_id,
        "enemy_type": enemy.enemy_type,
        "damage": BASE_DAMAGE_PER_ENEMY,
        "base_hp": base_hp,
      }, self.clients)
      if base_hp <= 0:
        self._finish_game("DEFEAT", "BASE_DESTROYED")
        return

  def _broadcast_state(self) -> None:
    if self.clients:
      self.server.broadcast(STATE_UPDATE, self.state.snapshot(), self.clients)

  def _complete_wave_if_idle(self) -> None:
    if self.state.current_wave and not self.state.enemies and self.enemy_queue.empty():
      if self.state.current_wave >= TOTAL_WAVES:
        self._finish_game("VICTORY", "ALL_WAVES_CLEARED")
      else:
        self.wave_complete_event.set()

  def _remove_client(self, client: ClientConnection) -> None:
    with self.server.clients_lock:
      self.clients.pop(client.player_id, None)
      self.ready_players.discard(client.player_id)
    self.server.unregister(client)
    self.server.close_connection(client)

  def _add_client(self, client: ClientConnection) -> None:
    with self.server.clients_lock:
      if len(self.clients) >= MAX_PLAYERS:
        reject = True
      else:
        self.clients[client.player_id] = client
        reject = False
    if reject:
      self._send_error(client, "MAX_PLAYERS", "The game is full")
      self.server.close_connection(client)

  def _lock_roster(self) -> None:
    if self.roster_locked:
      return
    with self.server.clients_lock:
      roster = tuple(
        player_id for player_id in sorted(self.ready_players)
        if player_id in self.clients
      )
      if len(roster) < MIN_PLAYERS:
        return
      self.participants = set(roster)
      self.roster_locked = True
      self.start_barrier = threading.Barrier(len(roster))
    for player_id in roster:
      threading.Thread(
        target=self._arrive_at_start_barrier,
        args=(player_id,),
        name=f"ready_barrier_{player_id}",
        daemon=True,
      ).start()

  def _arrive_at_start_barrier(self, _player_id: int) -> None:
    if self.start_barrier is None:
      return
    try:
      self.start_barrier.wait(timeout=READY_BARRIER_TIMEOUT_SECONDS)
    except threading.BrokenBarrierError:
      return
    self.ready_event.set()

  def _require_participant(self, client: ClientConnection) -> None:
    if self.roster_locked and client.player_id not in self.participants:
      raise ValueError("GAME_ALREADY_STARTED")

  def _finish_game(self, result: str, reason: str) -> None:
    if self.game_over_sent:
      return
    self.game_over_sent = True
    self.server.broadcast(GAME_OVER, {
      "result": result,
      "reason": reason,
      "wave": self.state.current_wave,
    }, self.clients)
    self.stop_event.set()

  def _send_error(self, client: ClientConnection, code: str, message: str) -> None:
    self.server.send(client, ERROR, {"code": code, "message": message})

  @staticmethod
  def _error_message(code: str) -> str:
    messages = {
      "INSUFFICIENT_GOLD": "The team does not have enough gold",
      "POSITION_OCCUPIED": "That tower position is occupied",
      "INVALID_TOWER_TYPE": "The tower type is invalid",
      "INVALID_LANE": "The lane is invalid",
      "INVALID_POSITION": "The tower position is invalid",
      "TOWER_NOT_FOUND": "The tower does not exist",
      "GAME_ALREADY_STARTED": "The game has already started",
    }
    return messages.get(code, "Invalid message payload")

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
