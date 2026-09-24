extends Control
## TopBar (Penpot 06 · TinyCompute / HUD / TopBar, 1920×52): mission pill, sim state badge,
## controls (reset/step/play), speed segmented, 3 metrics (right-anchored), menu button.

signal menu_pressed

const H := 52.0

var _mission_idx: Label
var _mission_title: Label
var _mission_formula: Label
var _state_box: Panel
var _state_dot: Panel
var _state_label: Label
var _btn_boxes := {}  # "reset"/"step"/"play" -> Panel
var _play_icon: TextureRect
var _speed_pill: Panel
var _speed_labels := []
var _metric := {}  # kind -> {box, value, unit}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = H
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := HudKit.box(self, Vector2.ZERO, Vector2(0, H), Palette.SURFACE_PANEL)
	bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bg.offset_bottom = H
	var rule := HudKit.box(self, Vector2(0, 51), Vector2(0, 1), Palette.SURFACE_BORDER)
	rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rule.offset_top = 51
	rule.offset_bottom = 52
	HudKit.icon(self, "icon_components", Vector2(18, 14), 24, Palette.DATA_NUMBER)

	# mission pill 58,8 300×36
	var pill := HudKit.box(self, Vector2(58, 8), Vector2(300, 36), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 18)
	_mission_idx = HudKit.label(pill, "01", Vector2(16, 10), 10, HudKit.W_MEDIUM, Palette.TEXT_MUTED)
	_mission_title = HudKit.label(pill, "", Vector2(40, 9), 12, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 128)
	_mission_formula = HudKit.label(pill, "", Vector2(170, 10), 11, HudKit.W_XBOLD, Palette.DATA_NUMBER, 96)
	HudKit.icon(pill, "icon_chevron_down", Vector2(272, 10), 16, Palette.TEXT_SECONDARY)

	# state badge 700,10 120×32
	_state_box = HudKit.box(self, Vector2(700, 10), Vector2(120, 32), Palette.SURFACE_SUNKEN, Palette.STATE_BUILD, 1.5, 16)
	_state_dot = HudKit.dot(_state_box, Vector2(18, 16), 7, Palette.STATE_BUILD)
	_state_label = HudKit.label(_state_box, "BUILD", Vector2(28, 9), 10, HudKit.W_XBOLD, Palette.STATE_BUILD)

	# controls 836,8 132×36: reset / step / play (36×36, 12 px gaps)
	var sm := _mgr()
	var names := ["reset", "step", "play"]
	var icons := ["icon_reset", "icon_step", "icon_play"]
	var acts := [func(): sm.reset_run(), func(): sm.step_once(), func(): sm.toggle()]
	for i in 3:
		var p := Vector2(836 + i * 48, 8)
		var b := HudKit.box(self, p, Vector2(36, 36), Palette.SURFACE_RAISED, Palette.SURFACE_BORDER, 1, 4)
		_btn_boxes[names[i]] = b
		var ic := HudKit.icon(b, icons[i], Vector2(6, 6), 24, Palette.TEXT_PRIMARY)
		if names[i] == "play":
			_play_icon = ic
		HudKit.hit(self, p, Vector2(36, 36), acts[i], ["Reset (Backspace)", "Step (.)", "Run / pause (Space)"][i])

	# speed segmented 984,10 120×32
	_speed_pill = HudKit.box(self, Vector2(984, 10), Vector2(120, 32), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 16)
	var speeds: Array = sm.SPEEDS
	for i in speeds.size():
		var s: int = speeds[i]
		var seg_pos := Vector2(4 + i * 28, 4)
		var seg := HudKit.box(_speed_pill, seg_pos, Vector2(28, 24), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12)
		var l := HudKit.label(seg, "%d×" % s, Vector2(0, 5), 10, HudKit.W_XBOLD, Palette.TEXT_MUTED, 28, HORIZONTAL_ALIGNMENT_CENTER)
		_speed_labels.append([seg, l, s])
		HudKit.hit(_speed_pill, seg_pos, Vector2(28, 24), func(): sm.set_speed(s), "Speed %d×" % s)

	# right group: metrics (−420/−304/−188 from the right edge) + menu (−56)
	var right := Control.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -420
	right.offset_right = 0
	right.offset_bottom = H
	var kinds := [["throughput", "icon_throughput", "/s"], ["power", "icon_power", ""], ["latency", "icon_latency", "t"]]
	for i in 3:
		var mb := HudKit.box(right, Vector2(i * 116, 8), Vector2(108, 36), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 18)
		var ic := HudKit.icon(mb, kinds[i][1], Vector2(12, 9), 18, Palette.TEXT_SECONDARY)
		var v := HudKit.label(mb, "—", Vector2(36, 9), 13, HudKit.W_XBOLD, Palette.TEXT_PRIMARY)
		var u := HudKit.label(mb, kinds[i][2], Vector2(80, 11), 10, HudKit.W_MEDIUM, Palette.TEXT_MUTED)
		_metric[kinds[i][0]] = {"box": mb, "value": v, "unit": u, "icon": ic}
	var menu := HudKit.box(right, Vector2(364, 8), Vector2(36, 36), Palette.SURFACE_RAISED, Palette.SURFACE_BORDER, 1, 4)
	HudKit.icon(menu, "icon_menu", Vector2(6, 6), 24, Palette.TEXT_PRIMARY)
	HudKit.hit(right, Vector2(364, 8), Vector2(36, 36), func(): menu_pressed.emit(), "Menu")

	sm.mission_loaded.connect(func(_d): _refresh_mission())
	_refresh_mission()


func _mgr() -> Node:
	return get_node("/root/SimulationManager")


func _refresh_mission() -> void:
	var d: MissionDef = _mgr().mission
	if d == null:
		return
	_mission_idx.text = "%02d" % (d.index + 1)
	_mission_title.text = d.title
	_mission_formula.text = d.formula
	# Title at its natural width (max 150), the formula takes the rest up to the chevron (x 264).
	var tw := minf(TclTheme.font(HudKit.W_XBOLD).get_string_size(d.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 150.0)
	_mission_title.size.x = tw
	_mission_formula.position.x = 40.0 + tw + 12.0
	_mission_formula.size.x = 264.0 - _mission_formula.position.x


func _process(_delta: float) -> void:
	var sm := _mgr()
	if sm.sim == null:
		return
	# state badge
	var st := HudKit.sim_state()
	var c := HudKit.state_color(st)
	HudKit.set_text(_state_label, st, c)
	HudKit.restyle(_state_box, Palette.SURFACE_SUNKEN, c, 1.5, 16)
	HudKit.restyle(_state_dot, c, Color(0, 0, 0, 0), 0, 7)
	# play/pause: the active control is lit
	_play_icon.texture = Art.icon("icon_pause" if sm.running else "icon_play")
	HudKit.restyle(_btn_boxes["play"], Palette.DATA_NUMBER_DIM if sm.running else Palette.SURFACE_RAISED,
		Palette.DATA_NUMBER if sm.running else Palette.SURFACE_BORDER, 1, 4)
	# speed
	for e in _speed_labels:
		var on: bool = e[2] == sm.speed
		HudKit.restyle(e[0], Palette.SURFACE_RAISED if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12)
		e[1].add_theme_color_override("font_color", Palette.TEXT_PRIMARY if on else Palette.TEXT_MUTED)
	# metrics
	var thr: float = sm.sim.throughput()
	var warn := false
	for g in sm.mission.goals:
		if g["kind"] == "throughput" and g.has("min") and sm.sim.tick > 0 and thr < float(g["min"]):
			warn = true
	var mt: Dictionary = _metric["throughput"]
	HudKit.set_text(mt["value"], "%.1f" % sm.real_rate(thr) if thr > 0.0 else "—", Palette.STATE_BLOCKED if warn else Palette.TEXT_PRIMARY)
	HudKit.restyle(mt["box"], Palette.SURFACE_SUNKEN, Palette.STATE_BLOCKED if warn else Color(0, 0, 0, 0), 1 if warn else 0, 18)
	HudKit.set_text(_metric["power"]["value"], str(sm.sim.total_power()))
	var lat: float = sm.sim.avg_latency()
	HudKit.set_text(_metric["latency"]["value"], "%d" % roundi(lat) if lat > 0.0 else "—")
