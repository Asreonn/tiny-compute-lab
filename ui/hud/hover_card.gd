extends Control
## Hover card (SYSTEMS_EXPANSION §9, systems_v1.js INTERACTION): a 232x150 panel for the machine
## under the pointer. Appears after 180 ms (α 0→1 and a 4 px rise over 120 ms) at pointer +16/−16,
## clamped to the viewport, follows the pointer, and hides during a drag, wire or placement.
## Rows: family tab + resource indicators, name + what it does, state chip (with progress),
## POWER · CLOCK · TEMP · PORTS — Penpot 18 / UX 01.
## Drawn procedurally (no child Controls) so it never takes the mouse.

const SIZE := Vector2(232, 150)
const DELAY := 0.18
const APPEAR := 0.12

var tools: Node
var _mid := -1  # machine under the pointer
var _wait := 0.0  # seconds hovered so far
var _shown := 0.0  # appear progress 0..1
var _refresh := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = SIZE
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
	_wait += delta
	if _wait < DELAY:
		return
	_shown = minf(1.0, _shown + delta / APPEAR)
	visible = true
	modulate.a = _shown
	var mp := get_viewport().get_mouse_position()
	var vp := get_viewport_rect().size
	var p := mp + Vector2(16, -16 - SIZE.y)
	if p.x + SIZE.x > vp.x - 8:
		p.x = mp.x - 16 - SIZE.x
	p.y = clampf(p.y, 60.0, vp.y - SIZE.y - 8)
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
	var r := Rect2(Vector2.ZERO, SIZE)
	for i in 3:  # tooltip shadow
		var sh := r.grow(2.0 + i * 2.0)
		sh.position.y += 3.0
		SystemsDraw.rrect(self, sh, 10.0 + i * 2.0, Color(0, 0, 0, 0.10))
	SystemsDraw.rrect(self, r, 8.0, Palette.SURFACE_PANEL)
	SystemsDraw.rrect_outline(self, r, 8.0, Palette.SURFACE_BORDER_STRONG, 1.0)
	# family tab + resource indicators (Penpot 18 / UX 01)
	SystemsDraw.rrect(self, Rect2(12, 10, 16, 3), 1.0, Palette.family(str(def["family"])))
	_draw_ri(SIZE.x - 12.0, 8.0, m.processing_ticks(), m.power_demand(), m.clock_mode())
	# name + what it does, on one line
	var name := str(def["name"])
	var fb := TclTheme.font("ExtraBold")
	var nw := fb.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_text(Vector2(12, 32), name, 12, "ExtraBold", Palette.TEXT_PRIMARY)
	_text(Vector2(12 + nw + 8, 32), _function_text(m), 10, "Medium", Palette.TEXT_MUTED, SIZE.x - nw - 32)
	# state chip (with the job's progress)
	var st_name: String = Machine.STATE_NAMES[m.state]
	if m.heat_stage >= ThermalGrid.Stage.THROTTLING and m.state != Machine.State.ERROR:
		st_name = ThermalGrid.STAGE_NAMES[m.heat_stage]
	elif m.state == Machine.State.PROCESSING and not m.job.is_empty():
		var tot := maxf(float(m.job.get("work_total", 1)), 1.0)
		st_name += " %d%%" % roundi(100.0 * (tot - float(m.job.get("work_left", tot))) / tot)
	var sc := Rect2(12, 42, 16 + st_name.length() * 5.6, 14)
	SystemsDraw.rrect(self, sc, 7.0, Palette.SURFACE_SUNKEN)
	draw_circle(sc.position + Vector2(8, 7), 2.5, _state_color(m))
	_text(sc.position + Vector2(14, 10), st_name, 8, "ExtraBold", Palette.TEXT_SECONDARY)
	# rows
	var y := 76.0
	for row in _rows(sim, m):
		_text(Vector2(12, y), str(row[0]), 7, "ExtraBold", Palette.TEXT_MUTED)
		_text(Vector2(64, y), str(row[1]), 10, "ExtraBold", row[2], SIZE.x - 76)
		y += 16.0


## Resource indicators as on the chassis (STYLE_GUIDE §3): clock chevrons, one dot per job tick
## (max 6, then +), a divider, one gold pip per power unit (max 4). `xr` = right edge.
func _draw_ri(xr: float, y: float, ticks: int, power: int, mode: String) -> void:
	var chev := 1 if mode == "fast" else (2 if mode == "overclocked" else 0)
	var dots := mini(ticks, 6)
	var pips := mini(power, 4)
	var w := chev * 6 + (2 if chev > 0 else 0) + dots * 6 + (4 if ticks > 6 else 0) + 6 + (pips * 5 if power > 0 else 5)
	var x := xr - w
	for i in chev:
		draw_polyline(PackedVector2Array([Vector2(x + 1, y + 1), Vector2(x + 4, y + 4), Vector2(x + 1, y + 7)]), Palette.STATE_BLOCKED, 1.5, true)
		x += 6
	if chev > 0:
		x += 2
	for i in dots:
		draw_circle(Vector2(x + 2.5, y + 4.0), 2.5, Color(Palette.MATERIAL_SILK, 0.7))
		x += 6
	if ticks > 6:
		draw_rect(Rect2(x, y + 3.5, 3, 1), Color(Palette.MATERIAL_SILK, 0.7))
		draw_rect(Rect2(x + 1, y + 2.5, 1, 3), Color(Palette.MATERIAL_SILK, 0.7))
		x += 4
	x += 3
	draw_rect(Rect2(x, y + 1, 1, 6), Color(Palette.MATERIAL_SILK, 0.25))
	x += 3
	if power == 0:
		draw_rect(Rect2(x, y + 1, 3, 6), Color(Palette.MATERIAL_SILK, 0.35), false, 0.75)
	for i in pips:
		draw_rect(Rect2(x, y, 3, 8), Color(Palette.MATERIAL_GOLD, 0.9))
		x += 5


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
	var cap := sim.power_capacity()
	var dem := m.power_demand()
	var pw := ("%d of %d" % [dem, cap]) if cap > 0 else "%d" % dem
	var over := sim.overloaded() and not m.locked and m.power() > 0
	if over:
		pw += " · brownout"
	out.append(["POWER", pw, Palette.STATE_ERROR if over else Palette.TEXT_PRIMARY])
	var mode := m.clock_mode()
	var cost := m.processing_ticks()
	out.append(["CLOCK", "%d tick%s · %s" % [cost, "" if cost == 1 else "s", mode], Palette.STATE_BLOCKED if mode != "normal" else Palette.TEXT_PRIMARY])
	if sim.thermal != null:
		var warm := m.heat_stage >= ThermalGrid.Stage.WARM
		out.append(["TEMP", "%d °C · %s" % [roundi(ThermalGrid.celsius(m.temp)), ThermalGrid.STAGE_NAMES[m.heat_stage]], Palette.STATE_BLOCKED if warm else Palette.TEXT_PRIMARY])
	else:
		out.append(["TEMP", "25 °C · ambient", Palette.TEXT_MUTED])
	var ins := []
	var outs := []
	for p in m.ports():
		var pid: String = p["id"]
		var w := "raw" if m.port_role(pid) == Catalog.ROLE_RAW else "%d" % m.port_width(pid)
		if p["dir"] == Catalog.DIR_OUT:
			outs.append(w)
		else:
			ins.append(w)
	var pt := ""
	if not ins.is_empty():
		pt += "in " + ",".join(ins) + ("" if ins[-1] == "raw" else "-bit")
	if not outs.is_empty():
		pt += (" → " if pt != "" else "") + "out " + ",".join(outs) + ("" if outs[-1] == "raw" else "-bit")
	out.append(["PORTS", pt if pt != "" else "none", Palette.TEXT_PRIMARY])
	return out
