"""Stress tests for shared-state invariants."""

from __future__ import annotations

import queue
import threading
import unittest

from models import (Flight, FlightStatus, InvalidTransition, PlaneStatus,
                    Priority, SimulationClock)
from scheduler import Scheduler, SchedulerConfig, SharedState
from workers import AssignmentWorker, PlaneWorker, build_planes


class StressTests(unittest.TestCase):
  def test_invalid_transition_is_rejected(self):
    plane = build_planes(1, 3)[0]
    with self.assertRaises(InvalidTransition):
      plane.transition(PlaneStatus.IN_FLIGHT)

  def test_flight_machine_has_explicit_states(self):
    flight = self._make_flights(1)[0]
    self.assertEqual(flight.status, FlightStatus.PENDING)

  def test_fifty_planes_five_hundred_flights_eight_assigners(self):
    scheduler, state, stop_event, workers = self._start_stress()
    self._wait_and_stop(scheduler, state, stop_event, workers)

  def test_stress_is_repeatable_across_seeds(self):
    for seed in (23, 41, 59):
      with self.subTest(seed=seed):
        scheduler, state, stop_event, workers = self._start_stress(seed)
        self._wait_and_stop(scheduler, state, stop_event, workers)

  def _start_stress(self, seed=17):
    clock = SimulationClock(600.0)
    state = SharedState(build_planes(50, seed), clock)
    scheduler = Scheduler(state, SchedulerConfig())
    stop_event = threading.Event()
    for flight in self._make_flights(500):
      scheduler.register(flight)
    workers = self._stress_workers(scheduler, state, stop_event)
    for worker in workers:
      worker.start()
    return scheduler, state, stop_event, workers

  @staticmethod
  def _stress_workers(scheduler, state, stop_event):
    workers = [AssignmentWorker(scheduler, queue.Queue(), stop_event, index)
               for index in range(8)]
    workers.extend(PlaneWorker(scheduler, plane_id, stop_event)
                   for plane_id in state.planes)
    return workers

  def _wait_and_stop(self, scheduler, state, stop_event, workers):
    stop_event.wait(1.0)
    stop_event.set()
    with state.condition:
      state.condition.notify_all()
    for worker in workers:
      worker.join(timeout=3.0)
      self.assertFalse(worker.is_alive(), worker.name)
    scheduler.verify_invariants()
    self._assert_active_assignments_are_unique(state)

  def _assert_active_assignments_are_unique(self, state):
    active_statuses = {FlightStatus.ASSIGNED, FlightStatus.DELAYED,
                       FlightStatus.IN_PROGRESS}
    active_planes = [flight.assigned_plane_id
                     for flight in state.flights.values()
                     if flight.status in active_statuses]
    self.assertEqual(len(active_planes), len(set(active_planes)))
    for plane in state.planes.values():
      if plane.active_flight_id is not None:
        self.assertEqual(
            sum(flight.assigned_plane_id == plane.plane_id
                and flight.status in active_statuses
                for flight in state.flights.values()), 1)

  @staticmethod
  def _make_flights(count):
    return [Flight(f"ST-{index:04d}", "EZE", "AEP", 0.0, 1.0,
                   80, Priority.REGULAR, 0.0) for index in range(count)]


if __name__ == "__main__":
  unittest.main()
