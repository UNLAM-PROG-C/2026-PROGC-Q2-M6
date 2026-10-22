"""Factory for authoritative tower models."""

from servidor.game_state import Tower


def create_tower(
  tower_id: int,
  tower_type: str,
  lane: int,
  position: tuple[float, float],
) -> Tower:
  """Create one validated tower model for the game state."""
  return Tower(tower_id, tower_type, lane, position)
