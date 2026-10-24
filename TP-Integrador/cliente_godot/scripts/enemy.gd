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
@onready var sprite: Sprite2D = $Sprite2D


func set_state(payload: Dictionary, screen_position: Vector2) -> void:
	enemy_type = StringName(payload.get("enemy_type", "DISCOUNT_CHILD"))
	position = screen_position
	sprite.texture = TEXTURES.get(enemy_type)
	sprite.modulate = Color("#ffe178") if payload.get("stunned", false) else Color.WHITE
	queue_redraw()


func _draw() -> void:
	if sprite.modulate != Color.WHITE:
		draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 24, Color("#ffe178"), 3.0)
