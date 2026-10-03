"""Domain models and explicit state machines for the airline simulation."""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass, field
from enum import Enum


MAX_WAIT_REAL_SECONDS = 0.25


class PlaneStatus(Enum):
  AVAILABLE = "AVAILABLE"
  ASSIGNED = "ASSIGNED"
  IN_FLIGHT = "IN_FLIGHT"
  TURNAROUND = "TURNAROUND"
  MAINTENANCE = "MAINTENANCE"


class FlightStatus(Enum):
  PENDING = "PENDING"
  ASSIGNED = "ASSIGNED"
  IN_PROGRESS = "IN_PROGRESS"
  COMPLETED = "COMPLETED"
  CANCELLED = "CANCELLED"
  DELAYED = "DELAYED"


class Priority(Enum):
  EMERGENCY = (4, "EMERGENCY")
  VIP = (3, "VIP")
  REGULAR = (2, "REGULAR")
  CARGO = (1, "CARGO")

  @property
  def weight(self):
    return self.value[0]


PLANE_TRANSITIONS = {
  PlaneStatus.AVAILABLE: {PlaneStatus.ASSIGNED, PlaneStatus.MAINTENANCE},
  PlaneStatus.ASSIGNED: {PlaneStatus.IN_FLIGHT, PlaneStatus.AVAILABLE,
                         PlaneStatus.MAINTENANCE},
  PlaneStatus.IN_FLIGHT: {PlaneStatus.TURNAROUND, PlaneStatus.MAINTENANCE,
                          PlaneStatus.AVAILABLE},
  PlaneStatus.TURNAROUND: {PlaneStatus.AVAILABLE, PlaneStatus.MAINTENANCE},
  PlaneStatus.MAINTENANCE: {PlaneStatus.AVAILABLE},
}


FLIGHT_TRANSITIONS = {
  FlightStatus.PENDING: {FlightStatus.ASSIGNED, FlightStatus.CANCELLED},
  FlightStatus.ASSIGNED: {FlightStatus.IN_PROGRESS, FlightStatus.PENDING,
                          FlightStatus.CANCELLED, FlightStatus.DELAYED},
  FlightStatus.DELAYED: {FlightStatus.ASSIGNED, FlightStatus.PENDING,
                         FlightStatus.CANCELLED, FlightStatus.IN_PROGRESS},
  FlightStatus.IN_PROGRESS: {FlightStatus.COMPLETED, FlightStatus.CANCELLED},
  FlightStatus.COMPLETED: set(),
  FlightStatus.CANCELLED: set(),
}


class InvalidTransition(RuntimeError):
  """Raised when a state machine transition is not explicitly allowed."""


@dataclass
class Plane:
  plane_id: str
  model: str
  capacity: int
  range_km: int
  current_airport: str
  status: PlaneStatus = PlaneStatus.AVAILABLE
  active_flight_id: str | None = None
  available_since: float = 0.0
  lock: threading.RLock = field(default_factory=threading.RLock,
                                repr=False, compare=False)

  def transition(self, new_status):
    allowed = PLANE_TRANSITIONS[self.status]
    if new_status not in allowed:
      raise InvalidTransition(f"{self.status.value} -> {new_status.value}")
    self.status = new_status


@dataclass
class Flight:
  flight_id: str
  origin: str
  destination: str
  scheduled_departure: float
  duration_minutes: float
  passengers: int
  priority: Priority
  created_at: float
  status: FlightStatus = FlightStatus.PENDING
  assigned_plane_id: str | None = None
  delay_minutes: float = 0.0
  started_at: float | None = None
  completed_at: float | None = None
  cancelled_reason: str | None = None

  def transition(self, new_status):
    allowed = FLIGHT_TRANSITIONS[self.status]
    if new_status not in allowed:
      raise InvalidTransition(f"{self.status.value} -> {new_status.value}")
    self.status = new_status

  def effective_priority(self, now, aging_minutes):
    age = max(0.0, now - self.created_at)
    return self.priority.weight + age / aging_minutes


@dataclass(frozen=True)
class SimulationClock:
  minutes_per_real_second: float
  started_at: float = field(default_factory=time.monotonic)

  def now(self):
    elapsed = time.monotonic() - self.started_at
    return elapsed * self.minutes_per_real_second

  def real_seconds(self, simulated_minutes):
    return simulated_minutes / self.minutes_per_real_second

  def wait_until(self, target_minutes, stop_event):
    while not stop_event.is_set() and self.now() < target_minutes:
      remaining = target_minutes - self.now()
      stop_event.wait(min(self.real_seconds(remaining), MAX_WAIT_REAL_SECONDS))
    return not stop_event.is_set()

  def wait_sim(self, simulated_minutes, stop_event):
    return not stop_event.wait(self.real_seconds(simulated_minutes))
