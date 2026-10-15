"""Process resource metrics and simulation run reporting."""

from __future__ import annotations

import json
import os
from collections import Counter
from pathlib import Path
from time import monotonic

import psutil


MEGABYTE = 1024 * 1024


class ProcessMetrics:
  """Non-blocking process sampler suitable for an existing monitor thread."""

  def __init__(self, process=None):
    self.process = process or psutil.Process(os.getpid())
    self._last_wall = None
    self._last_cpu = None
    self._wall_seconds = 0.0
    self._cpu_seconds = 0.0
    self._cpu_percent_sum = 0.0
    self._cpu_percent_max = 0.0
    self._sample_count = 0
    self._initial_rss = None
    self._final_rss = None
    self._peak_rss = 0
    self._initial_threads = None
    self._final_threads = None
    self._peak_threads = 0

  def sample(self):
    """Capture one non-blocking sample of the current process."""
    wall_now = monotonic()
    cpu_times = self.process.cpu_times()
    cpu_now = cpu_times.user + cpu_times.system
    rss_now = self.process.memory_info().rss
    threads_now = self.process.num_threads()

    if self._initial_rss is None:
      self._initial_rss = rss_now
      self._initial_threads = threads_now
    if self._last_wall is not None:
      wall_delta = max(0.0, wall_now - self._last_wall)
      cpu_delta = max(0.0, cpu_now - self._last_cpu)
      self._wall_seconds += wall_delta
      self._cpu_seconds += cpu_delta
      if wall_delta > 0:
        cpu_percent = 100.0 * cpu_delta / wall_delta
        self._cpu_percent_sum += cpu_percent
        self._cpu_percent_max = max(self._cpu_percent_max, cpu_percent)

    self._last_wall = wall_now
    self._last_cpu = cpu_now
    self._final_rss = rss_now
    self._peak_rss = max(self._peak_rss, rss_now)
    self._final_threads = threads_now
    self._peak_threads = max(self._peak_threads, threads_now)
    self._sample_count += 1

  def summary(self):
    """Return JSON-serializable aggregate metrics."""
    sample_intervals = max(0, self._sample_count - 1)
    average_cpu = (self._cpu_percent_sum / sample_intervals
                   if sample_intervals else 0.0)
    return {
        "samples": self._sample_count,
        "sample_intervals": sample_intervals,
        "wall_seconds_sampled": round(self._wall_seconds, 4),
        "cpu_time_seconds": round(self._cpu_seconds, 4),
        "cpu_percent_average": round(average_cpu, 2),
        "cpu_percent_max": round(self._cpu_percent_max, 2),
        "rss_initial_bytes": self._initial_rss,
        "rss_peak_bytes": self._peak_rss,
        "rss_final_bytes": self._final_rss,
        "rss_initial_mb": _megabytes(self._initial_rss),
        "rss_peak_mb": _megabytes(self._peak_rss),
        "rss_final_mb": _megabytes(self._final_rss),
        "threads_initial": self._initial_threads,
        "threads_peak": self._peak_threads,
        "threads_final": self._final_threads,
    }


def build_report(args, clock, state, threads, metrics, elapsed_seconds,
                 invariants_ok, invariant_error=None):
  """Build the functional and resource evidence for one simulation run."""
  snapshot = state.snapshot()
  status_counts = Counter(flight["status"] for flight in snapshot["flights"])
  with state.log_lock:
    operations = list(state.operation_log)
  alive_threads = [thread.name for thread in threads if thread.is_alive()]
  no_deadlocks = not alive_threads

  return {
      "configuration": {
          "duration_seconds": args.duration,
          "planes": args.planes,
          "flights": args.flights,
          "assigners": args.assigners,
          "speed": args.speed,
          "seed": args.seed,
          "dashboard": not args.no_dashboard,
      },
      "execution": {
          "elapsed_seconds": round(elapsed_seconds, 4),
          "simulated_minutes": round(clock.now(), 2),
          "threads_alive": alive_threads,
          "final_invariants": invariants_ok,
          "invariant_error": invariant_error,
      },
      "functionality": {
          "flights_generated": len(snapshot["flights"]),
          "flights_completed": status_counts.get("COMPLETED", 0),
          "flights_cancelled": status_counts.get("CANCELLED", 0),
          "flights_pending": status_counts.get("PENDING", 0),
          "flights_by_status": dict(sorted(status_counts.items())),
          "assignments": sum(operation.startswith("assigned ")
                             for operation in operations),
          "delays": sum(operation.startswith("delay ")
                        for operation in operations),
          "maintenance_entries": sum("-> MAINTENANCE" in operation
                                      for operation in operations),
          "maintenance_releases": sum("MAINTENANCE -> AVAILABLE" in operation
                                       for operation in operations),
      },
      "concurrency_evidence": {
          "synchronization_invariants_passed": invariants_ok,
          "deadlocks_absent": no_deadlocks,
          "deadlock_threads_remaining": alive_threads,
          "mutual_exclusion_invariants_passed": invariants_ok and no_deadlocks,
          "race_condition_invariants_passed": invariants_ok and no_deadlocks,
      },
      "resources": metrics.summary(),
  }


def write_report(path, report):
  """Write one complete report as formatted JSON."""
  report_path = Path(path)
  report_path.parent.mkdir(parents=True, exist_ok=True)
  report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                         encoding="utf-8")


def _megabytes(value):
  return round(value / MEGABYTE, 2) if value is not None else None
