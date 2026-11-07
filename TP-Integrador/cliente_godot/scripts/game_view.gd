extends Control

const TOWER_SCENE: PackedScene = preload("res://scenes/Tower.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

var tower_views: Dictionary = {}
var enemy_views: Dictionary = {}
var attack_effects: Array[Dictionary] = []
var base_hp: float = 100.0

@onready var input_handler: GameInputHandler = $InputHandler
@onready var hud: GameHud = $Hud
@onready var entities: Node2D = $Entities
@onready var game_over: GameOverPanel = $GameOver


func _ready() -> void:
	NetworkClient.state_update_received.connect(_on_state_update)
	NetworkClient.error_received.connect(_on_error)
	NetworkClient.game_over_received.connect(_on_game_over)
	NetworkClient.attack_received.connect(_on_attack)
	hud.tower_selected.connect(input_handler.select_tower)
	input_handler.placement_rejected.connect(hud.show_error)
	game_over.visible = false
	queue_redraw()


func _process(delta: float) -> void:
	for effect in attack_effects:
		effect["remaining"] = float(effect["remaining"]) - delta
	attack_effects = attack_effects.filter(func(effect: Dictionary) -> bool:
		return float(effect["remaining"]) > 0.0
	)
	queue_redraw()


func _draw() -> void:
	_draw_background()
	_draw_lanes()
	_draw_base()
	for effect in attack_effects:
		var tower: Node2D = tower_views.get(int(effect["tower_id"])) as Node2D
		var enemy: Node2D = enemy_views.get(int(effect["target_id"])) as Node2D
		if tower != null and enemy != null:
			draw_line(tower.position, enemy.position, Color("#ffe36e"), 4.0)
			draw_circle(enemy.position, 7.0, Color("#fff4a8"))


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#27313b"))
	draw_rect(Rect2(0, 90, size.x, 34), Color("#a66042"))
	draw_rect(Rect2(0, 124, size.x, size.y - 124), Color("#e7d8b9"))


func _draw_lanes() -> void:
	for lane_y in GameConstants.LANE_Y:
		draw_line(
			Vector2(GameConstants.BOARD_LEFT, lane_y + 32),
			Vector2(GameConstants.BOARD_LEFT + GameConstants.BOARD_WIDTH, lane_y + 32),
			Color("#b8aa91"),
			2.0,
		)


func _draw_base() -> void:
	var ratio := clampf(base_hp / 100.0, 0.0, 1.0)
	var outer_color := Color("#55a5bd").lerp(Color("#713838"), 1.0 - ratio)
	draw_rect(Rect2(822, 150, 112, 280), outer_color)
	draw_rect(Rect2(834, 165, 88, 230), Color("#bcecf1").lerp(Color("#d36d55"), 1.0 - ratio))
	if ratio < 0.75:
		draw_line(Vector2(850, 210), Vector2(880, 260), Color("#713838"), 4.0)
	if ratio < 0.45:
		draw_line(Vector2(885, 290), Vector2(850, 350), Color("#713838"), 4.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(842, 190),
		"BASE",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		20,
		Color("#183244"),
	)


func _on_state_update(payload: Dictionary) -> void:
	base_hp = float(payload.get("base_hp", 100.0))
	hud.update_state(payload)
	_sync_towers(payload.get("towers", []))
	_sync_enemies(payload.get("enemies", []))
	input_handler.update_towers(payload.get("towers", []))


func _sync_towers(states: Array) -> void:
	var active_ids: Dictionary = {}
	for state in states:
		var tower_id := int(state.get("tower_id", -1))
		active_ids[tower_id] = true
		var view: TowerView = tower_views.get(tower_id) as TowerView
		if view == null:
			view = TOWER_SCENE.instantiate() as TowerView
			entities.add_child(view)
			tower_views[tower_id] = view
		view.set_state(state, _entity_position(state))
	_remove_stale(tower_views, active_ids)


func _sync_enemies(states: Array) -> void:
	var active_ids: Dictionary = {}
	for state in states:
		var enemy_id := int(state.get("enemy_id", -1))
		active_ids[enemy_id] = true
		var view: EnemyView = enemy_views.get(enemy_id) as EnemyView
		if view == null:
			view = ENEMY_SCENE.instantiate() as EnemyView
			entities.add_child(view)
			enemy_views[enemy_id] = view
		view.set_state(state, _entity_position(state))
	_remove_stale(enemy_views, active_ids)


func _remove_stale(views: Dictionary, active_ids: Dictionary) -> void:
	for entity_id in views.keys():
		if active_ids.has(entity_id):
			continue
		views[entity_id].queue_free()
		views.erase(entity_id)


func _entity_position(state: Dictionary) -> Vector2:
	var raw_pos: Array = state.get("pos", [0.0, 0.0])
	return Vector2(
		GameConstants.world_to_screen_x(float(raw_pos[0])),
		GameConstants.lane_to_screen_y(int(state.get("lane", 0))),
	)


func _on_error(payload: Dictionary) -> void:
	hud.show_error(String(payload.get("message", "Error de juego")))


func _on_game_over(payload: Dictionary) -> void:
	game_over.show_result(payload)


func _on_attack(payload: Dictionary) -> void:
	for target_id in payload.get("target_ids", []):
		attack_effects.append({
			"tower_id": int(payload.get("tower_id", -1)),
			"target_id": int(target_id),
			"remaining": 0.16,
		})
	queue_redraw()


func reset_for_new_game() -> void:
	for view in tower_views.values():
		view.queue_free()
	for view in enemy_views.values():
		view.queue_free()
	tower_views.clear()
	enemy_views.clear()
	attack_effects.clear()
	game_over.visible = false
