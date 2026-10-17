extends Control

@onready var host_input: LineEdit = $Panel/MarginContainer/Content/HostInput
@onready var port_input: LineEdit = $Panel/MarginContainer/Content/PortInput
@onready var status_label: Label = $Panel/MarginContainer/Content/StatusLabel
@onready var connect_button: Button = $Panel/MarginContainer/Content/ConnectButton


func _ready() -> void:
  port_input.text = str(ProtocolConstants.DEFAULT_PORT)
  connect_button.pressed.connect(_on_connect_pressed)
  NetworkClient.connection_requested.connect(_on_connection_requested)
  NetworkClient.connected_to_server.connect(_on_connected)
  NetworkClient.connection_failed.connect(_on_connection_failed)
  NetworkClient.disconnected_from_server.connect(_on_disconnected)
  NetworkClient.welcome_received.connect(_on_welcome)
  NetworkClient.state_update_received.connect(_on_state_update)
  NetworkClient.error_received.connect(_on_error)


func _on_connect_pressed() -> void:
  var host := host_input.text.strip_edges()
  var port_text := port_input.text.strip_edges()
  if host.is_empty() or not port_text.is_valid_int():
    status_label.text = "Enter a valid host and port."
    return
  NetworkClient.request_connection(host, int(port_text))


func _on_connection_requested(host: String, port: int) -> void:
  status_label.text = "Connecting to %s:%d" % [host, port]


func _on_connected() -> void:
  status_label.text = "Connected. Waiting for game state..."


func _on_connection_failed(message: String) -> void:
  status_label.text = message


func _on_disconnected() -> void:
  status_label.text = "Disconnected"


func _on_welcome(payload: Dictionary) -> void:
  status_label.text = "Player %s connected (%s players)" % [
    payload.get("player_id", "?"), payload.get("players", "?")
  ]


func _on_state_update(payload: Dictionary) -> void:
  status_label.text = "Wave %s | Gold %s | Base %s" % [
    payload.get("current_wave", 0),
    payload.get("gold", 0),
    payload.get("base_hp", 0),
  ]


func _on_error(payload: Dictionary) -> void:
  status_label.text = "Error: %s" % payload.get("message", "Unknown error")
