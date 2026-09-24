extends Control
## Overlay legend (VISUAL_SYSTEM §21.2): a 264x64 panel at the top right while the thermal (T) or
## power (P) overlay is shown. Thermal: the four stage swatches; power: the PSU gauge enlarged
## with demand / capacity. It steps left of the Inspector while a machine is selected.

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
	var tools := get_tree().get_first_node_in_group("tools")
	var inspector_open: bool = tools != null and int(tools.get("selected_machine")) >= 0
	var vw := get_viewport_rect().size.x
	position = Vector2(vw - W - 16.0 - (308.0 if inspector_open else 0.0), 68.0)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(W, H))
	SystemsDraw.rrect(self, r, 8.0, Palette.SURFACE_PANEL)
	SystemsDraw.rrect_outline(self, r, 8.0, Palette.SURFACE_BORDER_STRONG, 1.0)
	var sim: Simulation = get_node("/root/SimulationManager").sim
	if sim == null:
		return
	if _kind == "thermal":
		_thermal(sim)
	elif _kind == "power":
		_power(sim)


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
