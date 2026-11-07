extends Control
class_name GameOverPanel

signal play_again

@onready var result_label: Label = $Panel/Content/ResultLabel
@onready var reason_label: Label = $Panel/Content/ReasonLabel
@onready var play_again_button: Button = $Panel/Content/PlayAgainButton


func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again_pressed)


func show_result(payload: Dictionary) -> void:
	result_label.text = "VICTORIA" if payload.get("result") == "VICTORY" else "DERROTA"
	reason_label.text = String(payload.get("reason", ""))
	play_again_button.visible = NetworkClient.is_host
	visible = true


func _on_play_again_pressed() -> void:
	visible = false
	play_again.emit()
