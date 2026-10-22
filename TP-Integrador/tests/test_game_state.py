"""Tests for the authoritative game state models."""

import threading

from servidor.constants import BASE_DAMAGE_PER_ENEMY, INITIAL_BASE_HP, INITIAL_GOLD
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
  first.towers.append(Tower(1, "MOPPER", 0, (10.0, 20.0)))
  first.enemies.append(Enemy(1, "DISCOUNT_CHILD", 30, 0, (0.0, 0.0)))

  assert second.towers == []
  assert second.enemies == []


def test_game_state_buys_and_serializes_a_tower() -> None:
  state = GameState()

  tower = state.buy_tower("MOPPER", 1, (100.0, 200.0))

  assert tower.tower_id == 1
  assert state.gold == 150
  assert state.snapshot()["towers"] == [{
    "tower_id": 1,
    "tower_type": "MOPPER",
    "lane": 1,
    "pos": [100.0, 200.0],
  }]


def test_purchase_race_accepts_only_one_tower() -> None:
  state = GameState(gold=50)
  start_barrier = threading.Barrier(3)
  errors: list[str] = []

  def buy(position: tuple[float, float]) -> None:
    try:
      start_barrier.wait(timeout=2)
      state.buy_tower("MOPPER", 0, position)
    except ValueError as error:
      errors.append(str(error))

  threads = [threading.Thread(target=buy, args=((10.0 + index, 20.0),))
             for index in range(2)]
  for thread in threads:
    thread.start()
  start_barrier.wait(timeout=2)
  for thread in threads:
    thread.join(timeout=3)

  assert errors == ["INSUFFICIENT_GOLD"]
  assert len(state.towers) == 1
  assert state.gold == 0


def test_position_is_rejected_atomically() -> None:
  state = GameState()
  state.buy_tower("MOPPER", 0, (10.0, 20.0))

  try:
    state.buy_tower("STOCK_REPLENISHER", 0, (10.0, 20.0))
  except ValueError as error:
    assert str(error) == "POSITION_OCCUPIED"
  else:  # pragma: no cover - assertion diagnostics
    raise AssertionError("occupied position was accepted")


def test_invalid_tower_fields_are_rejected() -> None:
  state = GameState()
  invalid_inputs = [
    ("INVALID", 0, (10.0, 20.0), "INVALID_TOWER_TYPE"),
    ("MOPPER", 3, (10.0, 20.0), "INVALID_LANE"),
    ("MOPPER", 0, (10.0,), "INVALID_POSITION"),
  ]

  for tower_type, lane, position, code in invalid_inputs:
    try:
      state.buy_tower(tower_type, lane, position)
    except ValueError as error:
      assert str(error) == code
    else:  # pragma: no cover - assertion diagnostics
      raise AssertionError(f"invalid input was accepted: {code}")


def test_concurrent_sale_refunds_once() -> None:
  state = GameState()
  tower = state.buy_tower("MOPPER", 0, (10.0, 20.0))
  errors: list[str] = []

  def sell() -> None:
    try:
      state.sell_tower(tower.tower_id)
    except ValueError as error:
      errors.append(str(error))

  threads = [threading.Thread(target=sell) for _ in range(2)]
  for thread in threads:
    thread.start()
  for thread in threads:
    thread.join(timeout=2)

  assert errors == ["TOWER_NOT_FOUND"]
  assert state.gold == 175


def test_concurrent_rewards_are_not_lost() -> None:
  state = GameState()
  threads = [threading.Thread(
    target=state.reward_enemy, args=("DISCOUNT_CHILD",)
  ) for _ in range(20)]
  for thread in threads:
    thread.start()
  for thread in threads:
    thread.join(timeout=2)

  assert state.gold == INITIAL_GOLD + 20 * 5


def test_defeated_enemy_is_removed_and_rewarded_once() -> None:
  state = GameState()
  state.enemies.append(Enemy(1, "DISCOUNT_CHILD", 0, 0, (0.0, 0.0)))

  assert state.defeat_enemy(1) == 5
  try:
    state.defeat_enemy(1)
  except ValueError as error:
    assert str(error) == "ENEMY_NOT_FOUND"
  else:  # pragma: no cover - assertion diagnostics
    raise AssertionError("defeated enemy was rewarded twice")


def test_concurrent_base_damage_is_clamped_at_zero() -> None:
  state = GameState()
  threads = [threading.Thread(
    target=state.damage_base, args=(BASE_DAMAGE_PER_ENEMY,)
  ) for _ in range(20)]
  for thread in threads:
    thread.start()
  for thread in threads:
    thread.join(timeout=2)

  assert state.base_hp == 0


def test_tower_attack_defeats_and_rewards_enemy() -> None:
  state = GameState()
  state.buy_tower("MOPPER", 0, (10.0, 20.0))
  state.enemies.append(Enemy(1, "DISCOUNT_CHILD", 10, 0, (5.0, 0.0)))

  assert state.resolve_attacks(0.05) == [1]
  assert state.gold == INITIAL_GOLD - 50 + 5
  assert state.enemies == []


def test_audio_tower_stuns_without_moving_enemy() -> None:
  state = GameState()
  state.buy_tower("AUDIO_TOWER", 1, (10.0, 20.0))
  enemy = Enemy(1, "DISCOUNT_CHILD", 30, 1, (5.0, 1.0))
  state.enemies.append(enemy)

  state.resolve_attacks(0.05)
  position = enemy.position
  enemy.advance(0.05)

  assert enemy.stun_remaining > 0
  assert enemy.position == position
