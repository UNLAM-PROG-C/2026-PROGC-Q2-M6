"""Authoritative game state models for the threaded server."""

from __future__ import annotations

import threading
from dataclasses import dataclass, field
from typing import Callable

from servidor.constants import (
  ENEMY_EXIT_POSITION,
  ENEMY_STATS,
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
  cooldown_remaining: float = 0.0


@dataclass
class Enemy:
  """An enemy currently tracked by the game state."""

  enemy_id: int
  enemy_type: str
  health: int
  lane: int
  position: tuple[float, float]
  stun_remaining: float = 0.0

  def advance(self, elapsed_seconds: float) -> None:
    """Move the enemy according to its configured speed."""
    if self.stun_remaining > 0:
      self.stun_remaining = max(0.0, self.stun_remaining - elapsed_seconds)
      return
    speed_name = ENEMY_STATS[self.enemy_type]["speed"]
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
  """Mutable authoritative state with independently protected resources."""

  gold: int = INITIAL_GOLD
  base_hp: int = INITIAL_BASE_HP
  current_wave: int = 0
  towers: list[Tower] = field(default_factory=list)
  enemies: list[Enemy] = field(default_factory=list)
  purchase_hook: Callable[[], None] | None = field(
    default=None, repr=False, compare=False
  )
  gold_lock: threading.Lock = field(
    default_factory=threading.Lock, init=False, repr=False, compare=False
  )
  base_hp_lock: threading.Lock = field(
    default_factory=threading.Lock, init=False, repr=False, compare=False
  )

  def buy_tower(
    self,
    tower_type: str,
    lane: int,
    position: tuple[float, float],
  ) -> Tower:
    """Atomically validate, charge and place one tower."""
    with self.gold_lock:
      self._validate_tower(tower_type, lane, position)
      if self._position_occupied(lane, position):
        raise ValueError("POSITION_OCCUPIED")
      cost = TOWER_STATS[tower_type]["cost"]
      if self.gold < cost:
        raise ValueError("INSUFFICIENT_GOLD")
      self.gold -= cost
      from servidor.patterns.tower_factory import create_tower

      tower = create_tower(self._next_tower_id(), tower_type, lane, position)
      self.towers.append(tower)
      return tower

  def sell_tower(self, tower_id: int) -> int:
    """Atomically remove a tower and return its refund."""
    with self.gold_lock:
      for index, tower in enumerate(self.towers):
        if tower.tower_id == tower_id:
          self.towers.pop(index)
          refund = TOWER_STATS[tower.tower_type]["cost"] // 2
          self.gold += refund
          return refund
      raise ValueError("TOWER_NOT_FOUND")

  def reward_enemy(self, enemy_type: str) -> int:
    """Credit the configured reward for one defeated enemy."""
    if not isinstance(enemy_type, str) or enemy_type not in ENEMY_STATS:
      raise ValueError("INVALID_ENEMY_TYPE")
    with self.gold_lock:
      reward = ENEMY_STATS[enemy_type]["reward"]
      self.gold += reward
      return reward

  def defeat_enemy(self, enemy_id: int) -> int:
    """Remove one enemy and atomically credit its configured reward."""
    with self.gold_lock:
      for index, enemy in enumerate(self.enemies):
        if enemy.enemy_id == enemy_id:
          self.enemies.pop(index)
          reward = ENEMY_STATS[enemy.enemy_type]["reward"]
          self.gold += reward
          return reward
      raise ValueError("ENEMY_NOT_FOUND")

  def damage_base(self, damage: int) -> int:
    """Apply damage without losing concurrent updates and return HP left."""
    if isinstance(damage, bool) or damage <= 0:
      raise ValueError("INVALID_DAMAGE")
    with self.base_hp_lock:
      self.base_hp = max(0, self.base_hp - damage)
      return self.base_hp

  def resolve_attacks(self, elapsed_seconds: float) -> list[int]:
    """Resolve every tower attack and return defeated enemy IDs."""
    from servidor.patterns.attack_strategy import create_attack_strategy

    defeated: list[int] = []
    for tower in self.towers:
      strategy = create_attack_strategy(tower.tower_type)
      effects = strategy.attack(tower, self.enemies, elapsed_seconds)
      defeated.extend(self._apply_attack_effects(effects))
    return defeated

  def add_enemy(self, enemy: Enemy) -> None:
    """Add an enemy received from the producer queue."""
    self.enemies.append(enemy)

  def reset_match(self) -> None:
    """Restore shared resources for a new match."""
    with self.gold_lock:
      with self.base_hp_lock:
        self.gold = INITIAL_GOLD
        self.base_hp = INITIAL_BASE_HP
        self.current_wave = 0
        self.towers.clear()
        self.enemies.clear()

  def advance_enemies(self, elapsed_seconds: float) -> list[Enemy]:
    """Move enemies and return those that reached the base."""
    for enemy in self.enemies:
      enemy.advance(elapsed_seconds)
    reached = [enemy for enemy in self.enemies if enemy.reached_base]
    self.enemies = [enemy for enemy in self.enemies if not enemy.reached_base]
    return reached

  def snapshot(self) -> dict:
    """Return a JSON-compatible copy of the current state."""
    with self.gold_lock:
      with self.base_hp_lock:
        return self._snapshot_unlocked()

  def _snapshot_unlocked(self) -> dict:
    """Build a snapshot while the resource locks are already held."""
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

  def _position_occupied(
    self,
    lane: int,
    position: tuple[float, float],
  ) -> bool:
    return any(
      tower.lane == lane and tower.position == position
      for tower in self.towers
    )

  @staticmethod
  def _validate_tower(
    tower_type: str,
    lane: int,
    position: tuple[float, float],
  ) -> None:
    if not isinstance(tower_type, str) or tower_type not in TOWER_STATS:
      raise ValueError("INVALID_TOWER_TYPE")
    if not isinstance(lane, int) or isinstance(lane, bool):
      raise ValueError("INVALID_LANE")
    if not 0 <= lane < LANE_COUNT:
      raise ValueError("INVALID_LANE")
    if not isinstance(position, (tuple, list)) or len(position) != 2 or not all(
      type(value) in (int, float) for value in position
    ):
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
      "max_health": ENEMY_STATS[enemy.enemy_type]["health"],
      "lane": enemy.lane,
      "pos": list(enemy.position),
      "stunned": enemy.stun_remaining > 0,
    }

  def _apply_attack_effects(self, effects: list) -> list[int]:
    defeated: list[int] = []
    for effect in effects:
      for enemy in tuple(self.enemies):
        if enemy.enemy_id not in effect.target_ids:
          continue
        enemy.health -= effect.damage
        enemy.stun_remaining = max(enemy.stun_remaining, effect.stun_seconds)
        if enemy.health <= 0:
          enemy_id = enemy.enemy_id
          self.defeat_enemy(enemy_id)
          defeated.append(enemy_id)
    return defeated
