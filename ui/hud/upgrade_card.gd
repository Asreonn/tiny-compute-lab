extends Control
## Upgrade card (FACTORY_SYSTEMS §3.1 / §7.3): a 360 px panel for the selected, unlocked machine.
## One segmented row per upgrade axis (Width · Lanes · Clock · Efficiency), a live preview line
## from Simulation.upgrade_preview, and an APPLY button that commits every differing axis as one
## undo step. Opens from the quick bar's Upgrade button or the U key; closes on Esc, APPLY, a
## selection change or when the machine disappears. Drawn procedurally (no child Controls).

const WIDTH := 360.0
const ROW_H := 40.0
const SEG_H := 24.0
const SEG_GAP := 2.0
const SEG_X0 := 110.0
const SEG_X1 := 344.0
const BRACKET := 12.0  # world px the selection brackets reach past the footprint (quick bar)

var tools: Node
var upgrade_card: Control = null  # (mirrors quick_bar; unused here)

var _mid := -1
var _bound := false
var _chosen_width := 1
var _chosen_lanes := 1
var _chosen_clock := "normal"
var _chosen_eff := false
var _note := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(WIDTH, 154.0)
	visible = false


func _machine() -> Machine:
	var sm := get_node("/root/SimulationManager")
	if _mid < 0 or sm.sim == null or not sm.sim.machines.has(_mid):
		return null
	var m: Machine = sm.sim.machines[_mid]
	return null if m.locked else m


func _run():
	var sm := get_node("/root/SimulationManager")
	return sm.run


## Open the card for an unlocked machine, choosing its current values.
func open(mid: int) -> void:
	var sm := get_node("/root/SimulationManager")
	if tools == null or sm.sim == null or not sm.sim.machines.has(mid):
		return
	var m: Machine = sm.sim.machines[mid]
	if m.locked:
		return
	_mid = mid
	_chosen_width = m.width
	_chosen_lanes = m.lanes()
	_chosen_clock = m.clock_mode()
	_chosen_eff = m.efficient()
	_note = ""
	visible = true
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_U:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		if tools == null or tools.tool != "select" or tools.selected_machine < 0:
			return
		open(tools.selected_machine)
	elif k.keycode == KEY_ESCAPE:
		if visible:
			visible = false


func _on_selection(mid: int, _cid: int) -> void:
	if mid != _mid:
		visible = false


func _process(delta: float) -> void:
	if tools != null and not _bound:
		_bound = true
		tools.selection_changed.connect(_on_selection)
	if not visible:
		return
	var sm := get_node("/root/SimulationManager")
	if _mid < 0 or sm.sim == null or not sm.sim.machines.has(_mid):
		visible = false
		return
	var m: Machine = sm.sim.machines[_mid]
	if m.locked:
		visible = false
		return
	var n := _rows(m, sm.sim, _run()).size()
	size = Vector2(WIDTH, 114.0 + n * ROW_H)
	# anchored like the quick bar: centred under the footprint, 8 px below the quick bar
	var ct := get_viewport().get_canvas_transform()
	var fp := Rect2(Vector2(m.cell) * Palette.TILE, Vector2(Catalog.size_of(m.type, m.rot)) * Palette.TILE)
	var bottom_mid: Vector2 = ct * Vector2(fp.get_center().x, fp.end.y + BRACKET)
	var vp := get_viewport_rect().size
	var qb := Vector2(clampf(bottom_mid.x - 88.0, 8.0, vp.x - 184.0), clampf(bottom_mid.y + 8.0, 60.0, vp.y - 66.0))
	position = Vector2(clampf(bottom_mid.x - size.x * 0.5, 8.0, vp.x - size.x - 8.0), clampf(qb.y + 44.0, 60.0, vp.y - size.y - 8.0))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var m := _machine()
	if m == null:
		return
	var sm := get_node("/root/SimulationManager")
	var rows := _rows(m, sm.sim, _run())
	if event is InputEventMouseMotion:
		var pos := (event as InputEventMouseMotion).position
		var note := ""
		for ri in rows.size():
			var segs: Array = rows[ri]["segments"]
			for si in segs.size():
				if _seg_rect(ri, si, segs.size()).has_point(pos) and bool(segs[si]["locked"]):
					note = str(segs[si]["reason"])
		if note != _note:
			_note = note
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var pos := (event as InputEventMouseButton).position
		for ri in rows.size():
			var segs: Array = rows[ri]["segments"]
			for si in segs.size():
				if _seg_rect(ri, si, segs.size()).has_point(pos):
					var seg: Dictionary = segs[si]
					if not bool(seg["locked"]):
						_apply_chosen(str(rows[ri]["key"]), seg["value"])
						queue_redraw()
					return
		if _button_rect().has_point(pos) and not _change(m).is_empty():
			_apply()


func _apply_chosen(key: String, value: Variant) -> void:
	match key:
		"Width": _chosen_width = int(value)
		"Lanes": _chosen_lanes = int(value)
		"Clock": _chosen_clock = str(value)
		"Efficiency": _chosen_eff = bool(value)


func _change(m: Machine) -> Dictionary:
	var c := {}
	if _chosen_width != m.width:
		c["width"] = _chosen_width
	if _chosen_lanes != m.lanes():
		c["lanes"] = _chosen_lanes
	if _chosen_clock != m.clock_mode():
		c["clock"] = _chosen_clock
	if _chosen_eff != m.efficient():
		c["efficiency"] = _chosen_eff
	return c


func _apply() -> void:
	var sm := get_node("/root/SimulationManager")
	var sim: Simulation = sm.sim
	var m := _machine()
	if m == null or sim == null:
		return
	sm.request_edit()
	var ok := true
	if _chosen_width != m.width:
		sim.set_width(m.id, _chosen_width)
	if _chosen_lanes != m.lanes():
		if not sim.set_machine_lanes(m.id, _chosen_lanes):
			ok = false
	if _chosen_clock != m.clock_mode():
		if not sim.set_param(m.id, "clock", _chosen_clock):
			ok = false
	if _chosen_eff != m.efficient():
		if not sim.set_machine_efficiency(m.id, _chosen_eff):
			ok = false
	if ok:
		visible = false
	else:
		_note = str(sim.last_error)
		queue_redraw()


## A level index g is shown as "Unlocks at L%d · title" only when in the lab.
func _level_reason(level_idx: int) -> String:
	var sm := get_node("/root/SimulationManager")
	if sm.in_lab:
		return "Unlocks at L%d · %s" % [level_idx + 1, LabDef.level(level_idx)["title"]]
	return "Unlocks later"


func _rows(m: Machine, sim: Simulation, run) -> Array:
	var rows := []
	# Width: steps 3 / 5 / 8 / 16
	var wired := false
	for p in m.ports():
		if sim.connection_at_port(m.id, str(p["id"])) != null:
			wired = true
			break
	var max_allowed := maxi(sim.default_width, m.width)
	var wsegs := []
	for w in [3, 5, 8, 16]:
		var locked := false
		var reason := ""
		if w > max_allowed:
			locked = true
			reason = "Unlocks later"
		elif wired and w != m.width:
			locked = true
			reason = "Unwire to change the width"
		wsegs.append({"label": str(w), "value": w, "chosen": _chosen_width == w, "current": m.width == w, "locked": locked, "reason": reason})
	rows.append({"key": "Width", "segments": wsegs})
	# Lanes: only when the def allows more than one
	var max_lanes := int(m.def().get("max_lanes", 1))
	if max_lanes > 1:
		var gate := 8
		if run != null and run.has_method("max_lanes"):
			gate = int(run.max_lanes())
		var lsegs := []
		for l in [1, 2, 4, 8]:
			if l > max_lanes:
				continue
			var locked: bool = l > gate
			var reason := ""
			if locked:
				var g := [2, 4, 8].find(l)
				reason = _level_reason(int(LabDef.CONFIG.lane_levels[g]))
			lsegs.append({"label": str(l), "value": l, "chosen": _chosen_lanes == l, "current": m.lanes() == l, "locked": locked, "reason": reason})
		rows.append({"key": "Lanes", "segments": lsegs})
	# Clock: only when the def has a "clock" param
	if (m.def()["params"] as Dictionary).has("clock"):
		var clock_unlocked := false
		if run != null and run.has_method("clock_unlocked"):
			clock_unlocked = bool(run.clock_unlocked())
		var csegs := []
		for c in ["normal", "fast", "overclocked"]:
			var locked: bool = (not clock_unlocked) and c != m.clock_mode()
			csegs.append({"label": c, "value": c, "chosen": _chosen_clock == c, "current": m.clock_mode() == c, "locked": locked, "reason": "Unlocks later" if locked else ""})
		rows.append({"key": "Clock", "segments": csegs})
	# Efficiency: only when the def has an "efficiency" param
	if (m.def()["params"] as Dictionary).has("efficiency"):
		var eff_unlocked := false
		if run != null and run.has_method("efficiency_unlocked"):
			eff_unlocked = bool(run.efficiency_unlocked())
		var esegs := []
		for e in [false, true]:
			var locked: bool = e and not eff_unlocked
			var reason := ""
			if locked:
				reason = _level_reason(int(LabDef.CONFIG.efficiency_level))
			esegs.append({"label": "standard" if not e else "efficient", "value": e, "chosen": _chosen_eff == e, "current": m.efficient() == e, "locked": locked, "reason": reason})
		rows.append({"key": "Efficiency", "segments": esegs})
	return rows


func _rows_top() -> float:
	return 38.0


func _note_y(n: int) -> float:
	return _rows_top() + n * ROW_H + 14.0


func _preview_y(n: int) -> float:
	return _note_y(n) + 18.0


func _seg_rect(ri: int, si: int, n: int) -> Rect2:
	var total := SEG_X1 - SEG_X0
	var w := (total - SEG_GAP * (n - 1)) / float(n)
	var x := SEG_X0 + si * (w + SEG_GAP)
	var y := _rows_top() + ri * ROW_H + (ROW_H - SEG_H) * 0.5
	return Rect2(x, y, w, SEG_H)


func _button_rect() -> Rect2:
	return Rect2(size.x - 96.0 - 12.0, size.y - 28.0 - 12.0, 96.0, 28.0)


func _draw() -> void:
	var sm := get_node("/root/SimulationManager")
	var sim: Simulation = sm.sim
	var m := _machine()
	if m == null or sim == null:
		return
	var rows := _rows(m, sim, _run())
	var r := Rect2(Vector2.ZERO, size)
	for i in 3:
		var sh := r.grow(2.0 + i * 2.0)
		sh.position.y += 3.0
		SystemsDraw.rrect(self, sh, 10.0 + i * 2.0, Color(0, 0, 0, 0.10))
	SystemsDraw.rrect(self, r, 8.0, Palette.SURFACE_PANEL)
	SystemsDraw.rrect_outline(self, r, 8.0, Palette.SURFACE_BORDER_STRONG, 1.0)
	# title
	_text(Vector2(16, 22), "UPGRADE · %s" % str(m.def()["name"]), 11, "ExtraBold", Palette.TEXT_PRIMARY)
	# rows
	for ri in rows.size():
		_draw_row(rows[ri], ri)
	# one-line note (locked-step reason) under the rows
	if _note != "":
		_text(Vector2(16, _note_y(rows.size())), _note, 9, "Medium", Palette.TEXT_MUTED)
	# preview line
	var change := _change(m)
	if change.is_empty():
		_text(Vector2(16, _preview_y(rows.size())), "No change", 10, "Medium", Palette.TEXT_MUTED)
	else:
		_draw_preview(sim.upgrade_preview(m.id, change), _preview_y(rows.size()))
	# APPLY button
	var br := _button_rect()
	var disabled := change.is_empty()
	SystemsDraw.rrect(self, br, 6.0, Palette.SURFACE_RAISED if disabled else Color(Palette.STATE_BUILD, 0.9))
	var lb := TclTheme.font("ExtraBold").get_string_size("APPLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	draw_string(TclTheme.font("ExtraBold"), Vector2(br.get_center().x - lb.x * 0.5, br.get_center().y + 4), "APPLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.TEXT_MUTED if disabled else Palette.TEXT_PRIMARY)


func _draw_row(row: Dictionary, ri: int) -> void:
	_text(Vector2(16, _rows_top() + ri * ROW_H + 16), str(row["key"]), 9, "ExtraBold", Palette.TEXT_MUTED)
	var segs: Array = row["segments"]
	for si in segs.size():
		_draw_seg(_seg_rect(ri, si, segs.size()), segs[si])


func _draw_seg(rect: Rect2, seg: Dictionary) -> void:
	if bool(seg["chosen"]):
		SystemsDraw.rrect(self, rect, 4.0, Color(Palette.STATE_BUILD, 0.22))
		SystemsDraw.rrect_outline(self, rect, 4.0, Palette.STATE_BUILD, 1.0)
	else:
		SystemsDraw.rrect(self, rect, 4.0, Palette.SURFACE_SUNKEN)
		SystemsDraw.rrect_outline(self, rect, 4.0, Palette.SURFACE_BORDER, 1.0)
	var locked := bool(seg["locked"])
	var col := Palette.TEXT_PRIMARY if bool(seg["chosen"]) else (Palette.TEXT_MUTED if locked else Palette.TEXT_SECONDARY)
	var label := str(seg["label"])
	var f := TclTheme.font("Medium")
	var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var lx := rect.get_center().x - lw * 0.5
	draw_string(f, Vector2(lx, rect.get_center().y + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	if locked:
		var t := Art.icon("icon_lock")
		if t != null:
			draw_texture_rect(t, Rect2(lx + lw + 2, rect.get_center().y - 5, 10, 10), false, Palette.TEXT_MUTED)
	elif bool(seg["current"]):
		draw_circle(Vector2(rect.get_center().x, rect.get_center().y + 8), 1.5, Palette.TEXT_MUTED)


func _draw_preview(p: Dictionary, y: float) -> void:
	var parts := [
		["Rate ", Palette.TEXT_PRIMARY],
		["%.1f" % float(p["rate_before"]), Palette.TEXT_PRIMARY],
		[" → ", Palette.TEXT_PRIMARY],
		["%.1f" % float(p["rate_after"]), Palette.STATE_VALID if float(p["rate_after"]) > float(p["rate_before"]) else Palette.TEXT_PRIMARY],
		[" /s · Power ", Palette.TEXT_PRIMARY],
		[str(int(p["power_before"])), Palette.TEXT_PRIMARY],
		[" → ", Palette.TEXT_PRIMARY],
		[str(int(p["power_after"])), Palette.STATE_BLOCKED if int(p["power_after"]) > int(p["power_before"]) else Palette.TEXT_PRIMARY],
		[" · Heat ", Palette.TEXT_PRIMARY],
		[str(int(p["heat_before"])), Palette.TEXT_PRIMARY],
		[" → ", Palette.TEXT_PRIMARY],
		[str(int(p["heat_after"])), Palette.STATE_BLOCKED if int(p["heat_after"]) > int(p["heat_before"]) else Palette.TEXT_PRIMARY],
	]
	var x := 16.0
	for part in parts:
		var s: String = part[0]
		var f := TclTheme.font("Medium")
		draw_string(f, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, part[1])
		x += f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x


func _text(pos: Vector2, s: String, px: int, weight: String, c: Color, width := -1.0) -> void:
	draw_string(TclTheme.font(weight), pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, px, c)