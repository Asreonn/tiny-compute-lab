extends Control
## MissionSummary (Penpot 06, 320×232 expanded / 300×36 collapsed, bottom-left, 16 px margins).
## Input and output cells show the mission values in the current view mode (3-bit BIN: 010).
## Output cells: pending = sunken/muted, correct = green stroke, wrong = red stroke.

const W := 320.0
const H := 232.0

var _expanded := true
var _root: Control
var _out_cells := []  # [Panel, Label]
var _track_fill: Panel
var _progress: Label
var _last: Label  # "Last: , ✗  expected C" or the stall warning
var _rejected: Label
## Lab contract rows (NEEDS / OUTPUT / RATE / LOST), refreshed every frame in _lab_refresh.
var _rows: Array = []  # [key, Label]
var _last_done := -1  # for the delivered-count roll


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	var sm := get_node("/root/SimulationManager")
	sm.mission_loaded.connect(func(_d): _rebuild())
	sm.view_mode_changed.connect(func(_m): _rebuild())
	sm.ticked.connect(func(_t): _refresh())
	_rebuild()


func _mgr() -> Node:
	return get_node("/root/SimulationManager")


func _rebuild() -> void:
	if _root:
		_root.queue_free()
	_out_cells.clear()
	var sm := _mgr()
	var d: MissionDef = sm.mission
	if d == null:
		return
	if sm.in_lab and sm.lab_run != null:
		_lab_rebuild(sm)
		return
	var h := H if _expanded else 36.0
	var w := W if _expanded else 300.0
	offset_left = 16
	offset_top = -16 - h
	offset_right = 16 + w
	offset_bottom = -16
	_root = HudKit.box(self, Vector2.ZERO, Vector2(w, h), Palette.SURFACE_PANEL, Palette.SURFACE_BORDER, 1, 10)
	var title := "%02d · %s" % [d.index + 1, d.title]
	if not _expanded:
		HudKit.label(_root, title, Vector2(16, 10), 12, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 240)
		HudKit.icon(_root, "icon_chevron_right", Vector2(268, 10), 16, Palette.TEXT_MUTED)
		HudKit.hit(_root, Vector2.ZERO, Vector2(w, h), _toggle, "Show mission")
		HudKit.panel_show(self, Vector2(0, 12), 0.18)
		return
	HudKit.label(_root, title, Vector2(18, 16), 14, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 260)
	HudKit.icon(_root, "icon_chevron_down", Vector2(286, 14), 20, Palette.TEXT_MUTED)
	HudKit.hit(_root, Vector2(280, 8), Vector2(32, 32), _toggle, "Collapse")
	var brief := HudKit.label(_root, "", Vector2(18, 40), 11, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size = Vector2(284, 0)
	brief.size = Vector2(284, 30)
	brief.text = d.brief
	var fbox := HudKit.box(_root, Vector2(18, 72), Vector2(284, 30), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 6)
	HudKit.label(fbox, d.formula, Vector2(0, 7), 12, HudKit.W_XBOLD, Palette.DATA_NUMBER, 284, HORIZONTAL_ALIGNMENT_CENTER)
	# input row (y 116) and output row (y 142)
	if not d.inputs.is_empty():
		var inp: Dictionary = d.inputs[0]
		_cells(inp["values"], int(inp.get("width", d.default_width)), 116.0, false)
	if not d.outputs.is_empty():
		var outp: Dictionary = d.outputs[0]
		_cells(outp["expected"], int(outp.get("width", d.default_width)), 142.0, true)
	HudKit.box(_root, Vector2(18, 176), Vector2(284, 4), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 2)
	_track_fill = HudKit.box(_root, Vector2(18, 176), Vector2(0, 4), Palette.STATE_VALID, Color(0, 0, 0, 0), 0, 2)
	_progress = HudKit.label(_root, "", Vector2(18, 188), 11, HudKit.W_XBOLD, Palette.TEXT_PRIMARY)
	_last = HudKit.label(_root, "", Vector2(18, 208), 10, HudKit.W_MEDIUM, Palette.TEXT_MUTED, 284)
	if not d.goals.is_empty():
		HudKit.icon(_root, "icon_star_empty", Vector2(150, 188), 16, Palette.TEXT_SECONDARY)
		HudKit.label(_root, "%d optional goal%s" % [d.goals.size(), "" if d.goals.size() == 1 else "s"], Vector2(172, 189), 10, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
	_refresh()
	HudKit.panel_show(self, Vector2(0, 12), 0.18)


func _cells(values: Array, width: int, y: float, is_output: bool) -> void:
	var x := 18.0
	var f := TclTheme.font(HudKit.W_BOLD)
	for i in values.size():
		var text := HudKit.fmt(MissionDef.to_bits(values[i], width))
		var cw := maxf(30.0, f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 12.0)
		if x + cw > 302.0:
			var more := HudKit.box(_root, Vector2(x, y), Vector2(30, 20), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 4)
			HudKit.label(more, "…", Vector2(0, 3), 10, HudKit.W_BOLD, Palette.TEXT_MUTED, 30, HORIZONTAL_ALIGNMENT_CENTER)
			break
		var c := HudKit.box(_root, Vector2(x, y), Vector2(cw, 20), Palette.SURFACE_RAISED, Palette.SURFACE_BORDER_STRONG, 1, 4)
		var l := HudKit.label(c, text, Vector2(0, 3), 10, HudKit.W_BOLD, Palette.TEXT_PRIMARY, cw, HORIZONTAL_ALIGNMENT_CENTER)
		if is_output:
			_out_cells.append([c, l])
		x += cw + 6.0


func _toggle() -> void:
	_expanded = not _expanded
	_rebuild()


## Lab layout: QUEST CARDS. One card per active quest (Q6 · title, request, progress); the
## focused card (click a card) also shows its brief and NEEDS / OUTPUT / RATE / LOST rows. A
## filled quest turns green and says how to file it (the desk's COMPLETED tray).
const CARD_W := 300.0
const CARD_H := 56.0
var _focus := -1  # the expanded quest (-1: the lowest active one)
var _cards: Array = []  # [q, Panel card, Label status, Panel bar fill, Label request]


func _lab_rebuild(sm: Node) -> void:
	var lr: LabRun = sm.lab_run
	_cards.clear()
	_rows.clear()
	var quests := lr.active_quests()
	if not _focus in quests:
		_focus = quests[0] if not quests.is_empty() else -1
	var n_rows := _row_keys(lr, _focus).size() if _focus >= 0 else 0
	var focus_h := 88.0 + n_rows * 13.0 + 20.0
	var h := 38.0 + (quests.size() - 1) * (CARD_H + 8.0) + (focus_h if _focus >= 0 else 64.0) + 10.0
	offset_left = 16
	offset_top = -16 - h
	offset_right = 16 + 320.0
	offset_bottom = -16
	_root = HudKit.box(self, Vector2.ZERO, Vector2(320.0, h), Palette.SURFACE_PANEL, Palette.SURFACE_BORDER, 1, 10)
	HudKit.label(_root, "QUESTS", Vector2(18, 13), 9, HudKit.W_XBOLD, Palette.TEXT_MUTED)
	HudKit.label(_root, "%d done" % lr.files, Vector2(200, 13), 9, HudKit.W_MEDIUM, Palette.TEXT_MUTED, 102, HORIZONTAL_ALIGNMENT_RIGHT)
	var y := 32.0
	if quests.is_empty():
		var free := HudKit.box(_root, Vector2(10, y), Vector2(CARD_W, 64), Palette.SURFACE_RAISED, Palette.STATE_SUCCESS, 1, 8)
		HudKit.label(free, "Free Build", Vector2(12, 10), 13, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 276)
		HudKit.label(free, "Every quest is filed — the Lab is yours.", Vector2(12, 34), 10, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY, 276)
		_progress = null
		HudKit.panel_show(self, Vector2(0, 12), 0.18)
		return
	for q in quests:
		var focused: bool = q == _focus
		var ch := focus_h if focused else CARD_H
		var card := HudKit.box(_root, Vector2(10, y), Vector2(CARD_W, ch), Palette.SURFACE_RAISED, Palette.SURFACE_BORDER_STRONG if focused else Palette.SURFACE_BORDER, 1, 8)
		var tag := HudKit.box(card, Vector2(10, 8), Vector2(30, 18), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 4)
		HudKit.label(tag, "Q%d" % (q + 1), Vector2(0, 2), 10, HudKit.W_XBOLD, Palette.TEXT_SECONDARY, 30, HORIZONTAL_ALIGNMENT_CENTER)
		HudKit.label(card, lr.quest_title(q), Vector2(48, 8), 12, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 150)
		var status := HudKit.label(card, "", Vector2(186, 10), 10, HudKit.W_BOLD, Palette.TEXT_SECONDARY, 104, HORIZONTAL_ALIGNMENT_RIGHT)
		var c := lr.quest_contract(q)
		var req := HudKit.label(card, _request_text(q, c), Vector2(12, 29), 10, HudKit.W_BOLD, Palette.FAMILY_IO if c.accept_format != "bits" else Palette.DATA_NUMBER, 276)
		HudKit.box(card, Vector2(12, 46), Vector2(276, 3), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 2)
		var fill := HudKit.box(card, Vector2(12, 46), Vector2(0, 3), Palette.STATE_VALID, Color(0, 0, 0, 0), 0, 2)
		_cards.append([q, card, status, fill, req])
		if focused:
			var brief := HudKit.label(card, str(LabDef.level(q).get("brief", "")), Vector2(12, 56), 10, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
			brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			brief.custom_minimum_size = Vector2(276, 0)
			brief.size = Vector2(276, 26)
			var keys := _row_keys(lr, q)
			for i in keys.size():
				var ry := 88.0 + i * 13.0
				HudKit.label(card, keys[i].to_upper(), Vector2(12, ry), 9, HudKit.W_XBOLD, Palette.TEXT_MUTED, 60)
				_rows.append([keys[i], HudKit.label(card, "", Vector2(72, ry), 10, HudKit.W_BOLD, Palette.TEXT_SECONDARY, 216)])
			_last = HudKit.label(card, "", Vector2(12, 88.0 + keys.size() * 13.0 + 2.0), 10, HudKit.W_MEDIUM, Palette.STATE_BLOCKED, 276)
		else:
			var qq: int = q
			HudKit.hit(card, Vector2.ZERO, Vector2(CARD_W, ch), func():
				_focus = qq
				_rebuild(), "Show this quest")
		y += ch + 8.0
	_progress = _cards[0][2]
	_refresh()
	HudKit.panel_show(self, Vector2(0, 12), 0.18)


func _request_text(q: int, c: Contract) -> String:
	if c.kind == "deliver":
		var want := LabDef.request_bits(q)
		return "DELIVER  %s  × %d   (%d-bit)" % [HudKit.fmt(want), c.count, want.width]
	return "%s  %s  × %d" % [c.kind.to_upper(), c.describe(), c.count]


func _row_keys(lr: LabRun, q: int) -> Array:
	var c := lr.quest_contract(q)
	var keys := ["needs", "output"]
	if c.min_rate > 0.0:
		keys.append("rate")
	if c.max_lost >= 0:
		keys.append("lost")
	return keys


func lr_brief(lr: LabRun) -> String:
	var lv: Dictionary = LabDef.level(lr.level)
	return str(lv.get("brief", ""))


func _refresh() -> void:
	var sm := _mgr()
	if sm.run == null or not _expanded or _progress == null:
		return
	if sm.in_lab and sm.lab_run != null:
		_lab_refresh(sm)
		return
	var d: MissionDef = sm.mission
	var done: int = sm.run.progress[0] if not sm.run.progress.is_empty() else 0
	var lo: Dictionary = sm.run.last_ok[0] if not sm.run.last_ok.is_empty() else {}
	var failed: bool = sm.run.status == MissionRun.Status.FAIL or (not lo.is_empty() and not bool(lo.get("ok", true)))
	for i in _out_cells.size():
		var c: Panel = _out_cells[i][0]
		var l: Label = _out_cells[i][1]
		if i < done:
			HudKit.restyle(c, Palette.SURFACE_RAISED, Palette.STATE_VALID, 1, 4)
			l.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
		elif failed and i == done:
			HudKit.restyle(c, Palette.SURFACE_RAISED, Palette.STATE_ERROR, 1, 4)
			l.add_theme_color_override("font_color", Palette.STATE_ERROR)
		else:
			HudKit.restyle(c, Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 4)
			l.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	var total := maxi(d.expected_total(), 1)
	var correct: int = sm.run.correct_total()
	HudKit.progress_bar(_track_fill, 284.0 * correct / total)
	_roll_done(correct, d.expected_total())
	# Last arrival (rejected values are shown, never fatal) or the stall warning.
	if sm.run.warning != "":
		HudKit.set_text(_last, "⚠ " + sm.run.warning, Palette.STATE_BLOCKED)
	elif not lo.is_empty() and not bool(lo.get("ok", true)):
		var got := "—"
		for mid in sm.sim.sorted_machine_ids():
			var m: Machine = sm.sim.machines[mid]
			if m.channel == 0 and m.type in ["output", "terminal_output"] and not m.received.is_empty():
				var last: Packet = m.received[m.received.size() - 1]
				got = last.raw.glyph() if last.is_raw() else HudKit.fmt(last.data)
		var want := HudKit.fmt(sm.run.expected_bits[0][mini(done, sm.run.expected_bits[0].size() - 1)])
		HudKit.set_text(_last, "Last: %s ✗   expected %s" % [got, want], Palette.STATE_ERROR)
	else:
		HudKit.set_text(_last, "", Palette.TEXT_MUTED)


func _roll_done(done: int, total: int) -> void:
	if done == _last_done:
		_progress.text = "%d / %d" % [done, total]
		return
	var from: int = maxi(_last_done, 0)
	_last_done = done
	if HudKit.REDUCED_MOTION or done <= from:
		_progress.text = "%d / %d" % [done, total]
		return
	HudKit.roll_value(self, "roll_done", float(from), float(done),
		func(v: float): _progress.text = "%d / %d" % [roundi(v), total])


func _lab_refresh(sm: Node) -> void:
	var lr: LabRun = sm.lab_run
	for e in _cards:
		var q: int = e[0]
		var qp := lr.quest_progress(q)
		var n := lr.quest_contract(q).count
		var card: Panel = e[1]
		HudKit.progress_bar(e[3], 276.0 * lr.quest_fill(q))
		if qp.filled:
			HudKit.set_text(e[2], "✓ READY", Palette.STATE_SUCCESS)
			HudKit.restyle(card, Palette.SURFACE_RAISED, Palette.STATE_SUCCESS, 1.5, 8)
		else:
			var rj := "  · %d ✗" % qp.rejected if qp.rejected > 0 else ""
			HudKit.set_text(e[2], "%d / %d%s" % [qp.delivered, n, rj], Palette.TEXT_PRIMARY)
	if _focus < 0:
		return
	_refresh_rows(sm, lr)
	var w := lr.quest_progress(_focus).warning
	if w == "" and _focus == lr.level:
		w = lr.warning
	if lr.quest_progress(_focus).filled:
		HudKit.set_text(_last, "", Palette.STATE_BLOCKED)
	elif w != "":
		HudKit.set_text(_last, "⚠ " + w, Palette.STATE_BLOCKED)
	else:
		HudKit.set_text(_last, "", Palette.STATE_BLOCKED)


## NEEDS / OUTPUT / RATE / LOST rows of the focused quest, in plain words. A filled quest says how
## to file it instead.
func _refresh_rows(sm: Node, lr: LabRun) -> void:
	var q := _focus
	var c := lr.quest_contract(q)
	var qp := lr.quest_progress(q)
	for r in _rows:
		var key: String = r[0]
		var l: Label = r[1]
		if qp.filled:
			HudKit.set_text(l, "✓ Drop the Q%d Job stick in COMPLETED" % (q + 1) if key == "needs" else "", Palette.STATE_SUCCESS)
			continue
		match key:
			"needs":
				var missing := PackedStringArray()
				var places := lr.quest_stick_places(sm.sim, q)
				for st in places:
					if int(places[st]) < 0:
						missing.append(Devices.display_name(st).replace(" module", ""))
				if places.is_empty():
					HudKit.set_text(l, "—", Palette.TEXT_MUTED)
				elif missing.is_empty():
					HudKit.set_text(l, "✓ Q%d stick%s plugged in" % [q + 1, "s" if places.size() > 1 else ""], Palette.STATE_VALID)
				else:
					HudKit.set_text(l, "Plug the Q%d %s stick into a USB port" % [q + 1, " + ".join(missing)], Palette.STATE_BLOCKED)
			"output":
				if lr.quest_job_plugged(sm.sim, q):
					HudKit.set_text(l, "✓ Q%d Job stick plugged in" % (q + 1), Palette.STATE_VALID)
				else:
					HudKit.set_text(l, "Plug the Q%d Job stick into an output port" % (q + 1), Palette.STATE_BLOCKED)
			"rate":
				var rt := lr.quest_rate(q)
				HudKit.set_text(l, "%.1f / %.1f values/s" % [rt, c.min_rate], Palette.STATE_VALID if rt >= c.min_rate else Palette.TEXT_SECONDARY)
			"lost":
				var bad := qp.window_lost > c.max_lost
				HudKit.set_text(l, "%d / %d lost" % [qp.window_lost, c.max_lost], Palette.STATE_BLOCKED if bad else Palette.TEXT_SECONDARY)
