extends Control
class_name GameHud

signal tower_selected(tower_type: StringName)

const ERROR_VISIBLE_SECONDS: float = 2.5
const GO_VISIBLE_SECONDS: float = 0.8
const NOT_ENOUGH_GOLD_TEXT: String = "No hay suficiente dinero para comprar esa torre."
const POSITION_TAKEN_TEXT: String = "Ese lugar ya está ocupado."
const MAX_LEVEL_TEXT: String = "Esta torre ya está en su nivel máximo."
const FRIENDLY_MESSAGES: Dictionary = {
	"INSUFFICIENT_GOLD": NOT_ENOUGH_GOLD_TEXT,
	"The team does not have enough gold": NOT_ENOUGH_GOLD_TEXT,
	"POSITION_OCCUPIED": POSITION_TAKEN_TEXT,
	"That tower position is occupied": POSITION_TAKEN_TEXT,
	"MAX_TOWER_LEVEL": MAX_LEVEL_TEXT,
	"That tower is already at maximum level": MAX_LEVEL_TEXT,
	"ONLY_HOST_CAN_START": "Solo el anfitrión puede iniciar o reiniciar la partida.",
	"INVALID_POSITION": "Elegí una posición válida dentro del tablero.",
}

@onready var gold_label: Label = $TopBar/GoldLabel
@onready var base_label: Label = $TopBar/BaseLabel
@onready var base_bar: ProgressBar = $TopBar/BaseBar
@onready var wave_label: Label = $TopBar/WaveLabel
@onready var error_label: Label = $ErrorLabel
@onready var countdown_label: Label = $CountdownLabel


func _ready() -> void:
	$TowerPanel/MopperButton.pressed.connect(_select_mopper)
	$TowerPanel/StockButton.pressed.connect(_select_stock)
	$TowerPanel/AudioButton.pressed.connect(_select_audio)
	error_label.visible = false
	countdown_label.visible = false
	NetworkClient.countdown_received.connect(_on_countdown)


func update_state(payload: Dictionary) -> void:
	var gold: int = int(payload.get("gold", 0))
	var base_hp: int = int(payload.get("base_hp", 0))
	var current_wave: int = int(payload.get("current_wave", 0))
	gold_label.text = "ORO: %d" % gold
	base_label.text = "BASE: %d/%d" % [base_hp, GameConstants.INITIAL_BASE_HP]
	base_bar.value = float(payload.get("base_hp", 0))
	wave_label.text = "OLEADA: %d/%d" % [current_wave, GameConstants.TOTAL_WAVES]


func reset_state() -> void:
	update_state({
		"gold": GameConstants.INITIAL_GOLD,
		"base_hp": GameConstants.INITIAL_BASE_HP,
		"current_wave": 0,
	})


func show_error(message: String) -> void:
	error_label.text = FRIENDLY_MESSAGES.get(message, message)
	error_label.visible = true
	get_tree().create_timer(ERROR_VISIBLE_SECONDS).timeout.connect(_hide_error)


func _hide_error() -> void:
	error_label.visible = false


func _on_countdown(payload: Dictionary) -> void:
	var seconds := int(payload.get("seconds", 0))
	countdown_label.text = "GO" if seconds == 0 else "LA OLEADA EMPIEZA EN %d" % seconds
	countdown_label.visible = true
	if seconds == 0:
		get_tree().create_timer(GO_VISIBLE_SECONDS).timeout.connect(func() -> void:
			countdown_label.visible = false
		)


func _select_mopper() -> void:
	tower_selected.emit(&"MOPPER")


func _select_stock() -> void:
	tower_selected.emit(&"STOCK_REPLENISHER")


func _select_audio() -> void:
	tower_selected.emit(&"AUDIO_TOWER")
