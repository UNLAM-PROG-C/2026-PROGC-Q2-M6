extends Control
class_name GameOverPanel

signal play_again

const VICTORY_CODE: String = "VICTORY"
const VICTORY_TITLE: String = "VICTORIA"
const DEFEAT_TITLE: String = "DERROTA"
const PLAY_AGAIN_TEXT: String = "Reiniciar"
const DEFAULT_VICTORY_REASON: String = "¡Ganaron la partida!"
const DEFAULT_DEFEAT_REASON: String = "La partida terminó en derrota."
const REASON_MESSAGES: Dictionary = {
	"ALL_WAVES_CLEARED": "¡Superaron todas las oleadas y protegieron el frigorífico!",
	"BASE_DESTROYED": "Los enemigos destruyeron el frigorífico.",
}

@onready var result_label: Label = $Panel/Content/ResultLabel
@onready var reason_label: Label = $Panel/Content/ReasonLabel
@onready var play_again_button: Button = $Panel/Content/PlayAgainButton


func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again_pressed)


func show_result(payload: Dictionary) -> void:
	var is_victory: bool = payload.get("result") == VICTORY_CODE
	var reason_code: String = String(payload.get("reason", ""))
	var fallback: String = DEFAULT_VICTORY_REASON if is_victory else DEFAULT_DEFEAT_REASON
	result_label.text = VICTORY_TITLE if is_victory else DEFEAT_TITLE
	reason_label.text = REASON_MESSAGES.get(reason_code, fallback)
	play_again_button.text = PLAY_AGAIN_TEXT
	play_again_button.visible = true
	visible = true


func _on_play_again_pressed() -> void:
	visible = false
	play_again.emit()
