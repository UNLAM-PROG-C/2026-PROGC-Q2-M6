"""Non-blocking monitor and invariant auditor."""

from __future__ import annotations

import logging
import threading


LOGGER = logging.getLogger("airline.monitor")


class Monitor(threading.Thread):
  def __init__(self, scheduler, stop_event, interval, metrics=None):
    super().__init__(name="monitor-auditor")
    self.scheduler = scheduler
    self.stop_event = stop_event
    self.interval = interval
    self.metrics = metrics

  def run(self):
    while not self.stop_event.wait(self.interval):
      self._audit()
    self._audit()

  def _audit(self):
    try:
      self.scheduler.verify_invariants()
      self._report(self.scheduler.state.snapshot())
    except AssertionError as error:
      LOGGER.error("invariant violation: %s", error)
    finally:
      if self.metrics is not None:
        self.metrics.sample()

  @staticmethod
  def _report(snapshot):
    counts = {}
    for plane in snapshot["planes"]:
      counts[plane["status"]] = counts.get(plane["status"], 0) + 1
    LOGGER.info("fleet=%s flights=%d", counts, len(snapshot["flights"]))
