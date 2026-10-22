"""Tests for the Sprint 2 enemy producer."""

import queue
import threading

from servidor.game_state import Enemy
from servidor.constants import ENEMY_STATS
from servidor.spawner import EnemySpawner, WaveStart


def test_spawner_enqueues_wave_and_enemy(monkeypatch) -> None:
  enemy_queue = queue.Queue()
  ready_event = threading.Event()
  wave_complete_event = threading.Event()
  stop_event = threading.Event()
  monkeypatch.setattr(
    "servidor.spawner.request_wave",
    lambda _worker, _wave: {
      "wave": 1,
      "enemies": [{"type": "DISCOUNT_CHILD", "count": 1}],
    },
  )
  spawner = EnemySpawner(
    enemy_queue,
    object(),
    ready_event,
    wave_complete_event,
    stop_event,
  )

  ready_event.set()
  spawner.start()
  first = enemy_queue.get(timeout=2)
  second = enemy_queue.get(timeout=2)
  stop_event.set()
  spawner.join()

  assert isinstance(first, WaveStart)
  assert isinstance(second, Enemy)
  assert second.enemy_type == "DISCOUNT_CHILD"
  assert second.health == ENEMY_STATS["DISCOUNT_CHILD"]["health"]
