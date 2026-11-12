extends Control

signal restart_requested

const TOWER_SCENE: PackedScene = preload("res://scenes/Tower.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const NO_ENTITY_ID: int = -1
const ATTACK_EFFECT_SECONDS: float = 0.16
const DEFAULT_ERROR_TEXT: String = "Error de juego"

const BACKGROUND_COLOR: Color = Color("#27313b")
const ATTACK_LINE_COLOR: Color = Color("#ffe36e")
const ATTACK_LINE_WIDTH: float = 4.0
const ATTACK_HIT_COLOR: Color = Color("#fff4a8")
const ATTACK_HIT_RADIUS: float = 7.0

const WALL_TOP: float = 90.0
const BASEBOARD_TOP: float = 178.0
const FLOOR_TOP: float = 198.0
const WALL_TILE: float = 40.0
const FLOOR_TILE: float = 64.0
const WALL_COLOR_EVEN: Color = Color("#f3dfae")
const WALL_COLOR_ODD: Color = Color("#e9cf96")
const WALL_SHINE_RECT: Rect2 = Rect2(3, 3, 6, 2)
const WALL_SHINE_COLOR: Color = Color("#fbefcf")
const WALL_GROUT_COLOR: Color = Color("#d8bd84")
const GROUT_WIDTH: float = 1.0

const BASEBOARD_COLOR: Color = Color("#9a5b3c")
const BASEBOARD_TOP_EDGE: float = 4.0
const BASEBOARD_TOP_COLOR: Color = Color("#c27c55")
const BASEBOARD_BOTTOM_EDGE: float = 3.0
const BASEBOARD_BOTTOM_COLOR: Color = Color("#6e3d28")
const BASEBOARD_SHADOW_HEIGHT: float = 6.0
const BASEBOARD_SHADOW_COLOR: Color = Color(0, 0, 0, 0.08)

const FLOOR_COLOR: Color = Color("#efeadf")
const FLOOR_ALT_COLOR: Color = Color("#e8e2d4")
const BEVEL_LIGHT_COLOR: Color = Color("#fbf8f1")
const BEVEL_SHADOW_COLOR: Color = Color("#d6cfc0")
const BEVEL_WIDTH: float = 2.0

const LANE_HALF_HEIGHT: float = 44.0
const LANE_STRIPE_COLOR: Color = Color("#b8ab92", 0.12)
const LANE_DASH_OFFSET_Y: float = 36.0
const LANE_DASH_LENGTH: float = 20.0
const LANE_DASH_SPACING: float = 36.0
const LANE_DASH_COLOR: Color = Color("#cfc4ae")
const LANE_DASH_WIDTH: float = 2.0

var tower_views: Dictionary = {}
var enemy_views: Dictionary = {}
var attack_effects: Array[Dictionary] = []
var base_hp: float = GameConstants.INITIAL_BASE_HP

@onready var input_handler: GameInputHandler = $InputHandler
@onready var hud: GameHud = $Hud
@onready var entities: Node2D = $Entities
@onready var game_over: GameOverPanel = $GameOver
@onready var restart_button: Button = $RestartButton
@onready var fridge: FridgeView = $Fridge


func _ready() -> void:
	NetworkClient.state_update_received.connect(_on_state_update)
	NetworkClient.error_received.connect(_on_error)
	NetworkClient.game_over_received.connect(_on_game_over)
	NetworkClient.attack_received.connect(_on_attack)
	hud.tower_selected.connect(input_handler.select_tower)
	input_handler.placement_rejected.connect(hud.show_error)
	game_over.visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	queue_redraw()


func _process(delta: float) -> void:
	for effect in attack_effects:
		effect["remaining"] = float(effect["remaining"]) - delta
	attack_effects = attack_effects.filter(func(effect: Dictionary) -> bool:
		return float(effect["remaining"]) > 0.0
	)
	queue_redraw()


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _draw() -> void:
	_draw_background()
	_draw_lanes()
	for effect in attack_effects:
		_draw_attack_effect(effect)


func _draw_attack_effect(effect: Dictionary) -> void:
	var tower: Node2D = tower_views.get(int(effect["tower_id"])) as Node2D
	var enemy: Node2D = enemy_views.get(int(effect["target_id"])) as Node2D
	if tower == null or enemy == null:
		return
	draw_line(tower.position, enemy.position, ATTACK_LINE_COLOR, ATTACK_LINE_WIDTH)
	draw_circle(enemy.position, ATTACK_HIT_RADIUS, ATTACK_HIT_COLOR)


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
	_draw_wall()
	_draw_baseboard()
	_draw_floor()


func _draw_wall() -> void:
	var cols: int = int(ceil(size.x / WALL_TILE))
	var y: float = WALL_TOP
	var row: int = 0
	while y < BASEBOARD_TOP:
		var height: float = minf(WALL_TILE, BASEBOARD_TOP - y)
		for col in cols:
			_draw_wall_tile(row, col, y, height)
		y += WALL_TILE
		row += 1
	_draw_wall_grout(cols)


func _draw_wall_tile(row: int, col: int, y: float, height: float) -> void:
	var tile_color: Color = WALL_COLOR_EVEN if (row + col) % 2 == 0 else WALL_COLOR_ODD
	var origin := Vector2(col * WALL_TILE, y)
	draw_rect(Rect2(origin, Vector2(WALL_TILE, height)), tile_color)
	draw_rect(Rect2(origin + WALL_SHINE_RECT.position, WALL_SHINE_RECT.size), WALL_SHINE_COLOR)


func _draw_wall_grout(cols: int) -> void:
	for col in range(0, cols + 1):
		var x: float = col * WALL_TILE
		draw_line(Vector2(x, WALL_TOP), Vector2(x, BASEBOARD_TOP), WALL_GROUT_COLOR, GROUT_WIDTH)
	var y: float = WALL_TOP
	while y < BASEBOARD_TOP:
		draw_line(Vector2(0, y), Vector2(size.x, y), WALL_GROUT_COLOR, GROUT_WIDTH)
		y += WALL_TILE


func _draw_baseboard() -> void:
	var height: float = FLOOR_TOP - BASEBOARD_TOP
	draw_rect(Rect2(0, BASEBOARD_TOP, size.x, height), BASEBOARD_COLOR)
	draw_rect(Rect2(0, BASEBOARD_TOP, size.x, BASEBOARD_TOP_EDGE), BASEBOARD_TOP_COLOR)
	var bottom_y: float = FLOOR_TOP - BASEBOARD_BOTTOM_EDGE
	draw_rect(Rect2(0, bottom_y, size.x, BASEBOARD_BOTTOM_EDGE), BASEBOARD_BOTTOM_COLOR)
	# Soft baseboard shadow over the floor
	draw_rect(Rect2(0, FLOOR_TOP, size.x, BASEBOARD_SHADOW_HEIGHT), BASEBOARD_SHADOW_COLOR)


func _draw_floor() -> void:
	draw_rect(Rect2(0, FLOOR_TOP, size.x, size.y - FLOOR_TOP), FLOOR_COLOR)
	var cols: int = int(ceil(size.x / FLOOR_TILE))
	var rows: int = int(ceil((size.y - FLOOR_TOP) / FLOOR_TILE))
	for row in rows:
		for col in cols:
			_draw_floor_tile(row, col)


func _draw_floor_tile(row: int, col: int) -> void:
	var origin := Vector2(col * FLOOR_TILE, FLOOR_TOP + row * FLOOR_TILE)
	var tile := Rect2(origin, Vector2(FLOOR_TILE, FLOOR_TILE))
	if (row + col) % 2 == 1:
		draw_rect(tile, FLOOR_ALT_COLOR)
	# Bevel: light on top/left, shadow on bottom/right
	var top_right := Vector2(tile.end.x, tile.position.y)
	var bottom_left := Vector2(tile.position.x, tile.end.y)
	draw_line(tile.position, top_right, BEVEL_LIGHT_COLOR, BEVEL_WIDTH)
	draw_line(tile.position, bottom_left, BEVEL_LIGHT_COLOR, BEVEL_WIDTH)
	draw_line(bottom_left + Vector2.UP, tile.end + Vector2.UP, BEVEL_SHADOW_COLOR, BEVEL_WIDTH)
	draw_line(top_right + Vector2.LEFT, tile.end + Vector2.LEFT, BEVEL_SHADOW_COLOR, BEVEL_WIDTH)


func _draw_lanes() -> void:
	var lane_end: float = GameConstants.BOARD_LEFT + GameConstants.BOARD_WIDTH
	for lane_y in GameConstants.LANE_Y:
		# Faint stripe that marks the lane without cutting the floor
		var stripe := Rect2(0, lane_y - LANE_HALF_HEIGHT, lane_end, LANE_HALF_HEIGHT * 2.0)
		draw_rect(stripe, LANE_STRIPE_COLOR)
		_draw_lane_dashes(lane_y + LANE_DASH_OFFSET_Y, lane_end)


func _draw_lane_dashes(dash_y: float, lane_end: float) -> void:
	var x: float = GameConstants.BOARD_LEFT
	while x < lane_end:
		var dash_end := Vector2(minf(x + LANE_DASH_LENGTH, lane_end), dash_y)
		draw_line(Vector2(x, dash_y), dash_end, LANE_DASH_COLOR, LANE_DASH_WIDTH)
		x += LANE_DASH_SPACING


func _on_state_update(payload: Dictionary) -> void:
	base_hp = float(payload.get("base_hp", GameConstants.INITIAL_BASE_HP))
	fridge.set_hp(base_hp)
	hud.update_state(payload)
	_sync_towers(payload.get("towers", []))
	_sync_enemies(payload.get("enemies", []))
	input_handler.update_towers(payload.get("towers", []))


func _sync_towers(states: Array) -> void:
	_sync_views(states, tower_views, "tower_id", TOWER_SCENE)


func _sync_enemies(states: Array) -> void:
	_sync_views(states, enemy_views, "enemy_id", ENEMY_SCENE)


func _sync_views(states: Array, views: Dictionary, id_key: String, scene: PackedScene) -> void:
	var active_ids: Dictionary = {}
	for state in states:
		var entity_id := int(state.get(id_key, NO_ENTITY_ID))
		active_ids[entity_id] = true
		var view = views.get(entity_id)
		if view == null:
			view = scene.instantiate()
			entities.add_child(view)
			views[entity_id] = view
		view.set_state(state, _entity_position(state))
	_remove_stale(views, active_ids)


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
	hud.show_error(String(payload.get("message", DEFAULT_ERROR_TEXT)))


func _on_game_over(payload: Dictionary) -> void:
	game_over.show_result(payload)


func _on_attack(payload: Dictionary) -> void:
	var tower_id := int(payload.get("tower_id", NO_ENTITY_ID))
	var target_ids: Array = payload.get("target_ids", [])
	var tower: TowerView = tower_views.get(tower_id) as TowerView
	if tower != null:
		tower.play_attack(target_ids.size())
	for target_id in target_ids:
		attack_effects.append({
			"tower_id": tower_id,
			"target_id": int(target_id),
			"remaining": ATTACK_EFFECT_SECONDS,
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
	base_hp = GameConstants.INITIAL_BASE_HP
	fridge.set_hp(base_hp)
	game_over.visible = false
	hud.reset_state()
