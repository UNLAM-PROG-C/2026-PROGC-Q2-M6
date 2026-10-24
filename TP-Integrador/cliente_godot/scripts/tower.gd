extends Node2D
class_name TowerView

const TEXTURES: Dictionary = {
	&"MOPPER": preload("res://assets/characters/mopper.svg"),
	&"STOCK_REPLENISHER": preload("res://assets/characters/stock_replenisher.svg"),
	&"AUDIO_TOWER": preload("res://assets/characters/audio_tower.svg"),
}

var tower_type: StringName = &"MOPPER"
var pulse_time: float = 0.0
@onready var sprite: Sprite2D = $Sprite2D


func set_state(payload: Dictionary, screen_position: Vector2) -> void:
	tower_type = StringName(payload.get("tower_type", "MOPPER"))
	position = screen_position
	sprite.texture = TEXTURES.get(tower_type)
	queue_redraw()


func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()


func _draw() -> void:
	if tower_type == &"MOPPER":
		draw_ellipse_shape(Vector2(0, 31), Vector2(34, 9), Color("#78d8e8", 0.7))
	if tower_type == &"AUDIO_TOWER":
		var radius := 32.0 + sin(pulse_time * 5.0) * 5.0
		draw_arc(Vector2.ZERO, radius, -0.8, 0.8, 18, Color("#f5d16a", 0.7), 3.0)


func draw_ellipse_shape(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 24:
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
