"""Authoritative game state models for the threaded server."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

from servidor.constants import (
  ENEMY_EXIT_POSITION,
  ENEMY_SPEEDS,
  INITIAL_BASE_HP,
  INITIAL_GOLD,
  LANE_COUNT,
  TOWER_STATS,
)


@dataclass
class Tower:
  """A tower placed by the cooperative team."""

  tower_id: int
  tower_type: str
  lane: int
  position: tuple[float, float]


@dataclass
class Enemy:
  """An enemy currently tracked by the game state."""

  enemy_id: int
  enemy_type: str
  health: int
  lane: int
  position: tuple[float, float]

  def advance(self, elapsed_seconds: float) -> None:
    """Move the enemy according to its configured speed."""
    speed_name = "NORMAL"
    if self.enemy_type in ("ORC", "TROLL"):
      speed_name = "SLOW"
    if self.enemy_type == "RUNNER":
      speed_name = "FAST"
    speed = ENEMY_SPEEDS[speed_name]
    self.position = (
      self.position[0] + speed * elapsed_seconds,
      self.position[1],
    )

  @property
  def reached_base(self) -> bool:
    """Return whether the enemy reached the end of its lane."""
    return self.position[0] >= ENEMY_EXIT_POSITION


@dataclass
class GameState:
  """Mutable game state without synchronization primitives yet."""

  gold: int = INITIAL_GOLD
  base_hp: int = INITIAL_BASE_HP
  current_wave: int = 0
  towers: list[Tower] = field(default_factory=list)
  enemies: list[Enemy] = field(default_factory=list)
  purchase_hook: Callable[[], None] | None = field(
    default=None, repr=False, compare=False
  )

  def buy_tower(
    self,
    tower_type: str,
    lane: int,
    position: tuple[float, float],
  ) -> Tower:
    """Buy and place a tower without synchronization."""
    self._validate_tower(tower_type, lane, position)
    cost = TOWER_STATS[tower_type]["cost"]
    if self.gold < cost:
      raise ValueError("INSUFFICIENT_GOLD")
    if self.purchase_hook is not None:
      self.purchase_hook()
    self.gold -= cost
    tower = Tower(self._next_tower_id(), tower_type, lane, position)
    self.towers.append(tower)
    return tower

  def sell_tower(self, tower_id: int) -> int:
    """Sell a tower and return the refunded gold."""
    for index, tower in enumerate(self.towers):
      if tower.tower_id == tower_id:
        self.towers.pop(index)
        refund = TOWER_STATS[tower.tower_type]["cost"] // 2
        self.gold += refund
        return refund
    raise ValueError("TOWER_NOT_FOUND")

  def add_enemy(self, enemy: Enemy) -> None:
    """Add an enemy received from the producer queue."""
    self.enemies.append(enemy)

  def advance_enemies(self, elapsed_seconds: float) -> None:
    """Move enemies and remove those that leave the play area."""
    for enemy in self.enemies:
      enemy.advance(elapsed_seconds)
    self.enemies = [enemy for enemy in self.enemies if not enemy.reached_base]

  def snapshot(self) -> dict:
    """Return a JSON-compatible copy of the current state."""
    return {
      "gold": self.gold,
      "base_hp": self.base_hp,
      "current_wave": self.current_wave,
      "towers": [self._tower_payload(tower) for tower in self.towers],
      "enemies": [self._enemy_payload(enemy) for enemy in self.enemies],
    }

  def _next_tower_id(self) -> int:
    tower_ids = [tower.tower_id for tower in self.towers]
    return max(tower_ids, default=0) + 1

  @staticmethod
  def _validate_tower(
    tower_type: str,
    lane: int,
    position: tuple[float, float],
  ) -> None:
    if tower_type not in TOWER_STATS:
      raise ValueError("INVALID_TOWER_TYPE")
    if isinstance(lane, bool) or not 0 <= lane < LANE_COUNT:
      raise ValueError("INVALID_LANE")
    if len(position) != 2 or not all(isinstance(value, (int, float)) for value in position):
      raise ValueError("INVALID_POSITION")

  @staticmethod
  def _tower_payload(tower: Tower) -> dict:
    return {
      "tower_id": tower.tower_id,
      "tower_type": tower.tower_type,
      "lane": tower.lane,
      "pos": list(tower.position),
    }

  @staticmethod
  def _enemy_payload(enemy: Enemy) -> dict:
    return {
      "enemy_id": enemy.enemy_id,
      "enemy_type": enemy.enemy_type,
      "health": enemy.health,
      "lane": enemy.lane,
      "pos": list(enemy.position),
    }
