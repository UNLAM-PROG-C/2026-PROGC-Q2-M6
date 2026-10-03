"""Worker threads for demand, assignment, aircraft operation and events."""

from __future__ import annotations

import logging
import queue
import random
import threading

from models import Flight, FlightStatus, PlaneStatus, Priority


LOGGER = logging.getLogger("airline.workers")
AIRPORTS = ("EZE", "AEP", "COR", "MDZ", "BRC")
MODELS = (("A320", 180, 6100), ("B737", 170, 5600),
          ("E190", 110, 4300), ("A330", 280, 11500))
MIN_DURATION = 35.0
MAX_DURATION = 180.0
MIN_PASSENGERS = 30
MAX_PASSENGERS = 250
MIN_LEAD = 1.0
MAX_LEAD = 25.0
MIN_INTERVAL = 0.3
MAX_INTERVAL = 1.4
MIN_DELAY = 5.0
MAX_DELAY = 30.0
MIN_MAINTENANCE_WAIT = 0.05
MAX_MAINTENANCE_WAIT = 0.2
QUEUE_TIMEOUT_SECONDS = 0.1


class FlightGenerator(threading.Thread):
  def __init__(self, scheduler, flight_queue, stop_event, clock, total, seed):
    super().__init__(name="flight-generator")
    self.scheduler = scheduler
    self.flight_queue = flight_queue
    self.stop_event = stop_event
    self.clock = clock
    self.total = total
    self.random = random.Random(seed)

  def run(self):
    for index in range(1, self.total + 1):
      if self.stop_event.is_set():
        break
      self.flight_queue.put(self._make_flight(index))
      self.stop_event.wait(self.clock.real_seconds(self._interval()))

  def _make_flight(self, index):
    origin, destination = self._route()
    return Flight(f"FL-{index:04d}", origin, destination,
                  self.clock.now() + self.random.uniform(MIN_LEAD, MAX_LEAD),
                  self.random.uniform(MIN_DURATION, MAX_DURATION),
                  self.random.randint(MIN_PASSENGERS, MAX_PASSENGERS),
                  self.random.choice(tuple(Priority)), self.clock.now())

  def _route(self):
    origin = self.random.choice(AIRPORTS)
    destination = self.random.choice(AIRPORTS)
    while destination == origin:
      destination = self.random.choice(AIRPORTS)
    return origin, destination

  def _interval(self):
    return self.random.uniform(MIN_INTERVAL, MAX_INTERVAL)


class AssignmentWorker(threading.Thread):
  def __init__(self, scheduler, flight_queue, stop_event, index):
    super().__init__(name=f"assigner-{index:02d}")
    self.scheduler = scheduler
    self.flight_queue = flight_queue
    self.stop_event = stop_event

  def run(self):
    while not self.stop_event.is_set():
      self._register_one()
      if not self.scheduler.assign_one():
        self.scheduler.wait_for_work(self.stop_event)

  def _register_one(self):
    try:
      flight = self.flight_queue.get(timeout=QUEUE_TIMEOUT_SECONDS)
    except queue.Empty:
      return
    if flight is not None:
      self.scheduler.register(flight)
    self.flight_queue.task_done()


class PlaneWorker(threading.Thread):
  def __init__(self, scheduler, plane_id, stop_event):
    super().__init__(name=f"plane-{plane_id}")
    self.scheduler = scheduler
    self.plane_id = plane_id
    self.stop_event = stop_event

  def run(self):
    while not self.stop_event.is_set():
      flight_id = self.scheduler.wait_for_plane(self.plane_id,
                                                self.stop_event)
      if not flight_id:
        continue
      flight = self.scheduler.claim_flight(self.plane_id)
      if flight is None:
        continue
      completed = self._operate(flight)
      if completed:
        self.scheduler.complete_flight(self.plane_id, flight.flight_id)
        self._turnaround(flight.flight_id)
      else:
        self.scheduler.abort_plane_job(self.plane_id, flight.flight_id)

  def _operate(self, flight):
    clock = self.scheduler.state.clock
    if not clock.wait_until(flight.scheduled_departure, self.stop_event):
      return False
    return clock.wait_sim(flight.duration_minutes, self.stop_event)

  def _turnaround(self, flight_id):
    clock = self.scheduler.state.clock
    if clock.wait_sim(self.scheduler.config.turnaround_minutes, self.stop_event):
      self.scheduler.finish_turnaround(self.plane_id, flight_id)
    else:
      self.scheduler.abort_plane_job(self.plane_id, flight_id)


class EventWorker(threading.Thread):
  def __init__(self, scheduler, stop_event, seed, event_interval):
    super().__init__(name="external-events")
    self.scheduler = scheduler
    self.stop_event = stop_event
    self.random = random.Random(seed)
    self.event_interval = event_interval

  def run(self):
    while not self.stop_event.wait(self.event_interval):
      self._emit_event()

  def _emit_event(self):
    snapshot = self.scheduler.state.snapshot()
    choice = self.random.choice(("delay", "cancel", "maintenance"))
    if choice == "delay":
      self._delay(snapshot)
    elif choice == "cancel":
      self._cancel(snapshot)
    else:
      self._maintenance(snapshot)

  def _delay(self, snapshot):
    ids = self._flight_ids(snapshot, (FlightStatus.PENDING.value,
                                      FlightStatus.ASSIGNED.value,
                                      FlightStatus.DELAYED.value))
    if ids:
      self.scheduler.delay_flight(self.random.choice(ids),
                                  self.random.uniform(MIN_DELAY, MAX_DELAY))

  def _cancel(self, snapshot):
    ids = self._flight_ids(snapshot, (FlightStatus.PENDING.value,
                                      FlightStatus.ASSIGNED.value,
                                      FlightStatus.DELAYED.value))
    if ids:
      self.scheduler.cancel_random_flight(self.random.choice(ids),
                                          "external cancellation")

  def _maintenance(self, snapshot):
    ids = [plane["id"] for plane in snapshot["planes"]
           if plane["status"] in (PlaneStatus.AVAILABLE.value,
                                   PlaneStatus.ASSIGNED.value)]
    if not ids:
      return
    plane_id = self.random.choice(ids)
    if self.scheduler.place_maintenance(plane_id, "external maintenance"):
      self.stop_event.wait(self.random.uniform(MIN_MAINTENANCE_WAIT,
                                               MAX_MAINTENANCE_WAIT))
      self.scheduler.release_maintenance(plane_id)

  @staticmethod
  def _flight_ids(snapshot, statuses):
    return [flight["id"] for flight in snapshot["flights"]
            if flight["status"] in statuses]


def build_planes(count, seed):
  rng = random.Random(seed)
  planes = []
  for index in range(1, count + 1):
    model, capacity, range_km = rng.choice(MODELS)
    airport = rng.choice(AIRPORTS)
    planes.append(PlaneFactory.create(index, model, capacity, range_km,
                                      airport))
  return planes


class PlaneFactory:
  @staticmethod
  def create(index, model, capacity, range_km, airport):
    from models import Plane
    return Plane(f"AV-{index:03d}", model, capacity, range_km, airport)
