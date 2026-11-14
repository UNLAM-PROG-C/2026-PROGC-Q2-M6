"""TCP framing and shared JSON protocol definitions."""

from __future__ import annotations

import json
import socket
import struct
from typing import Any, Mapping

FRAME_HEADER_SIZE = 4
FRAME_HEADER_FORMAT = ">I"
MAX_FRAME_SIZE = 1_048_576
TEXT_ENCODING = "utf-8"

HELLO = "HELLO"
READY = "READY"
START_GAME = "START_GAME"
RESET_MATCH = "RESET_MATCH"
BUY_TOWER = "BUY_TOWER"
UPGRADE_TOWER = "UPGRADE_TOWER"
SELL_TOWER = "SELL_TOWER"
PING = "PING"

WELCOME = "WELCOME"
STATE_UPDATE = "STATE_UPDATE"
WAVE_START = "WAVE_START"
COUNTDOWN = "COUNTDOWN"
BASE_DAMAGE = "BASE_DAMAGE"
GAME_OVER = "GAME_OVER"
ERROR = "ERROR"
ATTACK = "ATTACK"
MATCH_RESET = "MATCH_RESET"
MATCH_STARTED = "MATCH_STARTED"

CLIENT_MESSAGE_TYPES = (
  HELLO, READY, START_GAME, RESET_MATCH, BUY_TOWER, UPGRADE_TOWER,
  SELL_TOWER, PING
)
SERVER_MESSAGE_TYPES = (
  WELCOME,
  STATE_UPDATE,
  WAVE_START,
  COUNTDOWN,
  BASE_DAMAGE,
  GAME_OVER,
  MATCH_RESET,
  MATCH_STARTED,
  ERROR,
  ATTACK,
)

ERROR_INVALID_MESSAGE = "INVALID_MESSAGE"
ERROR_UNKNOWN_MESSAGE = "UNKNOWN_MESSAGE"
ERROR_MAX_PLAYERS = "MAX_PLAYERS"
ERROR_INVALID_NAME = "INVALID_NAME"
ERROR_GAME_ALREADY_STARTED = "GAME_ALREADY_STARTED"
ERROR_GAME_NOT_STARTED = "GAME_NOT_STARTED"
ERROR_ONLY_HOST_CAN_START = "ONLY_HOST_CAN_START"
ERROR_INSUFFICIENT_PLAYERS = "INSUFFICIENT_PLAYERS"
ERROR_INSUFFICIENT_GOLD = "INSUFFICIENT_GOLD"
ERROR_POSITION_OCCUPIED = "POSITION_OCCUPIED"
ERROR_INVALID_TOWER_TYPE = "INVALID_TOWER_TYPE"
ERROR_INVALID_LANE = "INVALID_LANE"
ERROR_INVALID_POSITION = "INVALID_POSITION"
ERROR_TOWER_NOT_FOUND = "TOWER_NOT_FOUND"
ERROR_MAX_TOWER_LEVEL = "MAX_TOWER_LEVEL"
ERROR_ENEMY_NOT_FOUND = "ENEMY_NOT_FOUND"
ERROR_INVALID_DAMAGE = "INVALID_DAMAGE"

RESULT_VICTORY = "VICTORY"
RESULT_DEFEAT = "DEFEAT"
REASON_ALL_WAVES_CLEARED = "ALL_WAVES_CLEARED"
REASON_BASE_DESTROYED = "BASE_DESTROYED"


class ProtocolError(ValueError):
  """Raised when a frame does not follow the protocol contract."""


def _validate_frame_size(size: int) -> None:
  if size <= 0 or size > MAX_FRAME_SIZE:
    raise ProtocolError(f"Invalid frame size: {size}")


def encode_message(message_type: str, payload: Mapping[str, Any]) -> bytes:
  """Encode one protocol message with its four-byte length prefix."""
  message = {"type": message_type, "payload": payload}
  body = json.dumps(message).encode(TEXT_ENCODING)
  _validate_frame_size(len(body))
  return struct.pack(FRAME_HEADER_FORMAT, len(body)) + body


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
    message = json.loads(body.decode(TEXT_ENCODING))
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
  size = struct.unpack(FRAME_HEADER_FORMAT, header)[0]
  _validate_frame_size(size)
  body = _recv_exact(sock, size)
  if body is None:
    raise ConnectionError("Connection closed before frame body")
  return _decode_body(body)
