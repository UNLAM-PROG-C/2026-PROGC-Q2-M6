extends Control

const ProtocolConstants = preload("res://scripts/protocol_constants.gd")

@onready var host_label: Label = $Panel/MarginContainer/Content/HostLabel
@onready var host_input: LineEdit = $Panel/MarginContainer/Content/ConnectionRow/HostInput
@onready var copy_button: Button = $Panel/MarginContainer/Content/ConnectionRow/CopyButton
@onready var status_label: Label = $Panel/MarginContainer/Content/StatusLabel
@onready var connect_button: Button = $Panel/MarginContainer/Content/ConnectButton
@onready var create_party_button: Button = $Panel/MarginContainer/Content/CreatePartyButton
@onready var start_button: Button = $Panel/MarginContainer/Content/StartButton

const MODEL_IP := "127.0.0.1:5000"
const MAX_PLAYERS := 4

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
var _using_model_ip := true
var _disconnect_reason := ""


func _ready() -> void:
	connect_button.pressed.connect(_on_connect_pressed)
	create_party_button.pressed.connect(_on_create_party_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	start_button.pressed.connect(_on_start_match_pressed)
	host_input.focus_entered.connect(_on_host_input_focus_entered)
	host_input.gui_input.connect(_on_host_input_gui_input)
	host_label.text = "Pega el IP para conectarte"
	host_input.text = MODEL_IP
	host_input.placeholder_text = MODEL_IP
	_using_model_ip = true
	start_button.visible = false
	start_button.disabled = true
	status_label.text = "Listo para crear o unirte a una partida."
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


func _on_host_input_focus_entered() -> void:
	if _using_model_ip:
		_using_model_ip = false
		host_input.text = ""


func _on_host_input_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _using_model_ip:
		_using_model_ip = false
		host_input.text = ""


func _on_connect_pressed() -> void:
	var connection := _parse_connection_code(host_input.text)
	if connection.is_empty():
		status_label.text = "Pega una direccion valida con formato IP:puerto."
		return
	var host: String = connection[0]
	var port: int = connection[1]
	_disconnect_reason = ""
	_vpn_activation_required = false
	host_label.text = "Pega el IP para conectarte"
	_start_vpn_for_join(host, port)


func _on_copy_pressed() -> void:
	var connection_code := host_input.text.strip_edges()
	if connection_code.is_empty():
		return
	DisplayServer.clipboard_set(connection_code)


func _on_connection_requested(host: String, port: int) -> void:
	if not _creating_game:
		status_label.text = "Conectando a %s:%d..." % [host, port]


func _on_connected() -> void:
	if _is_host:
		status_label.text = _share_message + "\nPartida creada. Esperando jugadores."
		start_button.text = "Iniciar partida"
	else:
		status_label.text = "Unido a la partida. Esperando que el anfitrion inicie..."
	_update_start_button()


func _on_connection_failed(message: String) -> void:
	var was_joining := not _is_host and not _creating_game
	_joining_vpn = false
	_creating_game = false
	_starting_docker = false
	connect_button.disabled = false
	create_party_button.disabled = false
	start_button.visible = false
	start_button.disabled = true
	if not _disconnect_reason.is_empty():
		status_label.text = _disconnect_reason
		return
	if was_joining:
		var vpn_net := _detect_radmin_vpn_network()
		if not vpn_net.is_empty():
			status_label.text = (
				"%s\nEstas conectado a la red VPN '%s'. Decile a tus amigos que se conecten a esa misma red en Radmin VPN."
				% [message, vpn_net]
			)
		else:
			status_label.text = (
				"%s\nVerifica que vos y tus amigos esten conectados a la misma red en Radmin VPN."
				% message
			)
	else:
		status_label.text = message


func _on_disconnected() -> void:
	start_button.visible = false
	start_button.disabled = true
	connect_button.disabled = false
	create_party_button.disabled = false
	_is_host = false
	_players_count = 0
	if not _disconnect_reason.is_empty():
		status_label.text = _disconnect_reason
	else:
		status_label.text = "Desconectado del servidor."


func _on_welcome(payload: Dictionary) -> void:
	_disconnect_reason = ""
	_is_host = bool(payload.get("is_host", _is_host))
	_game_started = bool(payload.get("game_started", false))
	_players_count = int(payload.get("players", _players_count))
	_minimum_players = 2
	if _is_host:
		host_label.text = "IP: pasale esto a tus amigos"
		start_button.visible = true
		status_label.text = "Servidor iniciado. Esperando otros jugadores.\nJugadores conectados: %d/%d" % [
			_players_count, MAX_PLAYERS
		]
		start_button.text = "Iniciar partida"
	else:
		start_button.visible = false
		status_label.text = "Esperando a que el host inicie la partida.\nJugadores conectados: %d/%d" % [
			_players_count, MAX_PLAYERS
		]
	_update_start_button()


func _update_start_button() -> void:
	start_button.disabled = (
		not _is_host
		or _players_count < 2
		or not NetworkClient.is_connected_to_server()
	)


func _on_create_party_pressed() -> void:
	status_label.text = "Preparando la partida..."
	_disconnect_reason = ""
	_vpn_activation_required = false
	_using_model_ip = false
	host_label.text = "IP: pasale esto a tus amigos"
	create_party_button.disabled = true
	connect_button.disabled = true
	_creating_game = true
	_is_host = true
	_start_vpn()


func _on_start_match_pressed() -> void:
	if not _is_host:
		return
	if _players_count < _minimum_players:
		status_label.text = "Se necesitan al menos %d jugadores para iniciar la partida." % _minimum_players
		start_button.disabled = true
		return
	NetworkClient.send_message(ProtocolConstants.START_GAME, {})
	start_button.disabled = true
	status_label.text = "Iniciando partida para todos..."


func _send_ready() -> void:
	NetworkClient.send_message(ProtocolConstants.READY, {})
	start_button.disabled = true
	if _share_message.is_empty():
		status_label.text = "Esperando a que los demas jugadores inicien..."
	else:
		status_label.text = _share_message + "\nEsperando jugadores..."


func _start_local_stack() -> void:
	_creating_game = true
	_is_host = true
	_start_vpn()


func _start_vpn() -> void:
	var script_path := _find_stack_script()
	if not FileAccess.file_exists(script_path):
		_creating_game = false
		_joining_vpn = false
		create_party_button.disabled = false
		connect_button.disabled = false
		status_label.text = "Error en Radmin VPN: No se encontro el script de inicio: %s" % script_path
		return
	if _creating_game:
		_ready_after_stack = true
	else:
		_joining_vpn = true
	create_party_button.disabled = true
	connect_button.disabled = true
	status_label.text = "Iniciando Radmin VPN..."
	_clear_stack_status()
	_stack_process_id = OS.create_process("powershell.exe", [
		"-NoProfile",
		"-WindowStyle",
		"Hidden",
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
		create_party_button.disabled = false
		connect_button.disabled = false
		status_label.text = "Error en Radmin VPN: No se pudo iniciar el proceso."


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
		create_party_button.disabled = false
		connect_button.disabled = false
		status_label.text = "Error en Docker: No se encontro el script de inicio: %s" % script_path
		return
	_starting_docker = true
	create_party_button.disabled = true
	connect_button.disabled = true
	start_button.disabled = true
	status_label.text = "Radmin VPN conectado. Iniciando Docker y servidor en segundo plano..."
	_clear_stack_status()
	_stack_process_id = OS.create_process("powershell.exe", [
		"-NoProfile",
		"-WindowStyle",
		"Hidden",
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
		create_party_button.disabled = false
		connect_button.disabled = false
		status_label.text = "Error en Docker: No se pudo iniciar el proceso. Revisa que Docker Desktop este instalado."


func _find_stack_script() -> String:
	var project_script := ProjectSettings.globalize_path("res://../start-stack.ps1")
	if FileAccess.file_exists(project_script):
		return project_script
	var executable_dir := OS.get_executable_path().get_base_dir()
	var local_script := executable_dir.path_join("start-stack.ps1")
	if FileAccess.file_exists(local_script):
		return local_script
	var executable_root := executable_dir.get_base_dir()
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
		status_label.text = "El proceso de inicio supero los 3 minutos. Revisa permisos, Radmin VPN y Docker Desktop."
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
		create_party_button.disabled = false
		start_button.disabled = true
		status_label.text = "Radmin VPN esta desconectado. Por favor conecte el VPN y vuelva a intentar."
		OS.alert(
			"Por favor conecte el VPN.\n\nEncienda el boton en Radmin VPN y vuelva a intentar.",
			"Radmin VPN"
		)
		return
	if state == "ready":
		_stack_process_id = -1
		_starting_docker = false
		_is_host = true
		connect_button.disabled = false
		create_party_button.disabled = false
		_share_message = message
		_connection_code = _connection_code_from_status(message)
		if _connection_code.is_empty():
			_stack_process_id = -1
			_ready_after_stack = false
			start_button.disabled = false
			status_label.text = "El servidor inicio, pero no devolvio una direccion IP:puerto valida."
			return
		_using_model_ip = false
		host_label.text = "IP: pasale esto a tus amigos"
		host_input.text = _connection_code
		status_label.text = "Servidor iniciado. Conectando..."
		var connection := _parse_connection_code(_connection_code)
		NetworkClient.request_connection("127.0.0.1", connection[1])
	elif state == "error":
		_stack_process_id = -1
		_ready_after_stack = false
		_is_host = false
		_joining_vpn = false
		_creating_game = false
		_starting_docker = false
		connect_button.disabled = false
		create_party_button.disabled = false
		start_button.disabled = true
		status_label.text = message


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


func _detect_radmin_vpn_network() -> String:
	var log_path := "C:/ProgramData/Famatech/Radmin VPN/service.log"
	if not FileAccess.file_exists(log_path):
		return ""
	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		return ""
	var content := file.get_as_text()
	file.close()
	var active_networks: Array[String] = []
	for line in content.split("\n"):
		var net_idx := line.find("network '")
		if net_idx < 0:
			continue
		var start := net_idx + "network '".length()
		var end := line.find("'", start)
		if end <= start:
			continue
		var net_name := line.substr(start, end - start).strip_edges()
		if net_name.is_empty():
			continue
		var lower := line.to_lower()
		if lower.find("leave network '") >= 0 or lower.find("remove network '") >= 0 or lower.find("removed network '") >= 0 or lower.find("left network '") >= 0:
			active_networks.erase(net_name)
		elif lower.find("create network '") >= 0 or lower.find("join network '") >= 0 or lower.find("joined network '") >= 0:
			if not active_networks.has(net_name):
				active_networks.append(net_name)
	if active_networks.is_empty():
		return ""
	return active_networks[active_networks.size() - 1]


func show_waiting_for_start() -> void:
	visible = true


func _on_state_update(_payload: Dictionary) -> void:
	pass


func _on_wave_start(_payload: Dictionary) -> void:
	pass


func _on_base_damage(_payload: Dictionary) -> void:
	pass


func _on_game_over(_payload: Dictionary) -> void:
	pass


func reset_lobby() -> void:
	_is_host = false
	_share_message = ""
	_connection_code = ""
	_vpn_activation_required = false
	_game_started = false
	_players_count = 0
	_disconnect_reason = ""
	_using_model_ip = true
	host_label.text = "Pega el IP para conectarte"
	host_input.text = MODEL_IP
	start_button.text = "Iniciar partida"
	start_button.visible = false
	start_button.disabled = true
	create_party_button.disabled = false
	connect_button.disabled = false
	status_label.text = "Partida reiniciada. Podes crear o unirte nuevamente."


func _on_error(payload: Dictionary) -> void:
	var code := String(payload.get("code", ""))
	if code == "MAX_PLAYERS":
		_disconnect_reason = "Servidor lleno (4/4 jugadores)."
		status_label.text = _disconnect_reason
		connect_button.disabled = false
		create_party_button.disabled = false
		start_button.visible = false
		start_button.disabled = true
		NetworkClient.disconnect_from_server()
		return
	if code == "GAME_ALREADY_STARTED":
		_disconnect_reason = "La partida ya esta en curso."
		status_label.text = _disconnect_reason
		return
	status_label.text = "Error: %s" % payload.get("message", "Unknown error")
