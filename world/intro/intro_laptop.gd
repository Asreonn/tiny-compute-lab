class_name IntroLaptop
extends Node2D
## Opening sequence (docs/MOTION_SYSTEM.md §10, Penpot page `20 Intro · Laptop`): a top-down
## laptop whose keyboard has ONE keycap per board tile, laid exactly on the current grid. The
## camera eases toward the keyboard, the lid slides away, the keys dissolve left → right into
## their PCB tiles, the housing fades to the board edge, then the HUD slides in.
##
## Pure presentation: it reads the board size and the locked IO rows, never the simulation
## state, and it removes itself when done. Any key or click skips to the end state.

signal finished

const T := Palette.TILE
const RIM := 28.0            # deck housing around the keyboard (px, world space)
const PALM := 0.45           # front lip of the deck below the board, in tiles
const LID_RATIO := 0.62      # lid height relative to the keyboard height

# Timeline (seconds), MOTION_SYSTEM §10
const T_CAM := Vector2(0.3, 3.8)     # camera ease from the laptop to the gameplay framing
const T_LID := Vector2(0.6, 2.0)     # lid slides out of the top
const T_KEYS := Vector2(1.8, 3.1)   # start of the first / last key dissolve
const KEY_FADE := 0.3
const T_DECK := Vector2(3.1, 4.0)    # housing fades to the board edge
const T_HUD := 4.2                   # HUD entrance start
const HUD_SLIDE := 24.0
const HUD_DUR := 0.22
const HUD_STAGGER := 0.06
const T_END := 5.0
## US ANSI laptop layout, 15 u wide: [height in u, [[legend, width u], ...]]. "↑↓" is the
## inverted-T arrow pair (two half-height keys stacked in one 1 u slot).
const US_ROWS := [
	[0.6, [["esc", 1.0], ["F1", 1.0], ["F2", 1.0], ["F3", 1.0], ["F4", 1.0], ["F5", 1.0], ["F6", 1.0], ["F7", 1.0], ["F8", 1.0], ["F9", 1.0], ["F10", 1.0], ["F11", 1.0], ["F12", 1.0], ["home", 1.0], ["del", 1.0]]],
	[1.0, [["~", 1.0], ["1", 1.0], ["2", 1.0], ["3", 1.0], ["4", 1.0], ["5", 1.0], ["6", 1.0], ["7", 1.0], ["8", 1.0], ["9", 1.0], ["0", 1.0], ["-", 1.0], ["=", 1.0], ["delete", 2.0]]],
	[1.0, [["tab", 1.5], ["Q", 1.0], ["W", 1.0], ["E", 1.0], ["R", 1.0], ["T", 1.0], ["Y", 1.0], ["U", 1.0], ["I", 1.0], ["O", 1.0], ["P", 1.0], ["[", 1.0], ["]", 1.0], ["\\", 1.5]]],
	[1.0, [["caps", 1.75], ["A", 1.0], ["S", 1.0], ["D", 1.0], ["F", 1.0], ["G", 1.0], ["H", 1.0], ["J", 1.0], ["K", 1.0], ["L", 1.0], [";", 1.0], ["'", 1.0], ["return", 2.25]]],
	[1.0, [["shift", 2.25], ["Z", 1.0], ["X", 1.0], ["C", 1.0], ["V", 1.0], ["B", 1.0], ["N", 1.0], ["M", 1.0], [",", 1.0], [".", 1.0], ["/", 1.0], ["shift", 2.75]]],
	[1.0, [["fn", 1.0], ["ctrl", 1.0], ["opt", 1.0], ["cmd", 1.25], ["", 5.5], ["cmd", 1.25], ["opt", 1.0], ["←", 1.0], ["↑↓", 1.0], ["→", 1.0]]],
]
const KB_UNITS := 15.0

var _cols := 20
var _rows := 12
var _in_rows: Array[int] = []    # rows of the locked USB inputs (west side ports)
var _out_rows: Array[int] = []   # rows of the contract drive (east side port)
var _t := 0.0
var _camera: Camera2D
var _cam_from := {}
var _cam_to := {}
var _hud: Control
var _hud_items: Array = []       # [{node, home: Vector2, from: Vector2, delay}]
var _hud_started := false
var _done := false
var _font: Font
var _style_deck := StyleBoxFlat.new()
var _style_rim := StyleBoxFlat.new()
var _sb := StyleBoxFlat.new()  # reused by _draw_round_rect (draw_style_box emits geometry at call time)


## Configure from the current board. `camera` is the world camera (its current position/zoom
## is the gameplay framing = the end state); `hud` is the HUD root whose panels slide in.
func setup(sim: Simulation, camera: Camera2D, hud: Control) -> void:
	_cols = sim.size.x
	_rows = sim.size.y
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if not m.locked:
			continue
		if m.type == "usb_input":
			_in_rows.append(m.cell.y)
		elif m.type == "usb_output":
			_out_rows.append(m.cell.y)
	_camera = camera
	_cam_to = {"pos": camera.position, "zoom": camera.zoom.x}
	# The rig re-applies its board fit every frame; hand the camera to the intro until done.
	_camera.set_process(false)
	_camera.set_process_unhandled_input(false)
	var vs := get_viewport_rect().size
	var r := _laptop_rect()
	var z := minf(vs.x / r.size.x, vs.y / r.size.y) * 0.9
	_cam_from = {"pos": r.get_center(), "zoom": z}
	_hud = hud
	_font = TclTheme.font("ExtraBold")
	_style_deck.draw_center = false
	_style_deck.bg_color = Color(0, 0, 0, 0)
	_style_deck.border_color = Palette.MACHINE_BODY
	_style_deck.set_corner_radius_all(40)
	_style_deck.border_width_left = int(RIM)
	_style_deck.border_width_right = int(RIM)
	_style_deck.border_width_top = int(RIM)
	_style_deck.border_width_bottom = int(RIM + PALM * T)
	_style_deck.anti_aliasing = true
	_style_rim.draw_center = false
	_style_rim.bg_color = Color(0, 0, 0, 0)
	_style_rim.border_color = Palette.MACHINE_FRAME
	_style_rim.set_border_width_all(2)
	_style_rim.set_corner_radius_all(40)
	_style_rim.anti_aliasing = true
	z_index = 100
	_prepare_hud()
	_apply_camera(0.0)


func _board_size() -> Vector2:
	return Vector2(_cols * T, _rows * T)


func _lid_height() -> float:
	return _rows * T * LID_RATIO


## Whole laptop (lid + deck) in world space; the board sits at (0, 0).
func _laptop_rect() -> Rect2:
	var b := _board_size()
	var top := -RIM - _lid_height()
	return Rect2(Vector2(-RIM, top), Vector2(b.x + RIM * 2.0, b.y + RIM * 2.0 + PALM * T - top - RIM))


# ------------------------------------------------------------------ timeline

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_apply_camera(_t)
	if _t >= T_HUD and not _hud_started:
		_start_hud()
	if _t >= T_END:
		_finish()
		return
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	var skip: bool = (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if skip:
		get_viewport().set_input_as_handled()
		_finish()


func _apply_camera(t: float) -> void:
	if _camera == null:
		return
	var k := _ease_in_out(_phase(t, T_CAM))
	var z: float = lerpf(float(_cam_from["zoom"]), float(_cam_to["zoom"]), k)
	_camera.zoom = Vector2.ONE * z
	_camera.position = (_cam_from["pos"] as Vector2).lerp(_cam_to["pos"], k)


static func _phase(t: float, span: Vector2) -> float:
	return clampf((t - span.x) / maxf(span.y - span.x, 0.0001), 0.0, 1.0)


static func _ease_in_out(x: float) -> float:
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _finish() -> void:
	if _done:
		return
	_done = true
	_apply_camera(T_END)
	if is_instance_valid(_camera):
		_camera.set_process(true)
		_camera.set_process_unhandled_input(true)
	if not _hud_started:
		_start_hud(true)
	for it in _hud_items:
		var n: Control = it["node"]
		if is_instance_valid(n):
			n.position = it["home"]
			n.modulate.a = 1.0
	finished.emit()
	queue_free()


# ------------------------------------------------------------------ HUD entrance

## Hide every visible top-level HUD panel and remember where it lives; the entrance slides
## each one in from its docking side (top / left / bottom / right), 60 ms apart.
func _prepare_hud() -> void:
	if _hud == null:
		return
	var vs := get_viewport_rect().size
	var items := []
	for c in _hud.get_children():
		var n := c as Control
		if n == null or not n.visible:
			continue
		var rect := n.get_global_rect()
		var ctr := rect.get_center()
		var dir := Vector2.ZERO
		var order := 0
		if rect.position.y <= 8.0 and rect.size.x > vs.x * 0.5:
			dir = Vector2(0, -1)
		elif ctr.x < vs.x * 0.3:
			dir = Vector2(-1, 0)
			order = 1
		elif ctr.y > vs.y * 0.7:
			dir = Vector2(0, 1)
			order = 2
		else:
			dir = Vector2(1, 0)
			order = 3
		items.append({"node": n, "home": n.position, "from": n.position + dir * HUD_SLIDE, "order": order, "y": rect.position.y})
		n.modulate.a = 0.0
		n.position = n.position + dir * HUD_SLIDE
	items.sort_custom(func(a, b): return a["order"] < b["order"] or (a["order"] == b["order"] and a["y"] < b["y"]))
	for i in items.size():
		items[i]["delay"] = i * HUD_STAGGER
	_hud_items = items


func _start_hud(instant := false) -> void:
	_hud_started = true
	for it in _hud_items:
		var n: Control = it["node"]
		if not is_instance_valid(n):
			continue
		if instant:
			n.position = it["home"]
			n.modulate.a = 1.0
			continue
		var tw := n.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "position", it["home"], HUD_DUR).set_delay(it["delay"])
		tw.tween_property(n, "modulate:a", 1.0, HUD_DUR).set_delay(it["delay"])


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var b := _board_size()
	var deck_a := 1.0 - _phase(_t, T_DECK)
	# Deck housing: a frame around the keyboard (border-only style box, so the board shows
	# through the middle once the keys are gone) + palm rest with the trackpad.
	if deck_a > 0.001:
		var deck := Rect2(Vector2(-RIM, -RIM), Vector2(b.x + RIM * 2.0, b.y + RIM * 2.0 + PALM * T))
		_style_deck.border_color = Color(Palette.MACHINE_BODY, deck_a)
		_style_rim.border_color = Color(Palette.MACHINE_FRAME, deck_a)
		draw_style_box(_style_deck, deck)
		draw_style_box(_style_rim, deck)
		for row in _in_rows:
			_draw_side_port(Vector2(-RIM, row * T + 14.0), deck_a)
		for row in _out_rows:
			_draw_side_port(Vector2(b.x + RIM - 16.0, row * T + 14.0), deck_a)
	# Keyboard (realistic US layout scaled to the board width) + palm rest with the trackpad,
	# all INSIDE the board rect. The covering dissolves in vertical strips and the keys by their
	# centre x, left → right, so the factory emerges from under the keyboard.
	_draw_keyboard(b)
	# Lid: slides up out of the frame and fades (tilted-back screen seen from above).
	var lk := _ease_in_out(_phase(_t, T_LID))
	var lid_a := 1.0 - lk
	if lid_a > 0.001:
		var lh := _lid_height()
		var lid := Rect2(Vector2(-RIM * 0.6, -RIM - lh - lk * lh * 0.6), Vector2(b.x + RIM * 1.2, lh - 8.0))
		_draw_round_rect(lid, 36.0, Color(Palette.MACHINE_BODY, lid_a), Color(Palette.MACHINE_FRAME, lid_a), 2.0)
		var scr := lid.grow(-32.0)
		scr.size.y -= 24.0
		_draw_round_rect(scr, 12.0, Color(Palette.MACHINE_SCREEN, lid_a), Color(Palette.MATERIAL_FRAME, lid_a), 1.0)
		var fs := int(clampf(scr.size.y * 0.16, 18.0, 64.0))
		var text := "TINY COMPUTE LAB"
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := scr.get_center() + Vector2(-tw / 2.0, fs * 0.3)
		draw_string(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Palette.DATA_NUMBER, lid_a))
		# boot bar fills during the approach
		var bw := tw * 0.5
		var bar := Rect2(scr.get_center() + Vector2(-bw / 2.0, fs * 0.9), Vector2(bw, 4.0))
		draw_rect(bar, Color(Palette.MACHINE_RAIL, lid_a))
		draw_rect(Rect2(bar.position, Vector2(bw * clampf(_t / 1.6, 0.0, 1.0), 4.0)), Color(Palette.DATA_NUMBER, 0.7 * lid_a))
		var hinge := Rect2(Vector2(b.x / 2.0 - 60.0, lid.end.y - 20.0), Vector2(120.0, 6.0))
		draw_rect(hinge, Color(Palette.MACHINE_RAIL, lid_a))


## Sweep alpha at board x: 1 before the sweep reaches it, 0 once its KEY_FADE is over.
func _sweep_alpha(x: float, width: float) -> float:
	var start := T_KEYS.x + (T_KEYS.y - T_KEYS.x) * clampf(x / maxf(width, 1.0), 0.0, 1.0)
	return 1.0 - _ease_out(clampf((_t - start) / KEY_FADE, 0.0, 1.0))


func _draw_keyboard(b: Vector2) -> void:
	var u := b.x / (KB_UNITS + 0.7)           # key unit incl. a 0.35 u side margin each side
	var pad := u * 0.35
	var gap := u * 0.07
	var kb_h := pad * 2.0
	for row in US_ROWS:
		kb_h += float(row[0]) * u
	kb_h = minf(kb_h, b.y * 0.8)
	# covering: keyboard well (dark) over the top, palm rest (deck body) below, per tile strip
	var strips := int(ceilf(b.x / T))
	for c in strips:
		var x := c * T
		var w := minf(T, b.x - x)
		var a := _sweep_alpha(x + w * 0.5, b.x)
		if a <= 0.001:
			continue
		draw_rect(Rect2(x, 0.0, w, kb_h), Color(Palette.MATERIAL_VENT, a))
		draw_rect(Rect2(x, kb_h, w, b.y - kb_h), Color(Palette.MACHINE_BODY, a))
	# trackpad in the palm rest
	var palm := b.y - kb_h
	if palm > u:
		var tp := Rect2(Vector2(b.x / 2.0 - 2.9 * u, kb_h + palm * 0.14), Vector2(5.8 * u, palm * 0.7))
		var ta := _sweep_alpha(tp.get_center().x, b.x)
		if ta > 0.001:
			_draw_round_rect(tp, u * 0.16, Color(Palette.MACHINE_BODY_HI, ta), Color(Palette.MACHINE_FRAME, ta), 1.5)
	# keys
	var y := pad
	for row in US_ROWS:
		var rh: float = float(row[0]) * u
		var x := pad
		for k in row[1]:
			var kw: float = float(k[1]) * u
			var rect := Rect2(Vector2(x, y), Vector2(kw, rh))
			x += kw
			var a := _sweep_alpha(rect.get_center().x, b.x)
			if a <= 0.001:
				continue
			if str(k[0]) == "↑↓":
				var half := Vector2(kw, rh * 0.5)
				_draw_cap(Rect2(rect.position, half), "↑", u, gap, a, true)
				_draw_cap(Rect2(rect.position + Vector2(0.0, rh * 0.5), half), "↓", u, gap, a, true)
			else:
				_draw_cap(rect, str(k[0]), u, gap, a, float(row[0]) < 1.0)
		y += rh


func _draw_cap(slot: Rect2, legend: String, u: float, gap: float, a: float, small: bool) -> void:
	var cap := slot.grow(-gap * 0.5)
	_draw_round_rect(cap, u * 0.09, Color(Palette.MATERIAL_PLATE_HI, a), Color(Palette.MACHINE_FRAME, a), 1.2)
	draw_rect(Rect2(cap.position + Vector2(u * 0.08, u * 0.05), Vector2(cap.size.x - u * 0.16, 1.5)), Color(Palette.MATERIAL_SILK, 0.12 * a))
	if legend == "":
		return
	var fs := int(clampf(u * (0.13 if small or legend.length() > 1 else 0.2), 7.0, 40.0))
	var pos := cap.position + Vector2(u * 0.12, u * 0.1 + fs * 0.9)
	if small and cap.size.y < u * 0.7:
		pos.y = cap.position.y + cap.size.y * 0.5 + fs * 0.35
	draw_string(_font, pos, legend, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Palette.MATERIAL_SILK, 0.4 * a))


## A USB-A port opening on the deck side (port-face geometry, systems_v1.js portFace).
func _draw_side_port(p: Vector2, a: float) -> void:
	var frame := Rect2(p, Vector2(16.0, 36.0))
	_draw_round_rect(frame, 2.0, Color(Palette.MACHINE_FRAME_HOVER, a), Color(Palette.MATERIAL_SILK, 0.45 * a), 1.0)
	draw_rect(Rect2(p + Vector2(2.5, 2.5), Vector2(11.0, 31.0)), Color(Palette.MATERIAL_VENT, a))


func _draw_round_rect(r: Rect2, radius: float, fill: Color, stroke: Color, sw: float) -> void:
	_sb.bg_color = fill
	_sb.border_color = stroke
	_sb.set_border_width_all(int(ceilf(sw)))
	_sb.set_corner_radius_all(int(radius))
	_sb.anti_aliasing = true
	draw_style_box(_sb, r)
