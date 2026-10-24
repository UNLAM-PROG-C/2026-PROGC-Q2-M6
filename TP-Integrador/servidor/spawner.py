"""Producer thread that turns process patterns into enemy objects."""

from __future__ import annotations

import queue
import threading
from dataclasses import dataclass
from typing import Any

from servidor.constants import (
  LANE_COUNT,
  INTER_WAVE_DELAY_SECONDS,
  SPAWN_INTERVAL_SECONDS,
  TOTAL_WAVES,
)
from servidor.game_state import Enemy
from servidor.process_manager import ChildProcess, request_wave, send_stats_update
from servidor.patterns.enemy_factory import create_enemy


@dataclass
class WaveStart:
  """Marker consumed by the game loop before a wave's enemies."""

  wave: int
  pattern: list[dict[str, Any]]


class EnemySpawner:
  """Produce wave markers and enemies on a dedicated thread."""

  def __init__(
    self,
    enemy_queue: queue.Queue[Enemy | WaveStart],
    worker: ChildProcess,
    ready_event: threading.Event,
    wave_complete_event: threading.Event,
    stop_event: threading.Event,
    wave_start_event: threading.Event | None = None,
    match_reset_event: threading.Event | None = None,
  ) -> None:
    self.enemy_queue = enemy_queue
    self.worker = worker
    self.ready_event = ready_event
    self.wave_complete_event = wave_complete_event
    self.stop_event = stop_event
    self.wave_start_event = wave_start_event
    self.match_reset_event = match_reset_event
    self._next_enemy_id = 1
    self.thread = threading.Thread(
      target=self.run,
      name="spawner_thread",
      daemon=True,
    )

  def start(self) -> None:
    """Start the producer thread."""
    self.thread.start()

  def join(self, timeout: float = 2.0) -> None:
    """Wait for the producer thread."""
    self.thread.join(timeout)

  def run(self) -> None:
    """Wait for players and produce all deterministic waves."""
    while not self.stop_event.is_set():
      while not self.stop_event.is_set() and not self.ready_event.wait(0.1):
        pass
      if self.stop_event.is_set():
        return
      if self.wave_start_event is not None:
        while (
          not self.stop_event.is_set()
          and not self.wave_start_event.wait(0.1)
        ):
          pass
        if self.stop_event.is_set():
          return
        pass
        self.wave_start_event.clear()
      reset = False
      for wave in range(1, TOTAL_WAVES + 1):
        if self.stop_event.is_set() or (
          self.match_reset_event is not None and self.match_reset_event.is_set()
        ):
          reset = True
          break
        self._produce_wave(wave)
        if not self._wait_for_wave_completion():
          return
        send_stats_update(self.worker, {
          "wave": wave,
          "enemies_defeated": 0,
        })
        if wave < TOTAL_WAVES and self.stop_event.wait(INTER_WAVE_DELAY_SECONDS):
          return
      if reset:
        if self.match_reset_event is not None:
          self.match_reset_event.clear()
        continue
      self.ready_event.clear()

  def _produce_wave(self, wave: int) -> None:
    pattern = request_wave(self.worker, wave)
    self.enemy_queue.put(WaveStart(wave, pattern["enemies"]))
    for group in pattern["enemies"]:
      for _ in range(group["count"]):
        enemy = self._create_enemy(self._next_enemy_id, group["type"])
        self.enemy_queue.put(enemy)
        self._next_enemy_id += 1
        if self.stop_event.wait(SPAWN_INTERVAL_SECONDS):
          return

  def _wait_for_wave_completion(self) -> bool:
    self.wave_complete_event.clear()
    while not self.stop_event.is_set():
      if self.match_reset_event is not None and self.match_reset_event.is_set():
        return True
      if self.wave_complete_event.wait(0.1):
        return True
    return False

  @staticmethod
  def _create_enemy(enemy_id: int, enemy_type: str) -> Enemy:
    lane = (enemy_id - 1) % LANE_COUNT
    return create_enemy(enemy_id, enemy_type, lane)
