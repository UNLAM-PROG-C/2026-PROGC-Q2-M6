extends Control

@onready var lobby: Control = $Lobby
@onready var game_view: Control = $GameView


func _ready() -> void:
	game_view.visible = false
	NetworkClient.state_update_received.connect(_on_state_update)
	NetworkClient.game_over_received.connect(_on_game_over)
	game_view.game_over.play_again.connect(_on_play_again)


func _on_state_update(payload: Dictionary) -> void:
	var wave := int(payload.get("current_wave", 0))
	if wave == 0 and game_view.visible:
		return
	if wave == 0:
		return
	lobby.visible = false
	game_view.visible = true


func _on_game_over(_payload: Dictionary) -> void:
	game_view.visible = true


func _on_play_again() -> void:
	game_view.reset_for_new_game()
	game_view.visible = false
	lobby.show_waiting_for_start()
