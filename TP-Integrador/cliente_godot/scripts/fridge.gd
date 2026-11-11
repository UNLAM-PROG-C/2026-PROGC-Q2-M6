extends Node2D
class_name FridgeView

## Heladera exhibidora ("Frigorífico") que actúa como base del equipo.
## Se dibuja de forma procedural y reacciona al HP de la base.

const BODY_RECT: Rect2 = Rect2(1110, 176, 162, 420)
const GLASS_TINT_OK: Color = Color("#cfefff")
const GLASS_TINT_DAMAGED: Color = Color("#d36d55")
const GLOW_OK: Color = Color("#7ff3ff")
const GLOW_DANGER: Color = Color("#ff4d4d")
const CRACK_COLOR: Color = Color("#5a2a2a")

var hp_ratio: float = 1.0


func _ready() -> void:
	set_process(false)
	queue_redraw()


func set_hp(hp: float) -> void:
	hp_ratio = clampf(hp / 100.0, 0.0, 1.0)
	set_process(hp_ratio < 0.25)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r: Rect2 = BODY_RECT
	_draw_glow(r)
	# Carcasa
	draw_rect(r, Color("#1d4f7a"))
	draw_rect(r.grow(-3), Color("#3c8fd0"))
	draw_rect(r.grow(-3), Color("#8fd3ff"), false, 2.0)
	_draw_header(Rect2(r.position.x + 8, r.position.y + 8, r.size.x - 16, 30))
	var glass := Rect2(r.position.x + 8, r.position.y + 46, r.size.x - 16, 316)
	_draw_glass(glass)
	_draw_base_vent(Rect2(r.position.x + 8, r.end.y - 50, r.size.x - 16, 42))
	_draw_damage(glass)


func _draw_glow(r: Rect2) -> void:
	var glow: Color = GLOW_OK
	var strength: float = 1.0
	if hp_ratio < 0.25:
		var t: float = Time.get_ticks_msec() / 1000.0
		glow = GLOW_DANGER
		strength = 0.6 + 0.4 * sin(t * 8.0)
	var layers := [[16.0, 0.05], [11.0, 0.08], [6.0, 0.12], [2.0, 0.18]]
	for layer in layers:
		draw_rect(r.grow(layer[0]), Color(glow, layer[1] * strength))


func _draw_header(h: Rect2) -> void:
	draw_rect(h, Color("#2a6fb5"))
	draw_rect(h, Color("#174a7c"), false, 2.0)
	var font: Font = ThemeDB.fallback_font
	var text_pos := Vector2(h.position.x + 4, h.position.y + 21)
	draw_string_outline(font, text_pos, "FRIGORÍFICO", HORIZONTAL_ALIGNMENT_LEFT, 104, 14, 4, Color("#0e2f52"))
	draw_string(font, text_pos, "FRIGORÍFICO", HORIZONTAL_ALIGNMENT_LEFT, 104, 14, Color("#ffffff"))
	var tag := Rect2(h.end.x - 38, h.position.y + 7, 34, 16)
	draw_rect(tag, Color("#3cc46a"))
	draw_rect(tag, Color("#1f7a3d"), false, 1.0)
	draw_string(font, Vector2(tag.position.x, tag.position.y + 12), "STOCK", HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 9, Color("#ffffff"))


func _draw_glass(g: Rect2) -> void:
	var tint: Color = GLASS_TINT_OK.lerp(GLASS_TINT_DAMAGED, 1.0 - hp_ratio)
	draw_rect(g, Color("#5fb4e6"))
	var row_h: float = (g.size.y - 12.0) / 2.0
	var col_w: float = (g.size.x - 16.0) / 3.0
	# Distribución: fila superior milanesas / cortes / cortes, inferior cortes / cortes / hielo
	var layout := [[&"milanesa", &"steak", &"steak"], [&"steak", &"steak", &"ice"]]
	for row in 2:
		for col in 3:
			var cell := Rect2(
				g.position.x + 4.0 + col * (col_w + 4.0),
				g.position.y + 4.0 + row * (row_h + 4.0),
				col_w,
				row_h,
			)
			draw_rect(cell, tint)
			draw_rect(cell, Color("#9ad6f5"), false, 1.0)
			_fill_cell(cell, layout[row][col])
	# Reflejos del vidrio
	var shine := Color(1, 1, 1, 0.22)
	for offset in [10.0, 70.0]:
		var x0: float = g.position.x + offset
		draw_colored_polygon(PackedVector2Array([
			Vector2(x0, g.end.y),
			Vector2(x0 + 14.0, g.end.y),
			Vector2(x0 + 64.0, g.position.y),
			Vector2(x0 + 50.0, g.position.y),
		]), shine)


func _fill_cell(cell: Rect2, product: StringName) -> void:
	var item_w: float = 18.0
	var cols: int = 2
	var gap_x: float = (cell.size.x - cols * item_w) / (cols + 1)
	var rows: int = 5
	var step_y: float = (cell.size.y - 8.0) / rows
	for row in rows:
		for col in cols:
			var pos := Vector2(
				cell.position.x + gap_x + col * (item_w + gap_x),
				cell.position.y + 6.0 + row * step_y,
			)
			match product:
				&"milanesa":
					_draw_milanesa(pos)
				&"steak":
					_draw_steak(pos)
				&"ice":
					_draw_ice(pos)


func _draw_milanesa(pos: Vector2) -> void:
	var r := Rect2(pos, Vector2(18, 16))
	draw_rect(Rect2(pos + Vector2(1, 0), Vector2(16, 16)), Color("#b8742c"))
	draw_rect(Rect2(pos + Vector2(0, 1), Vector2(18, 14)), Color("#b8742c"))
	draw_rect(r.grow(-2), Color("#e9a94f"))
	draw_rect(Rect2(pos + Vector2(3, 3), Vector2(4, 3)), Color("#f6cd85"))
	draw_rect(Rect2(pos + Vector2(2, 11), Vector2(14, 3)), Color("#fff1c4"))


func _draw_steak(pos: Vector2) -> void:
	draw_rect(Rect2(pos + Vector2(0, 4), Vector2(18, 12)), Color("#f4f7f9"))
	draw_rect(Rect2(pos + Vector2(0, 4), Vector2(18, 12)), Color("#b9c6cf"), false, 1.0)
	var center := pos + Vector2(9, 9)
	draw_colored_polygon(_ellipse(center, Vector2(8, 5.5), 12), Color("#a8323a"))
	draw_colored_polygon(_ellipse(center, Vector2(7, 4.5), 12), Color("#d9545a"))
	draw_line(center + Vector2(-4, -1), center + Vector2(3, 2), Color("#f3b0b0"), 1.5)
	draw_circle(center + Vector2(4, -2), 1.3, Color("#f8e6d8"))


func _draw_ice(pos: Vector2) -> void:
	for offset in [Vector2(0, 6), Vector2(9, 6), Vector2(4, 0)]:
		var cube := Rect2(pos + offset, Vector2(9, 9))
		draw_rect(cube, Color("#e8fbff"))
		draw_rect(cube, Color("#a9dff5"), false, 1.0)
		draw_rect(Rect2(cube.position + Vector2(2, 2), Vector2(3, 2)), Color("#ffffff"))


func _draw_base_vent(b: Rect2) -> void:
	draw_rect(b, Color("#2a6fb5"))
	draw_rect(b, Color("#174a7c"), false, 2.0)
	var vent := Rect2(b.position.x + 10, b.position.y + 12, b.size.x - 20, 18)
	draw_rect(vent, Color("#1b3f63"))
	var x: float = vent.position.x + 4.0
	while x < vent.end.x - 2.0:
		draw_line(Vector2(x, vent.position.y + 3), Vector2(x, vent.end.y - 3), Color("#0d243a"), 2.0)
		x += 6.0


func _draw_damage(g: Rect2) -> void:
	if hp_ratio < 0.75:
		draw_polyline(PackedVector2Array([
			g.position + Vector2(10, 30),
			g.position + Vector2(48, 90),
			g.position + Vector2(40, 140),
			g.position + Vector2(96, 220),
			g.position + Vector2(130, 300),
		]), CRACK_COLOR, 3.0)
	if hp_ratio < 0.45:
		draw_polyline(PackedVector2Array([
			Vector2(g.end.x - 8, g.position.y + 20),
			Vector2(g.end.x - 50, g.position.y + 110),
			Vector2(g.end.x - 36, g.position.y + 170),
			Vector2(g.position.x + 20, g.end.y - 20),
		]), CRACK_COLOR, 3.0)


func _ellipse(center: Vector2, radii: Vector2, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return points
