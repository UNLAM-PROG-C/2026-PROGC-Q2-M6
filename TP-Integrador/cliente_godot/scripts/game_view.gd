extends Control

signal restart_requested

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
		var tower: Node2D = tower_views.get(int(effect["tower_id"])) as Node2D
		var enemy: Node2D = enemy_views.get(int(effect["target_id"])) as Node2D
		if tower != null and enemy != null:
			draw_line(tower.position, enemy.position, Color("#ffe36e"), 4.0)
			draw_circle(enemy.position, 7.0, Color("#fff4a8"))


const WALL_TOP: float = 90.0
const BASEBOARD_TOP: float = 178.0
const FLOOR_TOP: float = 198.0
const WALL_TILE: float = 40.0
const FLOOR_TILE: float = 64.0


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#27313b"))
	_draw_wall()
	_draw_baseboard()
	_draw_floor()


func _draw_wall() -> void:
	var cols: int = int(ceil(size.x / WALL_TILE))
	var y: float = WALL_TOP
	var row: int = 0
	while y < BASEBOARD_TOP:
		var h: float = minf(WALL_TILE, BASEBOARD_TOP - y)
		for col in cols:
			var tile_color: Color = Color("#f3dfae") if (row + col) % 2 == 0 else Color("#e9cf96")
			draw_rect(Rect2(col * WALL_TILE, y, WALL_TILE, h), tile_color)
			draw_rect(Rect2(col * WALL_TILE + 3, y + 3, 6, 2), Color("#fbefcf"))
		y += WALL_TILE
		row += 1
	for col in range(0, cols + 1):
		draw_line(Vector2(col * WALL_TILE, WALL_TOP), Vector2(col * WALL_TILE, BASEBOARD_TOP), Color("#d8bd84"), 1.0)
	y = WALL_TOP
	while y < BASEBOARD_TOP:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("#d8bd84"), 1.0)
		y += WALL_TILE


func _draw_baseboard() -> void:
	draw_rect(Rect2(0, BASEBOARD_TOP, size.x, FLOOR_TOP - BASEBOARD_TOP), Color("#9a5b3c"))
	draw_rect(Rect2(0, BASEBOARD_TOP, size.x, 4), Color("#c27c55"))
	draw_rect(Rect2(0, FLOOR_TOP - 3, size.x, 3), Color("#6e3d28"))
	# Soft baseboard shadow over the floor
	draw_rect(Rect2(0, FLOOR_TOP, size.x, 6), Color(0, 0, 0, 0.08))


func _draw_floor() -> void:
	draw_rect(Rect2(0, FLOOR_TOP, size.x, size.y - FLOOR_TOP), Color("#efeadf"))
	var cols: int = int(ceil(size.x / FLOOR_TILE))
	var rows: int = int(ceil((size.y - FLOOR_TOP) / FLOOR_TILE))
	for row in rows:
		for col in cols:
			var tile := Rect2(col * FLOOR_TILE, FLOOR_TOP + row * FLOOR_TILE, FLOOR_TILE, FLOOR_TILE)
			if (row + col) % 2 == 1:
				draw_rect(tile, Color("#e8e2d4"))
			# Bisel: luz arriba/izquierda, sombra abajo/derecha
			draw_line(tile.position, Vector2(tile.end.x, tile.position.y), Color("#fbf8f1"), 2.0)
			draw_line(tile.position, Vector2(tile.position.x, tile.end.y), Color("#fbf8f1"), 2.0)
			draw_line(Vector2(tile.position.x, tile.end.y - 1), tile.end - Vector2(0, 1), Color("#d6cfc0"), 2.0)
			draw_line(Vector2(tile.end.x - 1, tile.position.y), tile.end - Vector2(1, 0), Color("#d6cfc0"), 2.0)


func _draw_lanes() -> void:
	var lane_end: float = GameConstants.BOARD_LEFT + GameConstants.BOARD_WIDTH
	for lane_y in GameConstants.LANE_Y:
		# Faint stripe that marks the lane without cutting the floor
		draw_rect(Rect2(0, lane_y - 44, lane_end, 88), Color("#b8ab92", 0.12))
		var x: float = GameConstants.BOARD_LEFT
		while x < lane_end:
			draw_line(Vector2(x, lane_y + 36), Vector2(minf(x + 20.0, lane_end), lane_y + 36), Color("#cfc4ae"), 2.0)
			x += 36.0


func _on_state_update(payload: Dictionary) -> void:
	base_hp = float(payload.get("base_hp", 100.0))
	fridge.set_hp(base_hp)
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
	var tower_id := int(payload.get("tower_id", -1))
	var target_ids: Array = payload.get("target_ids", [])
	var tower: TowerView = tower_views.get(tower_id) as TowerView
	if tower != null:
		tower.play_attack(target_ids.size())
	for target_id in payload.get("target_ids", []):
		attack_effects.append({
			"tower_id": tower_id,
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
	base_hp = 100.0
	fridge.set_hp(base_hp)
	game_over.visible = false
	hud.reset_state()
