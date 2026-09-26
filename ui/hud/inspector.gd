extends Control
## Inspector (Penpot 06, 300×366, right edge, 16 px margin, top 68). Visible while a machine is
## selected. Sections: CONFIGURATION (params, width, View as), STATE, PERFORMANCE, STATISTICS
## (collapsed). Rows 280×24: key 12/500 secondary, value 12/800 right-aligned.

const W := 300.0
const ROW := 24.0
const SEC := 28.0

var tools: Node
var _mid := -1
var _bg: Panel
var _body: Control
var _state_pill: Panel
var _state_dot: Panel
var _state_label: Label
var _values := {}  # key -> Label (refreshed every frame)
var _stats_open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -W - 16
	offset_right = -16
	offset_top = 68
	visible = false
	_bg = HudKit.box(self, Vector2.ZERO, Vector2(W, 366), Palette.SURFACE_PANEL, Color(0, 0, 0, 0), 0, 10)
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	var sm := _mgr()
	sm.layout_changed.connect(func(): if visible: _rebuild())
	sm.view_mode_changed.connect(func(_m): if visible: _rebuild())


func bind_tools(t: Node) -> void:
	tools = t
	tools.selection_changed.connect(_on_selection)


func _mgr() -> Node:
	return get_node("/root/SimulationManager")


func _on_selection(machine_id: int, _conn_id: int) -> void:
	# The Network Inspector owns the selection while a NIC is selected (JOB C8b): behave as if
	# nothing is selected (hide) so the two panels never stack.
	var nic := false
	if machine_id >= 0:
		var sim: Simulation = _mgr().sim
		var m = sim.machines.get(machine_id) if sim != null else null
		nic = m != null and m.type == "nic"
	if _mid >= 0 and (machine_id < 0 or nic):
		HudKit.panel_hide(self, Vector2(12, 0), 0.14)
	_mid = machine_id if not nic else -1
	if _mid >= 0:
		_rebuild()
		HudKit.panel_show(self, Vector2(12, 0), 0.18)


func _machine() -> Machine:
	var sim: Simulation = _mgr().sim
	return sim.machines.get(_mid) if sim != null else null


func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	_values.clear()
	var m := _machine()
	if m == null:
		visible = false
		return
	var def := m.def()
	# header
	var tile := HudKit.box(_body, Vector2(16, 16), Vector2(40, 40), Palette.MATERIAL_PLATE, Palette.MATERIAL_FRAME, 1, 6)
	HudKit.machine_icon(tile, m.type, Vector2(8, 8), 24, Palette.TEXT_PRIMARY)
	HudKit.label(_body, str(def["name"]), Vector2(68, 14), 15, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 200)
	_state_pill = HudKit.box(_body, Vector2(68, 38), Vector2(96, 20), Palette.SURFACE_SUNKEN, Palette.DATA_NUMBER, 1, 10)
	_state_dot = HudKit.dot(_state_pill, Vector2(11, 10), 6, Palette.DATA_NUMBER)
	_state_label = HudKit.label(_state_pill, "", Vector2(20, 4), 9, HudKit.W_XBOLD, Palette.DATA_NUMBER, 72)
	var y := 72.0
	# CONFIGURATION
	y = _section("CONFIGURATION", y, true)
	var run = _mgr().run
	var clock_ok: bool = run != null and run.has_method("clock_unlocked") and run.clock_unlocked()
	var lanes_ok: bool = run != null and run.has_method("max_lanes") and run.max_lanes() > 1
	var eff_ok: bool = run != null and run.has_method("efficiency_unlocked") and run.efficiency_unlocked()
	for key in def["params"]:
		if key == "clock" and not clock_ok:
			continue  # clock modes arrive with the power levels (SYSTEMS_EXPANSION §6)
		if key == "lanes" and not lanes_ok:
			continue  # lane upgrades arrive with the progression (FACTORY_SYSTEMS §3)
		if key == "efficiency" and not eff_ok:
			continue  # efficiency arrives with the progression (FACTORY_SYSTEMS §3)
		y = _param_row(m, key, def["params"][key], y)
	y = _row_static("Width", "%d-bit" % m.width, y, true)
	y = _view_as_row(y)
	# STATE
	y = _section("STATE", y + 4, true)
	y = _row("Job", "job", y)
	y = _row("Queue", "queue", y)
	if m.type == "add":
		y = _row("Last carry", "carry", y)
	# PERFORMANCE
	y = _section("PERFORMANCE", y + 4, true)
	y = _row("Busy", "busy", y)
	y = _row("Time / job", "tpj", y)
	# STATISTICS (collapsible)
	y = _section("STATISTICS", y + 4, _stats_open, _toggle_stats)
	if _stats_open:
		y = _row("Processed", "processed", y)
		if m.type == "add":
			y = _row("Carries", "carries", y)
	_bg.size = Vector2(W, y + 12)
	size = _bg.size


func _toggle_stats() -> void:
	_stats_open = not _stats_open
	_rebuild()


func _section(title: String, y: float, open: bool, on_toggle := Callable()) -> float:
	var l := HudKit.label(_body, title, Vector2(10, y + 8), 9, HudKit.W_XBOLD, Palette.TEXT_SECONDARY)
	l.add_theme_constant_override("outline_size", 0)
	HudKit.icon(_body, "icon_chevron_down" if open else "icon_chevron_right", Vector2(270, y + 6), 16, Palette.TEXT_MUTED)
	if on_toggle.is_valid():
		HudKit.hit(_body, Vector2(10, y), Vector2(280, SEC), on_toggle)
	return y + SEC + 4


func _row(key_text: String, key: String, y: float) -> float:
	HudKit.label(_body, key_text, Vector2(10, y + 4), 12, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
	_values[key] = HudKit.label(_body, "", Vector2(150, y + 4), 12, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 140, HORIZONTAL_ALIGNMENT_RIGHT)
	return y + ROW + 2


func _row_static(key_text: String, value: String, y: float, locked := false) -> float:
	HudKit.label(_body, key_text, Vector2(10, y + 8), 12, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
	var chip := HudKit.box(_body, Vector2(150, y), Vector2(140, 32), Palette.SURFACE_SUNKEN, Palette.SURFACE_BORDER, 1, 6)
	HudKit.label(chip, value, Vector2(12, 8), 12, HudKit.W_XBOLD, Palette.DATA_NUMBER)
	if locked:
		HudKit.icon(chip, "icon_lock", Vector2(114, 8), 16, Palette.TEXT_MUTED)
	return y + 38


## Stepper (int) or cycling dropdown (enum) in a 140×32 control at x 150.
func _param_row(m: Machine, key: String, pdef: Dictionary, y: float) -> float:
	HudKit.label(_body, str(pdef["label"]), Vector2(10, y + 8), 12, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
	var ctl := HudKit.box(_body, Vector2(150, y), Vector2(140, 32), Palette.SURFACE_RAISED, Palette.SURFACE_BORDER_STRONG, 1, 6)
	if pdef["kind"] == "enum":
		HudKit.label(ctl, str(m.params[key]), Vector2(12, 8), 12, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 100)
		HudKit.icon(ctl, "icon_chevron_down", Vector2(114, 8), 16, Palette.TEXT_SECONDARY)
		var opts: Array = pdef["options"]
		HudKit.hit(_body, Vector2(150, y), Vector2(140, 32), func():
			var i := opts.find(m.params[key])
			_set_param(key, opts[(i + 1) % opts.size()]))
		return y + 38
	if pdef["kind"] == "text":
		# free text (the ROM table): commit on Enter or when the field loses focus
		var le := LineEdit.new()
		le.position = Vector2(4, 2)
		le.size = Vector2(132, 28)
		le.text = str(m.params.get(key, pdef.get("default", "")))
		le.add_theme_font_override("font", TclTheme.font(HudKit.W_XBOLD))
		le.add_theme_font_size_override("font_size", 11)
		le.add_theme_color_override("font_color", Palette.DATA_NUMBER)
		le.add_theme_color_override("caret_color", Palette.DATA_NUMBER)
		le.add_theme_stylebox_override("normal", HudKit.style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4))
		le.add_theme_stylebox_override("focus", HudKit.style(Palette.SURFACE_SUNKEN, Palette.DATA_NUMBER, 1, 4))
		le.text_submitted.connect(func(t): _set_param(key, t))
		le.focus_exited.connect(func(): if le.text != str(m.params.get(key, "")): _set_param(key, le.text))
		ctl.add_child(le)
		return y + 38
	# int stepper: [−] value [+], value shown in the current view mode at the machine width
	var lo := int(pdef.get("min", 0))
	var hi := int(pdef.get("max", 255))
	if m.type in ["add", "compare", "modulo"]:
		lo = maxi(lo, 0)
		hi = mini(hi, (1 << m.width) - 1)
	var v := clampi(int(m.params[key]), lo, hi)
	if key == "k" and lo >= 0 and m.type in ["add", "compare", "modulo", "multiply"] and m.width <= 8:
		_bit_cells(ctl, key, v, m.width, hi)
		return y + 38
	var shown := HudKit.fmt_const(BitVector.of(v, m.width)) if lo >= 0 else str(v)
	HudKit.icon(ctl, "icon_minus", Vector2(8, 8), 16, Palette.TEXT_SECONDARY)
	HudKit.label(ctl, shown, Vector2(32, 8), 12, HudKit.W_XBOLD, Palette.DATA_NUMBER, 76, HORIZONTAL_ALIGNMENT_CENTER)
	HudKit.icon(ctl, "icon_plus", Vector2(116, 8), 16, Palette.TEXT_SECONDARY)
	HudKit.hit(_body, Vector2(150, y), Vector2(32, 32), func(): _set_param(key, clampi(v - 1, lo, hi)), "−1")
	HudKit.hit(_body, Vector2(258, y), Vector2(32, 32), func(): _set_param(key, clampi(v + 1, lo, hi)), "+1")
	return y + 38


## A constant as its bits (MSB left): click a bit to flip it. The machines work on bits, so the
## constant is set the same way.
func _bit_cells(ctl: Panel, key: String, v: int, width: int, hi: int) -> void:
	var cw := minf(16.0, 132.0 / width)
	var x0 := (140.0 - cw * width) * 0.5
	for i in width:
		var bit := width - 1 - i
		var on := (v >> bit) & 1 == 1
		var p := Vector2(x0 + i * cw + 1.0, 4.0)
		var cell := HudKit.box(ctl, p, Vector2(cw - 2.0, 24), Palette.SURFACE_SUNKEN if not on else Palette.SURFACE_RAISED, Palette.DATA_NUMBER if on else Palette.SURFACE_BORDER, 1, 3)
		HudKit.label(cell, "1" if on else "0", Vector2(0, 5), 11, HudKit.W_XBOLD, Palette.DATA_NUMBER if on else Palette.TEXT_MUTED, cw - 2.0, HORIZONTAL_ALIGNMENT_CENTER)
		var nv := v ^ (1 << bit)
		HudKit.hit(ctl, p, Vector2(cw - 2.0, 24), func(): _set_param(key, mini(nv, hi)), "Flip bit %d" % bit)


func _view_as_row(y: float) -> float:
	var modes: Array = _mgr().mission.view_modes
	if modes.is_empty():
		return y
	HudKit.label(_body, "View as", Vector2(10, y + 8), 12, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
	var seg := HudKit.box(_body, Vector2(150, y), Vector2(140, 32), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 16)
	var w := 132.0 / modes.size()
	for i in modes.size():
		var mode: int = modes[i]
		var on: bool = mode == HudKit.view_mode()
		var p := Vector2(4 + i * w, 4)
		HudKit.box(seg, p, Vector2(w, 24), Palette.SURFACE_RAISED if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12)
		HudKit.label(seg, ViewMode.chip(mode), p + Vector2(0, 5), 10, HudKit.W_XBOLD, Palette.TEXT_PRIMARY if on else Palette.TEXT_MUTED, w, HORIZONTAL_ALIGNMENT_CENTER)
		HudKit.hit(seg, p, Vector2(w, 24), func(): _mgr().set_view_mode(mode), "View the same bits as %s" % ViewMode.chip(mode))
	return y + 38


func _set_param(key: String, value: Variant) -> void:
	var sm := _mgr()
	sm.request_edit()
	sm.sim.set_param(_mid, key, value)


func _process(_delta: float) -> void:
	if not visible:
		return
	var m := _machine()
	if m == null:
		visible = false
		return
	var sim: Simulation = _mgr().sim
	var st: String = Machine.STATE_NAMES[m.state]
	var c := Palette.DATA_NUMBER
	match m.state:
		Machine.State.BLOCKED: c = Palette.STATE_BLOCKED
		Machine.State.ERROR: c = Palette.STATE_ERROR
		Machine.State.IDLE, Machine.State.DISABLED: c = Palette.TEXT_SECONDARY
	HudKit.set_text(_state_label, st, c)
	HudKit.restyle(_state_pill, Palette.SURFACE_SUNKEN, c, 1, 10)
	HudKit.restyle(_state_dot, c, Color(0, 0, 0, 0), 0, 6)
	var ticks := maxi(sim.tick, 1)
	_put("job", "%d%%" % roundi(m.job_progress() * 100.0) if not m.job.is_empty() else "idle")
	_put("queue", str(m.queued_count()))
	_put("carry", str(m.last_carry), Palette.STATE_BLOCKED if m.last_carry == 1 else Palette.TEXT_PRIMARY)
	var busy := 100.0 * m.busy_ticks / ticks
	_put("busy", "%d %%" % roundi(busy), Palette.STATE_BLOCKED if busy > 90.0 else Palette.TEXT_PRIMARY)
	_put("tpj", "%d tick%s" % [m.processing_ticks(), "" if m.processing_ticks() == 1 else "s"])
	_put("processed", str(m.processed))
	_put("carries", str(m.carries))


func _put(key: String, text: String, color = null) -> void:
	if _values.has(key):
		HudKit.set_text(_values[key], text, color)
