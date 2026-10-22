"""Small TCP bot for integration and concurrency tests."""

from __future__ import annotations

import argparse
import json
import random
import select
import socket
import struct
import time

from servidor.constants import LANE_COUNT, TOWER_STATS
from servidor.protocol import (
  BUY_TOWER,
  HELLO,
  PING,
  READY,
  SELL_TOWER,
  STATE_UPDATE,
  WELCOME,
  MAX_FRAME_SIZE,
  encode_message,
)


DEFAULT_DURATION_SECONDS = 10.0
DEFAULT_BUY_INTERVAL_SECONDS = 0.25
DEFAULT_PING_INTERVAL_SECONDS = 1.0
DEFAULT_SELL_INTERVAL_SECONDS = 1.5


class BotClient:
  """Connect, perform the handshake, buy towers and log state updates."""

  def __init__(self, args: argparse.Namespace) -> None:
    self.args = args
    self.random = random.Random(args.seed)
    self.next_buy = 0.0
    self.next_ping = 0.0
    self.next_sell = 0.0
    self.tower_ids: list[int] = []

  def run(self) -> None:
    """Run the bot for the configured duration."""
    with socket.create_connection((self.args.host, self.args.port), timeout=3) as sock:
      sock.setblocking(False)
      connection = BotConnection(sock)
      self._handshake(connection)
      self._run_loop(connection)
      self._close(connection)

  def _handshake(self, connection: "BotConnection") -> None:
    connection.send(HELLO, {"name": self.args.name})
    welcome = self._read_until(connection, WELCOME, 3.0)
    if welcome is None:
      raise RuntimeError("Server did not send WELCOME")
    print(f"{self.args.name}: WELCOME {welcome['payload']}", flush=True)
    connection.send(READY, {})

  def _run_loop(self, connection: "BotConnection") -> None:
    deadline = time.monotonic() + self.args.duration
    self.next_buy = time.monotonic()
    self.next_ping = time.monotonic()
    self.next_sell = time.monotonic() + self.args.sell_interval
    while time.monotonic() < deadline:
      self._read_available(connection)
      now = time.monotonic()
      if now >= self.next_buy:
        self._buy_random_tower(connection)
        self.next_buy = now + self.args.buy_interval
      if self.args.ping_interval > 0 and now >= self.next_ping:
        connection.send(PING, {"sequence": int(now * 1000)})
        self.next_ping = now + self.args.ping_interval
      if self.args.sell_interval > 0 and now >= self.next_sell:
        self._sell_random_tower(connection)
        self.next_sell = now + self.args.sell_interval
      time.sleep(0.01)

  def _read_available(self, connection: "BotConnection") -> None:
    for message in connection.poll():
      if message.get("type") == STATE_UPDATE:
        self.tower_ids = [
          tower["tower_id"] for tower in message["payload"].get("towers", [])
        ]
        print(f"{self.args.name}: STATE_UPDATE {message['payload']}", flush=True)

  def _read_until(
    self,
    connection: "BotConnection",
    message_type: str,
    timeout: float,
  ) -> dict | None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
      for message in connection.poll():
        if message.get("type") == message_type:
          return message
      time.sleep(0.01)
    return None

  def _buy_random_tower(self, connection: "BotConnection") -> None:
    tower_type = self.random.choice(tuple(TOWER_STATS))
    payload = {
      "tower_type": tower_type,
      "lane": self.random.randrange(LANE_COUNT),
      "pos": [self.random.randrange(50, 900), self.random.randrange(80, 460)],
    }
    connection.send(BUY_TOWER, payload)

  def _sell_random_tower(self, connection: "BotConnection") -> None:
    if self.tower_ids:
      connection.send(SELL_TOWER, {"tower_id": self.random.choice(self.tower_ids)})

  def _close(self, connection: "BotConnection") -> None:
    if not self.args.abrupt:
      return
    linger = struct.pack("ii", 1, 0)
    connection.sock.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, linger)


class BotConnection:
  """Non-blocking framed socket used by the bot."""

  def __init__(self, sock: socket.socket) -> None:
    self.sock = sock
    self.buffer = bytearray()

  def send(self, message_type: str, payload: dict) -> None:
    """Send a complete frame, handling a temporarily full socket."""
    frame = encode_message(message_type, payload)
    offset = 0
    while offset < len(frame):
      try:
        offset += self.sock.send(frame[offset:])
      except BlockingIOError:
        select.select([], [self.sock], [], 1)

  def poll(self) -> list[dict]:
    """Read available bytes and return every complete decoded frame."""
    readable, _, _ = select.select([self.sock], [], [], 0)
    if not readable:
      return []
    while True:
      try:
        chunk = self.sock.recv(65536)
      except BlockingIOError:
        break
      if not chunk:
        break
      self.buffer.extend(chunk)
    return self._decode_frames()

  def _decode_frames(self) -> list[dict]:
    messages = []
    while len(self.buffer) >= 4:
      size = struct.unpack(">I", self.buffer[:4])[0]
      if size <= 0 or size > MAX_FRAME_SIZE:
        self.buffer.clear()
        break
      if len(self.buffer) < 4 + size:
        break
      body = bytes(self.buffer[4:4 + size])
      del self.buffer[:4 + size]
      messages.append(json.loads(body.decode("utf-8")))
    return messages


def parse_args() -> argparse.Namespace:
  """Parse bot command-line options."""
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--host", default="127.0.0.1")
  parser.add_argument("--port", type=int, default=5000)
  parser.add_argument("--name", default="bot")
  parser.add_argument("--duration", type=float, default=DEFAULT_DURATION_SECONDS)
  parser.add_argument("--seed", type=int, default=1)
  parser.add_argument(
    "--buy-interval",
    type=float,
    default=DEFAULT_BUY_INTERVAL_SECONDS,
  )
  parser.add_argument(
    "--ping-interval",
    type=float,
    default=DEFAULT_PING_INTERVAL_SECONDS,
  )
  parser.add_argument(
    "--sell-interval",
    type=float,
    default=DEFAULT_SELL_INTERVAL_SECONDS,
  )
  parser.add_argument("--abrupt", action="store_true")
  return parser.parse_args()


if __name__ == "__main__":
  BotClient(parse_args()).run()
