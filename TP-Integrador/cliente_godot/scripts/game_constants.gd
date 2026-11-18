extends Node
class_name GameConstants

const BOARD_LEFT: float = 100.0
const BOARD_TOP: float = 150.0
const BOARD_WIDTH: float = 1000.0
const BOARD_HEIGHT: float = 500.0
const WORLD_START: float = 0.0
const WORLD_END: float = 100.0
const WORLD_POSITION_X_INDEX: int = 0
const DEFAULT_WORLD_POSITION: Array[float] = [WORLD_START, WORLD_START]
const LANE_Y: Array[float] = [250.0, 400.0, 550.0]
const FIRST_LANE: int = 0
const NO_GOLD: int = 0
const NO_BASE_HP: int = 0
const INITIAL_GOLD: int = 200
const INITIAL_BASE_HP: int = 100
const TOTAL_WAVES: int = 10
const NO_CURRENT_WAVE: int = 0


static func world_to_screen_x(world_x: float) -> float:
	return BOARD_LEFT + world_x / WORLD_END * BOARD_WIDTH


static func lane_to_screen_y(lane: int) -> float:
	return LANE_Y[clampi(lane, 0, LANE_Y.size() - 1)]
