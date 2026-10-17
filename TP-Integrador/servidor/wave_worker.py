"""Exec'ed child process that serves deterministic wave patterns."""

from __future__ import annotations

import os
import sys
from typing import Any

from servidor.constants import TOTAL_WAVES, WAVE_PATTERNS
from servidor.process_protocol import (
  CHILD_READY,
  SHUTDOWN,
  STATS_UPDATE,
  WAVE_PATTERN,
  WAVE_REQUEST,
  read_process_message,
  write_process_message,
)


def _pattern_for_wave(wave: int) -> list[dict[str, Any]]:
  if isinstance(wave, bool) or not 1 <= wave <= TOTAL_WAVES:
    raise ValueError(f"Wave must be between 1 and {TOTAL_WAVES}: {wave}")
  return [
    {"type": enemy_type, "count": count}
    for enemy_type, count in WAVE_PATTERNS[wave]
  ]


def _handle_message(message: dict[str, Any], write_fd: int) -> bool:
  if message["type"] == SHUTDOWN:
    return False
  if message["type"] == WAVE_REQUEST:
    wave = message["payload"].get("wave")
    write_process_message(
      write_fd,
      WAVE_PATTERN,
      {"wave": wave, "enemies": _pattern_for_wave(wave)},
    )
    return True
  if message["type"] == STATS_UPDATE:
    return True
  raise ValueError(f"Unsupported worker message: {message['type']}")


def run_worker(read_fd: int, write_fd: int) -> None:
  """Serve requests until the parent sends SHUTDOWN or closes the pipe."""
  try:
    write_process_message(
      write_fd,
      CHILD_READY,
      {"pid": os.getpid(), "worker": "servidor.wave_worker"},
    )
    while True:
      message = read_process_message(read_fd)
      if message is None or not _handle_message(message, write_fd):
        return
  finally:
    os.close(read_fd)
    os.close(write_fd)


def _main() -> int:
  if len(sys.argv) != 3:
    print("Usage: python -m servidor.wave_worker READ_FD WRITE_FD", file=sys.stderr)
    return 2
  run_worker(int(sys.argv[1]), int(sys.argv[2]))
  return 0


if __name__ == "__main__":
  raise SystemExit(_main())
