"""Tests for the parent/worker pipe framing."""

import json
import os
import struct

import pytest

from servidor.process_protocol import (
  ProcessProtocolError,
  WAVE_REQUEST,
  encode_process_message,
  read_process_message,
  write_process_message,
)


def test_process_message_round_trip() -> None:
  reader, writer = os.pipe()
  try:
    write_process_message(writer, WAVE_REQUEST, {"wave": 3})
    assert read_process_message(reader) == {
      "type": WAVE_REQUEST,
      "payload": {"wave": 3},
    }
  finally:
    os.close(reader)
    os.close(writer)


def test_process_message_rejects_unknown_type() -> None:
  with pytest.raises(ProcessProtocolError, match="Unknown process message"):
    encode_process_message("UNKNOWN", {})


def test_process_message_rejects_invalid_json() -> None:
  reader, writer = os.pipe()
  body = b"not-json"
  try:
    os.write(writer, struct.pack(">I", len(body)) + body)
    with pytest.raises(ProcessProtocolError, match="valid JSON"):
      read_process_message(reader)
  finally:
    os.close(reader)
    os.close(writer)


def test_process_message_rejects_non_object_payload() -> None:
  reader, writer = os.pipe()
  body = json.dumps({"type": WAVE_REQUEST, "payload": []}).encode("utf-8")
  try:
    os.write(writer, struct.pack(">I", len(body)) + body)
    with pytest.raises(ProcessProtocolError, match="payload must be an object"):
      read_process_message(reader)
  finally:
    os.close(reader)
    os.close(writer)
