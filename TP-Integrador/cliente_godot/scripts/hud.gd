extends Control
class_name GameHud

signal tower_selected(tower_type: StringName)

@onready var gold_label: Label = $TopBar/GoldLabel
@onready var base_label: Label = $TopBar/BaseLabel
@onready var wave_label: Label = $TopBar/WaveLabel
@onready var error_label: Label = $ErrorLabel


func _ready() -> void:
	$TowerPanel/MopperButton.pressed.connect(_select_mopper)
	$TowerPanel/StockButton.pressed.connect(_select_stock)
	$TowerPanel/AudioButton.pressed.connect(_select_audio)
	error_label.visible = false


func update_state(payload: Dictionary) -> void:
	gold_label.text = "ORO: %s" % payload.get("gold", 0)
	base_label.text = "BASE: %s/100" % payload.get("base_hp", 0)
	wave_label.text = "OLEADA: %s/10" % payload.get("current_wave", 0)


func show_error(message: String) -> void:
	var friendly_messages := {
		"INSUFFICIENT_GOLD": "No hay suficiente dinero para comprar esa torre.",
		"The team does not have enough gold": "No hay suficiente dinero para comprar esa torre.",
		"POSITION_OCCUPIED": "Ese lugar ya está ocupado.",
		"That tower position is occupied": "Ese lugar ya está ocupado.",
		"INVALID_POSITION": "Elegí una posición válida dentro del tablero.",
	}
	message = friendly_messages.get(message, message)
	error_label.text = message
	error_label.visible = true
	get_tree().create_timer(2.5).timeout.connect(_hide_error)


func _hide_error() -> void:
	error_label.visible = false


func _select_mopper() -> void:
	tower_selected.emit(&"MOPPER")


func _select_stock() -> void:
	tower_selected.emit(&"STOCK_REPLENISHER")


func _select_audio() -> void:
	tower_selected.emit(&"AUDIO_TOWER")
