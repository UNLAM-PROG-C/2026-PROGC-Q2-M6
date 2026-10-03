"""Shared state, scheduling policy, synchronization and invariant checks."""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass

from models import (FLIGHT_TRANSITIONS, Flight, FlightStatus, Plane,
                    PlaneStatus, SimulationClock)


LOGGER = logging.getLogger("airline.scheduler")
CONDITION_TIMEOUT_SECONDS = 0.25
LOG_HISTORY_LIMIT = 200
RANGE_PER_MINUTE_KM = 100


@dataclass(frozen=True)
class SchedulerConfig:
  aging_minutes: float = 10.0
  starvation_limit_minutes: float = 300.0
  turnaround_minutes: float = 3.0


class SharedState:
  """Single consistent state protected by a condition and per-plane locks."""

  def __init__(self, planes, clock):
    self.planes = {plane.plane_id: plane for plane in planes}
    self.flights = {}
    self.clock = clock
    self.lock = threading.RLock()
    self.condition = threading.Condition(self.lock)
    self.operation_log = []
    self.log_lock = threading.Lock()

  def record(self, message):
    with self.log_lock:
      self.operation_log.append(message)

  def snapshot(self):
    with self.condition:
      locks = self.acquire_plane_locks(self.planes)
      try:
        return self._copy_snapshot()
      finally:
        self.release_plane_locks(locks)

  def acquire_plane_locks(self, planes):
    ordered = sorted(planes.values(), key=lambda item: item.plane_id)
    for plane in ordered:
      plane.lock.acquire()
    return ordered

  def release_plane_locks(self, planes):
    for plane in reversed(planes):
      plane.lock.release()

  def _copy_snapshot(self):
    planes = [self._plane_view(plane) for plane in self.planes.values()]
    flights = [self._flight_view(flight) for flight in self.flights.values()]
    with self.log_lock:
      operations = self.operation_log[-LOG_HISTORY_LIMIT:]
    return {"simulated_minutes": self.clock.now(), "planes": planes,
            "flights": flights, "operations": operations}

  @staticmethod
  def _plane_view(plane):
    return {"id": plane.plane_id, "model": plane.model,
            "capacity": plane.capacity, "range_km": plane.range_km,
            "airport": plane.current_airport, "status": plane.status.value,
            "flight": plane.active_flight_id}

  @staticmethod
  def _flight_view(flight):
    return {"id": flight.flight_id, "origin": flight.origin,
            "destination": flight.destination,
            "departure": round(flight.scheduled_departure, 2),
            "duration": flight.duration_minutes,
            "passengers": flight.passengers, "priority": flight.priority.name,
            "status": flight.status.value, "plane": flight.assigned_plane_id,
            "delay": round(flight.delay_minutes, 2)}


class Scheduler:
  def __init__(self, state, config):
    self.state = state
    self.config = config

  def register(self, flight):
    with self.state.condition:
      self.state.flights[flight.flight_id] = flight
      self._log(f"flight {flight.flight_id} arrived as {flight.priority.name}")
      self.state.condition.notify_all()

  def assign_one(self):
    with self.state.condition:
      candidate = self._select_flight()
      if candidate is None:
        return False
      plane = self._select_plane(candidate)
      if plane is None:
        return False
      self._assign(candidate, plane)
      self.state.condition.notify_all()
      return True

  def wait_for_work(self, stop_event):
    with self.state.condition:
      if not stop_event.is_set():
        self.state.condition.wait(timeout=CONDITION_TIMEOUT_SECONDS)

  def wait_for_plane(self, plane_id, stop_event):
    with self.state.condition:
      while not stop_event.is_set():
        plane = self.state.planes[plane_id]
        if plane.status == PlaneStatus.ASSIGNED:
          return plane.active_flight_id
        self.state.condition.wait(timeout=CONDITION_TIMEOUT_SECONDS)
    return None

  def claim_flight(self, plane_id):
    with self.state.condition:
      plane = self.state.planes[plane_id]
      with plane.lock:
        if plane.status != PlaneStatus.ASSIGNED:
          return None
        flight = self.state.flights[plane.active_flight_id]
        if flight.status not in (FlightStatus.ASSIGNED, FlightStatus.DELAYED):
          return None
        self._transition_flight(flight, FlightStatus.IN_PROGRESS, plane_id)
        self._transition_plane(plane, PlaneStatus.IN_FLIGHT, flight.flight_id)
        flight.started_at = self.state.clock.now()
        self.state.condition.notify_all()
        return flight

  def complete_flight(self, plane_id, flight_id):
    with self.state.condition:
      plane = self.state.planes[plane_id]
      with plane.lock:
        flight = self.state.flights[flight_id]
        if flight.status == FlightStatus.IN_PROGRESS:
          self._transition_flight(flight, FlightStatus.COMPLETED, plane_id)
          flight.completed_at = self.state.clock.now()
        plane.current_airport = flight.destination
        self._transition_plane(plane, PlaneStatus.TURNAROUND, flight_id)
        self.state.condition.notify_all()

  def finish_turnaround(self, plane_id, flight_id):
    with self.state.condition:
      plane = self.state.planes[plane_id]
      with plane.lock:
        plane.active_flight_id = None
        plane.available_since = self.state.clock.now()
        self._transition_plane(plane, PlaneStatus.AVAILABLE, flight_id)
        self.state.condition.notify_all()

  def abort_plane_job(self, plane_id, flight_id):
    with self.state.condition:
      plane = self.state.planes[plane_id]
      with plane.lock:
        flight = self.state.flights.get(flight_id)
        if flight and flight.status == FlightStatus.IN_PROGRESS:
          self._transition_flight(flight, FlightStatus.CANCELLED, plane_id)
        plane.active_flight_id = None
        if plane.status != PlaneStatus.MAINTENANCE:
          self._transition_plane(plane, PlaneStatus.AVAILABLE, flight_id)
        self.state.condition.notify_all()

  def place_maintenance(self, plane_id, reason):
    with self.state.condition:
      plane = self.state.planes.get(plane_id)
      if plane is None:
        return False
      with plane.lock:
        if plane.status == PlaneStatus.IN_FLIGHT:
          return False
        self._unassign_for_maintenance(plane)
        self._transition_plane(plane, PlaneStatus.MAINTENANCE, reason)
        self.state.condition.notify_all()
        return True

  def release_maintenance(self, plane_id):
    with self.state.condition:
      plane = self.state.planes[plane_id]
      with plane.lock:
        if plane.status != PlaneStatus.MAINTENANCE:
          return False
        plane.available_since = self.state.clock.now()
        self._transition_plane(plane, PlaneStatus.AVAILABLE, "maintenance")
        self.state.condition.notify_all()
        return True

  def cancel_pending(self, reason):
    with self.state.condition:
      for flight in self.state.flights.values():
        if flight.status == FlightStatus.PENDING:
          self._transition_flight(flight, FlightStatus.CANCELLED, "shutdown")
          flight.cancelled_reason = reason
      self.state.condition.notify_all()

  def cancel_random_flight(self, flight_id, reason):
    with self.state.condition:
      flight = self.state.flights.get(flight_id)
      cancellable = (FlightStatus.PENDING, FlightStatus.ASSIGNED,
                     FlightStatus.DELAYED)
      if not flight or flight.status not in cancellable:
        return False
      plane = self.state.planes.get(flight.assigned_plane_id)
      locks = self.state.acquire_plane_locks({plane.plane_id: plane}) if plane else []
      try:
        self._cancel(flight, plane, reason)
      finally:
        self.state.release_plane_locks(locks)
      self.state.condition.notify_all()
      return True

  def delay_flight(self, flight_id, delay_minutes):
    with self.state.condition:
      flight = self.state.flights.get(flight_id)
      if not flight or flight.status in (FlightStatus.COMPLETED,
                                         FlightStatus.CANCELLED):
        return False
      flight.scheduled_departure += delay_minutes
      flight.delay_minutes += delay_minutes
      if flight.status == FlightStatus.ASSIGNED:
        self._transition_flight(flight, FlightStatus.DELAYED,
                                flight.assigned_plane_id or "external")
      self._log(f"delay {flight.flight_id}: +{delay_minutes:.1f} simulated minutes")
      self.state.condition.notify_all()
      return True

  def verify_invariants(self):
    with self.state.condition:
      locks = self.state.acquire_plane_locks(self.state.planes)
      try:
        self._assert_invariants()
      finally:
        self.state.release_plane_locks(locks)

  def _select_flight(self):
    pending = [flight for flight in self.state.flights.values()
               if flight.status == FlightStatus.PENDING]
    compatible = [flight for flight in pending if self._select_plane(flight)]
    if not compatible:
      return None
    now = self.state.clock.now()
    return max(compatible, key=lambda item: (
        item.effective_priority(now, self.config.aging_minutes),
        -item.scheduled_departure, item.flight_id))

  def _select_plane(self, flight):
    available = [plane for plane in self.state.planes.values()
                 if self._compatible(plane, flight)]
    return min(available, key=lambda item: self._plane_score(item, flight),
               default=None)

  @staticmethod
  def _compatible(plane, flight):
    return (plane.status == PlaneStatus.AVAILABLE
            and plane.current_airport == flight.origin
            and plane.capacity >= flight.passengers
            and plane.range_km >= RANGE_PER_MINUTE_KM * flight.duration_minutes)

  @staticmethod
  def _plane_score(plane, flight):
    idle = abs(plane.available_since - flight.scheduled_departure)
    spare_capacity = plane.capacity - flight.passengers
    return idle, spare_capacity, plane.plane_id

  def _assign(self, flight, plane):
    with plane.lock:
      self._align_departure(flight, plane)
      self._transition_flight(flight, FlightStatus.ASSIGNED, plane.plane_id)
      flight.assigned_plane_id = plane.plane_id
      plane.active_flight_id = flight.flight_id
      self._transition_plane(plane, PlaneStatus.ASSIGNED, flight.flight_id)
      self._log(f"assigned {flight.flight_id} to {plane.plane_id}")

  def _align_departure(self, flight, plane):
    if flight.scheduled_departure >= plane.available_since:
      return
    delay = plane.available_since - flight.scheduled_departure
    flight.scheduled_departure = plane.available_since
    flight.delay_minutes += delay
    self._log(f"delay {flight.flight_id}: +{delay:.1f} for {plane.plane_id}")

  def _unassign_for_maintenance(self, plane):
    if plane.active_flight_id is None:
      return
    flight = self.state.flights[plane.active_flight_id]
    if flight.status in (FlightStatus.ASSIGNED, FlightStatus.DELAYED):
      self._transition_flight(flight, FlightStatus.PENDING, plane.plane_id)
      flight.assigned_plane_id = None
      self._log(f"reassigned {flight.flight_id}: {plane.plane_id} entered maintenance")
    plane.active_flight_id = None

  def _cancel(self, flight, plane, reason):
    if flight.status in (FlightStatus.ASSIGNED, FlightStatus.DELAYED):
      self._transition_flight(flight, FlightStatus.CANCELLED,
                              flight.assigned_plane_id or "external")
      if plane:
        plane.active_flight_id = None
        self._transition_plane(plane, PlaneStatus.AVAILABLE, flight.flight_id)
    else:
      self._transition_flight(flight, FlightStatus.CANCELLED,
                              flight.assigned_plane_id or "external")
    flight.cancelled_reason = reason
    self._log(f"cancelled {flight.flight_id}: {reason}")

  def _assert_invariants(self):
    self._assert_plane_counts()
    self._assert_assignments()
    self._assert_no_overlaps()
    self._assert_waiting_bound()

  def _assert_plane_counts(self):
    counts = {status: 0 for status in PlaneStatus}
    for plane in self.state.planes.values():
      counts[plane.status] += 1
    assert sum(counts.values()) == len(self.state.planes), counts

  def _assert_assignments(self):
    seen = set()
    for plane in self.state.planes.values():
      if plane.status == PlaneStatus.MAINTENANCE:
        assert plane.active_flight_id is None, f"maintenance:{plane.plane_id}"
      if plane.active_flight_id:
        assert plane.active_flight_id not in seen, plane.active_flight_id
        seen.add(plane.active_flight_id)
        self._assert_plane_link(plane)
    self._assert_flight_links(seen)

  def _assert_plane_link(self, plane):
    flight = self.state.flights[plane.active_flight_id]
    message = f"link:{plane.plane_id}:{flight.flight_id}:{flight.assigned_plane_id}"
    assert flight.assigned_plane_id == plane.plane_id, message

  def _assert_flight_links(self, seen):
    active = (FlightStatus.ASSIGNED, FlightStatus.DELAYED,
              FlightStatus.IN_PROGRESS)
    for flight in self.state.flights.values():
      if flight.assigned_plane_id:
        assert flight.assigned_plane_id in self.state.planes, flight.flight_id
        if flight.status in active:
          assert flight.flight_id in seen, flight.flight_id

  def _assert_no_overlaps(self):
    last_end = {}
    flights = sorted(self.state.flights.values(),
                     key=lambda item: item.scheduled_departure)
    for flight in flights:
      plane_id = flight.assigned_plane_id
      if plane_id is None:
        continue
      previous_end = last_end.get(plane_id, float("-inf"))
      assert flight.scheduled_departure >= previous_end, flight.flight_id
      last_end[plane_id] = flight.scheduled_departure + flight.duration_minutes

  def _assert_waiting_bound(self):
    now = self.state.clock.now()
    for flight in self.state.flights.values():
      if flight.status != FlightStatus.PENDING:
        continue
      if now - flight.created_at > self.config.starvation_limit_minutes:
        assert self._select_plane(flight) is None, flight.flight_id

  def _transition_plane(self, plane, new_status, flight_id):
    old = plane.status.value
    plane.transition(new_status)
    self._log(f"plane {plane.plane_id}: {old} -> {new_status.value} ({flight_id})")

  def _transition_flight(self, flight, new_status, plane_id):
    old = flight.status.value
    flight.transition(new_status)
    if new_status in (FlightStatus.PENDING, FlightStatus.CANCELLED):
      flight.assigned_plane_id = None
    self._log(f"flight {flight.flight_id}: {old} -> {new_status.value} ({plane_id})")

  def _log(self, message):
    LOGGER.info(message)
    self.state.record(message)
