extends Node

signal connection_requested(host: String, port: int)
signal connected_to_server
signal connection_failed(message: String)
signal disconnected_from_server
signal message_received(message: Dictionary)
signal welcome_received(payload: Dictionary)
signal state_update_received(payload: Dictionary)
signal wave_start_received(payload: Dictionary)
signal base_damage_received(payload: Dictionary)
signal game_over_received(payload: Dictionary)
signal error_received(payload: Dictionary)

var server_host: String = "127.0.0.1"
var server_port: int = ProtocolConstants.DEFAULT_PORT
var _tcp: StreamPeerTCP
var _receive_buffer := PackedByteArray()
var _was_connected := false
var _hello_sent := false

const FRAME_HEADER_SIZE: int = 4
const MAX_FRAME_SIZE: int = 1048576


func _process(_delta: float) -> void:
	if _tcp == null:
		return
	_tcp.poll()
	var status := _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		_handle_connected()
		_read_available_data()
		return
	if _was_connected and status != StreamPeerTCP.STATUS_CONNECTING:
		_was_connected = false
		disconnected_from_server.emit()
	if status == StreamPeerTCP.STATUS_ERROR:
		connection_failed.emit("The server connection failed.")


func request_connection(host: String, port: int) -> void:
	if host.is_empty() or port < 1 or port > 65535:
		push_error("A valid host and port are required")
		return
	server_host = host
	server_port = port
	_close_connection()
	_tcp = StreamPeerTCP.new()
	_receive_buffer.clear()
	_hello_sent = false
	var result := _tcp.connect_to_host(server_host, server_port)
	if result != OK:
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
	var frame := _encode_frame(body_bytes)
	_tcp.put_data(frame)


func _handle_connected() -> void:
	if _was_connected:
		return
	_was_connected = true
	connected_to_server.emit()
	_hello_sent = true
	send_message(ProtocolConstants.HELLO, {"name": "godot-player"})
	send_message(ProtocolConstants.READY, {})


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
		if _receive_buffer.size() < FRAME_HEADER_SIZE + body_size:
			return
		var body := _receive_buffer.slice(FRAME_HEADER_SIZE, FRAME_HEADER_SIZE + body_size)
		_receive_buffer = _receive_buffer.slice(FRAME_HEADER_SIZE + body_size)
		_dispatch_message(body)


func _dispatch_message(body: PackedByteArray) -> void:
	var message = JSON.parse_string(body.get_string_from_utf8())
	if not message is Dictionary or not message.has("type"):
		error_received.emit({"code": "INVALID_MESSAGE", "message": "Invalid server message."})
		return
	if not message.has("payload") or not message["payload"] is Dictionary:
		error_received.emit({"code": "INVALID_MESSAGE", "message": "Invalid server payload."})
		return
	var message_type := StringName(message["type"])
	if not ProtocolConstants.SERVER_MESSAGE_TYPES.has(message_type):
		error_received.emit({"code": "UNKNOWN_MESSAGE", "message": "Unknown server message."})
		return
	var payload: Dictionary = message["payload"]
	message_received.emit(message)
	match String(message_type):
		String(ProtocolConstants.WELCOME):
			welcome_received.emit(payload)
		String(ProtocolConstants.STATE_UPDATE):
			state_update_received.emit(payload)
		String(ProtocolConstants.WAVE_START):
			wave_start_received.emit(payload)
		String(ProtocolConstants.BASE_DAMAGE):
			base_damage_received.emit(payload)
		String(ProtocolConstants.GAME_OVER):
			game_over_received.emit(payload)
		String(ProtocolConstants.ERROR):
			error_received.emit(payload)


func _encode_frame(body: PackedByteArray) -> PackedByteArray:
	var frame := PackedByteArray()
	frame.append((body.size() >> 24) & 255)
	frame.append((body.size() >> 16) & 255)
	frame.append((body.size() >> 8) & 255)
	frame.append(body.size() & 255)
	frame.append_array(body)
	return frame


func _decode_u32(bytes: PackedByteArray) -> int:
	return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]


func _close_connection() -> void:
	if _tcp != null:
		_tcp.disconnect_from_host()
	_was_connected = false
