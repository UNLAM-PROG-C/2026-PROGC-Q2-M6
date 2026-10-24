extends Control
class_name GameOverPanel

@onready var result_label: Label = $Panel/Content/ResultLabel
@onready var reason_label: Label = $Panel/Content/ReasonLabel


func show_result(payload: Dictionary) -> void:
	result_label.text = "VICTORIA" if payload.get("result") == "VICTORY" else "DERROTA"
	reason_label.text = String(payload.get("reason", ""))
	visible = true
