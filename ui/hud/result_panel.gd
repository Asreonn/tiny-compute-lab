extends Control
## ResultPanel (Penpot 06, 380×300, centred, modal dim). PASS: stars + accuracy/throughput/latency/
## power, CONTINUE / RETRY. VALIDATION FAILED: reason, Expected / Received / Packet (BIN bits
## beneath non-BIN values), path, FIX & RETRY. Failure explains WHY.

const W := 380.0
const H := 300.0

var _dim: ColorRect
var _panel: Panel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var sm := get_node("/root/SimulationManager")
	sm.run_finished.connect(_show)
	sm.ticked.connect(func(t): if t == 0: hide_panel())
	sm.mission_loaded.connect(func(_d): hide_panel())


func hide_panel() -> void:
	visible = false
	if _dim:
		_dim.queue_free()
		_dim = null


func _show(status: int) -> void:
	hide_panel()
	var sm := get_node("/root/SimulationManager")
	visible = true
	_dim = ColorRect.new()
	_dim.color = Color(Palette.BG_VOID, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.add_child(holder)
	_panel = HudKit.box(holder, Vector2(-W / 2, -H / 2), Vector2(W, H), Palette.SURFACE_PANEL, Palette.SURFACE_BORDER_STRONG, 1, 8)
	var ok := status == MissionRun.Status.PASS
	HudKit.box(_panel, Vector2.ZERO, Vector2(W, 4), Palette.STATE_VALID if ok else Palette.STATE_ERROR, Color(0, 0, 0, 0), 0, 2)
	if ok:
		_pass(sm)
	else:
		_fail(sm)


func _col(x: float, key: String, value: String, color: Color, y := 92.0, sub := "") -> void:
	HudKit.label(_panel, key, Vector2(x, y), 10, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
	HudKit.label(_panel, value, Vector2(x, y + 14), 22, HudKit.W_XBOLD, color, 110)
	if sub != "":
		HudKit.label(_panel, sub, Vector2(x, y + 44), 10, HudKit.W_MEDIUM, Palette.TEXT_MUTED, 110)


func _button(x: float, text: String, primary: bool, action: Callable) -> void:
	var p := Vector2(x, 240)
	HudKit.box(_panel, p, Vector2(104, 32), Palette.DATA_NUMBER if primary else Palette.SURFACE_RAISED,
		Palette.DATA_NUMBER if primary else Palette.SURFACE_BORDER_STRONG, 1, 4)
	HudKit.label(_panel, text, p + Vector2(0, 9), 11, HudKit.W_XBOLD, Palette.TEXT_INVERSE if primary else Palette.TEXT_PRIMARY, 104, HORIZONTAL_ALIGNMENT_CENTER)
	HudKit.hit(_panel, p, Vector2(104, 32), action)


func _pass(sm: Node) -> void:
	var sim: Simulation = sm.sim
	HudKit.label(_panel, "PASS", Vector2(24, 20), 20, HudKit.W_XBOLD, Palette.STATE_VALID)
	var stars: int = sm.run.stars(sim)
	for i in 3:
		HudKit.icon(_panel, "icon_star" if i < stars else "icon_star_empty", Vector2(288 + i * 24, 22), 20,
			Palette.FAMILY_ROUTING if i < stars else Palette.TEXT_MUTED)
	HudKit.label(_panel, sm.mission.title, Vector2(24, 58), 12, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY, 330)
	_col(24, "Accuracy", "%d%%" % roundi(sm.run.accuracy()), Palette.TEXT_PRIMARY)
	_col(200, "Throughput", "%.1f/s" % sm.real_rate(sim.throughput()), Palette.TEXT_PRIMARY)
	_col(24, "Latency", "%d t" % roundi(sim.avg_latency()), Palette.TEXT_PRIMARY, 150)
	_col(200, "Power", str(sim.total_power()), Palette.TEXT_PRIMARY, 150)
	var y := 206.0
	for g in sm.run.goal_results(sim):
		HudKit.label(_panel, ("✓ " if g["met"] else "✗ ") + str(g["label"]), Vector2(24, y), 10, HudKit.W_MEDIUM,
			Palette.STATE_VALID if g["met"] else Palette.TEXT_MUTED, 330)
		y += 14
	var all: Array = Missions.all()
	var idx: int = all.find(sm.mission)
	if idx >= 0 and idx + 1 < all.size():
		var next_id: String = all[idx + 1].id
		_button(24, "CONTINUE", true, func(): sm.load_mission(next_id))
		_button(140, "RETRY", false, func(): sm.reset_run())
	else:
		_button(24, "RETRY", true, func(): sm.reset_run())


func _fail(sm: Node) -> void:
	var f: Dictionary = sm.run.failure
	HudKit.label(_panel, "VALIDATION FAILED", Vector2(24, 20), 20, HudKit.W_XBOLD, Palette.STATE_ERROR)
	HudKit.label(_panel, str(f.get("reason", "")), Vector2(24, 58), 12, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY, 330)
	var mode := HudKit.view_mode()
	var exp_sub := ""
	var rec_sub := ""
	if mode != ViewMode.Mode.BIN:
		exp_sub = str(f.get("expected_bits", ""))
		rec_sub = str(f.get("received_bits", ""))
	_col(24, "Expected", str(f.get("expected", "—")), Palette.STATE_VALID, 92, exp_sub)
	_col(140, "Received", str(f.get("received", "—")), Palette.STATE_ERROR, 92, rec_sub)
	var pid := int(f.get("packet", -1))
	_col(256, "Packet", "#%d" % pid if pid >= 0 else "—", Palette.TEXT_PRIMARY)
	var path: PackedStringArray = f.get("path", PackedStringArray())
	if not path.is_empty():
		HudKit.label(_panel, "Path  " + " → ".join(path), Vector2(24, 150), 11, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY, 330)
		HudKit.label(_panel, "Highlighted on the board.", Vector2(24, 172), 10, HudKit.W_MEDIUM, Palette.TEXT_MUTED)
	_button(24, "FIX & RETRY", true, func(): sm.reset_run())
