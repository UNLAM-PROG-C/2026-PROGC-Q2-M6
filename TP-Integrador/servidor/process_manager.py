"""Parent-side lifecycle management for the exec'ed wave worker."""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from typing import Any, Mapping

from servidor.constants import (
  TOTAL_WAVES,
  WORKER_MODULE,
)
from servidor.process_protocol import (
  CHILD_READY,
  SHUTDOWN,
  STATS_UPDATE,
  WAVE_PATTERN,
  WAVE_REQUEST,
  read_process_message,
  write_process_message,
)


@dataclass
class ChildProcess:
  """Parent-side handles for the worker process and its two pipes."""

  pid: int
  parent_write_fd: int
  parent_read_fd: int
  exit_status: int | None = None
  shutdown_requested: bool = False


def _close_fd(file_descriptor: int) -> None:
  try:
    os.close(file_descriptor)
  except OSError:
    pass


def _worker_environment() -> dict[str, str]:
  environment = os.environ.copy()
  current_directory = os.getcwd()
  python_path = environment.get("PYTHONPATH", "")
  if current_directory not in python_path.split(os.pathsep):
    environment["PYTHONPATH"] = os.pathsep.join(
      part for part in (current_directory, python_path) if part
    )
  return environment


def _exec_worker(read_fd: int, write_fd: int) -> None:
  arguments = [sys.executable, "-m", WORKER_MODULE, str(read_fd), str(write_fd)]
  try:
    os.execve(sys.executable, arguments, _worker_environment())
  except OSError:
    os._exit(127)


def _close_child_pipe_ends(
    parent_read_fd: int,
    parent_write_fd: int,
    child_read_fd: int,
    child_write_fd: int,
) -> None:
  _close_fd(parent_read_fd)
  _close_fd(parent_write_fd)
  _close_fd(child_read_fd)
  _close_fd(child_write_fd)


def _create_pipes() -> tuple[int, int, int, int]:
  child_read_fd, parent_write_fd = os.pipe()
  parent_read_fd, child_write_fd = os.pipe()
  os.set_inheritable(child_read_fd, True)
  os.set_inheritable(child_write_fd, True)
  return child_read_fd, parent_write_fd, parent_read_fd, child_write_fd


def _fork_worker(
    child_read_fd: int,
    parent_write_fd: int,
    parent_read_fd: int,
    child_write_fd: int,
) -> int:
  pid = os.fork()
  if pid == 0:
    _close_fd(parent_write_fd)
    _close_fd(parent_read_fd)
    _exec_worker(child_read_fd, child_write_fd)
  _close_fd(child_read_fd)
  _close_fd(child_write_fd)
  return pid


def _complete_handshake(worker: ChildProcess) -> None:
  message = read_process_message(worker.parent_read_fd)
  if message is None or message["type"] != CHILD_READY:
    raise ChildProcessError("Wave worker did not complete its handshake")
  payload = message["payload"]
  if payload.get("pid") != worker.pid or payload.get("worker") != WORKER_MODULE:
    raise ChildProcessError("Wave worker handshake is invalid")


def start_wave_worker() -> ChildProcess:
  """Fork, exec and handshake with the wave worker."""
  if not hasattr(os, "fork"):
    raise RuntimeError("Sprint 1 requires fork(); use WSL on Windows")
  pipes = _create_pipes()
  child_read_fd, parent_write_fd, parent_read_fd, child_write_fd = pipes
  pid = None
  try:
    pid = _fork_worker(*pipes)
    worker = ChildProcess(pid, parent_write_fd, parent_read_fd)
    _complete_handshake(worker)
    return worker
  except BaseException:
    _close_child_pipe_ends(*pipes)
    if pid is not None:
      try:
        os.waitpid(pid, 0)
      except ChildProcessError:
        pass
    raise


def _validate_wave(wave: int) -> None:
  if isinstance(wave, bool) or not 1 <= wave <= TOTAL_WAVES:
    raise ValueError(f"Wave must be between 1 and {TOTAL_WAVES}: {wave}")


def _validate_pattern(payload: dict[str, Any], wave: int) -> None:
  if payload.get("wave") != wave or not isinstance(payload.get("enemies"), list):
    raise ChildProcessError("Wave worker returned an invalid pattern")
  for enemy in payload["enemies"]:
    if not isinstance(enemy, dict):
      raise ChildProcessError("Wave worker returned an invalid enemy entry")
    if not isinstance(enemy.get("type"), str):
      raise ChildProcessError("Wave worker returned an invalid enemy type")
    if not isinstance(enemy.get("count"), int) or enemy["count"] <= 0:
      raise ChildProcessError("Wave worker returned an invalid enemy count")


def request_wave(worker: ChildProcess, wave: int) -> dict[str, Any]:
  """Request a deterministic wave pattern from the worker."""
  _validate_wave(wave)
  write_process_message(worker.parent_write_fd, WAVE_REQUEST, {"wave": wave})
  message = read_process_message(worker.parent_read_fd)
  if message is None or message["type"] != WAVE_PATTERN:
    raise ChildProcessError("Wave worker returned no pattern")
  payload = message["payload"]
  _validate_pattern(payload, wave)
  return payload


def send_stats_update(worker: ChildProcess, stats: Mapping[str, Any]) -> None:
  """Send the current parent-side statistics to the worker."""
  write_process_message(worker.parent_write_fd, STATS_UPDATE, stats)


def _wait_for_worker(worker: ChildProcess) -> int:
  while True:
    try:
      _, status = os.waitpid(worker.pid, 0)
      return status
    except InterruptedError:
      continue


def shutdown_worker(worker: ChildProcess) -> None:
  """Stop the worker, close both pipes and reap it with waitpid."""
  if worker.exit_status is not None:
    return
  try:
    if not worker.shutdown_requested:
      write_process_message(worker.parent_write_fd, SHUTDOWN, {})
      worker.shutdown_requested = True
  except (BrokenPipeError, OSError):
    worker.shutdown_requested = True
  finally:
    _close_fd(worker.parent_write_fd)
    _close_fd(worker.parent_read_fd)
    worker.exit_status = _wait_for_worker(worker)
    if not os.WIFEXITED(worker.exit_status) or os.WEXITSTATUS(worker.exit_status) != 0:
      raise ChildProcessError(
        f"Wave worker exited with status {worker.exit_status}"
      )
