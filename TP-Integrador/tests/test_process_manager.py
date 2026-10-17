"""Integration tests for fork, execve, pipes and waitpid."""

import os

import pytest

from servidor.constants import TOTAL_WAVES, WAVE_PATTERNS
from servidor.process_manager import (
  request_wave,
  send_stats_update,
  shutdown_worker,
  start_wave_worker,
)


pytestmark = pytest.mark.skipif(
  not hasattr(os, "fork"), reason="Sprint 1 requires fork()"
)


def test_worker_handshake_patterns_and_clean_shutdown() -> None:
  worker = start_wave_worker()
  try:
    for wave in range(1, TOTAL_WAVES + 1):
      pattern = request_wave(worker, wave)
      assert pattern["wave"] == wave
      assert pattern["enemies"] == [
        {"type": enemy_type, "count": count}
        for enemy_type, count in WAVE_PATTERNS[wave]
      ]
    send_stats_update(worker, {"wave": TOTAL_WAVES, "enemies_defeated": 1})
  finally:
    shutdown_worker(worker)

  assert worker.exit_status is not None
  assert os.WIFEXITED(worker.exit_status)
  assert os.WEXITSTATUS(worker.exit_status) == 0


def test_request_wave_rejects_out_of_range_wave() -> None:
  worker = start_wave_worker()
  try:
    with pytest.raises(ValueError, match="between 1 and 10"):
      request_wave(worker, 0)
  finally:
    shutdown_worker(worker)
