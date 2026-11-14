"""Factory for authoritative enemy models."""

from servidor.constants import ENEMY_SPAWN_POSITION, ENEMY_STATS
from servidor.game_state import Enemy


def create_enemy(enemy_id: int, enemy_type: str, lane: int) -> Enemy:
  """Create an enemy with the configured starting health."""
  health = ENEMY_STATS[enemy_type]["health"]
  position = (ENEMY_SPAWN_POSITION, float(lane))
  return Enemy(enemy_id, enemy_type, health, lane, position)
