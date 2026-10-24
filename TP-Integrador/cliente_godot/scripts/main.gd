extends Control

@onready var lobby: Control = $Lobby
@onready var game_view: Control = $GameView


func _ready() -> void:
	game_view.visible = false
	NetworkClient.state_update_received.connect(_on_state_update)
	NetworkClient.game_over_received.connect(_on_game_over)


func _on_state_update(_payload: Dictionary) -> void:
	lobby.visible = false
	game_view.visible = true


func _on_game_over(_payload: Dictionary) -> void:
	game_view.visible = true
