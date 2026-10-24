extends Node
class_name GameConstants

const BOARD_LEFT: float = 80.0
const BOARD_TOP: float = 112.0
const BOARD_WIDTH: float = 720.0
const BOARD_HEIGHT: float = 360.0
const WORLD_END: float = 100.0
const LANE_Y: Array[float] = [172.0, 292.0, 412.0]
const ENTITY_SCALE: float = 0.72
const TOWER_TYPES: Array[StringName] = [
	&"MOPPER", &"STOCK_REPLENISHER", &"AUDIO_TOWER"
]
const TOWER_LABELS: Dictionary = {
	&"MOPPER": "Mopeador",
	&"STOCK_REPLENISHER": "Repositor",
	&"AUDIO_TOWER": "Paging",
}
const TOWER_COSTS: Dictionary = {
	&"MOPPER": 50,
	&"STOCK_REPLENISHER": 120,
	&"AUDIO_TOWER": 150,
}


static func world_to_screen_x(world_x: float) -> float:
	return BOARD_LEFT + world_x / WORLD_END * BOARD_WIDTH


static func lane_to_screen_y(lane: int) -> float:
	return LANE_Y[clampi(lane, 0, LANE_Y.size() - 1)]
