extends Control
class_name GameInputHandler

signal placement_rejected(message: String)

var selected_tower: StringName = &""
var towers: Array[Dictionary] = []


func select_tower(tower_type: StringName) -> void:
	selected_tower = tower_type


func update_towers(next_towers: Array) -> void:
	towers.clear()
	for tower in next_towers:
		towers.append(tower)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_handle_click(event)


func _handle_click(event: InputEventMouseButton) -> void:
	var tower_id := _tower_at(event.position)
	if tower_id >= 0:
		if event.button_index == MOUSE_BUTTON_LEFT:
			NetworkClient.send_message(ProtocolConstants.UPGRADE_TOWER, {"tower_id": tower_id})
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			NetworkClient.send_message(ProtocolConstants.SELL_TOWER, {"tower_id": tower_id})
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if selected_tower.is_empty():
		return
	if not _inside_board(event.position):
		placement_rejected.emit("Seleccioná un carril válido.")
		return
	var lane := _lane_at(event.position.y)
	var world_x := _screen_to_world_x(event.position.x)
	NetworkClient.send_message(ProtocolConstants.BUY_TOWER, {
		"tower_type": String(selected_tower),
		"lane": lane,
		"pos": [world_x, float(lane)],
	})


func _tower_at(screen_position: Vector2) -> int:
	for tower in towers:
		var position := _tower_screen_position(tower)
		if position.distance_to(screen_position) <= 34.0:
			return int(tower.get("tower_id", -1))
	return -1


func _tower_screen_position(tower: Dictionary) -> Vector2:
	var raw_pos: Array = tower.get("pos", [0.0, 0.0])
	return Vector2(
		GameConstants.world_to_screen_x(float(raw_pos[0])),
		GameConstants.lane_to_screen_y(int(tower.get("lane", 0))),
	)


func _inside_board(position: Vector2) -> bool:
	return Rect2(
		GameConstants.BOARD_LEFT,
		GameConstants.BOARD_TOP,
		GameConstants.BOARD_WIDTH,
		GameConstants.BOARD_HEIGHT,
	).has_point(position)


func _lane_at(screen_y: float) -> int:
	var lane := 0
	var distance := INF
	for index in GameConstants.LANE_Y.size():
		var current_distance: float = abs(screen_y - GameConstants.LANE_Y[index])
		if current_distance < distance:
			distance = current_distance
			lane = index
	return lane


func _screen_to_world_x(screen_x: float) -> float:
	var normalized := (screen_x - GameConstants.BOARD_LEFT) / GameConstants.BOARD_WIDTH
	return clampf(normalized * GameConstants.WORLD_END, 0.0, GameConstants.WORLD_END)
