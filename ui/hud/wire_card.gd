extends Control
## Wire card (FACTORY_SYSTEMS §2.1): a 300 px panel for the selected wire. Shows the bus class,
## a clickable Lanes row (1/2/4/8, gated by the run's max_bus_lanes), the live Load and
## Saturation readouts at 10 Hz, and a BANDWIDTH-BOUND warning when the wire is saturated.
## Shown while a wire is selected (and no machine) in the select tool; drawn procedurally.

const WIDTH := 300.0
const ROW_H := 30.0
const SEG_H := 22.0
const SEG_GAP := 2.0
const SEG_X0 := 110.0
const SEG_X1 := 288.0

var tools: Node

var _cid := -1
var _refresh := 0.0
var _note := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(WIDTH, 140.0)
	visible = false


func _process(delta: float) -> void:
	var sm := get_node("/root/SimulationManager")
	var sim: Simulation = sm.sim
	var show: bool = tools != null and tools.tool == "select" and tools.selected_machine < 0 and tools.selected_conn >= 0 and sim != null and sim.connections.has(tools.selected_conn)
	if not show:
		visible = false
		return
	_cid = tools.selected_conn
	visible = true
	var c: Connection = sim.connections[_cid]
	# 12 px right of the wire's midpoint (average of cell centres), clamped
	var cells := c.cells
	var mid := Vector2.ZERO
	for cell in cells:
		mid += Vector2(cell) * Palette.TILE + Vector2.ONE * (Palette.TILE * 0.5)
	mid /= float(cells.size())
	var ct := get_viewport().get_canvas_transform()
	var sp := ct * mid
	var vp := get_viewport_rect().size
	position = Vector2(clampf(sp.x + 12.0, 8.0, vp.x - size.x - 8.0), clampf(sp.y, 60.0, vp.y - size.y - 8.0))
	size = Vector2(WIDTH, 38.0 + 3.0 * ROW_H + 12.0 + (26.0 if sim.wire_bound(_cid) else 0.0))
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.1  # live load / saturation at 10 Hz
		queue_redraw()


func _row_y(i: int) -> float:
	return 38.0 + i * ROW_H


func _seg_rect(i: int) -> Rect2:
	var total := SEG_X1 - SEG_X0
	var w := (total - SEG_GAP * 3) / 4.0
	var x := SEG_X0 + i * (w + SEG_GAP)
	var y := _row_y(0) + (ROW_H - SEG_H) * 0.5
	return Rect2(x, y, w, SEG_H)


func _gui_input(event: InputEvent) -> void:
	var sm := get_node("/root/SimulationManager")
	var sim: Simulation = sm.sim
	if sim == null or not sim.connections.has(_cid):
		return
	var c: Connection = sim.connections[_cid]
	var gate := 8
	var run = sm.run
	if run != null and run.has_method("max_bus_lanes"):
		gate = int(run.max_bus_lanes())
	if event is InputEventMouseMotion:
		var pos := (event as InputEventMouseMotion).position
		var note := ""
		for i in 4:
			if _seg_rect(i).has_point(pos) and [1, 2, 4, 8][i] > gate:
				note = _bus_reason(i)
		if note != _note:
			_note = note
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var pos := (event as InputEventMouseButton).position
		for i in 4:
			if _seg_rect(i).has_point(pos):
				var l: int = [1, 2, 4, 8][i]
				if l > gate:
					return
				if l != c.lanes:
					sm.request_edit()
					sim.set_wire_lanes(_cid, l)
				return


func _bus_reason(i: int) -> String:
	var sm := get_node("/root/SimulationManager")
	if sm.in_lab:
		var g := int(LabDef.CONFIG.bus_lane_levels[i])
		return "Unlocks at L%d · %s" % [g + 1, LabDef.level(g)["title"]]
	return "Unlocks later"


func _draw() -> void:
	var sm := get_node("/root/SimulationManager")
	var sim: Simulation = sm.sim
	if sim == null or not sim.connections.has(_cid):
		return
	var c: Connection = sim.connections[_cid]
	var r := Rect2(Vector2.ZERO, size)
	for i in 3:
		var sh := r.grow(2.0 + i * 2.0)
		sh.position.y += 3.0
		SystemsDraw.rrect(self, sh, 10.0 + i * 2.0, Color(0, 0, 0, 0.10))
	SystemsDraw.rrect(self, r, 8.0, Palette.SURFACE_PANEL)
	SystemsDraw.rrect_outline(self, r, 8.0, Palette.SURFACE_BORDER_STRONG, 1.0)
	# title
	_text(Vector2(16, 22), "%s · %d-bit" % [Connection.class_title(c.width), c.width], 11, "ExtraBold", Palette.TEXT_PRIMARY)
	# Lanes row
	var gate := 8
	var run = sm.run
	if run != null and run.has_method("max_bus_lanes"):
		gate = int(run.max_bus_lanes())
	_draw_lanes(c, gate)
	# Load
	_text(Vector2(16, _row_y(1) + 16), "Load", 9, "ExtraBold", Palette.TEXT_MUTED)
	_text(Vector2(110, _row_y(1) + 16), "%d / %d" % [c.all_packets().size(), c.slots.size()], 10, "ExtraBold", Palette.TEXT_PRIMARY)
	# Saturated
	_text(Vector2(16, _row_y(2) + 16), "Saturated", 9, "ExtraBold", Palette.TEXT_MUTED)
	_text(Vector2(110, _row_y(2) + 16), "%d %%" % roundi(c.saturation_ratio() * 100.0), 10, "ExtraBold", Palette.TEXT_PRIMARY)
	# BANDWIDTH-BOUND warning
	if sim.wire_bound(_cid):
		var by := _row_y(3) + 8
		var t := Art.icon("icon_bottleneck")
		if t != null:
			draw_texture_rect(t, Rect2(16, by - 6, 12, 12), false, Palette.STATE_BLOCKED)
		_text(Vector2(34, by), "BANDWIDTH-BOUND · add lanes", 9, "ExtraBold", Palette.STATE_BLOCKED)
	# locked-step reason
	if _note != "":
		_text(Vector2(16, size.y - 8), _note, 9, "Medium", Palette.TEXT_MUTED)


func _draw_lanes(c: Connection, gate: int) -> void:
	_text(Vector2(16, _row_y(0) + 16), "Lanes", 9, "ExtraBold", Palette.TEXT_MUTED)
	var segs := [1, 2, 4, 8]
	for i in segs.size():
		var l: int = segs[i]
		var rect := _seg_rect(i)
		var chosen: bool = c.lanes == l
		var locked: bool = l > gate
		if chosen:
			SystemsDraw.rrect(self, rect, 4.0, Color(Palette.STATE_BUILD, 0.22))
			SystemsDraw.rrect_outline(self, rect, 4.0, Palette.STATE_BUILD, 1.0)
		else:
			SystemsDraw.rrect(self, rect, 4.0, Palette.SURFACE_SUNKEN)
			SystemsDraw.rrect_outline(self, rect, 4.0, Palette.SURFACE_BORDER, 1.0)
		var col := Palette.TEXT_PRIMARY if chosen else (Palette.TEXT_MUTED if locked else Palette.TEXT_SECONDARY)
		var label := str(l)
		var f := TclTheme.font("Medium")
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var lx := rect.get_center().x - lw * 0.5
		draw_string(f, Vector2(lx, rect.get_center().y + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		if locked:
			var t := Art.icon("icon_lock")
			if t != null:
				draw_texture_rect(t, Rect2(lx + lw + 2, rect.get_center().y - 5, 10, 10), false, Palette.TEXT_MUTED)


func _text(pos: Vector2, s: String, px: int, weight: String, c: Color, width := -1.0) -> void:
	draw_string(TclTheme.font(weight), pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, px, c)