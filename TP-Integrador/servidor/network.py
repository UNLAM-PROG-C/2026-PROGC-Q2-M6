"""Threaded TCP networking for the authoritative game server."""

from __future__ import annotations

import queue
import socket
import threading
from dataclasses import dataclass
from typing import Any

from servidor.constants import CLIENT_SOCKET_TIMEOUT_SECONDS
from servidor.protocol import (
  CLIENT_MESSAGE_TYPES,
  ProtocolError,
  recv_message,
)


CONNECT = "CONNECT"
DISCONNECT = "DISCONNECT"
MESSAGE = "MESSAGE"
INVALID = "INVALID"


@dataclass
class ClientConnection:
  """Socket and identity information for one connected player."""

  player_id: int
  sock: socket.socket
  address: tuple[str, int]
  name: str = ""


@dataclass
class ClientCommand:
  """Command transferred from a client thread to the game loop."""

  kind: str
  client: ClientConnection
  message: dict[str, Any] | None = None


def create_listener(host: str, port: int) -> socket.socket:
  """Create the reusable TCP listening socket."""
  listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
  listener.bind((host, port))
  listener.listen()
  listener.settimeout(CLIENT_SOCKET_TIMEOUT_SECONDS)
  return listener


class GameServer:
  """Accept clients and transfer their messages to the game loop."""

  def __init__(self, host: str, port: int) -> None:
    self.listener = create_listener(host, port)
    self.address = self.listener.getsockname()
    self.command_queue: queue.Queue[ClientCommand] = queue.Queue()
    self.stop_event = threading.Event()
    self._next_player_id = 1
    self._connections: list[ClientConnection] = []
    self._client_threads: list[threading.Thread] = []
    self._acceptor_thread: threading.Thread | None = None

  @property
  def acceptor_thread(self) -> threading.Thread | None:
    """Return the acceptor thread for lifecycle tests."""
    return self._acceptor_thread

  def start(self) -> None:
    """Start accepting clients."""
    self._acceptor_thread = threading.Thread(
      target=self._accept_loop,
      name="acceptor_thread",
      daemon=True,
    )
    self._acceptor_thread.start()

  def stop(self) -> None:
    """Stop accepting clients and close every socket."""
    self.stop_event.set()
    try:
      self.listener.close()
    except OSError:
      pass
    for connection in tuple(self._connections):
      self.close_connection(connection)

  def join(self, timeout: float = 2.0) -> None:
    """Wait briefly for acceptor and client threads to finish."""
    if self._acceptor_thread is not None:
      self._acceptor_thread.join(timeout)
    for thread in tuple(self._client_threads):
      thread.join(timeout)

  def send(self, client: ClientConnection, message_type: str, payload: dict) -> bool:
    """Send a message and report whether the socket is still usable."""
    from servidor.protocol import send_message

    try:
      send_message(client.sock, message_type, payload)
    except OSError:
      self.command_queue.put(ClientCommand(DISCONNECT, client))
      self.close_connection(client)
      return False
    return True

  def broadcast(
    self,
    message_type: str,
    payload: dict,
    clients: dict[int, ClientConnection],
  ) -> None:
    """Send one message to the current game-loop client snapshot."""
    for client in tuple(clients.values()):
      self.send(client, message_type, payload)

  def close_connection(self, client: ClientConnection) -> None:
    """Close one client socket without raising during shutdown."""
    try:
      client.sock.shutdown(socket.SHUT_RDWR)
    except OSError:
      pass
    try:
      client.sock.close()
    except OSError:
      pass

  def _accept_loop(self) -> None:
    while not self.stop_event.is_set():
      try:
        client_socket, address = self.listener.accept()
      except socket.timeout:
        continue
      except OSError:
        return
      self._start_client(client_socket, address)

  def _start_client(
    self,
    client_socket: socket.socket,
    address: tuple[str, int],
  ) -> None:
    client_socket.settimeout(CLIENT_SOCKET_TIMEOUT_SECONDS)
    client = ClientConnection(self._next_player_id, client_socket, address)
    self._next_player_id += 1
    self._connections.append(client)
    thread = threading.Thread(
      target=self._client_loop,
      args=(client,),
      name=f"client_thread_{client.player_id}",
      daemon=True,
    )
    self._client_threads.append(thread)
    self.command_queue.put(ClientCommand(CONNECT, client))
    thread.start()

  def _client_loop(self, client: ClientConnection) -> None:
    try:
      while not self.stop_event.is_set():
        try:
          message = recv_message(client.sock)
        except socket.timeout:
          continue
        except ProtocolError as error:
          self.command_queue.put(ClientCommand(
            INVALID, client, {"error": str(error)}
          ))
          continue
        except (ConnectionError, OSError):
          break
        if message is None:
          break
        self._enqueue_message(client, message)
    finally:
      self.command_queue.put(ClientCommand(DISCONNECT, client))
      self.close_connection(client)

  def _enqueue_message(
    self,
    client: ClientConnection,
    message: dict[str, Any],
  ) -> None:
    message_type = message.get("type")
    kind = MESSAGE if message_type in CLIENT_MESSAGE_TYPES else INVALID
    self.command_queue.put(ClientCommand(kind, client, message))
