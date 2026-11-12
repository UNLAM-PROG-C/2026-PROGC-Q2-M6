extends Control

const ProtocolConstants = preload("res://scripts/protocol_constants.gd")

const MODEL_IP := "127.0.0.1:5000"
const LOCAL_HOST := "127.0.0.1"
const MAX_PLAYERS := 4
const MIN_PLAYERS := 2
const MIN_PORT := 1
const MAX_PORT := 65535
const NO_PROCESS := -1
const STACK_TIMEOUT_MSEC := 180000
const STACK_SCRIPT_NAME := "start-stack.ps1"
const POWERSHELL := "powershell.exe"
const POWERSHELL_BASE_ARGS: PackedStringArray = [
	"-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File",
]
const RADMIN_LOG_PATH := "C:/ProgramData/Famatech/Radmin VPN/service.log"
const NETWORK_MARKER := "network '"
const LEAVE_MARKERS: Array[String] = [
	"leave network '", "remove network '", "removed network '", "left network '",
]
const JOIN_MARKERS: Array[String] = [
	"create network '", "join network '", "joined network '",
]
const STATUS_CODE_MARKER := "IP para tus amigos: "
const STATUS_PORT_MARKER := " | Puerto: "

const PASTE_IP_LABEL := "Pega el IP para conectarte"
const SHARE_IP_LABEL := "IP: pasale esto a tus amigos"
const START_TEXT := "Iniciar partida"
const READY_TEXT := "Listo para crear o unirte a una partida."
const INVALID_CODE_TEXT := "Pega una direccion valida con formato IP:puerto."
const CONNECTING_TEXT := "Conectando a %s:%d..."
const HOST_CONNECTED_TEXT := "\nPartida creada. Esperando jugadores."
const GUEST_CONNECTED_TEXT := "Unido a la partida. Esperando que el anfitrion inicie..."
const VPN_NETWORK_TEXT := ("%s\nEstas conectado a la red VPN '%s'. "
	+ "Decile a tus amigos que se conecten a esa misma red en Radmin VPN.")
const VPN_CHECK_TEXT := ("%s\nVerifica que vos y tus amigos esten conectados "
	+ "a la misma red en Radmin VPN.")
const DISCONNECTED_TEXT := "Desconectado del servidor."
const HOST_WAITING_TEXT := "Servidor iniciado. Esperando otros jugadores."
const GUEST_WAITING_TEXT := "Esperando a que el host inicie la partida."
const PLAYERS_TEXT := "\nJugadores conectados: %d/%d"
const PREPARING_TEXT := "Preparando la partida..."
const NOT_ENOUGH_PLAYERS_TEXT := "Se necesitan al menos %d jugadores para iniciar la partida."
const STARTING_MATCH_TEXT := "Iniciando partida para todos..."
const SCRIPT_NOT_FOUND_TEXT := "No se encontro el script de inicio: %s"
const VPN_ERROR_PREFIX := "Error en Radmin VPN: "
const DOCKER_ERROR_PREFIX := "Error en Docker: "
const VPN_STARTING_TEXT := "Iniciando Radmin VPN..."
const VPN_PROCESS_FAILED_TEXT := "Error en Radmin VPN: No se pudo iniciar el proceso."
const DOCKER_STARTING_TEXT := ("Radmin VPN conectado. "
	+ "Iniciando Docker y servidor en segundo plano...")
const DOCKER_PROCESS_FAILED_TEXT := ("Error en Docker: No se pudo iniciar el proceso. "
	+ "Revisa que Docker Desktop este instalado.")
const STACK_TIMEOUT_TEXT := ("El proceso de inicio supero los 3 minutos. "
	+ "Revisa permisos, Radmin VPN y Docker Desktop.")
const VPN_JOIN_CONNECTING_TEXT := "Radmin VPN abierto. Conectando a %s:%d..."
const VPN_DISCONNECTED_TEXT := ("Radmin VPN esta desconectado. "
	+ "Por favor conecte el VPN y vuelva a intentar.")
const VPN_ALERT_TEXT := ("Por favor conecte el VPN.\n\n"
	+ "Encienda el boton en Radmin VPN y vuelva a intentar.")
const VPN_ALERT_TITLE := "Radmin VPN"
const INVALID_ADDRESS_TEXT := "El servidor inicio, pero no devolvio una direccion IP:puerto valida."
const SERVER_CONNECTING_TEXT := "Servidor iniciado. Conectando..."
const LOBBY_RESET_TEXT := "Partida reiniciada. Podes crear o unirte nuevamente."
const SERVER_FULL_TEXT := "Servidor lleno (%d/%d jugadores)."
const GAME_IN_PROGRESS_TEXT := "La partida ya esta en curso."

@onready var host_label: Label = $Panel/MarginContainer/Content/HostLabel
@onready var host_input: LineEdit = $Panel/MarginContainer/Content/ConnectionRow/HostInput
@onready var copy_button: Button = $Panel/MarginContainer/Content/ConnectionRow/CopyButton
@onready var status_label: Label = $Panel/MarginContainer/Content/StatusLabel
@onready var connect_button: Button = $Panel/MarginContainer/Content/ConnectButton
@onready var create_party_button: Button = $Panel/MarginContainer/Content/CreatePartyButton
@onready var start_button: Button = $Panel/MarginContainer/Content/StartButton

var _stack_process_id: int = NO_PROCESS
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
var _minimum_players := MIN_PLAYERS
var _using_model_ip := true
var _disconnect_reason := ""


func _ready() -> void:
	_connect_ui_signals()
	_connect_network_signals()
	_reset_host_input()
	host_input.placeholder_text = MODEL_IP
	start_button.visible = false
	start_button.disabled = true
	status_label.text = READY_TEXT
	_stack_status_path = ProjectSettings.globalize_path(
		"user://stack-status-%s.json" % str(OS.get_process_id())
	)


func _connect_ui_signals() -> void:
	connect_button.pressed.connect(_on_connect_pressed)
	create_party_button.pressed.connect(_on_create_party_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	start_button.pressed.connect(_on_start_match_pressed)
	host_input.focus_entered.connect(_on_host_input_focus_entered)
	host_input.gui_input.connect(_on_host_input_gui_input)


func _connect_network_signals() -> void:
	NetworkClient.connection_requested.connect(_on_connection_requested)
	NetworkClient.connected_to_server.connect(_on_connected)
	NetworkClient.connection_failed.connect(_on_connection_failed)
	NetworkClient.disconnected_from_server.connect(_on_disconnected)
	NetworkClient.welcome_received.connect(_on_welcome)
	NetworkClient.error_received.connect(_on_error)


func _process(_delta: float) -> void:
	if _stack_process_id == NO_PROCESS:
		return
	_poll_stack_status()


func _reset_host_input() -> void:
	_using_model_ip = true
	host_label.text = PASTE_IP_LABEL
	host_input.text = MODEL_IP


func _set_buttons_enabled(enabled: bool) -> void:
	connect_button.disabled = not enabled
	create_party_button.disabled = not enabled


func _hide_start_button() -> void:
	start_button.visible = false
	start_button.disabled = true


func _on_host_input_focus_entered() -> void:
	_clear_model_ip()


func _on_host_input_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_clear_model_ip()


func _clear_model_ip() -> void:
	if _using_model_ip:
		_using_model_ip = false
		host_input.text = ""


func _on_connect_pressed() -> void:
	var connection := _parse_connection_code(host_input.text)
	if connection.is_empty():
		status_label.text = INVALID_CODE_TEXT
		return
	_disconnect_reason = ""
	_vpn_activation_required = false
	host_label.text = PASTE_IP_LABEL
	_start_vpn_for_join(connection[0], connection[1])


func _on_copy_pressed() -> void:
	var connection_code := host_input.text.strip_edges()
	if connection_code.is_empty():
		return
	DisplayServer.clipboard_set(connection_code)


func _on_connection_requested(host: String, port: int) -> void:
	if not _creating_game:
		status_label.text = CONNECTING_TEXT % [host, port]


func _on_connected() -> void:
	if _is_host:
		status_label.text = _share_message + HOST_CONNECTED_TEXT
		start_button.text = START_TEXT
	else:
		status_label.text = GUEST_CONNECTED_TEXT
	_update_start_button()


func _on_connection_failed(message: String) -> void:
	var was_joining := not _is_host and not _creating_game
	_joining_vpn = false
	_creating_game = false
	_starting_docker = false
	_set_buttons_enabled(true)
	_hide_start_button()
	if not _disconnect_reason.is_empty():
		status_label.text = _disconnect_reason
	elif was_joining:
		status_label.text = _join_failure_text(message)
	else:
		status_label.text = message


func _join_failure_text(message: String) -> String:
	var vpn_net := _detect_radmin_vpn_network()
	if vpn_net.is_empty():
		return VPN_CHECK_TEXT % message
	return VPN_NETWORK_TEXT % [message, vpn_net]


func _on_disconnected() -> void:
	_hide_start_button()
	_set_buttons_enabled(true)
	_is_host = false
	_players_count = 0
	if not _disconnect_reason.is_empty():
		status_label.text = _disconnect_reason
	else:
		status_label.text = DISCONNECTED_TEXT


func _on_welcome(payload: Dictionary) -> void:
	_disconnect_reason = ""
	_is_host = bool(payload.get("is_host", _is_host))
	_game_started = bool(payload.get("game_started", false))
	_players_count = int(payload.get("players", _players_count))
	_minimum_players = MIN_PLAYERS
	start_button.visible = _is_host
	var players_text := PLAYERS_TEXT % [_players_count, MAX_PLAYERS]
	if _is_host:
		host_label.text = SHARE_IP_LABEL
		status_label.text = HOST_WAITING_TEXT + players_text
		start_button.text = START_TEXT
	else:
		status_label.text = GUEST_WAITING_TEXT + players_text
	_update_start_button()


func _update_start_button() -> void:
	start_button.disabled = (
		not _is_host
		or _players_count < MIN_PLAYERS
		or not NetworkClient.is_connected_to_server()
	)


func _on_create_party_pressed() -> void:
	status_label.text = PREPARING_TEXT
	_disconnect_reason = ""
	_vpn_activation_required = false
	_using_model_ip = false
	host_label.text = SHARE_IP_LABEL
	_set_buttons_enabled(false)
	_creating_game = true
	_is_host = true
	_start_vpn()


func _on_start_match_pressed() -> void:
	if not _is_host:
		return
	if _players_count < _minimum_players:
		status_label.text = NOT_ENOUGH_PLAYERS_TEXT % _minimum_players
		start_button.disabled = true
		return
	NetworkClient.send_message(ProtocolConstants.START_GAME, {})
	start_button.disabled = true
	status_label.text = STARTING_MATCH_TEXT


func _start_vpn() -> void:
	var script_path := _find_stack_script()
	if not FileAccess.file_exists(script_path):
		_creating_game = false
		_joining_vpn = false
		_set_buttons_enabled(true)
		status_label.text = VPN_ERROR_PREFIX + SCRIPT_NOT_FOUND_TEXT % script_path
		return
	if _creating_game:
		_ready_after_stack = true
	else:
		_joining_vpn = true
	_set_buttons_enabled(false)
	status_label.text = VPN_STARTING_TEXT
	if not _launch_stack_script(script_path, PackedStringArray(["-OnlyVpn"])):
		_abort_vpn_start()


func _abort_vpn_start() -> void:
	_ready_after_stack = false
	_is_host = false
	_creating_game = false
	_joining_vpn = false
	_set_buttons_enabled(true)
	status_label.text = VPN_PROCESS_FAILED_TEXT


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
		_set_buttons_enabled(true)
		status_label.text = DOCKER_ERROR_PREFIX + SCRIPT_NOT_FOUND_TEXT % script_path
		return
	_starting_docker = true
	_set_buttons_enabled(false)
	start_button.disabled = true
	status_label.text = DOCKER_STARTING_TEXT
	var port_text := str(ProtocolConstants.DEFAULT_PORT)
	var docker_args := PackedStringArray(["-Port", port_text, "-SkipVpn"])
	if not _launch_stack_script(script_path, docker_args):
		_abort_docker_start()


func _abort_docker_start() -> void:
	_starting_docker = false
	_creating_game = false
	_ready_after_stack = false
	_is_host = false
	_set_buttons_enabled(true)
	status_label.text = DOCKER_PROCESS_FAILED_TEXT


## Runs start-stack.ps1 in the background; returns false if it could not start.
func _launch_stack_script(script_path: String, extra_args: PackedStringArray) -> bool:
	_clear_stack_status()
	var args := POWERSHELL_BASE_ARGS.duplicate()
	args.append(script_path)
	args.append_array(extra_args)
	args.append("-StatusPath")
	args.append(_stack_status_path)
	_stack_process_id = OS.create_process(POWERSHELL, args)
	_stack_started_at = Time.get_ticks_msec()
	if _stack_process_id < 0:
		_stack_process_id = NO_PROCESS
		return false
	return true


func _find_stack_script() -> String:
	var project_script := ProjectSettings.globalize_path("res://../" + STACK_SCRIPT_NAME)
	if FileAccess.file_exists(project_script):
		return project_script
	var executable_dir := OS.get_executable_path().get_base_dir()
	var local_script := executable_dir.path_join(STACK_SCRIPT_NAME)
	if FileAccess.file_exists(local_script):
		return local_script
	return executable_dir.get_base_dir().path_join(STACK_SCRIPT_NAME)


func _clear_stack_status() -> void:
	if not FileAccess.file_exists(_stack_status_path):
		return
	var status_file := FileAccess.open(_stack_status_path, FileAccess.READ)
	if status_file:
		status_file.close()
	DirAccess.remove_absolute(_stack_status_path)


func _poll_stack_status() -> void:
	if not FileAccess.file_exists(_stack_status_path):
		if Time.get_ticks_msec() - _stack_started_at > STACK_TIMEOUT_MSEC:
			_on_stack_timeout()
		return
	var status := _read_stack_status()
	if status.is_empty():
		return
	var message := String(status.get("message", ""))
	status_label.text = message
	_handle_stack_state(String(status.get("state", "")), message)


## Returns the status written by start-stack.ps1, or {} if nothing new.
func _read_stack_status() -> Dictionary:
	var file := FileAccess.open(_stack_status_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {}
	var timestamp := String(parsed.get("timestamp", ""))
	if timestamp == _last_stack_timestamp:
		return {}
	_last_stack_timestamp = timestamp
	return parsed


func _handle_stack_state(state: String, message: String) -> void:
	match state:
		"vpn_ready":
			_on_vpn_ready()
		"vpn_needs_activation":
			_on_vpn_needs_activation()
		"ready":
			_on_stack_ready(message)
		"error":
			_on_stack_error(message)


func _reset_stack_flow() -> void:
	_stack_process_id = NO_PROCESS
	_ready_after_stack = false
	_creating_game = false
	_starting_docker = false
	_joining_vpn = false
	_is_host = false


func _on_stack_timeout() -> void:
	_reset_stack_flow()
	connect_button.disabled = false
	start_button.disabled = false
	status_label.text = STACK_TIMEOUT_TEXT


func _on_vpn_ready() -> void:
	_stack_process_id = NO_PROCESS
	if _creating_game:
		_start_docker()
		return
	_joining_vpn = false
	connect_button.disabled = false
	status_label.text = VPN_JOIN_CONNECTING_TEXT % [_pending_join_host, _pending_join_port]
	NetworkClient.request_connection(_pending_join_host, _pending_join_port)


func _on_vpn_needs_activation() -> void:
	_stack_process_id = NO_PROCESS
	_vpn_activation_required = true
	_joining_vpn = false
	_set_buttons_enabled(true)
	start_button.disabled = true
	status_label.text = VPN_DISCONNECTED_TEXT
	OS.alert(VPN_ALERT_TEXT, VPN_ALERT_TITLE)


func _on_stack_ready(message: String) -> void:
	_stack_process_id = NO_PROCESS
	_starting_docker = false
	_is_host = true
	_set_buttons_enabled(true)
	_share_message = message
	_connection_code = _connection_code_from_status(message)
	if _connection_code.is_empty():
		_ready_after_stack = false
		start_button.disabled = false
		status_label.text = INVALID_ADDRESS_TEXT
		return
	_show_connection_code()
	var connection := _parse_connection_code(_connection_code)
	NetworkClient.request_connection(LOCAL_HOST, connection[1])


func _show_connection_code() -> void:
	_using_model_ip = false
	host_label.text = SHARE_IP_LABEL
	host_input.text = _connection_code
	status_label.text = SERVER_CONNECTING_TEXT


func _on_stack_error(message: String) -> void:
	_reset_stack_flow()
	_set_buttons_enabled(true)
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
	if port < MIN_PORT or port > MAX_PORT:
		return []
	return [host, port]


func _connection_code_from_status(message: String) -> String:
	var marker_position := message.find(STATUS_CODE_MARKER)
	if marker_position < 0:
		return ""
	var code := message.substr(marker_position + STATUS_CODE_MARKER.length()).strip_edges()
	var separator := code.find(STATUS_PORT_MARKER)
	if separator < 0:
		return ""
	return "%s:%s" % [
		code.substr(0, separator).strip_edges(),
		code.substr(separator + STATUS_PORT_MARKER.length()).strip_edges(),
	]


func _detect_radmin_vpn_network() -> String:
	if not FileAccess.file_exists(RADMIN_LOG_PATH):
		return ""
	var file := FileAccess.open(RADMIN_LOG_PATH, FileAccess.READ)
	if file == null:
		return ""
	var content := file.get_as_text()
	file.close()
	var active_networks: Array[String] = []
	for line in content.split("\n"):
		_apply_network_event(line, active_networks)
	if active_networks.is_empty():
		return ""
	return active_networks[active_networks.size() - 1]


func _apply_network_event(line: String, active_networks: Array[String]) -> void:
	var net_name := _network_name(line)
	if net_name.is_empty():
		return
	var lower := line.to_lower()
	if _contains_any(lower, LEAVE_MARKERS):
		active_networks.erase(net_name)
	elif _contains_any(lower, JOIN_MARKERS) and not active_networks.has(net_name):
		active_networks.append(net_name)


func _network_name(line: String) -> String:
	var net_idx := line.find(NETWORK_MARKER)
	if net_idx < 0:
		return ""
	var start := net_idx + NETWORK_MARKER.length()
	var end := line.find("'", start)
	if end <= start:
		return ""
	return line.substr(start, end - start).strip_edges()


func _contains_any(text: String, markers: Array[String]) -> bool:
	for marker in markers:
		if text.find(marker) >= 0:
			return true
	return false


func reset_lobby() -> void:
	_is_host = false
	_share_message = ""
	_connection_code = ""
	_vpn_activation_required = false
	_game_started = false
	_players_count = 0
	_disconnect_reason = ""
	_reset_host_input()
	start_button.text = START_TEXT
	_hide_start_button()
	_set_buttons_enabled(true)
	status_label.text = LOBBY_RESET_TEXT


func _on_error(payload: Dictionary) -> void:
	var code := String(payload.get("code", ""))
	if code == "MAX_PLAYERS":
		_disconnect_reason = SERVER_FULL_TEXT % [MAX_PLAYERS, MAX_PLAYERS]
		status_label.text = _disconnect_reason
		_set_buttons_enabled(true)
		_hide_start_button()
		NetworkClient.disconnect_from_server()
		return
	if code == "GAME_ALREADY_STARTED":
		_disconnect_reason = GAME_IN_PROGRESS_TEXT
		status_label.text = _disconnect_reason
		return
	status_label.text = "Error: %s" % payload.get("message", "Unknown error")
