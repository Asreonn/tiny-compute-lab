extends Control
## Hover card v2 (Penpot 18 / UX 01): a 250 px wide panel for the machine under the pointer.
## Appears after 180 ms (α 0→1 and a 4 px rise over 120 ms) at pointer +16/−16, clamped to the
## viewport, follows the pointer, and hides during a drag, wire or placement.
## Header: family bar, MK title + function/width subtitle, state chip at the right edge.
## Rows: WIDTH · LANES · RATE · POWER (feeder + bottleneck) · HEAT · TEMP · PROCESSING.
## Drawn procedurally (no child Controls) so it never takes the mouse.

const SIZE_W := 250.0
const HEADER_H := 60.0
const ROW_H := 16.0
const PAD_B := 10.0
const DELAY := 0.18
const APPEAR := 0.12

var tools: Node
var _mid := -1  # machine under the pointer
var _wait := 0.0  # seconds hovered so far
var _shown := 0.0  # appear progress 0..1
var _refresh := 0.0
var _size := Vector2(SIZE_W, HEADER_H + 6 * ROW_H + PAD_B)  # height follows the row count


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = _size
	visible = false


func bind_tools(t: Node) -> void:
	tools = t
	tools.hover_changed.connect(_on_hover)


func _on_hover(info: Dictionary) -> void:
	var id := -1
	if str(info.get("kind", "")) == "machine":
		id = int(info.get("id", -1))
	if id != _mid:
		_mid = id
		_wait = 0.0
		_shown = 0.0
		visible = false


func _blocked() -> bool:
	return tools == null or tools._dragging() or tools.tool == "place"


func _process(delta: float) -> void:
	var sim: Simulation = get_node("/root/SimulationManager").sim
	if _mid < 0 or sim == null or not sim.machines.has(_mid) or _blocked():
		if visible:
			visible = false
		_shown = 0.0
		return
	var m: Machine = sim.machines[_mid]
	_size = Vector2(SIZE_W, HEADER_H + _row_count(m) * ROW_H + PAD_B)
	_wait += delta
	if _wait < DELAY:
		return
	_shown = minf(1.0, _shown + delta / APPEAR)
	visible = true
	modulate.a = _shown
	var mp := get_viewport().get_mouse_position()
	var vp := get_viewport_rect().size
	var p := mp + Vector2(16, -16 - _size.y)
	if p.x + _size.x > vp.x - 8:
		p.x = mp.x - 16 - _size.x
	p.y = clampf(p.y, 60.0, vp.y - _size.y - 8)
	position = p + Vector2(0, 4.0 * (1.0 - _shown))
	_refresh -= delta
	if _refresh <= 0.0 or _shown < 1.0:
		_refresh = 0.1  # live rows (state, temperature) at 10 Hz
		queue_redraw()


func _text(pos: Vector2, s: String, px: int, weight: String, c: Color, width := -1.0) -> void:
	draw_string(TclTheme.font(weight), pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, px, c)


func _draw() -> void:
	var sim: Simulation = get_node("/root/SimulationManager").sim
	if sim == null or not sim.machines.has(_mid):
		return
	var m: Machine = sim.machines[_mid]
	var def := m.def()
	var r := Rect2(Vector2.ZERO, _size)
	for i in 3:  # tooltip shadow
		var sh := r.grow(2.0 + i * 2.0)
		sh.position.y += 3.0
		SystemsDraw.rrect(self, sh, 10.0 + i * 2.0, Color(0, 0, 0, 0.10))
	SystemsDraw.rrect(self, r, 8.0, Palette.SURFACE_PANEL)
	SystemsDraw.rrect_outline(self, r, 8.0, Palette.SURFACE_BORDER_STRONG, 1.0)
	# family tab
	SystemsDraw.rrect(self, Rect2(12, 10, 16, 3), 1.0, Palette.family(str(def["family"])))
	# title: DEF NAME (uppercase) + generation; subtitle: what it does + width
	var lanes := m.lanes()
	var title := str(def["name"]).to_upper()
	if lanes > 1:
		title += " · MK%d" % {2: 2, 4: 3, 8: 4}[lanes]
	_text(Vector2(12, 32), title, 12, "ExtraBold", Palette.TEXT_PRIMARY)
	_text(Vector2(12, 46), _function_text(m) + " · %d-bit" % m.width, 10, "Medium", Palette.TEXT_MUTED)
	# state chip (with the job's progress), right-aligned in the header
	var st_name: String = Machine.STATE_NAMES[m.state]
	if m.heat_stage >= ThermalGrid.Stage.THROTTLING and m.state != Machine.State.ERROR:
		st_name = ThermalGrid.STAGE_NAMES[m.heat_stage]
	elif m.state == Machine.State.PROCESSING and not m.job.is_empty():
		var tot := maxf(float(m.job.get("work_total", 1)), 1.0)
		st_name += " %d%%" % roundi(100.0 * (tot - float(m.job.get("work_left", tot))) / tot)
	var sc_w := 16 + st_name.length() * 5.6
	var sc := Rect2(_size.x - 12.0 - sc_w, 10, sc_w, 14)
	SystemsDraw.rrect(self, sc, 7.0, Palette.SURFACE_SUNKEN)
	draw_circle(sc.position + Vector2(8, 7), 2.5, _state_color(m))
	_text(sc.position + Vector2(14, 10), st_name, 8, "ExtraBold", Palette.TEXT_SECONDARY)
	# rows
	var y := HEADER_H
	for row in _rows(sim, m):
		_text(Vector2(12, y), str(row[0]), 9, "ExtraBold", Palette.TEXT_MUTED)
		_text(Vector2(86, y), str(row[1]), 10, "ExtraBold", row[2], _size.x - 86.0 - 12.0)
		y += ROW_H


## What the machine does with its current settings, in a few words ("in + 2 · wraps at 3 bits").
func _function_text(m: Machine) -> String:
	var k := int(m.params.get("k", 0))
	var w := m.width
	match m.type:
		"add": return "in + %d · wraps at %d bits" % [k, w]
		"multiply": return "in × %d · wraps at %d bits" % [k, w]
		"modulo": return "in mod %d" % k
		"adder": return "a + b · wraps at %d bits" % w
		"compare": return "in %s %d → 1 bit" % [str(m.params.get("op", ">")), k]
		"gate": return "passes in while ctrl is 1"
		"splitter": return "copies to A and B" if str(m.params.get("mode", "")) == "Duplicate" else "alternates A, B"
		"merger": return "takes A and B in turn"
		"buffer": return "queues up to %d" % int(m.params.get("capacity", 4))
		"delay": return "holds %d ticks" % int(m.params.get("ticks", 3))
		"bit_splitter": return "hi %d bits · lo %d bits" % [m.port_width("hi"), m.port_width("lo")]
		"bus_combiner": return "hi %d : lo %d → %d bits" % [m.port_width("hi"), m.port_width("lo"), w]
		"zero_extend", "sign_extend", "truncate": return "%d → %d bits" % [w, m.port_width("out")]
		"shift_left": return "in « %d" % int(m.params.get("n", 1))
		"shift_right": return "in » %d" % int(m.params.get("n", 1))
		"cond_router":
			var op := str(m.params.get("op", ">"))
			return ("bit %d set → A" % k) if op == "bit" else ("in %s %d → A, else B" % [op, k])
		"register": return "%s · holds 1 value" % str(m.params.get("mode", "echo"))
		"rom": return "table of %d" % str(m.params.get("table", "")).split(" ", false).size()
		"alu": return "OP 0 %s · OP 1 %s" % [str(m.params.get("op0", "ADD")), str(m.params.get("op1", "SUB"))]
	var d := str(m.def().get("desc", ""))
	var cut := d.find(".")
	return d.substr(0, cut) if cut > 0 else d


func _state_color(m: Machine) -> Color:
	if m.heat_stage == ThermalGrid.Stage.CRITICAL or m.state == Machine.State.ERROR:
		return Palette.STATE_ERROR
	if m.heat_stage == ThermalGrid.Stage.THROTTLING or m.state == Machine.State.BLOCKED:
		return Palette.STATE_BLOCKED
	match m.state:
		Machine.State.PROCESSING: return Palette.STATE_BUILD
		Machine.State.OUTPUT_READY: return Palette.STATE_VALID
		Machine.State.RECEIVING: return Palette.DATA_NUMBER
	return Palette.TEXT_MUTED


func _rows(sim: Simulation, m: Machine) -> Array:
	var out := []
	out.append(["WIDTH", "%d-bit" % m.width, Palette.TEXT_PRIMARY])
	if m.lanes() > 1:
		out.append(["LANES", "%d / %d busy" % [m.jobs.size(), m.lanes()], Palette.TEXT_PRIMARY])
	out.append(["RATE", "%.1f /s" % m.rate_per_sec(), Palette.TEXT_PRIMARY])
	var dem := m.power_demand()
	if dem == 0:
		out.append(["POWER", "none", Palette.TEXT_MUTED])
	else:
		var pw := "%d" % dem
		var col := Palette.TEXT_PRIMARY
		if sim.power_net != null:
			var f := sim.power_net.feeder_of(m.id)
			if f != "":
				pw += " · " + _node_name(f)
			var b := sim.power_bottleneck(m.id)
			if not b.is_empty():
				pw += " · %s %d/%d" % [_node_name(str(b["node"])), int(b["load"]), int(b["cap"])]
				col = Palette.STATE_BLOCKED
		out.append(["POWER", pw, col])
	if m.heat() == 0:
		out.append(["HEAT", "none", Palette.TEXT_MUTED])
	else:
		var ht := "%d /job" % m.heat()
		if sim.thermal != null and sim.thermal.net != null and sim.thermal.net.network_of(m.id) != "":
			ht += " · cooled"
		out.append(["HEAT", ht, Palette.TEXT_PRIMARY])
	if sim.thermal != null:
		var warm := m.heat_stage >= ThermalGrid.Stage.WARM
		out.append(["TEMP", "%d °C · %s" % [roundi(ThermalGrid.celsius(m.temp)), ThermalGrid.STAGE_NAMES[m.heat_stage]], Palette.STATE_BLOCKED if warm else Palette.TEXT_PRIMARY])
	else:
		out.append(["TEMP", "25 °C · ambient", Palette.TEXT_MUTED])
	var mode := m.clock_mode()
	var cost := m.processing_ticks()
	out.append(["PROCESSING", "%d tick%s · %s" % [cost, "" if cost == 1 else "s", mode], Palette.STATE_BLOCKED if mode != "normal" else Palette.TEXT_PRIMARY])
	return out


## The number of rows the card shows for `m` (LANES appears only above one lane).
func _row_count(m: Machine) -> int:
	return 6 + (1 if m.lanes() > 1 else 0)


## Display name of a power-node id ("source" → "PSU", chains "c…" → "Copper", …).
static func _node_name(nid: String) -> String:
	match nid:
		"source": return "PSU"
		"ctrl": return "VRM"
		"onboard": return "Onboard"
	if nid.begins_with("c"):
		return "Copper"
	if nid.begins_with("b"):
		return "Board"
	if nid.begins_with("p"):
		return "Contacts"
	return nid