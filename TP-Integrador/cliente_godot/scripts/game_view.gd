extends Control

const TOWER_SCENE: PackedScene = preload("res://scenes/Tower.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

var tower_views: Dictionary = {}
var enemy_views: Dictionary = {}

@onready var input_handler: GameInputHandler = $InputHandler
@onready var hud: GameHud = $Hud
@onready var entities: Node2D = $Entities
@onready var game_over: GameOverPanel = $GameOver


func _ready() -> void:
	NetworkClient.state_update_received.connect(_on_state_update)
	NetworkClient.error_received.connect(_on_error)
	NetworkClient.game_over_received.connect(_on_game_over)
	hud.tower_selected.connect(input_handler.select_tower)
	input_handler.placement_rejected.connect(hud.show_error)
	game_over.visible = false
	queue_redraw()


func _draw() -> void:
	_draw_background()
	_draw_lanes()
	_draw_base()


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
	draw_rect(Rect2(822, 150, 112, 280), Color("#55a5bd"))
	draw_rect(Rect2(834, 165, 88, 230), Color("#bcecf1"))
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
