extends Node2D
class_name TowerView

signal attack_started(target_count: int)
signal attack_finished

const TEXTURES: Dictionary = {
	&"MOPPER": preload("res://assets/characters/mopper.svg"),
	&"STOCK_REPLENISHER": preload("res://assets/characters/stock_replenisher.svg"),
	&"AUDIO_TOWER": preload("res://assets/characters/audio_tower.svg"),
}

enum State {
	IDLE,
	ATTACKING,
}

@export_category("Feedback visual del ataque")
@export var attack_pulse_scale: float = 1.12
@export_range(0.01, 1.0, 0.01) var attack_pulse_duration: float = 0.12
@export var attack_flash_color: Color = Color("#fff4a8")

var tower_type: StringName = &"MOPPER"
var pulse_time: float = 0.0
var state: State = State.IDLE
var _base_scale: Vector2 = Vector2.ONE
var _base_modulate: Color = Color.WHITE
var _attack_tween: Tween = null
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_base_scale = sprite.scale
	_base_modulate = sprite.modulate


func set_state(payload: Dictionary, screen_position: Vector2) -> void:
	tower_type = StringName(payload.get("tower_type", "MOPPER"))
	position = screen_position
	var texture: Texture2D = TEXTURES.get(tower_type) as Texture2D
	sprite.texture = texture
	queue_redraw()


func play_attack(target_count: int) -> void:
	if target_count <= 0:
		return

	if _attack_tween != null and _attack_tween.is_valid():
		_attack_tween.kill()

	state = State.ATTACKING
	attack_started.emit(target_count)
	sprite.modulate = attack_flash_color
	sprite.scale = _base_scale
	_attack_tween = create_tween()
	_attack_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(
		sprite,
		"scale",
		_base_scale * attack_pulse_scale,
		attack_pulse_duration,
	)
	_attack_tween.parallel().tween_property(
		sprite,
		"modulate",
		_base_modulate,
		attack_pulse_duration,
	)
	_attack_tween.tween_callback(_finish_attack)


func _finish_attack() -> void:
	state = State.IDLE
	sprite.scale = _base_scale
	sprite.modulate = _base_modulate
	attack_finished.emit()


func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()


func _draw() -> void:
	if tower_type == &"MOPPER":
		draw_ellipse_shape(Vector2(0, 31), Vector2(34, 9), Color("#78d8e8", 0.7))
	if tower_type == &"AUDIO_TOWER":
		var radius: float = 32.0 + sin(pulse_time * 5.0) * 5.0
		draw_arc(Vector2.ZERO, radius, -0.8, 0.8, 18, Color("#f5d16a", 0.7), 3.0)


func draw_ellipse_shape(center: Vector2, radii: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in 24:
		var angle: float = TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
