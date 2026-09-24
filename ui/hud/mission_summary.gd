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


## Lab layout: same 320-wide panel, but a request box instead of input/output cell rows.
func _lab_rebuild(sm: Node) -> void:
	var lr: LabRun = sm.lab_run
	var lvl: int = lr.level
	var h := 248.0
	offset_left = 16
	offset_top = -16 - h
	offset_right = 16 + 320.0
	offset_bottom = -16
	_root = HudKit.box(self, Vector2.ZERO, Vector2(320.0, h), Palette.SURFACE_PANEL, Palette.SURFACE_BORDER, 1, 10)
	HudKit.label(_root, "L%d · %s" % [lvl + 1, lr.title()], Vector2(18, 16), 14, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 260)
	var brief := HudKit.label(_root, lr_brief(lr), Vector2(18, 40), 11, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size = Vector2(284, 0)
	brief.size = Vector2(284, 26)
	# request box
	var fbox := HudKit.box(_root, Vector2(18, 72), Vector2(284, 44), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 6)
	HudKit.label(fbox, "DELIVER", Vector2(12, 8), 9, HudKit.W_XBOLD, Palette.TEXT_SECONDARY)
	var want: BitVector = lr.request_bits()
	var value_text := HudKit.fmt(want)
	var chip_w := TclTheme.font(HudKit.W_XBOLD).get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	HudKit.label(fbox, value_text, Vector2(64, 3), 18, HudKit.W_XBOLD, Palette.DATA_NUMBER)
	HudKit.label(fbox, "× %d" % lr.request_count(), Vector2(64 + chip_w + 10, 12), 14, HudKit.W_XBOLD, Palette.TEXT_PRIMARY)
	HudKit.label(fbox, "%d-bit" % want.width, Vector2(284 - 42, 12), 9, HudKit.W_MEDIUM, Palette.TEXT_MUTED, 38, HORIZONTAL_ALIGNMENT_RIGHT)
	# progress track + delivered
	HudKit.box(_root, Vector2(18, 176), Vector2(284, 4), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 2)
	_track_fill = HudKit.box(_root, Vector2(18, 176), Vector2(0, 4), Palette.STATE_VALID, Color(0, 0, 0, 0), 0, 2)
	_progress = HudKit.label(_root, "", Vector2(18, 188), 11, HudKit.W_XBOLD, Palette.TEXT_PRIMARY)
	_rejected = HudKit.label(_root, "", Vector2(18, 208), 10, HudKit.W_MEDIUM, Palette.TEXT_MUTED, 284)
	_last = HudKit.label(_root, "", Vector2(18, 224), 10, HudKit.W_MEDIUM, Palette.STATE_BLOCKED, 284)
	_refresh()


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
	_track_fill.size = Vector2(284.0 * correct / total, 4)
	_progress.text = "%d / %d" % [correct, d.expected_total()]
	# Last arrival (rejected values are shown, never fatal) or the stall warning.
	if sm.run.warning != "":
		HudKit.set_text(_last, "⚠ " + sm.run.warning, Palette.STATE_BLOCKED)
	elif not lo.is_empty() and not bool(lo.get("ok", true)):
		var got := "—"
		for mid in sm.sim.sorted_machine_ids():
			var m: Machine = sm.sim.machines[mid]
			if m.channel == 0 and m.type in ["output", "terminal_output"] and not m.received.is_empty():
				got = HudKit.fmt(m.received[m.received.size() - 1].data)
		var want := HudKit.fmt(sm.run.expected_bits[0][mini(done, sm.run.expected_bits[0].size() - 1)])
		HudKit.set_text(_last, "Last: %s ✗   expected %s" % [got, want], Palette.STATE_ERROR)
	else:
		HudKit.set_text(_last, "", Palette.TEXT_MUTED)


func _lab_refresh(sm: Node) -> void:
	var lr: LabRun = sm.lab_run
	var total := maxi(lr.request_count(), 1)
	var done := clampi(lr.delivered, 0, lr.request_count())
	_track_fill.size = Vector2(284.0 * done / total, 4)
	_progress.text = "%d / %d" % [lr.delivered, lr.request_count()]
	if lr.rejected > 0:
		HudKit.set_text(_rejected, "Rejected: %d" % lr.rejected, Palette.TEXT_MUTED)
	else:
		HudKit.set_text(_rejected, "", Palette.TEXT_MUTED)
	if lr.warning != "":
		HudKit.set_text(_last, "⚠ " + lr.warning, Palette.STATE_BLOCKED)
	else:
		HudKit.set_text(_last, "", Palette.STATE_BLOCKED)
