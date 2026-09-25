extends Control
## View dock (bottom centre): the board VIEWS as a main mechanic. Normal · Data · Flow · Heat ·
## Power (SimulationManager.VIEWS, keys N B F T P). Each view redraws the board around one question
## (what kind of data flows where · who is busy or blocked · what is hot · what draws power); the
## legend sits right above the dock. While a view is on, a thin frame in its colour rims the
## screen so the mode is never mistaken for the normal board.

const SEG := Vector2(76, 44)
const GAP := 4.0
const PAD := 6.0
const MARGIN := 16.0

var _dock: Control
var _hover := -1
var _frame_a := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock = Control.new()
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_dock.size = dock_size()
	_dock.draw.connect(_draw_dock)
	_dock.gui_input.connect(_on_input)
	_dock.mouse_exited.connect(func():
		_hover = -1
		_dock.queue_redraw())
	add_child(_dock)
	var sm := _sm()
	sm.overlay_changed.connect(func(_k): _dock.queue_redraw())
	sm.mission_loaded.connect(func(_d): _dock.queue_redraw())


func _sm() -> Node:
	return get_node("/root/SimulationManager")


static func dock_size() -> Vector2:
	var n: int = 5
	return Vector2(PAD * 2.0 + n * SEG.x + (n - 1) * GAP, SEG.y + PAD * 2.0)


## The accent of a view (the frame, the active segment's underline, the legend).
static func view_color(kind: String) -> Color:
	match kind:
		"data": return Palette.DATA_NUMBER
		"flow": return Palette.STATE_VALID
		"thermal": return Palette.STATE_BLOCKED
		"power": return Palette.MATERIAL_GOLD
	return Palette.TEXT_SECONDARY


func _process(delta: float) -> void:
	var vs := get_viewport_rect().size
	var ds := dock_size()
	_dock.position = Vector2(roundf((vs.x - ds.x) * 0.5), vs.y - MARGIN - ds.y)
	var want := 1.0 if str(_sm().overlay) != "" else 0.0
	var na := move_toward(_frame_a, want, delta / 0.15)
	if na != _frame_a:
		_frame_a = na
		queue_redraw()


func _seg_rect(i: int) -> Rect2:
	return Rect2(Vector2(PAD + i * (SEG.x + GAP), PAD), SEG)


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := -1
		for i in 5:
			if _seg_rect(i).has_point(event.position):
				h = i
		if h != _hover:
			_hover = h
			_dock.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in 5:
			if _seg_rect(i).has_point(event.position):
				_sm().set_overlay(str(_sm().VIEWS[i][0]))
				AudioBus.event("wire_connect")
		_dock.accept_event()


func _draw() -> void:
	if _frame_a <= 0.0:
		return
	var c := view_color(str(_sm().overlay))
	var r := Rect2(Vector2.ZERO, get_viewport_rect().size)
	draw_rect(r.grow(-1.0), Color(c, 0.45 * _frame_a), false, 2.0)


func _draw_dock() -> void:
	var ci := _dock
	var r := Rect2(Vector2.ZERO, dock_size())
	SystemsDraw.rrect(ci, r, 10.0, Palette.SURFACE_PANEL)
	SystemsDraw.rrect_outline(ci, r, 10.0, Palette.SURFACE_BORDER, 1.0)
	var sm := _sm()
	var cur := str(sm.overlay)
	var f := TclTheme.font(HudKit.W_XBOLD)
	var fm := TclTheme.font(HudKit.W_MEDIUM)
	for i in 5:
		var v: Array = sm.VIEWS[i]
		var kind := str(v[0])
		var on := kind == cur
		var s := _seg_rect(i)
		var col := view_color(kind)
		if on:
			SystemsDraw.rrect(ci, s, 7.0, Palette.SURFACE_RAISED)
			SystemsDraw.rrect_outline(ci, s, 7.0, Color(col, 0.8), 1.0)
			SystemsDraw.rrect(ci, Rect2(s.position + Vector2(12, s.size.y - 4), Vector2(s.size.x - 24, 2)), 1.0, col)
		elif i == _hover:
			SystemsDraw.rrect(ci, s, 7.0, Color(Palette.SURFACE_RAISED, 0.6))
		var ic := col if on else (Palette.TEXT_PRIMARY if i == _hover else Palette.TEXT_SECONDARY)
		_icon(ci, kind, s.position + Vector2(10, 13), ic)
		ci.draw_string(f, s.position + Vector2(34, 20), str(v[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT_PRIMARY if on else Palette.TEXT_SECONDARY)
		ci.draw_string(fm, s.position + Vector2(34, 34), str(v[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.TEXT_MUTED)


## 18 px view glyphs: the kit icons, and copper fins for heat (the kit has no thermal icon).
func _icon(ci: CanvasItem, kind: String, pos: Vector2, c: Color) -> void:
	var name := ""
	match kind:
		"": name = "tool_select"
		"data": name = "icon_packet"
		"flow": name = "icon_throughput"
		"power": name = "icon_power"
	if kind == "thermal":
		for k in 4:
			SystemsDraw.rrect(ci, Rect2(pos + Vector2(1 + k * 4.5, 2), Vector2(2.5, 14)), 1.0, c)
		ci.draw_rect(Rect2(pos + Vector2(0, 15), Vector2(18, 2)), c)
		return
	var tex := Art.icon(name)
	if tex != null:
		ci.draw_texture_rect(tex, Rect2(pos, Vector2(18, 18)), false, c)
