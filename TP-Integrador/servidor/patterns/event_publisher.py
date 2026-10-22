"""Small Observer implementation for authoritative game events."""

from collections import defaultdict
from collections.abc import Callable


ENEMY_KILLED = "ENEMY_KILLED"
BASE_DAMAGED = "BASE_DAMAGED"
WAVE_CLEARED = "WAVE_CLEARED"


class EventPublisher:
  """Publish named events to subscribed callbacks."""

  def __init__(self) -> None:
    self._observers: dict[str, list[Callable[[dict], None]]] = defaultdict(list)

  def subscribe(self, event_name: str, callback: Callable[[dict], None]) -> None:
    """Register one callback for an event."""
    self._observers[event_name].append(callback)

  def publish(self, event_name: str, payload: dict) -> None:
    """Notify every observer for an event."""
    for callback in tuple(self._observers[event_name]):
      callback(payload)
