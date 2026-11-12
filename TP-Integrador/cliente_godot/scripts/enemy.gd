extends Node2D
class_name EnemyView

const TEXTURES: Dictionary = {
	&"DISCOUNT_CHILD": preload("res://assets/characters/discount_child.svg"),
	&"SHOPPING_GRANDMA": preload("res://assets/characters/shopping_grandma.svg"),
	&"SKATEBOARD_CHILD": preload("res://assets/characters/skateboard_child.svg"),
	&"ARMORED_GRANDMA": preload("res://assets/characters/armored_grandma.svg"),
	&"GOLD_CART_BOSS": preload("res://assets/characters/gold_cart_boss.svg"),
}

const STUNNED_COLOR: Color = Color("#ffe178")
const HEALTH_BAR_RECT: Rect2 = Rect2(-30, -48, 60, 7)
const HEALTH_BAR_BACK_COLOR: Color = Color("#432d2d")
const HEALTH_BAR_FILL_COLOR: Color = Color("#57c978")
const HEALTH_TEXT_POSITION: Vector2 = Vector2(-30, -54)
const HEALTH_TEXT_FONT_SIZE: int = 12
const HEALTH_TEXT_COLOR: Color = Color("#111111")
const STUN_RING_RADIUS: float = 36.0
const STUN_RING_SEGMENTS: int = 24
const STUN_RING_WIDTH: float = 3.0

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
	sprite.modulate = STUNNED_COLOR if payload.get("stunned", false) else Color.WHITE
	queue_redraw()


func _draw() -> void:
	var health_ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	var fill_rect := HEALTH_BAR_RECT
	fill_rect.size.x *= health_ratio
	draw_rect(HEALTH_BAR_RECT, HEALTH_BAR_BACK_COLOR)
	draw_rect(fill_rect, HEALTH_BAR_FILL_COLOR)
	_draw_health_text()
	if sprite.modulate != Color.WHITE:
		_draw_stun_ring()


func _draw_health_text() -> void:
	draw_string(
		ThemeDB.fallback_font,
		HEALTH_TEXT_POSITION,
		"%d/%d" % [health, max_health],
		HORIZONTAL_ALIGNMENT_LEFT,
		HEALTH_BAR_RECT.size.x,
		HEALTH_TEXT_FONT_SIZE,
		HEALTH_TEXT_COLOR,
	)


func _draw_stun_ring() -> void:
	draw_arc(Vector2.ZERO, STUN_RING_RADIUS, 0.0, TAU, STUN_RING_SEGMENTS,
		STUNNED_COLOR, STUN_RING_WIDTH)
