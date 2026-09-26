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
var _play_running := false
var _speed_pill: Panel
var _speed_sel: Panel
var _speed_labels := []  # [Label, speed]
var _speed_tw: Tween
var _metric := {}  # kind -> {box, value, unit}
var _metric_last := {}  # kind -> float target, to detect change for the roll
var _metric_shown := {}  # kind -> true once its label shows the current target
var _power_cap := 0  # PSU capacity shown next to the demand; 0 = no PSU (plain demand)
var _state_c := Palette.STATE_BUILD
var _last_state := ""
var _breathe_tw: Tween
var _state_tw: Tween
var _power_chip: Panel
var _power_chip_label: Label
var _power_chip_text := ""
var _power_chip_last_vw := -1.0


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
	HudKit.hit(self, Vector2(58, 8), Vector2(300, 36), func(): menu_pressed.emit(), "Open menu")

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
		var b := HudKit.icon_button(self, p, Vector2(36, 36), icons[i], Vector2(6, 6), 24, acts[i], ["Reset (Backspace)", "Step (.)", "Run / pause (Space)"][i], 4)
		_btn_boxes[names[i]] = b
		if names[i] == "play":
			_play_icon = b.get_meta("ib_icon")

	# speed segmented 984,10 120×32: one sliding selection pill behind 4 static labels
	_speed_pill = HudKit.box(self, Vector2(984, 10), Vector2(120, 32), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 16)
	_speed_sel = HudKit.box(_speed_pill, Vector2.ZERO, Vector2(28, 24), Palette.SURFACE_RAISED, Palette.SURFACE_BORDER_STRONG, 1, 12)
	_speed_sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var speeds: Array = sm.SPEEDS
	for i in speeds.size():
		var s: int = speeds[i]
		var seg_pos := Vector2(4 + i * 28, 4)
		var l := HudKit.label(_speed_pill, "%d×" % s, seg_pos + Vector2(0, 5), 10, HudKit.W_XBOLD, Palette.TEXT_MUTED, 28, HORIZONTAL_ALIGNMENT_CENTER)
		_speed_labels.append([l, s])
		HudKit.hit(_speed_pill, seg_pos, Vector2(28, 24), func(): sm.set_speed(s), "Speed %d×" % s)
	_position_speed_pill(sm.speed, true)
	sm.speed_changed.connect(_on_speed)

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
	_metric["throughput"]["display"] = func(vf: float): _metric["throughput"]["value"].text = ("%.1f" % vf) if vf >= 0.0 else "—"
	_metric["power"]["display"] = func(vf: float): _metric["power"]["value"].text = _power_text(roundi(vf))
	_metric["latency"]["display"] = func(vf: float): _metric["latency"]["value"].text = ("%d" % roundi(vf)) if vf >= 0.0 else "—"
	# overload chip: the worst overloaded power node, 8 px right of the power value (hidden
	# until a node is over; only its text and glue position change in _process)
	_power_chip = HudKit.box(right, Vector2.ZERO, Vector2(0, 18), Palette.SURFACE_SUNKEN, Color(Palette.STATE_ERROR, 0.6), 1, 9)
	_power_chip_label = HudKit.label(_power_chip, "", Vector2(8, 3), 9, HudKit.W_XBOLD, Palette.STATE_ERROR)
	_power_chip.visible = false
	HudKit.icon_button(right, Vector2(364, 8), Vector2(36, 36), "icon_menu", Vector2(6, 6), 24, func(): menu_pressed.emit(), "Menu", 4)


	sm.mission_loaded.connect(func(_d): _refresh_mission())
	_refresh_mission()


func _mgr() -> Node:
	return get_node("/root/SimulationManager")


func _refresh_mission() -> void:
	var sm := _mgr()
	if sm.in_lab and sm.lab_run != null:
		var lr: LabRun = sm.lab_run
		_mission_idx.text = "∞" if lr.all_done() else "Q%d" % (lr.level + 1)
		_mission_title.text = lr.title()
		_mission_formula.text = "→ %d × %s" % [lr.request_count(), HudKit.fmt(lr.request_bits())]
		var twl := minf(TclTheme.font(HudKit.W_XBOLD).get_string_size(lr.title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 128.0)
		_mission_title.size.x = twl
		_mission_formula.position.x = 40.0 + twl + 12.0
		_mission_formula.size.x = 264.0 - _mission_formula.position.x
		return
	var d: MissionDef = sm.mission
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


func _on_speed(s: int) -> void:
	_position_speed_pill(s, false)


func _position_speed_pill(s: int, snap: bool) -> void:
	var idx := 0
	for i in _speed_labels.size():
		if _speed_labels[i][1] == s:
			idx = i
			break
	var x := 4.0 + idx * 28.0
	HudKit.kill(_speed_tw)
	for e in _speed_labels:
		var on: bool = e[1] == s
		e[0].add_theme_color_override("font_color", Palette.TEXT_PRIMARY if on else Palette.TEXT_MUTED)
	if HudKit.REDUCED_MOTION or snap:
		_speed_sel.position.x = x
		_speed_sel.size.x = 28.0
		return
	_speed_tw = HudKit.anim(self)
	_speed_tw.tween_property(_speed_sel, "position:x", x, 0.18)
	_speed_tw.parallel().tween_property(_speed_sel, "size:x", 28.0, 0.18)
	for e in _speed_labels:
		var on: bool = e[1] == s
		var target := Palette.TEXT_PRIMARY if on else Palette.TEXT_MUTED
		var from := Palette.TEXT_MUTED if on else Palette.TEXT_PRIMARY
		var l: Label = e[0]
		HudKit.kill_meta(l, "sp_tw")
		var tw := HudKit.anim(self)
		l.set_meta("sp_tw", tw)
		tw.tween_method(func(t: float): _apply_speed_color(l, from, target, t), 0.0, 1.0, 0.12)


func _apply_speed_color(l: Label, from: Color, to: Color, t: float) -> void:
	l.add_theme_color_override("font_color", from.lerp(to, t))


func _process(_delta: float) -> void:
	var sm := _mgr()
	if sm.sim == null:
		return
	# state badge: colour cross-fade 200 ms on change + RUNNING dot breathe
	var st := HudKit.sim_state()
	var c := HudKit.state_color(st)
	if st != _last_state:
		_last_state = st
		HudKit.set_text(_state_label, st, c)
		_cross_fade_state(c)
	_update_breathe(sm.running)
	# play/pause: the active control is lit (event-driven, so hover still works at rest)
	if sm.running != _play_running:
		_play_running = sm.running
		_play_icon.texture = Art.icon("icon_pause" if _play_running else "icon_play")
		var sb: StyleBoxFlat = _btn_boxes["play"].get_meta("sb")
		HudKit.kill_meta(_btn_boxes["play"], "ib_hover_tw")
		if _play_running:
			sb.bg_color = Palette.DATA_NUMBER_DIM
			sb.border_color = Palette.DATA_NUMBER
			sb.set_border_width_all(1)
			_play_icon.modulate = Palette.TEXT_PRIMARY
		else:
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color(0, 0, 0, 0)
			sb.set_border_width_all(0)
			_play_icon.modulate = Palette.TEXT_SECONDARY
	# metrics
	var thr: float = sm.sim.throughput()
	var warn := false
	for g in sm.mission.goals:
		if g["kind"] == "throughput" and g.has("min") and sm.sim.tick > 0 and thr < float(g["min"]):
			warn = true
	var mt: Dictionary = _metric["throughput"]
	_roll_metric("throughput", sm.real_rate(thr) if thr > 0.0 else -1.0)
	HudKit.set_color(mt["value"], Palette.STATE_BLOCKED if warn else Palette.TEXT_PRIMARY)
	HudKit.restyle(mt["box"], Palette.SURFACE_SUNKEN, Palette.STATE_BLOCKED if warn else Color(0, 0, 0, 0), 1 if warn else 0, 18)
	# power: demand, or demand/capacity once the Lab has a PSU (amber near capacity, red when
	# overloaded — a brownout; SYSTEMS_EXPANSION §4)
	var cap: int = sm.sim.power_capacity()
	var dem: int = sm.sim.power_demand()
	if cap != _power_cap:
		_metric_shown.erase("power")  # the label shows demand/capacity: redraw it
	_power_cap = cap
	_roll_metric("power", float(dem))
	var pc := Color(0, 0, 0, 0)
	if cap > 0 and dem > cap:
		pc = Palette.STATE_ERROR
	elif cap > 0 and dem * 4 >= cap * 3:
		pc = Palette.STATE_BLOCKED
	var pm: Dictionary = _metric["power"]
	HudKit.set_color(pm["value"], pc if pc.a > 0.0 else Palette.TEXT_PRIMARY)
	pm["icon"].modulate = pc if pc.a > 0.0 else Palette.TEXT_SECONDARY
	HudKit.restyle(pm["box"], Palette.SURFACE_SUNKEN, pc, 1 if pc.a > 0.0 else 0, 18)
	# overload chip: the worst overloaded power node, 8 px right of the power value (hidden
	# when nothing is over). Built once in _ready; updated only when its text changes.
	var chip_txt := ""
	if sm.sim.power_net != null:
		var worst := _worst_power_node(sm.sim)
		if not worst.is_empty():
			chip_txt = "%s %d/%d" % [_node_name(str(worst["id"])), int(worst["load"]), int(worst["cap"])]
	var vw := TclTheme.font(HudKit.W_XBOLD).get_string_size(pm["value"].text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	if chip_txt != _power_chip_text or vw != _power_chip_last_vw:
		_power_chip_text = chip_txt
		_power_chip_last_vw = vw
		if chip_txt == "":
			_power_chip.visible = false
		else:
			_power_chip.visible = true
			_power_chip_label.text = chip_txt
			_power_chip.size.x = TclTheme.font(HudKit.W_XBOLD).get_string_size(chip_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 16.0
			_power_chip.position = Vector2(pm["box"].position.x + pm["value"].position.x + vw + 8.0, pm["box"].position.y + (pm["box"].size.y - 18.0) / 2.0)
	var lat: float = sm.sim.avg_latency()
	_roll_metric("latency", lat if lat > 0.0 else -1.0)


func _power_text(v: int) -> String:
	if _power_cap <= 0:
		return str(v)
	return "%d/%d" % [v, _power_cap]


## The worst overloaded power node: the highest load / cap among the nodes with cap > 0 and
## load > cap (ties go to the first in ascending id order). {} when nothing is over.
func _worst_power_node(sim: Simulation) -> Dictionary:
	var best := {}
	var best_ratio := -1.0
	var best_id := ""
	for nid in sim.power_net.nodes:
		var n: Dictionary = sim.power_net.nodes[nid]
		var cap := int(n["cap"])
		var load := int(n["load"])
		if cap <= 0 or load <= cap:
			continue
		var ratio := float(load) / float(cap)
		if ratio > best_ratio or (is_equal_approx(ratio, best_ratio) and nid < best_id):
			best_ratio = ratio
			best_id = nid
			best = {"id": nid, "load": load, "cap": cap}
	return best


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


func _roll_metric(kind: String, target: float) -> void:
	if _metric_last.has(kind) and _metric_last[kind] == target and _metric_shown.has(kind):
		return  # unchanged: the label already shows it
	var last: float = _metric_last.get(kind, target)
	_metric_last[kind] = target
	_metric_shown[kind] = true
	HudKit.roll_value(self, "roll_" + kind, last, target, _metric[kind]["display"])


func _cross_fade_state(c: Color) -> void:
	HudKit.kill(_state_tw)
	var sb: StyleBoxFlat = _state_box.get_meta("sb")
	var dot_sb: StyleBoxFlat = _state_dot.get_meta("sb")
	var from: Color = sb.border_color
	var from_label: Color = _state_label.get_theme_color("font_color")
	_state_c = c
	sb.bg_color = Palette.SURFACE_SUNKEN
	sb.set_border_width_all(2)
	if HudKit.REDUCED_MOTION:
		sb.border_color = c
		dot_sb.bg_color = c
		_state_label.add_theme_color_override("font_color", c)
		return
	_state_tw = HudKit.anim(self)
	_state_tw.tween_method(func(t: float):
		var col := from.lerp(c, t)
		sb.border_color = col
		dot_sb.bg_color = col
		_state_label.add_theme_color_override("font_color", from_label.lerp(c, t)), 0.0, 1.0, 0.2)


func _update_breathe(running: bool) -> void:
	if running and _breathe_tw == null:
		_breathe_tw = self.create_tween().set_loops()
		_breathe_tw.tween_property(_state_dot, "modulate:a", 0.6, 0.8).set_trans(Tween.TRANS_SINE)
		_breathe_tw.tween_property(_state_dot, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
	elif not running:
		HudKit.kill(_breathe_tw)
		_breathe_tw = null
		_state_dot.modulate.a = 1.0
