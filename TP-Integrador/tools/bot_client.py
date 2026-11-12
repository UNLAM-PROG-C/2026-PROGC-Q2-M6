"""Small TCP bot for integration and concurrency tests."""

from __future__ import annotations

import argparse
import json
import random
import select
import socket
import struct
import time

from servidor.constants import LANE_COUNT, SERVER_PORT, TOWER_STATS
from servidor.protocol import (
  BUY_TOWER,
  HELLO,
  PING,
  READY,
  SELL_TOWER,
  STATE_UPDATE,
  WELCOME,
  FRAME_HEADER_SIZE,
  MAX_FRAME_SIZE,
  encode_message,
)


DEFAULT_DURATION_SECONDS = 10.0
DEFAULT_BUY_INTERVAL_SECONDS = 0.25
DEFAULT_PING_INTERVAL_SECONDS = 1.0
DEFAULT_SELL_INTERVAL_SECONDS = 1.5
DEFAULT_HOST = "127.0.0.1"
DEFAULT_NAME = "bot"
DEFAULT_SEED = 1
CONNECT_TIMEOUT_SECONDS = 3.0
WELCOME_TIMEOUT_SECONDS = 3.0
LOOP_SLEEP_SECONDS = 0.01
SEND_RETRY_TIMEOUT_SECONDS = 1.0
RECV_CHUNK_SIZE = 65536
MILLISECONDS_PER_SECOND = 1000
POSITION_X_RANGE = (50, 900)
POSITION_Y_RANGE = (80, 460)
FRAME_HEADER_FORMAT = ">I"
LINGER_ENABLED = 1
LINGER_TIMEOUT_SECONDS = 0


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
    address = (self.args.host, self.args.port)
    with socket.create_connection(
      address, timeout=CONNECT_TIMEOUT_SECONDS
    ) as sock:
      sock.setblocking(False)
      connection = BotConnection(sock)
      self._handshake(connection)
      self._run_loop(connection)
      self._close(connection)

  def _handshake(self, connection: "BotConnection") -> None:
    connection.send(HELLO, {"name": self.args.name})
    welcome = self._read_until(connection, WELCOME, WELCOME_TIMEOUT_SECONDS)
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
      self._run_due_actions(connection, time.monotonic())
      time.sleep(LOOP_SLEEP_SECONDS)

  def _run_due_actions(self, connection: "BotConnection", now: float) -> None:
    if now >= self.next_buy:
      self._buy_random_tower(connection)
      self.next_buy = now + self.args.buy_interval
    if self.args.ping_interval > 0 and now >= self.next_ping:
      sequence = int(now * MILLISECONDS_PER_SECOND)
      connection.send(PING, {"sequence": sequence})
      self.next_ping = now + self.args.ping_interval
    if self.args.sell_interval > 0 and now >= self.next_sell:
      self._sell_random_tower(connection)
      self.next_sell = now + self.args.sell_interval

  def _read_available(self, connection: "BotConnection") -> None:
    for message in connection.poll():
      if message.get("type") == STATE_UPDATE:
        self.tower_ids = [
          tower["tower_id"] for tower in message["payload"].get("towers", [])
        ]
        payload = message["payload"]
        print(f"{self.args.name}: STATE_UPDATE {payload}", flush=True)

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
      time.sleep(LOOP_SLEEP_SECONDS)
    return None

  def _buy_random_tower(self, connection: "BotConnection") -> None:
    tower_type = self.random.choice(tuple(TOWER_STATS))
    payload = {
      "tower_type": tower_type,
      "lane": self.random.randrange(LANE_COUNT),
      "pos": [
        self.random.randrange(*POSITION_X_RANGE),
        self.random.randrange(*POSITION_Y_RANGE),
      ],
    }
    connection.send(BUY_TOWER, payload)

  def _sell_random_tower(self, connection: "BotConnection") -> None:
    if self.tower_ids:
      tower_id = self.random.choice(self.tower_ids)
      connection.send(SELL_TOWER, {"tower_id": tower_id})

  def _close(self, connection: "BotConnection") -> None:
    if not self.args.abrupt:
      return
    linger = struct.pack("ii", LINGER_ENABLED, LINGER_TIMEOUT_SECONDS)
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
        select.select([], [self.sock], [], SEND_RETRY_TIMEOUT_SECONDS)

  def poll(self) -> list[dict]:
    """Read available bytes and return every complete decoded frame."""
    readable, _, _ = select.select([self.sock], [], [], 0)
    if not readable:
      return []
    while True:
      try:
        chunk = self.sock.recv(RECV_CHUNK_SIZE)
      except BlockingIOError:
        break
      if not chunk:
        break
      self.buffer.extend(chunk)
    return self._decode_frames()

  def _decode_frames(self) -> list[dict]:
    messages = []
    while len(self.buffer) >= FRAME_HEADER_SIZE:
      header = self.buffer[:FRAME_HEADER_SIZE]
      size = struct.unpack(FRAME_HEADER_FORMAT, header)[0]
      if size <= 0 or size > MAX_FRAME_SIZE:
        self.buffer.clear()
        break
      frame_end = FRAME_HEADER_SIZE + size
      if len(self.buffer) < frame_end:
        break
      body = bytes(self.buffer[FRAME_HEADER_SIZE:frame_end])
      del self.buffer[:frame_end]
      messages.append(json.loads(body.decode("utf-8")))
    return messages


def parse_args() -> argparse.Namespace:
  """Parse bot command-line options."""
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--host", default=DEFAULT_HOST)
  parser.add_argument("--port", type=int, default=SERVER_PORT)
  parser.add_argument("--name", default=DEFAULT_NAME)
  parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
  intervals = {
    "--duration": DEFAULT_DURATION_SECONDS,
    "--buy-interval": DEFAULT_BUY_INTERVAL_SECONDS,
    "--ping-interval": DEFAULT_PING_INTERVAL_SECONDS,
    "--sell-interval": DEFAULT_SELL_INTERVAL_SECONDS,
  }
  for flag, default in intervals.items():
    parser.add_argument(flag, type=float, default=default)
  parser.add_argument("--abrupt", action="store_true")
  return parser.parse_args()


if __name__ == "__main__":
  BotClient(parse_args()).run()
