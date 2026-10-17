"""Ensure Python and Godot expose the same protocol names."""

from pathlib import Path

from servidor.protocol import CLIENT_MESSAGE_TYPES, SERVER_MESSAGE_TYPES


def test_godot_protocol_constants_match_python() -> None:
  constants_path = Path("cliente_godot/scripts/protocol_constants.gd")
  constants = constants_path.read_text(encoding="utf-8")
  message_types = CLIENT_MESSAGE_TYPES + SERVER_MESSAGE_TYPES
  for message_type in message_types:
    declaration = f'const {message_type}: StringName = &"{message_type}"'
    assert declaration in constants
