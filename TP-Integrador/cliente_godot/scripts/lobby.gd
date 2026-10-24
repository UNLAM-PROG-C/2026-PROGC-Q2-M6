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
var party_endpoint := ""


func _ready() -> void:
	port_input.text = str(ProtocolConstants.DEFAULT_PORT)
	connect_button.pressed.connect(_on_connect_pressed)
	create_party_button.pressed.connect(_on_create_party_pressed)
	start_button.pressed.connect(_on_start_pressed)
	copy_button.pressed.connect(_on_copy_endpoint_pressed)
	start_button.disabled = true
	start_button.visible = true
	share_panel.visible = false
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
		status_label.text = "Ingresá la dirección con formato IP:puerto."
		return
	# Keep the shareable IP:port visible; the parsed values are sent separately.
	port_input.text = str(endpoint["port"])
	NetworkClient.request_connection(endpoint["host"], endpoint["port"])


func _on_create_party_pressed() -> void:
	var tailscale_ip := _tailscale_ip()
	if tailscale_ip.is_empty():
		status_label.text = "Iniciá sesión en Tailscale antes de crear la partida."
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
	party_endpoint = "%s:%d" % [tailscale_ip, port]
	host_input.text = party_endpoint
	port_input.text = str(port)
	share_label.text = "Pasale estos datos a tus amigos:\n%s" % party_endpoint
	share_panel.visible = true
	status_label.text = "Creando partida..."
	_copy_endpoint()
	create_party_button.disabled = true
	connect_button.disabled = true
	await get_tree().create_timer(6.0).timeout
	if is_inside_tree():
		# Connect exactly once after Docker has had time to publish the port.
		NetworkClient.request_connection(tailscale_ip, port)


func _copy_endpoint() -> void:
	if party_endpoint.is_empty():
		party_endpoint = host_input.text.strip_edges()
	DisplayServer.clipboard_set(party_endpoint)


func _on_copy_endpoint_pressed() -> void:
	_copy_endpoint()
	status_label.text = "IP y puerto copiados."


func _find_free_port() -> int:
	for port in range(5001, 5101):
		var probe := TCPServer.new()
		if probe.listen(port, "127.0.0.1") == OK:
			probe.stop()
			return port
	return -1


func _tailscale_ip() -> String:
	var output: Array[String] = []
	var executable := _tailscale_executable()
	if executable.is_empty():
		return ""
	var exit_code := OS.execute(executable, ["ip", "-4"], output, true)
	if exit_code != 0 or output.is_empty():
		return ""
	var ip := output[0].strip_edges()
	return ip if ip.begins_with("100.") else ""


func _tailscale_executable() -> String:
	var candidates := [
		"tailscale",
		"C:/Program Files/Tailscale/tailscale.exe",
		"C:/Program Files (x86)/Tailscale/tailscale.exe",
	]
	for candidate in candidates:
		if candidate == "tailscale" or FileAccess.file_exists(candidate):
			return candidate
	return ""


func _server_script_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://../start-server.ps1")
	return OS.get_executable_path().get_base_dir().path_join("start-server.ps1")


func _on_connection_requested(host: String, port: int) -> void:
	status_label.text = "Connecting to %s:%d" % [host, port]


func _on_connected() -> void:
	status_label.text = "Conectado. Verificando jugadores..."
	start_button.disabled = true
	create_party_button.disabled = false


func _on_connection_failed(message: String) -> void:
	status_label.text = message
	create_party_button.disabled = false
	connect_button.disabled = false


func _on_disconnected() -> void:
	status_label.text = "Disconnected"
	start_button.disabled = true
	create_party_button.disabled = false
	connect_button.disabled = false
	if not NetworkClient.is_host:
		share_panel.visible = false


func _on_welcome(payload: Dictionary) -> void:
	var players := int(payload.get("players", 0))
	var minimum := int(payload.get("min_players", 2))
	var player_id := int(payload.get("player_id", -1))
	NetworkClient.player_id = player_id
	# The first server-assigned ID is the host, also supporting older servers.
	NetworkClient.is_host = bool(payload.get("is_host", player_id == 1))
	if NetworkClient.is_host:
		var endpoint := host_input.text.strip_edges()
		share_label.text = "Pasale estos datos a tus amigos:\n%s" % endpoint
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
