extends Control
## View legend (VISUAL_SYSTEM §21.2): a 264x64 panel right above the View dock while a view is
## on. Heat: the four stage swatches; power: the PSU gauge enlarged with demand / capacity; data:
## bits vs raw; flow: busy / blocked and the bottleneck.

const W := 264.0
const H := 64.0
const FADE := 0.15
const STAGES := [["WARM", 1], ["HOT", 2], ["THROTTLE", 3], ["CRITICAL", 4]]

var _kind := ""
var _a := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	size = Vector2(W, H)
	modulate.a = 0.0


func _process(delta: float) -> void:
	var sm := get_node("/root/SimulationManager")
	var want: String = sm.overlay
	if want != _kind:
		_a = move_toward(_a, 0.0, delta / FADE)
		if _a <= 0.0:
			_kind = want
	else:
		_a = move_toward(_a, 1.0 if _kind != "" else 0.0, delta / FADE)
	modulate.a = _a
	visible = _a > 0.0
	if not visible:
		return
	# right above the View dock (bottom centre): the views live together
	var vs := get_viewport_rect().size
	var dock: Vector2 = load("res://ui/hud/view_dock.gd").dock_size()
	position = Vector2(roundf((vs.x - W) * 0.5), vs.y - 16.0 - dock.y - 8.0 - H)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(W, H))
	SystemsDraw.rrect(self, r, 8.0, Palette.SURFACE_PANEL)
	SystemsDraw.rrect_outline(self, r, 8.0, Palette.SURFACE_BORDER_STRONG, 1.0)
	var sim: Simulation = get_node("/root/SimulationManager").sim
	if sim == null:
		return
	match _kind:
		"thermal": _thermal(sim)
		"power": _power(sim)
		"data": _data(sim)
		"flow": _flow(sim)
		"compute": _compute(sim)
		"network": _network(sim)


func _text(pos: Vector2, s: String, px: int, weight: String, c: Color) -> void:
	draw_string(TclTheme.font(weight), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, c)


func _thermal(sim: Simulation) -> void:
	_text(Vector2(12, 18), "THERMAL", 10, "ExtraBold", Palette.TEXT_PRIMARY)
	_text(Vector2(W - 24, 18), "T", 10, "ExtraBold", Palette.TEXT_MUTED)
	if sim.thermal == null:
		_text(Vector2(12, 38), "No heat on this board yet", 10, "Medium", Palette.TEXT_SECONDARY)
		_text(Vector2(12, 52), "Heat arrives with L17", 9, "Medium", Palette.TEXT_MUTED)
		return
	for i in STAGES.size():
		var st: int = STAGES[i][1]
		var x := 12.0 + i * 62.0
		var col := Palette.STATE_ERROR if st == ThermalGrid.Stage.CRITICAL else Palette.STATE_BLOCKED
		var sw := Rect2(x, 30, 14, 14)
		SystemsDraw.rrect(self, sw, 3.0, Palette.BOARD_PAD)
		SystemsDraw.rrect(self, sw, 3.0, Color(col, SystemsOverlay.TILE_A[st] * 1.6))
		_text(Vector2(x + 18, 41), str(STAGES[i][0]), 8, "ExtraBold", Palette.TEXT_SECONDARY)
	_text(Vector2(12, 58), "hot tiles throttle ×½ · critical pauses", 8, "Medium", Palette.TEXT_MUTED)


func _swatch(x: float, col: Color, label: String, px := 8) -> void:
	SystemsDraw.rrect(self, Rect2(x, 30, 14, 14), 3.0, Color(col, 0.55))
	SystemsDraw.rrect_outline(self, Rect2(x, 30, 14, 14), 3.0, col, 1.0)
	_text(Vector2(x + 18, 41), label, px, "ExtraBold", Palette.TEXT_SECONDARY)


func _data(sim: Simulation) -> void:
	_text(Vector2(12, 18), "DATA", 10, "ExtraBold", Palette.TEXT_PRIMARY)
	_text(Vector2(W - 24, 18), "B", 10, "ExtraBold", Palette.TEXT_MUTED)
	_text(Vector2(64, 18), "%d wires" % sim.connections.size(), 10, "Medium", Palette.TEXT_SECONDARY)
	_swatch(12, Palette.DATA_NUMBER, "BITS")
	_swatch(100, Palette.FAMILY_IO, "RAW")
	_swatch(196, Palette.STATE_BLOCKED, "▲ BANDWIDTH", 7)
	_text(Vector2(12, 58), "lanes ×n · amber = saturated ≥ 50 % of 1 min", 8, "Medium", Palette.TEXT_MUTED)


func _flow(sim: Simulation) -> void:
	_text(Vector2(12, 18), "FLOW", 10, "ExtraBold", Palette.TEXT_PRIMARY)
	_text(Vector2(W - 24, 18), "F", 10, "ExtraBold", Palette.TEXT_MUTED)
	var bn := sim.bottleneck()
	_text(Vector2(64, 18), "bottleneck: %s" % (bn.label if bn != null else "none"), 10, "Medium", Palette.STATE_BLOCKED if bn != null else Palette.TEXT_SECONDARY)
	_swatch(12, Palette.STATE_VALID, "BUSY")
	_swatch(82, Palette.STATE_BLOCKED, "BLOCKED")
	_text(Vector2(170, 41), "wire = load", 8, "ExtraBold", Palette.TEXT_SECONDARY)
	_text(Vector2(12, 58), "share of the run each machine was busy", 8, "Medium", Palette.TEXT_MUTED)


func _power(sim: Simulation) -> void:
	var cap := sim.power_capacity()
	var dem := sim.power_demand()
	_text(Vector2(12, 18), "POWER", 10, "ExtraBold", Palette.TEXT_PRIMARY)
	_text(Vector2(W - 24, 18), "P", 10, "ExtraBold", Palette.TEXT_MUTED)
	if cap <= 0:
		_text(Vector2(64, 18), "demand %d" % dem, 10, "Medium", Palette.TEXT_SECONDARY)
		_text(Vector2(12, 40), "Unlimited power on this board", 10, "Medium", Palette.TEXT_SECONDARY)
		_text(Vector2(12, 54), "The PSU arrives with L16", 9, "Medium", Palette.TEXT_MUTED)
		return
	var over := dem > cap
	var near := not over and dem * 4 >= cap * 3
	var c := Palette.STATE_ERROR if over else (Palette.STATE_BLOCKED if near else Palette.TEXT_SECONDARY)
	_text(Vector2(64, 18), "%d / %d" % [dem, cap], 10, "ExtraBold", c)
	if over:
		_text(Vector2(130, 18), "brownout ×%.2f" % (float(cap) / float(dem)), 9, "Medium", Palette.STATE_ERROR)
	# the enlarged gauge fits the legend: 1 row up to 16 units, 2 up to 32, 3 for 64
	var rows := 1 if cap <= 16 else (2 if cap <= 32 else 3)
	var gh := rows * 9 + 6.0
	SystemsDraw.gauge(self, Vector2(12, 26 + (33.0 - gh) * 0.5), W - 40.0, cap, dem, rows)


func _compute(sim: Simulation) -> void:
	_text(Vector2(12, 18), "COMPUTE", 10, "ExtraBold", Palette.TEXT_PRIMARY)
	_text(Vector2(W - 24, 18), "C", 10, "ExtraBold", Palette.TEXT_MUTED)
	_swatch(12, Palette.FAMILY_COMPUTE, "LANES busy")
	_swatch(132, Palette.STATE_BLOCKED, "COMPUTE-BOUND")
	_text(Vector2(12, 58), "all lanes busy and inputs full ≥ 50 %", 8, "Medium", Palette.TEXT_MUTED)


func _network(sim: Simulation) -> void:
	_text(Vector2(12, 18), "NETWORK", 10, "ExtraBold", Palette.TEXT_PRIMARY)
	_text(Vector2(W - 24, 18), "W", 10, "ExtraBold", Palette.TEXT_MUTED)
	var best := _busiest_nic(sim)
	if best == null:
		_text(Vector2(64, 18), "no network card", 10, "Medium", Palette.TEXT_MUTED)
	else:
		_text(Vector2(64, 18), "%d/%d frames/s" % [NicLogic.load_per_sec(best), NicLogic.capacity(best)], 10, "ExtraBold", Palette.TEXT_PRIMARY)
	_swatch(12, Palette.DATA_NUMBER, "RX live")
	_swatch(100, Palette.STATE_BLOCKED, "TEST")
	_swatch(196, Palette.FAMILY_IO, "TX / sale", 7)
	_text(Vector2(12, 58), "channels that waited for credit turn red", 8, "Medium", Palette.TEXT_MUTED)


## The NIC with the highest load this second, null when the board has none.
func _busiest_nic(sim: Simulation) -> Machine:
	var best: Machine = null
	var best_load := -1
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type != "nic":
			continue
		var load := NicLogic.load_per_sec(m)
		if load > best_load:
			best_load = load
			best = m
	return best
