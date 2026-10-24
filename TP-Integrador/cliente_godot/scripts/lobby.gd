extends Control

@onready var host_input: LineEdit = $Panel/MarginContainer/Content/HostInput
@onready var port_input: LineEdit = $Panel/MarginContainer/Content/PortInput
@onready var status_label: Label = $Panel/MarginContainer/Content/StatusLabel
@onready var connect_button: Button = $Panel/MarginContainer/Content/ConnectButton
@onready var start_button: Button = $Panel/MarginContainer/Content/StartButton


func _ready() -> void:
	port_input.text = str(ProtocolConstants.DEFAULT_PORT)
	connect_button.pressed.connect(_on_connect_pressed)
	start_button.pressed.connect(_on_start_pressed)
	start_button.disabled = true
	NetworkClient.connection_requested.connect(_on_connection_requested)
	NetworkClient.connected_to_server.connect(_on_connected)
	NetworkClient.connection_failed.connect(_on_connection_failed)
	NetworkClient.disconnected_from_server.connect(_on_disconnected)
	NetworkClient.welcome_received.connect(_on_welcome)
	NetworkClient.state_update_received.connect(_on_state_update)
	NetworkClient.wave_start_received.connect(_on_wave_start)
	NetworkClient.base_damage_received.connect(_on_base_damage)
	NetworkClient.game_over_received.connect(_on_game_over)
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
	start_button.disabled = false


func _on_connection_failed(message: String) -> void:
	status_label.text = message


func _on_disconnected() -> void:
	status_label.text = "Disconnected"
	start_button.disabled = true


func _on_welcome(payload: Dictionary) -> void:
	var players := int(payload.get("players", 0))
	var minimum := int(payload.get("min_players", 2))
	status_label.text = "%d jugador(es) conectado(s). Se necesitan %d." % [
		players, minimum
	]
	start_button.disabled = players < minimum or bool(payload.get("game_started", false))


func _on_start_pressed() -> void:
	NetworkClient.send_message(ProtocolConstants.READY, {})
	start_button.disabled = true
	status_label.text = "Esperando a que los demás jugadores inicien..."


func show_waiting_for_start() -> void:
	visible = true


func _on_state_update(payload: Dictionary) -> void:
	status_label.text = "Wave %s | Gold %s | Base %s" % [
		payload.get("current_wave", 0),
		payload.get("gold", 0),
		payload.get("base_hp", 0),
	]
	if int(payload.get("current_wave", 0)) == 0:
		show_waiting_for_start()


func _on_wave_start(payload: Dictionary) -> void:
	status_label.text = "Wave %s started" % payload.get("wave", "?")


func _on_base_damage(payload: Dictionary) -> void:
	status_label.text = "Base damaged: %s HP left" % payload.get("base_hp", "?")


func _on_game_over(payload: Dictionary) -> void:
	status_label.text = "%s: %s" % [
		payload.get("result", "GAME OVER"), payload.get("reason", "")
	]


func _on_error(payload: Dictionary) -> void:
	status_label.text = "Error: %s" % payload.get("message", "Unknown error")
