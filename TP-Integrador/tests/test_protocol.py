"""Tests for length-prefixed JSON framing."""

from __future__ import annotations

import json
import socket
import struct

import pytest

from servidor.protocol import ProtocolError, encode_message, recv_message, send_message


class FragmentedSocket:
  """Socket-like reader that returns a configured number of bytes per call."""

  def __init__(self, data: bytes, chunk_size: int) -> None:
    self.data = data
    self.chunk_size = chunk_size

  def recv(self, size: int) -> bytes:
    read_size = min(size, self.chunk_size)
    chunk = self.data[:read_size]
    self.data = self.data[read_size:]
    return chunk


def test_recv_message_handles_fragmented_header_and_body() -> None:
  frame = encode_message("PING", {"sequence": 1})
  message = recv_message(FragmentedSocket(frame, 1))
  assert message == {"type": "PING", "payload": {"sequence": 1}}


def test_recv_message_handles_multiple_messages_in_one_stream() -> None:
  first = encode_message("PING", {"sequence": 1})
  second = encode_message("READY", {})
  left, right = socket.socketpair()
  try:
    left.sendall(first + second)
    assert recv_message(right) == {"type": "PING", "payload": {"sequence": 1}}
    assert recv_message(right) == {"type": "READY", "payload": {}}
  finally:
    left.close()
    right.close()


def test_send_message_writes_one_framed_message() -> None:
  left, right = socket.socketpair()
  try:
    send_message(left, "PING", {"sequence": 2})
    assert recv_message(right) == {"type": "PING", "payload": {"sequence": 2}}
  finally:
    left.close()
    right.close()


def test_recv_message_rejects_invalid_json() -> None:
  body = b"not-json"
  frame = struct.pack(">I", len(body)) + body
  with pytest.raises(ProtocolError, match="valid JSON"):
    recv_message(FragmentedSocket(frame, len(frame)))


def test_recv_message_rejects_non_object_payload() -> None:
  body = json.dumps({"type": "PING", "payload": []}).encode("utf-8")
  frame = struct.pack(">I", len(body)) + body
  with pytest.raises(ProtocolError, match="payload must be an object"):
    recv_message(FragmentedSocket(frame, len(frame)))
