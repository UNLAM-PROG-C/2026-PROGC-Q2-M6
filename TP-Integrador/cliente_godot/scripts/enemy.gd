extends Node2D
class_name EnemyView

const TEXTURES: Dictionary = {
	&"DISCOUNT_CHILD": preload("res://assets/characters/discount_child.svg"),
	&"SHOPPING_GRANDMA": preload("res://assets/characters/shopping_grandma.svg"),
	&"SKATEBOARD_CHILD": preload("res://assets/characters/skateboard_child.svg"),
	&"ARMORED_GRANDMA": preload("res://assets/characters/armored_grandma.svg"),
	&"GOLD_CART_BOSS": preload("res://assets/characters/gold_cart_boss.svg"),
}

var enemy_type: StringName = &"DISCOUNT_CHILD"
var health: int = 0
var max_health: int = 1
@onready var sprite: Sprite2D = $Sprite2D


func set_state(payload: Dictionary, screen_position: Vector2) -> void:
	enemy_type = StringName(payload.get("enemy_type", "DISCOUNT_CHILD"))
	health = int(payload.get("health", 0))
	max_health = maxi(1, int(payload.get("max_health", health)))
	position = screen_position
	sprite.texture = TEXTURES.get(enemy_type)
	sprite.modulate = Color("#ffe178") if payload.get("stunned", false) else Color.WHITE
	queue_redraw()


func _draw() -> void:
	var health_ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	draw_rect(Rect2(-30, -48, 60, 7), Color("#432d2d"))
	draw_rect(Rect2(-30, -48, 60 * health_ratio, 7), Color("#57c978"))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-30, -54),
		"%d/%d" % [health, max_health],
		HORIZONTAL_ALIGNMENT_LEFT,
		60,
		12,
		Color("#111111"),
	)
	if sprite.modulate != Color.WHITE:
		draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 24, Color("#ffe178"), 3.0)
