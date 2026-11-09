extends Control

const ProtocolConstants = preload("res://scripts/protocol_constants.gd")

@onready var host_input: LineEdit = $Panel/MarginContainer/Content/ConnectionRow/HostInput
@onready var copy_button: Button = $Panel/MarginContainer/Content/ConnectionRow/CopyButton
@onready var status_label: Label = $Panel/MarginContainer/Content/StatusLabel
@onready var connect_button: Button = $Panel/MarginContainer/Content/ConnectButton
@onready var create_party_button: Button = $Panel/MarginContainer/Content/CreatePartyButton
@onready var start_button: Button = $Panel/MarginContainer/Content/StartButton
var _stack_process_id: int = -1
var _stack_status_path: String
var _last_stack_timestamp := ""
var _ready_after_stack := false
var _is_host := false
var _stack_started_at := 0
var _share_message := ""
var _connection_code := ""
var _pending_join_host := ""
var _pending_join_port := 0
var _joining_vpn := false
var _creating_game := false
var _starting_docker := false
var _vpn_activation_required := false
var _game_started := false
var _players_count := 0
var _minimum_players := 2
const MAX_PLAYERS := 4


func _ready() -> void:
	connect_button.pressed.connect(_on_connect_pressed)
	create_party_button.pressed.connect(_on_start_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	start_button.pressed.connect(_on_start_pressed)
	start_button.disabled = false
	status_label.text = "Listo para crear una partida."
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
	_stack_status_path = ProjectSettings.globalize_path(
		"user://stack-status-%s.json" % str(OS.get_process_id())
	)


func _process(_delta: float) -> void:
	if _stack_process_id < 0:
		return
	_poll_stack_status()


func _on_connect_pressed() -> void:
	var connection := _parse_connection_code(host_input.text)
	if connection.is_empty():
		status_label.text = "Pegá una dirección válida con formato IP:puerto."
		return
	var host: String = connection[0]
	var port: int = connection[1]
	if _vpn_activation_required:
		_vpn_activation_required = false
		connect_button.disabled = true
		status_label.text = "Conectando a %s:%d..." % [host, port]
		NetworkClient.request_connection(host, port)
		return
	_start_vpn_for_join(host, port)


func _on_copy_pressed() -> void:
	var connection_code := host_input.text.strip_edges()
	if connection_code.is_empty():
		return
	DisplayServer.clipboard_set(connection_code)


func _on_connection_requested(host: String, port: int) -> void:
	if not _is_creating_party:
		status_label.text = "Conectando a %s:%d..." % [host, port]


func _on_connected() -> void:
	if _is_host:
		status_label.text = _share_message + "\nPartida creada. Esperando jugadores."
		start_button.text = "Iniciar partida"
	else:
		status_label.text = "Unido a la partida. Esperando que el anfitrión inicie..."
	_update_start_button()


func _on_connection_failed(message: String) -> void:
	_joining_vpn = false
	connect_button.disabled = false
	start_button.disabled = false
	status_label.text = message
	connect_button.disabled = false


func _on_disconnected() -> void:
	status_label.text = "Disconnected"
	start_button.disabled = true
	connect_button.disabled = false
	start_button.disabled = false


func _on_welcome(payload: Dictionary) -> void:
	_is_host = bool(payload.get("is_host", _is_host))
	_game_started = bool(payload.get("game_started", false))
	_players_count = int(payload.get("players", _players_count))
	_minimum_players = int(payload.get("min_players", _minimum_players))
	if _is_host:
		status_label.text = "%s\nPartida creada. Esperando jugadores.\nJugadores activos: %d/%d" % [
			_share_message, _players_count, MAX_PLAYERS
		]
		start_button.text = "Iniciar partida"
	else:
		status_label.text = "Unido a la partida. Esperando que el anfitrión inicie.\nJugadores activos: %d/%d" % [
			_players_count, MAX_PLAYERS
		]
		if _game_started:
			status_label.text = "La partida está comenzando..."
	_update_start_button()


func _update_start_button() -> void:
	start_button.disabled = (
		not _is_host
		or _players_count < _minimum_players
		or _game_started
		or not NetworkClient.is_connected_to_server()
	)


func _on_start_pressed() -> void:
	status_label.text = "Preparando la partida..."
	if _vpn_activation_required:
		_vpn_activation_required = false
		if _is_host:
			_start_docker()
		else:
			connect_button.disabled = true
			status_label.text = "Conectando a %s:%d..." % [_pending_join_host, _pending_join_port]
			NetworkClient.request_connection(_pending_join_host, _pending_join_port)
		return
	if NetworkClient.server_host.is_empty():
		status_label.text = "Enter a valid host first."
		return
	if not NetworkClient.is_connected_to_server():
		_start_local_stack()
		return
	if _is_host:
		if _players_count < 2:
			status_label.text = "Esperando al menos 2 jugadores para iniciar."
			start_button.disabled = true
			return
		NetworkClient.send_message(ProtocolConstants.START_GAME, {})
		start_button.disabled = true
		status_label.text = "Iniciando partida para todos..."
	else:
		status_label.text = "Esperando que el anfitrión inicie la partida..."


func _send_ready() -> void:
	NetworkClient.send_message(ProtocolConstants.READY, {})
	start_button.disabled = true
	if _share_message.is_empty():
		status_label.text = "Esperando a que los demás jugadores inicien..."
	else:
		status_label.text = _share_message + "\nEsperando jugadores..."


func _start_local_stack() -> void:
	_creating_game = true
	_is_host = true
	_start_vpn()


func _start_vpn() -> void:
	var port := ProtocolConstants.DEFAULT_PORT
	var script_path := _find_stack_script()
	if not FileAccess.file_exists(script_path):
		_creating_game = false
		_joining_vpn = false
		status_label.text = "No se encontró el script de inicio de Radmin VPN: %s" % script_path
		return
	if _creating_game:
		_ready_after_stack = true
		start_button.disabled = true
	else:
		_joining_vpn = true
	connect_button.disabled = true
	status_label.text = "Iniciando Radmin VPN..."
	_clear_stack_status()
	_stack_process_id = OS.create_process("powershell.exe", [
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		script_path,
		"-OnlyVpn",
		"-StatusPath",
		_stack_status_path,
	])
	_stack_started_at = Time.get_ticks_msec()
	if _stack_process_id < 0:
		_stack_process_id = -1
		_ready_after_stack = false
		_is_host = false
		_creating_game = false
		_joining_vpn = false
		connect_button.disabled = false
		start_button.disabled = false
		status_label.text = "No se pudo iniciar Radmin VPN."


func _start_vpn_for_join(host: String, port: int) -> void:
	_pending_join_host = host
	_pending_join_port = port
	_creating_game = false
	_is_host = false
	_start_vpn()


func _start_docker() -> void:
	var script_path := _find_stack_script()
	if not FileAccess.file_exists(script_path):
		_creating_game = false
		_ready_after_stack = false
		connect_button.disabled = false
		start_button.disabled = false
		status_label.text = "No se encontró el script de inicio de Docker: %s" % script_path
		return
	_starting_docker = true
	connect_button.disabled = true
	start_button.disabled = true
	status_label.text = "Radmin VPN iniciado. Iniciando Docker y servidor..."
	_clear_stack_status()
	_stack_process_id = OS.create_process("powershell.exe", [
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		script_path,
		"-Port",
		str(ProtocolConstants.DEFAULT_PORT),
		"-SkipVpn",
		"-StatusPath",
		_stack_status_path,
	])
	_stack_started_at = Time.get_ticks_msec()
	if _stack_process_id < 0:
		_stack_process_id = -1
	_starting_docker = false
	_creating_game = false
	_ready_after_stack = false
	_is_host = false
	connect_button.disabled = false
	start_button.disabled = false
	status_label.text = "No se pudo iniciar Docker. Revisá que Docker Desktop esté instalado."


func _find_stack_script() -> String:
	var project_script := ProjectSettings.globalize_path("res://../start-stack.ps1")
	if FileAccess.file_exists(project_script):
		return project_script
	var executable_root := OS.get_executable_path().get_base_dir().get_base_dir()
	return executable_root.path_join("start-stack.ps1")


func _clear_stack_status() -> void:
	if not FileAccess.file_exists(_stack_status_path):
		return
	var status_file := FileAccess.open(_stack_status_path, FileAccess.READ)
	if status_file:
		status_file.close()
	DirAccess.remove_absolute(_stack_status_path)


func _poll_stack_status() -> void:
	if Time.get_ticks_msec() - _stack_started_at > 180000 and not FileAccess.file_exists(_stack_status_path):
		_stack_process_id = -1
		_ready_after_stack = false
		_creating_game = false
		_starting_docker = false
		_joining_vpn = false
		_is_host = false
		connect_button.disabled = false
		start_button.disabled = false
		status_label.text = "El proceso de inicio superó los 3 minutos. Revisá permisos, Radmin VPN y Docker Desktop."
		return
	if not FileAccess.file_exists(_stack_status_path):
		return
	var file := FileAccess.open(_stack_status_path, FileAccess.READ)
	if file == null:
		return
	var contents := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(contents)
	if not parsed is Dictionary:
		return
	var timestamp := String(parsed.get("timestamp", ""))
	if timestamp == _last_stack_timestamp:
		return
	_last_stack_timestamp = timestamp
	var state := String(parsed.get("state", ""))
	var message := String(parsed.get("message", ""))
	status_label.text = message
	if state == "vpn_ready":
		_stack_process_id = -1
		if _creating_game:
			_start_docker()
		else:
			_joining_vpn = false
			connect_button.disabled = false
			status_label.text = "Radmin VPN abierto. Conectando a %s:%d..." % [
				_pending_join_host, _pending_join_port
			]
			NetworkClient.request_connection(_pending_join_host, _pending_join_port)
		return
	if state == "vpn_needs_activation":
		_stack_process_id = -1
		_vpn_activation_required = true
		_joining_vpn = false
		connect_button.disabled = false
		start_button.disabled = false
		status_label.text = "Radmin VPN está desconectado. Encendé el botón naranja y volvé a intentar."
		OS.alert(
			"Radmin VPN está desconectado.\n\nEncendé el botón naranja en Radmin VPN y luego presioná nuevamente el botón del juego.",
			"Activar Radmin VPN"
		)
		return
	if state == "ready":
		_stack_process_id = -1
		_starting_docker = false
		_is_host = true
		connect_button.disabled = false
		_share_message = message
		_connection_code = _connection_code_from_status(message)
		if _connection_code.is_empty():
			_stack_process_id = -1
			_ready_after_stack = false
			start_button.disabled = false
			status_label.text = "El servidor inició, pero no devolvió una dirección IP:puerto válida."
			return
		host_input.text = _connection_code
		status_label.text = _share_message
		var connection := _parse_connection_code(_connection_code)
		NetworkClient.request_connection(connection[0], connection[1])
	elif state == "error":
		_stack_process_id = -1
		_ready_after_stack = false
		_is_host = false
		_joining_vpn = false
		_creating_game = false
		_starting_docker = false
		connect_button.disabled = false
		start_button.disabled = false
		status_label.text = "No se pudo iniciar: %s" % message


func _parse_connection_code(value: String) -> Array:
	var code := value.strip_edges()
	var separator := code.rfind(":")
	if separator <= 0 or separator >= code.length() - 1:
		return []
	var host := code.substr(0, separator).strip_edges()
	var port_text := code.substr(separator + 1).strip_edges()
	if host.is_empty() or not port_text.is_valid_int():
		return []
	var port := int(port_text)
	if port < 1 or port > 65535:
		return []
	return [host, port]


func _connection_code_from_status(message: String) -> String:
	var marker := "IP para tus amigos: "
	var marker_position := message.find(marker)
	if marker_position < 0:
		return ""
	var code := message.substr(marker_position + marker.length()).strip_edges()
	var separator := code.find(" | Puerto: ")
	if separator < 0:
		return ""
	return "%s:%s" % [
		code.substr(0, separator).strip_edges(),
		code.substr(separator + " | Puerto: ".length()).strip_edges(),
	]


func show_waiting_for_start() -> void:
	visible = true


func _on_state_update(payload: Dictionary) -> void:
	if _is_host or not _share_message.is_empty():
		return
	if int(payload.get("current_wave", 0)) == 0:
		return
	status_label.text = "Wave %s | Gold %s | Base %s" % [
		payload.get("current_wave", 0),
		payload.get("gold", 0),
		payload.get("base_hp", 0),
	]


func _on_wave_start(payload: Dictionary) -> void:
	status_label.text = "Wave %s started" % payload.get("wave", "?")


func _on_base_damage(payload: Dictionary) -> void:
	status_label.text = "Base damaged: %s HP left" % payload.get("base_hp", "?")


func _on_game_over(payload: Dictionary) -> void:
	status_label.text = "%s: %s" % [
		payload.get("result", "GAME OVER"), payload.get("reason", "")
	]

func reset_lobby() -> void:
	_is_host = false
	_share_message = ""
	_connection_code = ""
	_vpn_activation_required = false
	_game_started = false
	_players_count = 0
	start_button.text = "Crear partida"
	start_button.disabled = false
	status_label.text = "Partida reiniciada. Podés crear o unirte nuevamente."


func _on_error(payload: Dictionary) -> void:
	status_label.text = "Error: %s" % payload.get("message", "Unknown error")
