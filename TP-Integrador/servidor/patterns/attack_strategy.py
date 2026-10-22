"""Strategy implementations for each cooperative tower attack."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

from servidor.constants import TOWER_STATS

if TYPE_CHECKING:
  from servidor.game_state import Enemy, Tower


@dataclass(frozen=True)
class AttackEffect:
  """One authoritative effect applied to matching enemies."""

  target_ids: tuple[int, ...]
  damage: int
  stun_seconds: float = 0.0


class AttackStrategy:
  """Base strategy that provides cooldown and lane target helpers."""

  def attack(
    self,
    tower: Tower,
    enemies: list[Enemy],
    elapsed_seconds: float,
  ) -> list[AttackEffect]:
    raise NotImplementedError

  @staticmethod
  def _ready(tower: Tower, elapsed_seconds: float) -> bool:
    tower.cooldown_remaining = max(
      0.0, tower.cooldown_remaining - elapsed_seconds
    )
    if tower.cooldown_remaining > 0:
      return False
    tower.cooldown_remaining = TOWER_STATS[tower.tower_type]["cooldown_seconds"]
    return True

  @staticmethod
  def _lane_enemies(tower: Tower, enemies: list[Enemy]) -> list[Enemy]:
    return sorted(
      (enemy for enemy in enemies if enemy.lane == tower.lane),
      key=lambda enemy: enemy.position[0],
    )


class MopperStrategy(AttackStrategy):
  """Single-target slippery-puddle attack."""

  def attack(self, tower, enemies, elapsed_seconds) -> list[AttackEffect]:
    if not self._ready(tower, elapsed_seconds):
      return []
    targets = self._lane_enemies(tower, enemies)[:1]
    return _effect_for(targets, tower.tower_type)


class StockReplenisherStrategy(AttackStrategy):
  """Heavy line-area attack against one lane."""

  def attack(self, tower, enemies, elapsed_seconds) -> list[AttackEffect]:
    if not self._ready(tower, elapsed_seconds):
      return []
    targets = self._lane_enemies(tower, enemies)
    return _effect_for(targets, tower.tower_type)


class AudioTowerStrategy(AttackStrategy):
  """Sonic attack that damages and briefly stuns a lane."""

  def attack(self, tower, enemies, elapsed_seconds) -> list[AttackEffect]:
    if not self._ready(tower, elapsed_seconds):
      return []
    targets = self._lane_enemies(tower, enemies)
    return _effect_for(targets, tower.tower_type)


def create_attack_strategy(tower_type: str) -> AttackStrategy:
  """Return the strategy associated with a tower type."""
  strategies = {
    "MOPPER": MopperStrategy,
    "STOCK_REPLENISHER": StockReplenisherStrategy,
    "AUDIO_TOWER": AudioTowerStrategy,
  }
  return strategies[tower_type]()


def _effect_for(targets: list[Enemy], tower_type: str) -> list[AttackEffect]:
  if not targets:
    return []
  stats = TOWER_STATS[tower_type]
  stun_seconds = stats.get("stun_seconds", 0.0)
  target_ids = tuple(enemy.enemy_id for enemy in targets)
  return [AttackEffect(target_ids, stats["damage"], stun_seconds)]
