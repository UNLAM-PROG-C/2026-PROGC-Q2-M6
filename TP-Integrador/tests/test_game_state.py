"""Tests for the authoritative game state models."""

import threading

from servidor.constants import INITIAL_BASE_HP, INITIAL_GOLD
from servidor.game_state import Enemy, GameState, Tower


def test_game_state_starts_with_configured_values() -> None:
  state = GameState()

  assert state.gold == INITIAL_GOLD
  assert state.base_hp == INITIAL_BASE_HP
  assert state.current_wave == 0
  assert state.towers == []
  assert state.enemies == []


def test_game_state_collections_are_independent() -> None:
  first = GameState()
  second = GameState()
  first.towers.append(Tower(1, "ARCHER", 0, (10.0, 20.0)))
  first.enemies.append(Enemy(1, "GOBLIN", 30, 0, (0.0, 0.0)))

  assert second.towers == []
  assert second.enemies == []


def test_game_state_buys_and_serializes_a_tower() -> None:
  state = GameState()

  tower = state.buy_tower("ARCHER", 1, (100.0, 200.0))

  assert tower.tower_id == 1
  assert state.gold == 150
  assert state.snapshot()["towers"] == [{
    "tower_id": 1,
    "tower_type": "ARCHER",
    "lane": 1,
    "pos": [100.0, 200.0],
  }]


def test_unsynchronized_purchase_race_is_reproducible() -> None:
  barrier = threading.Barrier(2)
  state = GameState(gold=50, purchase_hook=lambda: barrier.wait(timeout=2))
  errors: list[Exception] = []

  def buy() -> None:
    try:
      state.buy_tower("ARCHER", 0, (10.0, 20.0))
    except Exception as error:  # pragma: no cover - failure diagnostics
      errors.append(error)

  threads = [threading.Thread(target=buy) for _ in range(2)]
  for thread in threads:
    thread.start()
  for thread in threads:
    thread.join(timeout=3)

  assert errors == []
  assert len(state.towers) == 2
  assert state.gold == -50
