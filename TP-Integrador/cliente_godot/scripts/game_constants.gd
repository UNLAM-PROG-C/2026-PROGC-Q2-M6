extends Node
class_name GameConstants

const BOARD_LEFT: float = 100.0
const BOARD_TOP: float = 150.0
const BOARD_WIDTH: float = 1000.0
const BOARD_HEIGHT: float = 500.0
const WORLD_END: float = 100.0
const LANE_Y: Array[float] = [250.0, 400.0, 550.0]
const ENTITY_SCALE: float = 0.72
const INITIAL_GOLD: int = 200
const INITIAL_BASE_HP: int = 100
const TOTAL_WAVES: int = 10
const TOWER_TYPES: Array[StringName] = [
	&"MOPPER", &"STOCK_REPLENISHER", &"AUDIO_TOWER"
]
const TOWER_LABELS: Dictionary = {
	&"MOPPER": "Mopeador",
	&"STOCK_REPLENISHER": "Repositor",
	&"AUDIO_TOWER": "Altavoz",
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
