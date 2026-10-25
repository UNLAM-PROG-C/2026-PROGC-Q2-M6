extends Control

signal match_started

@onready var host_input: LineEdit = $Panel/MarginContainer/Content/HostInput
@onready var port_input: LineEdit = $Panel/MarginContainer/Content/PortInput
@onready var status_label: Label = $Panel/MarginContainer/Content/StatusLabel
@onready var connect_button: Button = $Panel/MarginContainer/Content/ConnectButton
@onready var create_party_button: Button = $Panel/MarginContainer/Content/CreatePartyButton
@onready var start_button: Button = $Panel/MarginContainer/Content/StartButton
@onready var share_panel: PanelContainer = $Panel/MarginContainer/Content/SharePanel
@onready var share_label: Label = $Panel/MarginContainer/Content/SharePanel/ShareRow/ShareLabel
@onready var copy_button: Button = $Panel/MarginContainer/Content/SharePanel/ShareRow/CopyButton

const RADMIN_NETWORK_NAME := "TowerDefense-UNLAM"
const RADMIN_NETWORK_PASSWORD := "1234"
const RADMIN_MISSING_MESSAGE := "Abrí Radmin VPN y unite a la red TowerDefense-UNLAM (clave 1234)."

var party_endpoint := ""
var _is_creating_party := false


func _ready() -> void:
	port_input.text = str(ProtocolConstants.DEFAULT_PORT)
	connect_button.pressed.connect(_on_connect_pressed)
	create_party_button.pressed.connect(_on_create_party_pressed)
	start_button.pressed.connect(_on_start_pressed)
	copy_button.pressed.connect(_on_copy_endpoint_pressed)

	start_button.disabled = true
	start_button.visible = true
	share_panel.visible = false
	_refresh_create_party_button()

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
	var endpoint := _parse_endpoint(host_input.text)
	if endpoint.is_empty():
		status_label.text = "Ingresá la dirección con formato host:puerto o IP:puerto."
		return
	var host: String = endpoint["host"]
	var port: int = endpoint["port"]
	port_input.text = str(port)
	if _get_radmin_ip().is_empty():
		status_label.text = RADMIN_MISSING_MESSAGE
		return
	if not host.begins_with("26."):
		status_label.text = "La dirección tiene que ser la IP de Radmin VPN del anfitrión (empieza con 26.)."
		return
	NetworkClient.request_connection(host, port)


func _on_create_party_pressed() -> void:
	if not _has_docker():
		status_label.text = "Falta Docker Desktop. Volvé a ejecutar el instalador para instalarlo."
		return

	var radmin_ip := _get_radmin_ip()
	if radmin_ip.is_empty():
		status_label.text = RADMIN_MISSING_MESSAGE
		return

	var port := _find_free_port()
	if port < 0:
		status_label.text = "No hay puertos libres para crear la partida."
		return

	var script_path := _server_script_path()
	var pid := OS.create_process("powershell.exe", [
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		script_path,
		"-Port",
		str(port),
		"-ProjectName",
		"tower-defense-%d" % port,
	])
	if pid < 0:
		status_label.text = "No se pudo iniciar Docker."
		return

	party_endpoint = "%s:%d" % [radmin_ip, port]
	host_input.text = party_endpoint
	port_input.text = str(port)

	share_label.text = "Pasale este código a tus amigos:\n%s" % party_endpoint
	share_panel.visible = true

	create_party_button.disabled = true
	connect_button.disabled = true
	_is_creating_party = true

	_poll_and_connect_host("127.0.0.1", port)


func _poll_and_connect_host(host: String, port: int) -> void:
	const MAX_ATTEMPTS := 35

	for attempt in range(1, MAX_ATTEMPTS + 1):
		if not is_inside_tree() or not _is_creating_party:
			return

		status_label.text = "Iniciando servidor (intento %d/%d)..." % [attempt, MAX_ATTEMPTS]
		NetworkClient.request_connection(host, port)

		await get_tree().create_timer(1.0).timeout

		if not is_inside_tree() or not _is_creating_party:
			return

		if NetworkClient.is_connected_to_server():
			_is_creating_party = false
			return

	_is_creating_party = false
	NetworkClient.disconnect_from_server()
	status_label.text = "Tiempo de espera agotado. No se pudo conectar al servidor."
	connect_button.disabled = false
	_refresh_create_party_button()


func _copy_endpoint() -> void:
	if party_endpoint.is_empty():
		party_endpoint = host_input.text.strip_edges()
	DisplayServer.clipboard_set(party_endpoint)


func _on_copy_endpoint_pressed() -> void:
	_copy_endpoint()
	status_label.text = "Enlace copiado al portapapeles."


func _find_free_port() -> int:
	for port in range(5001, 5101):
		var probe := TCPServer.new()
		if probe.listen(port, "127.0.0.1") == OK:
			probe.stop()
			return port
	return -1


func _get_radmin_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("26.") and addr.split(".").size() == 4:
			return addr
	return ""


func _has_docker() -> bool:
	var output: Array[String] = []
	return OS.execute("where.exe", ["docker"], output, true) == 0 and not output.is_empty()


func _refresh_create_party_button() -> void:
	if _is_creating_party:
		create_party_button.disabled = true
		return
	var has_docker := _has_docker()
	create_party_button.disabled = not has_docker
	if not has_docker:
		create_party_button.tooltip_text = "Falta Docker Desktop. Instalalo para crear partidas."
	else:
		create_party_button.tooltip_text = "Crear partida (LAN o pública por Playit.gg)"


func _server_script_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://../start-server.ps1")
	return OS.get_executable_path().get_base_dir().path_join("start-server.ps1")


func _on_connection_requested(host: String, port: int) -> void:
	if not _is_creating_party:
		status_label.text = "Conectando a %s:%d..." % [host, port]


func _on_connected() -> void:
	_is_creating_party = false
	status_label.text = "Conectado. Verificando jugadores..."
	start_button.disabled = true
	_refresh_create_party_button()


func _on_connection_failed(message: String) -> void:
	if _is_creating_party:
		return
	status_label.text = message
	_refresh_create_party_button()
	connect_button.disabled = false


func _on_disconnected() -> void:
	_is_creating_party = false
	status_label.text = "Disconnected"
	start_button.disabled = true
	_refresh_create_party_button()
	connect_button.disabled = false
	if not NetworkClient.is_host:
		share_panel.visible = false


func _on_welcome(payload: Dictionary) -> void:
	var players := int(payload.get("players", 0))
	var minimum := int(payload.get("min_players", 2))
	var player_id := int(payload.get("player_id", -1))
	NetworkClient.player_id = player_id
	NetworkClient.is_host = bool(payload.get("is_host", player_id == 1))
	if NetworkClient.is_host:
		share_panel.visible = true
		if players < minimum:
			status_label.text = "Partida creada. Jugadores conectados %d/4. Esperando otro jugador..." % players
		else:
			status_label.text = "Jugadores conectados %d/4. Ya podés iniciar la partida." % players
		start_button.text = "Iniciar partida"
		start_button.visible = true
		start_button.disabled = players < minimum or bool(payload.get("game_started", false))
	else:
		share_panel.visible = false
		status_label.text = "Jugadores conectados %d/4. Esperando que el anfitrión inicie..." % players
		start_button.text = "Esperando al anfitrión"
		start_button.visible = true
		start_button.disabled = true
	if bool(payload.get("game_started", false)):
		match_started.emit()


func _on_start_pressed() -> void:
	if not NetworkClient.is_host:
		return
	NetworkClient.send_message(ProtocolConstants.READY, {"start": true})
	start_button.disabled = true
	status_label.text = "Iniciando partida para todos..."


func show_waiting_for_start() -> void:
	visible = true


func _on_state_update(payload: Dictionary) -> void:
	if int(payload.get("current_wave", 0)) == 0:
		return
	status_label.text = "Wave %s | Gold %s | Base %s" % [
		payload.get("current_wave", 0),
		payload.get("gold", 0),
		payload.get("base_hp", 0),
	]


func _parse_endpoint(value: String) -> Dictionary:
	var endpoint := value.strip_edges()
	if endpoint.begins_with("tcp://"):
		endpoint = endpoint.substr(6).strip_edges()
	var separator := endpoint.rfind(":")
	if separator <= 0 or separator == endpoint.length() - 1:
		return {}
	var host := endpoint.substr(0, separator).strip_edges()
	var port_text := endpoint.substr(separator + 1).strip_edges()
	if host.is_empty() or not port_text.is_valid_int():
		return {}
	var port := int(port_text)
	if port < 1 or port > 65535:
		return {}
	return {"host": host, "port": port}


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
