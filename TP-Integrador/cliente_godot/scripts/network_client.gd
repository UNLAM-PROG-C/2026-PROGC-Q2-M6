extends Node

signal connection_requested(host: String, port: int)
signal connected_to_server
signal connection_failed(message: String)
signal disconnected_from_server
signal message_received(message: Dictionary)
signal welcome_received(payload: Dictionary)
signal state_update_received(payload: Dictionary)
signal wave_start_received(payload: Dictionary)
signal countdown_received(payload: Dictionary)
signal base_damage_received(payload: Dictionary)
signal game_over_received(payload: Dictionary)
signal match_reset_received
signal match_started_received
signal error_received(payload: Dictionary)
signal attack_received(payload: Dictionary)

const ProtocolConstants = preload("res://scripts/protocol_constants.gd")
const FRAME_HEADER_SIZE: int = 4
const MAX_FRAME_SIZE: int = 1048576
const BITS_PER_BYTE: int = 8
const BYTE_MASK: int = 0xFF
const CONNECT_TIMEOUT_MSEC: int = 15000
const MIN_PORT: int = 1
const MAX_PORT: int = 65535
const NO_PLAYER_ID: int = -1
const DEFAULT_HOST: String = "127.0.0.1"
const PLAYER_NAME: String = "godot-player"
const CONNECT_ERROR_TEXT: String = "No se pudo conectar a %s:%d."

var player_id: int = NO_PLAYER_ID
var is_host: bool = false
var server_host: String = DEFAULT_HOST
var server_port: int = ProtocolConstants.DEFAULT_PORT
var _tcp: StreamPeerTCP
var _receive_buffer := PackedByteArray()
var _was_connected := false
var _is_connecting := false
var _hello_sent := false
var _connection_started_at := 0
var _payload_signals: Dictionary = {}


func _ready() -> void:
	_payload_signals = {
		ProtocolConstants.WELCOME: welcome_received,
		ProtocolConstants.STATE_UPDATE: state_update_received,
		ProtocolConstants.WAVE_START: wave_start_received,
		ProtocolConstants.COUNTDOWN: countdown_received,
		ProtocolConstants.BASE_DAMAGE: base_damage_received,
		ProtocolConstants.GAME_OVER: game_over_received,
		ProtocolConstants.ERROR: error_received,
		ProtocolConstants.ATTACK: attack_received,
	}


func _process(_delta: float) -> void:
	if _tcp == null:
		return
	_tcp.poll()
	var status := _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		_is_connecting = false
		_handle_connected()
		_read_available_data()
	elif status == StreamPeerTCP.STATUS_CONNECTING:
		_check_connect_timeout()
	elif _was_connected:
		_handle_lost_connection(status)
	elif _is_connecting:
		_fail_connection()


func request_connection(host: String, port: int) -> void:
	if host.is_empty() or port < MIN_PORT or port > MAX_PORT:
		push_error("A valid host and port are required")
		return
	_reset_session(host, port)
	_close_connection()
	_tcp = StreamPeerTCP.new()
	_is_connecting = true
	_connection_started_at = Time.get_ticks_msec()
	if _tcp.connect_to_host(server_host, server_port) != OK:
		_close_connection()
		connection_failed.emit("Could not start the connection.")
		return
	connection_requested.emit(server_host, server_port)


func send_message(message_type: StringName, payload: Dictionary) -> void:
	if _tcp == null or _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var body := JSON.stringify({"type": String(message_type), "payload": payload})
	var body_bytes := body.to_utf8_buffer()
	if body_bytes.size() <= 0 or body_bytes.size() > MAX_FRAME_SIZE:
		connection_failed.emit("The message size is invalid.")
		return
	_tcp.put_data(_encode_frame(body_bytes))


func is_connected_to_server() -> bool:
	if not _was_connected or _tcp == null:
		return false
	return _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED


func disconnect_from_server() -> void:
	_close_connection()


func _reset_session(host: String, port: int) -> void:
	server_host = host
	server_port = port
	player_id = NO_PLAYER_ID
	is_host = false
	_receive_buffer.clear()
	_hello_sent = false


func _check_connect_timeout() -> void:
	var elapsed := Time.get_ticks_msec() - _connection_started_at
	if _connection_started_at > 0 and elapsed > CONNECT_TIMEOUT_MSEC:
		_fail_connection()


func _handle_lost_connection(status: StreamPeerTCP.Status) -> void:
	_read_available_data()
	_close_connection()
	disconnected_from_server.emit()
	if status == StreamPeerTCP.STATUS_ERROR:
		connection_failed.emit(CONNECT_ERROR_TEXT % [server_host, server_port])


func _fail_connection() -> void:
	_close_connection()
	connection_failed.emit(CONNECT_ERROR_TEXT % [server_host, server_port])


func _handle_connected() -> void:
	if _was_connected:
		return
	_connection_started_at = 0
	_was_connected = true
	connected_to_server.emit()
	_hello_sent = true
	send_message(ProtocolConstants.HELLO, {"name": PLAYER_NAME})


func _read_available_data() -> void:
	var available := _tcp.get_available_bytes()
	if available <= 0:
		return
	var result := _tcp.get_partial_data(available)
	if result[0] != OK:
		connection_failed.emit("Could not read from the server.")
		return
	_receive_buffer.append_array(result[1])
	_parse_frames()


func _parse_frames() -> void:
	while _receive_buffer.size() >= FRAME_HEADER_SIZE:
		var body_size := _decode_u32(_receive_buffer)
		if body_size <= 0 or body_size > MAX_FRAME_SIZE:
			connection_failed.emit("The server sent an invalid frame.")
			_receive_buffer.clear()
			return
		var frame_end := FRAME_HEADER_SIZE + body_size
		if _receive_buffer.size() < frame_end:
			return
		var body := _receive_buffer.slice(FRAME_HEADER_SIZE, frame_end)
		_receive_buffer = _receive_buffer.slice(frame_end)
		_dispatch_message(body)


func _dispatch_message(body: PackedByteArray) -> void:
	var message = JSON.parse_string(body.get_string_from_utf8())
	var error := _validate_message(message)
	if not error.is_empty():
		error_received.emit(error)
		return
	message_received.emit(message)
	_route_message(StringName(message["type"]), message["payload"])


func _validate_message(message: Variant) -> Dictionary:
	if not message is Dictionary or not message.has("type"):
		return {"code": "INVALID_MESSAGE", "message": "Invalid server message."}
	if not message.has("payload") or not message["payload"] is Dictionary:
		return {"code": "INVALID_MESSAGE", "message": "Invalid server payload."}
	if not ProtocolConstants.SERVER_MESSAGE_TYPES.has(StringName(message["type"])):
		return {"code": "UNKNOWN_MESSAGE", "message": "Unknown server message."}
	return {}


func _route_message(message_type: StringName, payload: Dictionary) -> void:
	if message_type == ProtocolConstants.WELCOME:
		player_id = int(payload.get("player_id", player_id))
		is_host = bool(payload.get("is_host", is_host))
	if _payload_signals.has(message_type):
		(_payload_signals[message_type] as Signal).emit(payload)
	elif message_type == ProtocolConstants.MATCH_RESET:
		match_reset_received.emit()
	elif message_type == ProtocolConstants.MATCH_STARTED:
		match_started_received.emit()


func _encode_frame(body: PackedByteArray) -> PackedByteArray:
	var frame := PackedByteArray()
	for index in FRAME_HEADER_SIZE:
		var shift := (FRAME_HEADER_SIZE - 1 - index) * BITS_PER_BYTE
		frame.append((body.size() >> shift) & BYTE_MASK)
	frame.append_array(body)
	return frame


func _decode_u32(bytes: PackedByteArray) -> int:
	var value := 0
	for index in FRAME_HEADER_SIZE:
		value = (value << BITS_PER_BYTE) | bytes[index]
	return value


func _close_connection() -> void:
	if _tcp != null:
		_tcp.disconnect_from_host()
	_tcp = null
	_was_connected = false
	_connection_started_at = 0
	_is_connecting = false
