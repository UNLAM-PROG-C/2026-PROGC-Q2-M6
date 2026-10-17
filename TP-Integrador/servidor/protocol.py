"""TCP framing and shared JSON protocol definitions."""

from __future__ import annotations

import json
import socket
import struct
from typing import Any, Mapping

FRAME_HEADER_SIZE = 4
MAX_FRAME_SIZE = 1_048_576

HELLO = "HELLO"
READY = "READY"
BUY_TOWER = "BUY_TOWER"
SELL_TOWER = "SELL_TOWER"
PING = "PING"

WELCOME = "WELCOME"
STATE_UPDATE = "STATE_UPDATE"
WAVE_START = "WAVE_START"
BASE_DAMAGE = "BASE_DAMAGE"
GAME_OVER = "GAME_OVER"
ERROR = "ERROR"

CLIENT_MESSAGE_TYPES = (HELLO, READY, BUY_TOWER, SELL_TOWER, PING)
SERVER_MESSAGE_TYPES = (
  WELCOME,
  STATE_UPDATE,
  WAVE_START,
  BASE_DAMAGE,
  GAME_OVER,
  ERROR,
)


class ProtocolError(ValueError):
  """Raised when a frame does not follow the protocol contract."""


def _validate_frame_size(size: int) -> None:
  if size <= 0 or size > MAX_FRAME_SIZE:
    raise ProtocolError(f"Invalid frame size: {size}")


def encode_message(message_type: str, payload: Mapping[str, Any]) -> bytes:
  """Encode one protocol message with its four-byte length prefix."""
  body = json.dumps({"type": message_type, "payload": payload}).encode("utf-8")
  _validate_frame_size(len(body))
  return struct.pack(">I", len(body)) + body


def send_message(sock: socket.socket, message_type: str,
                 payload: Mapping[str, Any]) -> None:
  """Send one complete framed protocol message."""
  sock.sendall(encode_message(message_type, payload))


def _recv_exact(sock: socket.socket, size: int) -> bytes | None:
  """Read exactly size bytes, returning None only on clean connection close."""
  chunks = bytearray()
  while len(chunks) < size:
    chunk = sock.recv(size - len(chunks))
    if not chunk:
      if not chunks:
        return None
      raise ConnectionError("Connection closed during a frame")
    chunks.extend(chunk)
  return bytes(chunks)


def _decode_body(body: bytes) -> dict[str, Any]:
  try:
    message = json.loads(body.decode("utf-8"))
  except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise ProtocolError("Frame body is not valid JSON") from error
  if not isinstance(message, dict):
    raise ProtocolError("Message must be a JSON object")
  if not isinstance(message.get("type"), str):
    raise ProtocolError("Message type must be a string")
  if not isinstance(message.get("payload"), dict):
    raise ProtocolError("Message payload must be an object")
  return message


def recv_message(sock: socket.socket) -> dict[str, Any] | None:
  """Receive one framed message, or None when the peer closed cleanly."""
  header = _recv_exact(sock, FRAME_HEADER_SIZE)
  if header is None:
    return None
  size = struct.unpack(">I", header)[0]
  _validate_frame_size(size)
  body = _recv_exact(sock, size)
  if body is None:
    raise ConnectionError("Connection closed before frame body")
  return _decode_body(body)
