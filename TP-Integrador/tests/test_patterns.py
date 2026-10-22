"""Tests for the Sprint 4 factories and attack strategies."""

from servidor.constants import ENEMY_STATS, TOWER_STATS
from servidor.game_state import Enemy, Tower
from servidor.patterns.attack_strategy import (
  AudioTowerStrategy,
  MopperStrategy,
  StockReplenisherStrategy,
)
from servidor.patterns.enemy_factory import create_enemy
from servidor.patterns.tower_factory import create_tower


def test_character_catalog_matches_sprint_four() -> None:
  assert set(TOWER_STATS) == {
    "MOPPER", "STOCK_REPLENISHER", "AUDIO_TOWER",
  }
  assert set(ENEMY_STATS) == {
    "DISCOUNT_CHILD", "SHOPPING_GRANDMA", "SKATEBOARD_CHILD",
    "ARMORED_GRANDMA", "GOLD_CART_BOSS",
  }
  assert TOWER_STATS["MOPPER"]["cost"] == 50
  assert TOWER_STATS["STOCK_REPLENISHER"]["damage"] == 40
  assert TOWER_STATS["AUDIO_TOWER"]["cooldown_seconds"] == 2.0
  assert ENEMY_STATS["GOLD_CART_BOSS"]["health"] == 500


def test_factories_create_configured_models() -> None:
  tower = create_tower(3, "MOPPER", 1, (30.0, 1.0))
  enemy = create_enemy(4, "SHOPPING_GRANDMA", 2)

  assert tower == Tower(3, "MOPPER", 1, (30.0, 1.0))
  assert enemy == Enemy(4, "SHOPPING_GRANDMA", 80, 2, (0.0, 2.0))


def test_mopper_targets_one_enemy_and_respects_cooldown() -> None:
  tower = Tower(1, "MOPPER", 0, (10.0, 0.0))
  enemies = [
    Enemy(1, "DISCOUNT_CHILD", 30, 0, (2.0, 0.0)),
    Enemy(2, "DISCOUNT_CHILD", 30, 0, (4.0, 0.0)),
  ]
  strategy = MopperStrategy()

  first = strategy.attack(tower, enemies, 0.05)
  second = strategy.attack(tower, enemies, 0.05)

  assert first[0].target_ids == (1,)
  assert first[0].damage == 10
  assert second == []


def test_stock_replenisher_hits_every_enemy_in_lane() -> None:
  tower = Tower(1, "STOCK_REPLENISHER", 0, (10.0, 0.0))
  enemies = [
    Enemy(1, "DISCOUNT_CHILD", 30, 0, (2.0, 0.0)),
    Enemy(2, "DISCOUNT_CHILD", 30, 1, (4.0, 1.0)),
    Enemy(3, "DISCOUNT_CHILD", 30, 0, (6.0, 0.0)),
  ]

  effects = StockReplenisherStrategy().attack(tower, enemies, 0.05)

  assert effects[0].target_ids == (1, 3)
  assert effects[0].damage == 40


def test_audio_tower_adds_stun_effect() -> None:
  tower = Tower(1, "AUDIO_TOWER", 2, (10.0, 2.0))
  enemies = [Enemy(1, "DISCOUNT_CHILD", 30, 2, (2.0, 2.0))]

  effects = AudioTowerStrategy().attack(tower, enemies, 0.05)

  assert effects[0].damage == 15
  assert effects[0].stun_seconds == 0.5
