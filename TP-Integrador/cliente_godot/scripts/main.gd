extends Control

const ProtocolConstants = preload("res://scripts/protocol_constants.gd")

@onready var lobby: Control = $Lobby
@onready var game_view: Control = $GameView
var _match_started := false


func _ready() -> void:
	game_view.visible = false
	NetworkClient.state_update_received.connect(_on_state_update)
	NetworkClient.game_over_received.connect(_on_game_over)
	NetworkClient.match_started_received.connect(_on_match_started_received)
	NetworkClient.match_reset_received.connect(_on_match_reset_received)
	game_view.game_over.play_again.connect(_on_play_again)
	game_view.restart_requested.connect(_on_restart_requested)


func _on_state_update(payload: Dictionary) -> void:
	if not _match_started:
		return
	var wave := int(payload.get("current_wave", 0))
	if wave == 0 and game_view.visible:
		return
	if wave == 0:
		return
	lobby.visible = false
	game_view.visible = true


func _on_match_started_received() -> void:
	_match_started = true
	lobby.visible = false
	game_view.visible = true


func _on_game_over(_payload: Dictionary) -> void:
	game_view.visible = true


func _on_play_again() -> void:
	_on_restart_requested()


func _on_restart_requested() -> void:
	if not NetworkClient.is_connected_to_server():
		return
	NetworkClient.send_message(ProtocolConstants.RESET_MATCH, {})


func _on_match_reset_received() -> void:
	_match_started = true
	game_view.reset_for_new_game()
	game_view.visible = true
	lobby.visible = false
