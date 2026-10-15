"""Command-line entry point for the airline concurrency simulation."""

from __future__ import annotations

import argparse
import logging
import queue
import threading
from time import monotonic

from dashboard import DashboardServer
from metrics import ProcessMetrics, build_report, write_report
from models import SimulationClock
from monitor import Monitor
from scheduler import Scheduler, SchedulerConfig, SharedState
from workers import (AssignmentWorker, EventWorker, FlightGenerator,
                     PlaneWorker, build_planes)


DEFAULT_DURATION = 20.0
DEFAULT_PLANES = 8
DEFAULT_FLIGHTS = 40
DEFAULT_ASSIGNERS = 3
DEFAULT_SPEED = 10.0
DEFAULT_SEED = 42
DEFAULT_PORT = 8080
DEFAULT_METRICS_FILE = "metrics.json"
CONTAINER_BIND_HOST = "0.0.0.0"
DEFAULT_INTERVAL = 0.6
JOIN_TIMEOUT_SECONDS = 5.0


def parse_args():
  parser = argparse.ArgumentParser(description="Concurrent airline simulator")
  parser.add_argument("--duration", type=float, default=DEFAULT_DURATION)
  parser.add_argument("--planes", type=int, default=DEFAULT_PLANES)
  parser.add_argument("--flights", type=int, default=DEFAULT_FLIGHTS)
  parser.add_argument("--assigners", type=int, default=DEFAULT_ASSIGNERS)
  parser.add_argument("--speed", type=float, default=DEFAULT_SPEED)
  parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
  parser.add_argument("--port", type=int, default=DEFAULT_PORT)
  parser.add_argument("--no-dashboard", action="store_true")
  parser.add_argument("--metrics-file", default=DEFAULT_METRICS_FILE)
  return parser.parse_args()


def configure_logging():
  logging.basicConfig(level=logging.INFO,
                      format="%(asctime)s %(levelname)s [%(threadName)s] %(message)s",
                      datefmt="%H:%M:%S")


def make_simulation(args):
  clock = SimulationClock(args.speed)
  state = SharedState(build_planes(args.planes, args.seed), clock)
  config = SchedulerConfig()
  scheduler = Scheduler(state, config)
  stop_event = threading.Event()
  work_queue = queue.Queue()
  return clock, state, scheduler, stop_event, work_queue


def start_threads(args, scheduler, state, stop_event, work_queue, metrics=None):
  threads = []
  threads.append(FlightGenerator(scheduler, work_queue, stop_event,
                                 state.clock, args.flights, args.seed + 1))
  threads.extend(AssignmentWorker(scheduler, work_queue, stop_event, index)
                 for index in range(1, args.assigners + 1))
  threads.extend(PlaneWorker(scheduler, plane_id, stop_event)
                 for plane_id in state.planes)
  threads.append(EventWorker(scheduler, stop_event, args.seed + 2,
                             DEFAULT_INTERVAL))
  threads.append(Monitor(scheduler, stop_event, DEFAULT_INTERVAL, metrics))
  for thread in threads:
    thread.start()
  return threads


def stop_threads(threads, assigners, work_queue, stop_event, state):
  stop_event.set()
  with state.condition:
    state.condition.notify_all()
  scheduler = threads[0].scheduler
  scheduler.cancel_pending("simulation ended")
  for _ in range(assigners):
    work_queue.put(None)
  for thread in threads[:-1]:
    thread.join(timeout=JOIN_TIMEOUT_SECONDS)
  scheduler.cancel_pending("simulation ended")
  threads[-1].join(timeout=JOIN_TIMEOUT_SECONDS)
  return [thread.name for thread in threads if thread.is_alive()]


def run(args):
  started_at = monotonic()
  clock, state, scheduler, stop_event, work_queue = make_simulation(args)
  metrics = ProcessMetrics()
  metrics.sample()
  dashboard = start_dashboard(args, state)
  threads = start_threads(args, scheduler, state, stop_event, work_queue,
                          metrics)
  invariant_error = None
  alive_threads = []
  try:
    stop_event.wait(args.duration)
  finally:
    alive_threads = stop_threads(threads, args.assigners, work_queue,
                                 stop_event, state)
    if dashboard:
      dashboard.close()
    try:
      scheduler.verify_invariants()
    except AssertionError as error:
      invariant_error = str(error)
      logging.error("final invariant violation: %s", error)
    metrics.sample()

  report = build_report(args, clock, state, threads, metrics,
                        monotonic() - started_at,
                        invariant_error is None, invariant_error)
  report["execution"]["threads_alive"] = alive_threads
  write_report(args.metrics_file, report)
  _report_summary(report, args.metrics_file)
  logging.info("simulation finished at %.1f simulated minutes", clock.now())
  if invariant_error is not None:
    raise AssertionError(invariant_error)
  return report


def _report_summary(report, metrics_file):
  functionality = report["functionality"]
  resources = report["resources"]
  execution = report["execution"]
  logging.info(
      "metrics: flights=%d completed=%d cancelled=%d pending=%d "
      "cpu_avg=%.2f%% cpu_max=%.2f%% rss_peak=%.2f MB",
      functionality["flights_generated"],
      functionality["flights_completed"],
      functionality["flights_cancelled"],
      functionality["flights_pending"],
      resources["cpu_percent_average"],
      resources["cpu_percent_max"],
      resources["rss_peak_mb"] or 0.0)
  logging.info("metrics report: %s invariants=%s threads_alive=%s",
               metrics_file, execution["final_invariants"],
               execution["threads_alive"])


def start_dashboard(args, state):
  if args.no_dashboard:
    return None
  dashboard = DashboardServer(state, CONTAINER_BIND_HOST, args.port)
  dashboard.start()
  logging.info("dashboard: http://127.0.0.1:%s", dashboard.address[1])
  return dashboard


def main():
  configure_logging()
  args = parse_args()
  try:
    run(args)
  except KeyboardInterrupt:
    logging.info("shutdown requested")


if __name__ == "__main__":
  main()
