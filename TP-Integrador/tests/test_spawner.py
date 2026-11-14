"""Tests for the Sprint 2 enemy producer."""

import queue
import threading

from servidor.game_state import Enemy
from servidor.constants import ENEMY_STATS
from servidor.spawner import EnemySpawner, WaveStart


def _single_enemy_wave(_worker: object, _wave: int) -> dict:
  return {
    "wave": 1,
    "enemies": [{"type": "DISCOUNT_CHILD", "count": 1}],
  }


def test_spawner_enqueues_wave_and_enemy(monkeypatch) -> None:
  enemy_queue = queue.Queue()
  ready_event, stop_event = threading.Event(), threading.Event()
  monkeypatch.setattr("servidor.spawner.request_wave", _single_enemy_wave)
  spawner = EnemySpawner(
    enemy_queue, object(), ready_event, threading.Event(), stop_event
  )

  ready_event.set()
  spawner.start()
  first, second = (enemy_queue.get(timeout=2) for _ in range(2))
  stop_event.set()
  spawner.join()

  assert isinstance(first, WaveStart)
  assert isinstance(second, Enemy)
  assert second.enemy_type == "DISCOUNT_CHILD"
  assert second.health == ENEMY_STATS["DISCOUNT_CHILD"]["health"]
