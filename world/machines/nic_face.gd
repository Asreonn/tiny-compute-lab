class_name NicFace
extends Node2D
## The NIC fixture's face (JOB C8a): lamp captions, the load bar, silk, sealed port caps and
## the footprint outline. The NIC (size "x") has no pad / state-overlay art, so this painter
## draws those marks over the shell. Read-only: MachineView pushes sync() every frame and
## _draw() renders only when the compact key changed.

const PORT_IDS := ["rx_a", "rx_b", "rx_c", "tx_a", "tx_b"]
const PORT_CAPS := ["RX A", "RX B", "RX C", "TX A", "TX B"]

var machine: Machine
var _hovered := false
var _selected := false
var _key := ""


## Push the current view inputs; redraws only when what is drawn changed.
func sync(m: Machine, _sim: Simulation, hovered: bool, selected: bool) -> void:
	machine = m
	_hovered = hovered
	_selected = selected
	var tier := NicLogic.tier(m)
	var open := NicLogic.open_ports(tier)
	var key := "%s|%d|%d|%d|%d|%s|%d|%d" % [
		MachineView.nic_area_state(m), NicLogic.load_per_sec(m), NicLogic.capacity(m),
		int(hovered), int(selected), ",".join(open), m.state, tier,
	]
	if key != _key:
		_key = key
		queue_redraw()


func _draw() -> void:
	var m := machine
	if m == null:
		return
	var tier := NicLogic.tier(m)
	_draw_footprint(m)
	_draw_caps(NicLogic.open_ports(tier))
	_draw_load(m)
	_draw_lamps(m)
	_draw_silk(tier)


## Hover / selected / blocked / error outline in place of the missing pad + state art.
func _draw_footprint(m: Machine) -> void:
	var rect := Rect2(-2, -2, 324, 68)
	if _selected:
		SystemsDraw.rrect_outline(self, rect, 8.0, Palette.STATE_SELECT, 2.0)
	elif _hovered:
		SystemsDraw.rrect_outline(self, rect, 8.0, Palette.STATE_HOVER, 2.0)
	elif m.state == Machine.State.BLOCKED:
		SystemsDraw.rrect_outline(self, rect, 8.0, Palette.STATE_BLOCKED, 1.5)
	elif m.state == Machine.State.ERROR:
		SystemsDraw.rrect_outline(self, rect, 8.0, Palette.STATE_ERROR, 1.5)


## Sealed ports: a plate cap over the port (MachineView hides the port sprite + ring too).
func _draw_caps(open: PackedStringArray) -> void:
	for i in PORT_IDS.size():
		if PORT_IDS[i] in open:
			continue
		var cap := Rect2(i * 64.0 + 24, 58, 16, 10)
		SystemsDraw.rrect(self, cap, 3.0, Palette.MATERIAL_PLATE)
		SystemsDraw.rrect_outline(self, cap, 3.0, Palette.MATERIAL_FRAME, 1.0)


## Load well: the last second's frames against the tier's budget (one DATA_NUMBER segment —
## NicLogic keeps RX and TX in one frames window). 1 px blocked outline at ≥ 75 % load.
func _draw_load(m: Machine) -> void:
	var cap := NicLogic.capacity(m)
	var frames := NicLogic.load_per_sec(m)
	var well := Rect2(116, 31, 86, 8)
	var fill_w := well.size.x * minf(1.0, float(frames) / float(maxf(cap, 1)))
	if fill_w > 0.0:
		draw_rect(Rect2(well.position, Vector2(fill_w, well.size.y)), Color(Palette.DATA_NUMBER, 0.8))
	if float(frames) >= float(cap) * 0.75:
		SystemsDraw.rrect_outline(self, well, 2.0, Palette.STATE_BLOCKED, 1.0)


## Lamp captions: the lit lamp reads TEXT_INVERSE, the other TEXT_MUTED (the lamp shapes are
## in the area art).
func _draw_lamps(m: Machine) -> void:
	var lamp := MachineView.nic_area_state(m)
	_draw_lamp(Rect2(116, 15, 40, 10), "TEST", lamp == "test")
	_draw_lamp(Rect2(162, 15, 40, 10), "LIVE", lamp == "live")


func _draw_lamp(rect: Rect2, text: String, lit: bool) -> void:
	var f := ThemeDB.fallback_font
	var col: Color = Palette.TEXT_INVERSE if lit else Palette.TEXT_MUTED
	var asc := f.get_ascent(6.0)
	var desc := f.get_descent(6.0)
	var base := Vector2(rect.position.x, rect.position.y + (rect.size.y - (asc + desc)) * 0.5 + asc)
	draw_string(f, base, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 6.0, col)


## Silk: the tier plate, the MAIN / AUX labels and the port captions.
func _draw_silk(tier: int) -> void:
	_draw_text(Vector2(214, 10), "NIC MK%d" % tier, 7.0, Color(Palette.MATERIAL_SILK, 0.6))
	_draw_text(Vector2(24, 13), "MAIN", 6.0, Color(Palette.MATERIAL_SILK, 0.5))
	_draw_text(Vector2(262, 13), "AUX", 6.0, Color(Palette.MATERIAL_SILK, 0.5))
	for i in PORT_CAPS.size():
		_draw_text_center(Rect2(i * 64.0 + 18, 44, 28, 10), PORT_CAPS[i], 6.5, Color(Palette.MATERIAL_SILK, 0.55))


func _draw_text(pos: Vector2, text: String, size: float, col: Color) -> void:
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(pos.x, pos.y + f.get_ascent(size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_text_center(box: Rect2, text: String, size: float, col: Color) -> void:
	var f := ThemeDB.fallback_font
	var asc := f.get_ascent(size)
	var desc := f.get_descent(size)
	var base := Vector2(box.position.x, box.position.y + (box.size.y - (asc + desc)) * 0.5 + asc)
	draw_string(f, base, text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, size, col)