extends Control
## Hover card (SYSTEMS_EXPANSION §9, systems_v1.js INTERACTION): a 232x150 panel for the machine
## under the pointer. Appears after 180 ms (α 0→1 and a 4 px rise over 120 ms) at pointer +16/−16,
## clamped to the viewport, follows the pointer, and hides during a drag, wire or placement.
## Rows: family chip + name, function + key parameters, state chip, POWER · CLOCK · TEMP · PORTS.
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
	# family chip + name
	var fam := str(def["family"])
	var fc := Palette.family(fam)
	var chip := Rect2(12, 10, 8 + fam.length() * 6.0, 14)
	SystemsDraw.rrect(self, chip, 3.0, Color(fc, 0.18))
	SystemsDraw.rrect_outline(self, chip, 3.0, Color(fc, 0.7), 1.0)
	_text(chip.position + Vector2(4, 11), fam.to_upper(), 8, "ExtraBold", fc)
	_text(Vector2(chip.end.x + 8, 22), str(def["name"]), 12, "ExtraBold", Palette.TEXT_PRIMARY, SIZE.x - chip.end.x - 20)
	# function + key parameters
	_text(Vector2(12, 40), str(def.get("desc", "")), 9, "Medium", Palette.TEXT_SECONDARY, SIZE.x - 24)
	var ps := _params(m)
	if ps != "":
		_text(Vector2(12, 54), ps, 9, "ExtraBold", Palette.DATA_NUMBER, SIZE.x - 24)
	# state chip
	var st_name: String = Machine.STATE_NAMES[m.state]
	var st_col := _state_color(m)
	if m.heat_stage >= ThermalGrid.Stage.THROTTLING and m.state != Machine.State.ERROR:
		st_name = ThermalGrid.STAGE_NAMES[m.heat_stage]
	var sc := Rect2(12, 62, 14 + st_name.length() * 6.0, 14)
	SystemsDraw.rrect(self, sc, 7.0, Palette.SURFACE_SUNKEN)
	draw_circle(sc.position + Vector2(8, 7), 3.0, st_col)
	_text(sc.position + Vector2(14, 11), st_name, 8, "ExtraBold", Palette.TEXT_SECONDARY)
	# rows
	var y := 94.0
	for row in _rows(sim, m):
		_text(Vector2(12, y), str(row[0]), 8, "ExtraBold", Palette.TEXT_MUTED)
		_text(Vector2(64, y), str(row[1]), 9, "Medium", row[2], SIZE.x - 76)
		y += 15.0


func _params(m: Machine) -> String:
	var parts := []
	for k in m.def()["params"]:
		if k == "clock" or not m.params.has(k):
			continue
		var v = m.params[k]
		if k == "k":
			parts.append("k = %s" % HudKit.fmt_const(BitVector.of(int(v), m.width)))
		else:
			parts.append("%s %s" % [str(m.def()["params"][k].get("label", k)).to_lower(), str(v)])
	return " · ".join(parts)


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
	var mode := m.clock_mode()
	var pw := "%d" % m.power_demand()
	if mode != "normal":
		pw += "  (%d × %s)" % [m.power(), "1.5" if mode == "fast" else "2"]
	if sim.overloaded() and not m.locked and m.power() > 0:
		pw += "  · brownout"
	out.append(["POWER", pw, Palette.STATE_ERROR if sim.overloaded() and m.power() > 0 and not m.locked else Palette.TEXT_PRIMARY])
	var cost := m.processing_ticks()
	out.append(["CLOCK", "%s · %d tick%s / job" % [mode, cost, "" if cost == 1 else "s"], Palette.STATE_BLOCKED if mode != "normal" else Palette.TEXT_PRIMARY])
	if sim.thermal != null:
		var warm := m.heat_stage >= ThermalGrid.Stage.WARM
		out.append(["TEMP", "%d °C · %s" % [roundi(ThermalGrid.celsius(m.temp)), ThermalGrid.STAGE_NAMES[m.heat_stage]], Palette.STATE_BLOCKED if warm else Palette.TEXT_PRIMARY])
	else:
		out.append(["TEMP", "ambient", Palette.TEXT_MUTED])
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
		pt += "in " + ",".join(ins)
	if not outs.is_empty():
		pt += ("  ·  " if pt != "" else "") + "out " + ",".join(outs)
	out.append(["PORTS", pt if pt != "" else "none", Palette.TEXT_PRIMARY])
	return out
