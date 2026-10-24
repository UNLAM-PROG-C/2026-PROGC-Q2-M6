extends Control

@onready var host_input: LineEdit = $Panel/MarginContainer/Content/HostInput
@onready var port_input: LineEdit = $Panel/MarginContainer/Content/PortInput
@onready var status_label: Label = $Panel/MarginContainer/Content/StatusLabel
@onready var connect_button: Button = $Panel/MarginContainer/Content/ConnectButton
@onready var create_party_button: Button = $Panel/MarginContainer/Content/CreatePartyButton
@onready var start_button: Button = $Panel/MarginContainer/Content/StartButton


func _ready() -> void:
	port_input.text = str(ProtocolConstants.DEFAULT_PORT)
	connect_button.pressed.connect(_on_connect_pressed)
	create_party_button.pressed.connect(_on_create_party_pressed)
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
	host_input.text = tailscale_ip
	port_input.text = str(port)
	status_label.text = "Creando en %s:%d..." % [tailscale_ip, port]
	DisplayServer.clipboard_set("%s:%d" % [tailscale_ip, port])
	create_party_button.disabled = true
	await get_tree().create_timer(4.0).timeout
	NetworkClient.request_connection(tailscale_ip, port)


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
	status_label.text = "Conectado al puerto %s. Esperando jugadores..." % port_input.text
	start_button.disabled = false
	create_party_button.disabled = false


func _on_connection_failed(message: String) -> void:
	status_label.text = message
	create_party_button.disabled = false


func _on_disconnected() -> void:
	status_label.text = "Disconnected"
	start_button.disabled = true
	create_party_button.disabled = false


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
