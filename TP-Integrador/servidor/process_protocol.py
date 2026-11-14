"""Length-prefixed JSON protocol used by the parent and worker processes."""

from __future__ import annotations

import json
import os
import struct
from typing import Any, Mapping

from servidor.constants import FIRST_WAVE, TOTAL_WAVES
from servidor.protocol import (
  FRAME_HEADER_FORMAT,
  FRAME_HEADER_SIZE,
  MAX_FRAME_SIZE,
  TEXT_ENCODING,
)

WAVE_REQUEST = "WAVE_REQUEST"
STATS_UPDATE = "STATS_UPDATE"
SHUTDOWN = "SHUTDOWN"
CHILD_READY = "CHILD_READY"
WAVE_PATTERN = "WAVE_PATTERN"

PROCESS_MESSAGE_TYPES = (
  WAVE_REQUEST,
  STATS_UPDATE,
  SHUTDOWN,
  CHILD_READY,
  WAVE_PATTERN,
)


class ProcessProtocolError(ValueError):
  """Raised when an IPC frame violates the process protocol."""


def validate_wave(wave: int) -> None:
  """Reject wave numbers outside the fixed campaign."""
  if isinstance(wave, bool) or not FIRST_WAVE <= wave <= TOTAL_WAVES:
    raise ValueError(
      f"Wave must be between {FIRST_WAVE} and {TOTAL_WAVES}: {wave}"
    )


def _validate_frame_size(size: int) -> None:
  if size <= 0 or size > MAX_FRAME_SIZE:
    raise ProcessProtocolError(f"Invalid process frame size: {size}")


def encode_process_message(
    message_type: str, payload: Mapping[str, Any]) -> bytes:
  """Encode one process message with a four-byte length prefix."""
  if message_type not in PROCESS_MESSAGE_TYPES:
    raise ProcessProtocolError(f"Unknown process message type: {message_type}")
  message = {"type": message_type, "payload": payload}
  body = json.dumps(message).encode(TEXT_ENCODING)
  _validate_frame_size(len(body))
  return struct.pack(FRAME_HEADER_FORMAT, len(body)) + body


def write_process_message(
  file_descriptor: int,
  message_type: str,
  payload: Mapping[str, Any],
) -> None:
  """Write one complete process message, handling partial writes."""
  frame = encode_process_message(message_type, payload)
  offset = 0
  while offset < len(frame):
    try:
      written = os.write(file_descriptor, frame[offset:])
    except InterruptedError:
      continue
    if written == 0:
      raise BrokenPipeError("Process pipe closed while writing")
    offset += written


def _read_exact(file_descriptor: int, size: int) -> bytes | None:
  chunks = bytearray()
  while len(chunks) < size:
    try:
      chunk = os.read(file_descriptor, size - len(chunks))
    except InterruptedError:
      continue
    if not chunk:
      if not chunks:
        return None
      raise EOFError("Process pipe closed during a frame")
    chunks.extend(chunk)
  return bytes(chunks)


def _decode_body(body: bytes) -> dict[str, Any]:
  try:
    message = json.loads(body.decode(TEXT_ENCODING))
  except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise ProcessProtocolError(
      "Process frame body is not valid JSON"
    ) from error
  if not isinstance(message, dict):
    raise ProcessProtocolError("Process message must be a JSON object")
  if message.get("type") not in PROCESS_MESSAGE_TYPES:
    raise ProcessProtocolError("Unknown process message type")
  if not isinstance(message.get("payload"), dict):
    raise ProcessProtocolError("Process payload must be an object")
  return message


def read_process_message(file_descriptor: int) -> dict[str, Any] | None:
  """Read one process message, or None after a clean EOF."""
  header = _read_exact(file_descriptor, FRAME_HEADER_SIZE)
  if header is None:
    return None
  size = struct.unpack(FRAME_HEADER_FORMAT, header)[0]
  _validate_frame_size(size)
  body = _read_exact(file_descriptor, size)
  if body is None:
    raise EOFError("Process pipe closed before the frame body")
  return _decode_body(body)
