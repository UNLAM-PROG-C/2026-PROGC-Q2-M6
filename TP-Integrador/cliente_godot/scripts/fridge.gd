extends Node2D
class_name FridgeView

## Display fridge ("Frigorífico") that acts as the team base.
## Drawn procedurally and reacts to the base HP.

const BODY_RECT: Rect2 = Rect2(1110, 176, 162, 420)
const GLASS_TINT_OK: Color = Color("#cfefff")
const GLASS_TINT_DAMAGED: Color = Color("#d36d55")
const GLOW_OK: Color = Color("#7ff3ff")
const GLOW_DANGER: Color = Color("#ff4d4d")
const CRACK_COLOR: Color = Color("#5a2a2a")
const CRACK_WIDTH: float = 3.0

const DANGER_RATIO: float = 0.25
const LIGHT_DAMAGE_RATIO: float = 0.75
const HEAVY_DAMAGE_RATIO: float = 0.45
const MSEC_PER_SECOND: float = 1000.0
const PULSE_BASE: float = 0.6
const PULSE_AMPLITUDE: float = 0.4
const PULSE_SPEED: float = 8.0
## Each layer is [grow pixels, alpha].
const GLOW_LAYERS: Array = [[16.0, 0.05], [11.0, 0.08], [6.0, 0.12], [2.0, 0.18]]

const SHELL_COLOR: Color = Color("#1d4f7a")
const SHELL_INNER_COLOR: Color = Color("#3c8fd0")
const SHELL_EDGE_COLOR: Color = Color("#8fd3ff")
const SHELL_INSET: float = 3.0
const PANEL_COLOR: Color = Color("#2a6fb5")
const PANEL_EDGE_COLOR: Color = Color("#174a7c")
const PANEL_MARGIN: float = 8.0
const HEADER_HEIGHT: float = 30.0
const GLASS_TOP: float = 46.0
const GLASS_HEIGHT: float = 316.0
const VENT_PANEL_BOTTOM: float = 50.0
const VENT_PANEL_HEIGHT: float = 42.0
const THIN_LINE: float = 1.0
const THICK_LINE: float = 2.0

const TITLE_TEXT: String = "FRIGORÍFICO"
const TITLE_OFFSET: Vector2 = Vector2(4, 21)
const TITLE_WIDTH: float = 104.0
const TITLE_FONT_SIZE: int = 14
const TITLE_OUTLINE_SIZE: int = 4
const TITLE_OUTLINE_COLOR: Color = Color("#0e2f52")
const TEXT_COLOR: Color = Color("#ffffff")
const TAG_TEXT: String = "STOCK"
const TAG_SIZE: Vector2 = Vector2(34, 16)
const TAG_OFFSET: Vector2 = Vector2(-38, 7)
const TAG_TEXT_BASELINE: float = 12.0
const TAG_FONT_SIZE: int = 9
const TAG_COLOR: Color = Color("#3cc46a")
const TAG_EDGE_COLOR: Color = Color("#1f7a3d")

const GLASS_COLOR: Color = Color("#5fb4e6")
const CELL_EDGE_COLOR: Color = Color("#9ad6f5")
const CELL_GAP: float = 4.0
const SHELF_ROWS: int = 2
const SHELF_COLS: int = 3
## Top row cutlets / meat / meat, bottom row meat / meat / ice.
const SHELF_LAYOUT: Array = [
	[&"milanesa", &"steak", &"steak"],
	[&"steak", &"steak", &"ice"],
]
const SHINE_COLOR: Color = Color(1, 1, 1, 0.22)
const SHINE_OFFSETS: Array[float] = [10.0, 70.0]
const SHINE_BOTTOM_WIDTH: float = 14.0
const SHINE_TOP_LEFT: float = 50.0
const SHINE_TOP_RIGHT: float = 64.0

const ITEM_WIDTH: float = 18.0
const ITEM_COLS: int = 2
const ITEM_ROWS: int = 5
const ITEM_TOP_PADDING: float = 6.0
const ITEM_VERTICAL_PADDING: float = 8.0

const MILANESA_EDGE_COLOR: Color = Color("#b8742c")
const MILANESA_COLOR: Color = Color("#e9a94f")
const MILANESA_CRUMB_COLOR: Color = Color("#f6cd85")
const MILANESA_LEMON_COLOR: Color = Color("#fff1c4")
const MILANESA_SIZE: Vector2 = Vector2(18, 16)
const MILANESA_INSET: float = 2.0
## Rounded-corner outline, each entry is [offset, size].
const MILANESA_PARTS: Array = [
	[Vector2(1, 0), Vector2(16, 16)],
	[Vector2(0, 1), Vector2(18, 14)],
]
const MILANESA_CRUMB: Rect2 = Rect2(3, 3, 4, 3)
const MILANESA_LEMON: Rect2 = Rect2(2, 11, 14, 3)

const TRAY_RECT: Rect2 = Rect2(0, 4, 18, 12)
const TRAY_COLOR: Color = Color("#f4f7f9")
const TRAY_EDGE_COLOR: Color = Color("#b9c6cf")
const STEAK_CENTER: Vector2 = Vector2(9, 9)
const STEAK_OUTER_RADII: Vector2 = Vector2(8, 5.5)
const STEAK_INNER_RADII: Vector2 = Vector2(7, 4.5)
const STEAK_SEGMENTS: int = 12
const STEAK_OUTER_COLOR: Color = Color("#a8323a")
const STEAK_INNER_COLOR: Color = Color("#d9545a")
const STEAK_FAT_FROM: Vector2 = Vector2(-4, -1)
const STEAK_FAT_TO: Vector2 = Vector2(3, 2)
const STEAK_FAT_COLOR: Color = Color("#f3b0b0")
const STEAK_FAT_WIDTH: float = 1.5
const STEAK_BONE_OFFSET: Vector2 = Vector2(4, -2)
const STEAK_BONE_RADIUS: float = 1.3
const STEAK_BONE_COLOR: Color = Color("#f8e6d8")

const ICE_OFFSETS: Array[Vector2] = [Vector2(0, 6), Vector2(9, 6), Vector2(4, 0)]
const ICE_SIZE: Vector2 = Vector2(9, 9)
const ICE_COLOR: Color = Color("#e8fbff")
const ICE_EDGE_COLOR: Color = Color("#a9dff5")
const ICE_SHINE: Rect2 = Rect2(2, 2, 3, 2)

const VENT_INSET: Vector2 = Vector2(10, 12)
const VENT_HEIGHT: float = 18.0
const VENT_COLOR: Color = Color("#1b3f63")
const VENT_SLOT_COLOR: Color = Color("#0d243a")
const VENT_SLOT_START: float = 4.0
const VENT_SLOT_END_MARGIN: float = 2.0
const VENT_SLOT_INSET: float = 3.0
const VENT_SLOT_SPACING: float = 6.0

const LIGHT_CRACK: Array[Vector2] = [
	Vector2(10, 30), Vector2(48, 90), Vector2(40, 140),
	Vector2(96, 220), Vector2(130, 300),
]
## Points relative to the glass top-right corner, except the last one.
const HEAVY_CRACK_TOP: Array[Vector2] = [
	Vector2(-8, 20), Vector2(-50, 110), Vector2(-36, 170),
]
const HEAVY_CRACK_END: Vector2 = Vector2(20, -20)

var hp_ratio: float = 1.0


func _ready() -> void:
	set_process(false)
	queue_redraw()


func set_hp(hp: float) -> void:
	hp_ratio = clampf(hp / float(GameConstants.INITIAL_BASE_HP), 0.0, 1.0)
	set_process(hp_ratio < DANGER_RATIO)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var body: Rect2 = BODY_RECT
	_draw_glow(body)
	_draw_shell(body)
	var inner_width: float = body.size.x - PANEL_MARGIN * 2.0
	var left: float = body.position.x + PANEL_MARGIN
	_draw_header(Rect2(left, body.position.y + PANEL_MARGIN, inner_width, HEADER_HEIGHT))
	var glass := Rect2(left, body.position.y + GLASS_TOP, inner_width, GLASS_HEIGHT)
	_draw_glass(glass)
	var vent_top: float = body.end.y - VENT_PANEL_BOTTOM
	_draw_base_vent(Rect2(left, vent_top, inner_width, VENT_PANEL_HEIGHT))
	_draw_damage(glass)


func _draw_shell(body: Rect2) -> void:
	draw_rect(body, SHELL_COLOR)
	draw_rect(body.grow(-SHELL_INSET), SHELL_INNER_COLOR)
	draw_rect(body.grow(-SHELL_INSET), SHELL_EDGE_COLOR, false, THICK_LINE)


func _draw_glow(body: Rect2) -> void:
	var glow: Color = GLOW_OK
	var strength: float = 1.0
	if hp_ratio < DANGER_RATIO:
		var seconds: float = Time.get_ticks_msec() / MSEC_PER_SECOND
		glow = GLOW_DANGER
		strength = PULSE_BASE + PULSE_AMPLITUDE * sin(seconds * PULSE_SPEED)
	for layer in GLOW_LAYERS:
		draw_rect(body.grow(layer[0]), Color(glow, layer[1] * strength))


func _draw_header(header: Rect2) -> void:
	draw_rect(header, PANEL_COLOR)
	draw_rect(header, PANEL_EDGE_COLOR, false, THICK_LINE)
	var font: Font = ThemeDB.fallback_font
	var text_pos := header.position + TITLE_OFFSET
	draw_string_outline(font, text_pos, TITLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT,
		TITLE_WIDTH, TITLE_FONT_SIZE, TITLE_OUTLINE_SIZE, TITLE_OUTLINE_COLOR)
	draw_string(font, text_pos, TITLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT,
		TITLE_WIDTH, TITLE_FONT_SIZE, TEXT_COLOR)
	_draw_stock_tag(font, Vector2(header.end.x, header.position.y) + TAG_OFFSET)


func _draw_stock_tag(font: Font, tag_position: Vector2) -> void:
	var tag := Rect2(tag_position, TAG_SIZE)
	draw_rect(tag, TAG_COLOR)
	draw_rect(tag, TAG_EDGE_COLOR, false, THIN_LINE)
	var baseline := Vector2(tag.position.x, tag.position.y + TAG_TEXT_BASELINE)
	draw_string(font, baseline, TAG_TEXT, HORIZONTAL_ALIGNMENT_CENTER,
		tag.size.x, TAG_FONT_SIZE, TEXT_COLOR)


func _draw_glass(glass: Rect2) -> void:
	var tint: Color = GLASS_TINT_OK.lerp(GLASS_TINT_DAMAGED, 1.0 - hp_ratio)
	draw_rect(glass, GLASS_COLOR)
	var cell_size := Vector2(
		(glass.size.x - CELL_GAP * (SHELF_COLS + 1)) / SHELF_COLS,
		(glass.size.y - CELL_GAP * (SHELF_ROWS + 1)) / SHELF_ROWS,
	)
	for row in SHELF_ROWS:
		for col in SHELF_COLS:
			var offset := Vector2(col, row) * (cell_size + Vector2.ONE * CELL_GAP)
			var cell := Rect2(glass.position + Vector2.ONE * CELL_GAP + offset, cell_size)
			draw_rect(cell, tint)
			draw_rect(cell, CELL_EDGE_COLOR, false, THIN_LINE)
			_fill_cell(cell, SHELF_LAYOUT[row][col])
	_draw_glass_shine(glass)


func _draw_glass_shine(glass: Rect2) -> void:
	for offset in SHINE_OFFSETS:
		var x0: float = glass.position.x + offset
		draw_colored_polygon(PackedVector2Array([
			Vector2(x0, glass.end.y),
			Vector2(x0 + SHINE_BOTTOM_WIDTH, glass.end.y),
			Vector2(x0 + SHINE_TOP_RIGHT, glass.position.y),
			Vector2(x0 + SHINE_TOP_LEFT, glass.position.y),
		]), SHINE_COLOR)


func _fill_cell(cell: Rect2, product: StringName) -> void:
	var gap_x: float = (cell.size.x - ITEM_COLS * ITEM_WIDTH) / (ITEM_COLS + 1)
	var step_y: float = (cell.size.y - ITEM_VERTICAL_PADDING) / ITEM_ROWS
	for row in ITEM_ROWS:
		for col in ITEM_COLS:
			var pos := Vector2(
				cell.position.x + gap_x + col * (ITEM_WIDTH + gap_x),
				cell.position.y + ITEM_TOP_PADDING + row * step_y,
			)
			_draw_product(product, pos)


func _draw_product(product: StringName, pos: Vector2) -> void:
	match product:
		&"milanesa":
			_draw_milanesa(pos)
		&"steak":
			_draw_steak(pos)
		&"ice":
			_draw_ice(pos)


func _draw_milanesa(pos: Vector2) -> void:
	for part in MILANESA_PARTS:
		draw_rect(Rect2(pos + part[0], part[1]), MILANESA_EDGE_COLOR)
	draw_rect(Rect2(pos, MILANESA_SIZE).grow(-MILANESA_INSET), MILANESA_COLOR)
	draw_rect(Rect2(pos + MILANESA_CRUMB.position, MILANESA_CRUMB.size), MILANESA_CRUMB_COLOR)
	draw_rect(Rect2(pos + MILANESA_LEMON.position, MILANESA_LEMON.size), MILANESA_LEMON_COLOR)


func _draw_steak(pos: Vector2) -> void:
	var tray := Rect2(pos + TRAY_RECT.position, TRAY_RECT.size)
	draw_rect(tray, TRAY_COLOR)
	draw_rect(tray, TRAY_EDGE_COLOR, false, THIN_LINE)
	var center := pos + STEAK_CENTER
	draw_colored_polygon(_ellipse(center, STEAK_OUTER_RADII, STEAK_SEGMENTS), STEAK_OUTER_COLOR)
	draw_colored_polygon(_ellipse(center, STEAK_INNER_RADII, STEAK_SEGMENTS), STEAK_INNER_COLOR)
	draw_line(center + STEAK_FAT_FROM, center + STEAK_FAT_TO, STEAK_FAT_COLOR, STEAK_FAT_WIDTH)
	draw_circle(center + STEAK_BONE_OFFSET, STEAK_BONE_RADIUS, STEAK_BONE_COLOR)


func _draw_ice(pos: Vector2) -> void:
	for offset in ICE_OFFSETS:
		var cube := Rect2(pos + offset, ICE_SIZE)
		draw_rect(cube, ICE_COLOR)
		draw_rect(cube, ICE_EDGE_COLOR, false, THIN_LINE)
		draw_rect(Rect2(cube.position + ICE_SHINE.position, ICE_SHINE.size), TEXT_COLOR)


func _draw_base_vent(panel: Rect2) -> void:
	draw_rect(panel, PANEL_COLOR)
	draw_rect(panel, PANEL_EDGE_COLOR, false, THICK_LINE)
	var vent_width: float = panel.size.x - VENT_INSET.x * 2.0
	var vent := Rect2(panel.position + VENT_INSET, Vector2(vent_width, VENT_HEIGHT))
	draw_rect(vent, VENT_COLOR)
	var x: float = vent.position.x + VENT_SLOT_START
	while x < vent.end.x - VENT_SLOT_END_MARGIN:
		var top := Vector2(x, vent.position.y + VENT_SLOT_INSET)
		var bottom := Vector2(x, vent.end.y - VENT_SLOT_INSET)
		draw_line(top, bottom, VENT_SLOT_COLOR, THICK_LINE)
		x += VENT_SLOT_SPACING


func _draw_damage(glass: Rect2) -> void:
	if hp_ratio < LIGHT_DAMAGE_RATIO:
		var light := PackedVector2Array()
		for point in LIGHT_CRACK:
			light.append(glass.position + point)
		draw_polyline(light, CRACK_COLOR, CRACK_WIDTH)
	if hp_ratio < HEAVY_DAMAGE_RATIO:
		var top_right := Vector2(glass.end.x, glass.position.y)
		var heavy := PackedVector2Array()
		for point in HEAVY_CRACK_TOP:
			heavy.append(top_right + point)
		heavy.append(Vector2(glass.position.x, glass.end.y) + HEAVY_CRACK_END)
		draw_polyline(heavy, CRACK_COLOR, CRACK_WIDTH)


func _ellipse(center: Vector2, radii: Vector2, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in segments:
		var angle: float = TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points
