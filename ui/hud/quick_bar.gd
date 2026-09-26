extends Control
## Quick action bar (SYSTEMS_EXPANSION §9, systems_v1.js INTERACTION): a 176x36 panel 8 px below
## the selection brackets of the selected player machine: Move · Duplicate · Rotate · Copy
## settings | Delete. Buttons 32x28; hover = surface.raised + border-strong; Delete hover turns
## red instantly. The hovered button's label and shortcut show below. Fades in over 150 ms with
## the selection; hidden while dragging, carrying or placing.

const SIZE := Vector2(208, 36)
const FADE := 0.15
const BRACKET := 12.0  # world px the selection brackets reach past the footprint
## [action, label, shortcut]
const ACTIONS := [["move", "Move", "drag"], ["duplicate", "Duplicate", "Ctrl+D"], ["rotate", "Rotate", "R"],
	["upgrade", "Upgrade", "U"], ["copy", "Copy settings", "Ctrl+Shift+C"], ["delete", "Delete", "X / Del"]]
## A box-selected group: move, duplicate or delete it together.
const GROUP_ACTIONS := [["move", "Move group", "drag"], ["duplicate", "Duplicate group", "Ctrl+D"], ["delete", "Delete group", "X / Del"]]

var tools: Node
var upgrade_card: Control
var _mid := -1
var _a := 0.0
var _hover := -1


func _ready() -> void:
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _group() -> bool:
	return tools != null and tools.selected_group.size() >= 2


func _actions() -> Array:
	return GROUP_ACTIONS if _group() else ACTIONS


func _bar_w() -> float:
	return 112.0 if _group() else SIZE.x


func _button_rect(i: int) -> Rect2:
	var last := _actions().size() - 1
	var x := 4.0 + i * 32.0 + (4.0 if i == last else 0.0)
	return Rect2(x, 4, 32, 28)


func _machine() -> Machine:
	var sim: Simulation = get_node("/root/SimulationManager").sim
	if tools == null or sim == null or tools.selected_machine < 0 or not sim.machines.has(tools.selected_machine):
		return null
	var m: Machine = sim.machines[tools.selected_machine]
	return null if m.locked else m


func _process(delta: float) -> void:
	var m := _machine()
	var group := _group()
	var busy: bool = tools == null or tools._dragging() or tools.tool != "select"
	var want := (m != null or group) and not busy
	var key := -2 if group else (m.id if m != null else -1)
	if want and key != _mid:
		_mid = key
		_a = 0.0
	_a = move_toward(_a, 1.0 if want else 0.0, delta / FADE)
	visible = _a > 0.0 and (m != null or group)
	modulate.a = _a
	if not visible:
		_hover = -1
		return
	size = Vector2(_bar_w(), SIZE.y)
	# under the footprint (or the group's bounds), in screen space
	var ct := get_viewport().get_canvas_transform()
	var fp: Rect2 = tools.group_rect() if group else Rect2(Vector2(m.cell) * Palette.TILE, Vector2(Catalog.size_of(m.type, m.rot)) * Palette.TILE)
	var bottom_mid: Vector2 = ct * Vector2(fp.get_center().x, fp.end.y + BRACKET)
	var vp := get_viewport_rect().size
	position = Vector2(clampf(bottom_mid.x - size.x * 0.5, 8.0, vp.x - size.x - 8.0), clampf(bottom_mid.y + 8.0, 60.0, vp.y - SIZE.y - 30.0))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := -1
		for i in _actions().size():
			if _button_rect(i).has_point((event as InputEventMouseMotion).position):
				h = i
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if _hover < 0:
			return
		if _group():
			match str(GROUP_ACTIONS[_hover][0]):
				"move": tools.move_group_carry()
				"duplicate": tools.duplicate_selection()
				"delete": tools.delete_group()
			return
		var m := _machine()
		if m == null:
			return
		match str(ACTIONS[_hover][0]):
			"move": tools.begin_move(m.id)
			"duplicate": tools.duplicate_selection()
			"rotate": tools.rotate_machine(m.id)
			"upgrade":
				if upgrade_card != null and upgrade_card.has_method("open"):
					upgrade_card.open(m.id)
			"copy": tools.copy_settings(m.id)
			"delete": tools.delete_machine(m.id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover >= 0:
		_hover = -1
		queue_redraw()


func _draw() -> void:
	var acts := _actions()
	var r := Rect2(Vector2.ZERO, Vector2(_bar_w(), SIZE.y))
	for i in 3:
		var sh := r.grow(2.0 + i * 2.0)
		sh.position.y += 3.0
		SystemsDraw.rrect(self, sh, 10.0 + i * 2.0, Color(0, 0, 0, 0.10))
	SystemsDraw.rrect(self, r, 8.0, Palette.SURFACE_PANEL)
	SystemsDraw.rrect_outline(self, r, 8.0, Palette.SURFACE_BORDER_STRONG, 1.0)
	var last := acts.size() - 1
	draw_rect(Rect2(_button_rect(last).position.x - 3.0, 8, 1, 20), Palette.SURFACE_BORDER)
	for i in acts.size():
		var b := _button_rect(i)
		var on := i == _hover
		var danger := on and i == last
		if on:
			SystemsDraw.rrect(self, b, 5.0, Palette.SURFACE_RAISED)
			SystemsDraw.rrect_outline(self, b, 5.0, Color(Palette.STATE_ERROR, 0.6) if danger else Palette.SURFACE_BORDER_STRONG, 1.0)
		var c := Palette.STATE_ERROR if danger else (Palette.TEXT_PRIMARY if on else Palette.TEXT_SECONDARY)
		_icon(str(acts[i][0]), b.get_center(), c)
	if _hover >= 0 and _hover < acts.size():
		var a: Array = acts[_hover]
		var text := "%s · %s" % [a[1], a[2]]
		var f := TclTheme.font("Medium")
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 12.0
		var b2 := _button_rect(_hover)
		var tip := Rect2(b2.get_center().x - w * 0.5, SIZE.y + 4, w, 18)
		var danger_tip := _hover == acts.size() - 1  # Delete: the label turns red too (Penpot 18)
		SystemsDraw.rrect(self, tip, 4.0, Palette.SURFACE_RAISED)
		SystemsDraw.rrect_outline(self, tip, 4.0, Color(Palette.STATE_ERROR, 0.6) if danger_tip else Palette.SURFACE_BORDER, 1.0)
		draw_string(f, tip.position + Vector2(6, 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.STATE_ERROR if danger_tip else Palette.TEXT_PRIMARY)


## 16 px action glyphs: the canonical icons where they exist, simple strokes otherwise.
func _icon(action: String, c: Vector2, col: Color) -> void:
	match action:
		"duplicate":
			_tex("icon_duplicate", c, col)
		"rotate":
			_tex("tool_rotate", c, col)
		"upgrade":
			_tex("icon_upgrade", c, col)
		"delete":
			_tex("tool_delete", c, col)
		"move":
			for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				var tip: Vector2 = c + d * 7.0
				draw_line(c + d * 2.0, tip, col, 1.5)
				var s := Vector2(-d.y, d.x) * 2.5
				draw_polyline(PackedVector2Array([tip - d * 2.5 + s, tip, tip - d * 2.5 - s]), col, 1.5)
		"copy":
			# two stacked parameter sliders
			for k in 2:
				var y := c.y - 3.0 + k * 6.0
				draw_line(Vector2(c.x - 6, y), Vector2(c.x + 6, y), Color(col, 0.6), 1.2)
				draw_circle(Vector2(c.x + (-2.5 if k == 0 else 3.0), y), 2.2, col)


func _tex(icon_name: String, c: Vector2, col: Color) -> void:
	var t := Art.icon(icon_name)
	if t != null:
		draw_texture_rect(t, Rect2(c - Vector2(8, 8), Vector2(16, 16)), false, col)
