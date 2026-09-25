class_name DeskView
extends Node2D
## Desk zones + port racks (docs/SYSTEMS_EXPANSION.md §2.1–2.2, Penpot 15 / 02c–02d).
##
## Beside the laptop lie two mats: INPUT MODULES (left) and OUTPUT DEVICES (right). Owned USB
## modules lie in their slots; the player drags one onto an open port to plug it in (a module
## already there swaps back), drags a plugged module back onto the desk to unplug it, or
## rearranges slots. Click-then-click does the same without dragging. Sealed port bays are drawn
## here too (dashed reserved footprint + label + capped port face).
##
## Every input stick belongs to a quest ("Q6" on its body, its data store fills with the quest's
## progress, green once filled). Under the input mat lies the COMPLETED tray: dropping a filled
## quest's stick there files the quest (LabRun.file_from_desk / file_from_port).
##
## Pure view + input: every change goes through LabRun.plug_from_desk / unplug_to_desk /
## move_on_desk (which call Simulation.insert_device / remove_device).

const T := Palette.TILE
const DESK_W := 168.0
const SLOT_H := 76.0
const HEADER := 40.0
const GAP := 32.0             # between the plugged module overhang and the desk mat
const MODULE_OVERHANG := 112.0
const DRAG_START := 4.0       # px of movement before a press becomes a drag
const NOTE_S := 1.8           # refusal note lifetime
const PULSE_S := 0.3          # "New" pulse (2 pulses)
const TRAY_H := 112.0
const READY_S := 1.6          # the tray's "a quest is ready" breathing period

var _drag := {}               # {kind, from: "desk"|"port", side, slot, port, start: Vector2}
var _dragging := false
var _selected := {}           # click-click pick (same shape as _drag)
var _mouse := Vector2.ZERO
var _note := ""
var _note_pos := Vector2.ZERO
var _note_start := -1.0
var _pulse_kinds := PackedStringArray()
var _pulse_start := -1.0
var _font: Font
var _psu_key := []  # [capacity, demand] last drawn (the gauge redraws when they change)
var _psu_over_start := -1.0  # overload onset: the overflow chevrons pulse twice, then hold


func _ready() -> void:
	z_index = 5
	_font = TclTheme.font("ExtraBold")


func _lab() -> LabRun:
	var r = SimulationManager.run
	return r as LabRun if r is LabRun else null


func _sim() -> Simulation:
	return SimulationManager.sim


func _board_px() -> Vector2:
	var sim := _sim()
	return Vector2(sim.size) * T if sim != null else Vector2.ZERO


## Mat rect of a desk side in world space.
func desk_rect(side: String) -> Rect2:
	var run := _lab()
	var n := run.desk_slot_count(side) if run != null else 3
	var h := HEADER + n * SLOT_H + 8.0
	var x := -MODULE_OVERHANG - GAP - DESK_W if side == "in" else _board_px().x + MODULE_OVERHANG + GAP
	return Rect2(Vector2(x, 0.0), Vector2(DESK_W, h))


func slot_rect(side: String, i: int) -> Rect2:
	var d := desk_rect(side)
	return Rect2(d.position + Vector2(10.0, HEADER + i * SLOT_H), Vector2(DESK_W - 20.0, SLOT_H - 8.0))


## Where a module lies in a slot (body top-left); outputs lie flipped (plug west).
func _module_pos(side: String, i: int) -> Vector2:
	var s := slot_rect(side, i)
	return s.position + (Vector2(6.0, 6.0) if side == "in" else Vector2(28.0, 6.0))


## The COMPLETED tray under the input mat.
func tray_rect() -> Rect2:
	var d := desk_rect("in")
	return Rect2(Vector2(d.position.x, d.end.y + 36.0), Vector2(DESK_W, TRAY_H))


# ------------------------------------------------------------------ ports

## Lab port machines of a side, in board order.
func _ports(side: String) -> Array:
	var out := []
	var sim := _sim()
	if sim == null:
		return out
	var ty := "usb_input" if side == "in" else LabDef.OUTPUT_TYPE
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == ty and m.socket:
			out.append(m)
	return out


## The part of a port that belongs to the desk interaction: its port face + the plugged module
## sticking out of the laptop (never the machine body, which stays the tools' business).
func _port_grab_rect(m: Machine) -> Rect2:
	var o := Vector2(m.cell) * T
	if m.type == "usb_input":
		return Rect2(o + Vector2(-104.0, 2.0), Vector2(116.0, 60.0))
	return Rect2(o + Vector2(116.0, 2.0), Vector2(116.0, 60.0))


## Drop target: the whole port incl. its machine body (only while dragging).
func _port_drop_rect(m: Machine) -> Rect2:
	var o := Vector2(m.cell) * T
	if m.type == "usb_input":
		return Rect2(o + Vector2(-104.0, 0.0), Vector2(232.0, 64.0))
	return Rect2(o + Vector2(0.0, 0.0), Vector2(232.0, 64.0))


func _port_under(p: Vector2, side: String, drop := true) -> Machine:
	for m in _ports(side):
		var r := _port_drop_rect(m) if drop else _port_grab_rect(m)
		if r.has_point(p):
			return m
	return null


func _slot_under(p: Vector2, side: String) -> int:
	var run := _lab()
	if run == null:
		return -1
	for i in run.desk_slot_count(side):
		if slot_rect(side, i).has_point(p):
			return i
	return -1


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	var run := _lab()
	if run == null or _sim() == null:
		return
	if event is InputEventMouseMotion:
		_mouse = (make_input_local(event) as InputEventMouseMotion).position
		if not _drag.is_empty() and not _dragging and _mouse.distance_to(_drag["start"]) > DRAG_START:
			_dragging = true
			_selected = {}
		if not _drag.is_empty():
			get_viewport().set_input_as_handled()
		queue_redraw()
		return
	if not (event is InputEventMouseButton) or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE and not _selected.is_empty():
			_selected = {}
			queue_redraw()
			get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	var p := (make_input_local(event) as InputEventMouseButton).position
	_mouse = p
	if mb.pressed:
		var pick := _pick_at(p)
		if pick.is_empty():
			if not _selected.is_empty() and _try_drop(_selected, p):
				_selected = {}
				get_viewport().set_input_as_handled()
			return
		# click on a target while something is selected → act; else start a (possible) drag
		if not _selected.is_empty() and _try_drop(_selected, p):
			_selected = {}
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
		_drag = pick
		_drag["start"] = p
		_dragging = false
		get_viewport().set_input_as_handled()
	elif not _drag.is_empty():
		if _dragging:
			_try_drop(_drag, p)
		else:
			_selected = {} if (not _selected.is_empty() and _same(_selected, _drag)) else _drag.duplicate()
		_drag = {}
		_dragging = false
		get_viewport().set_input_as_handled()
		queue_redraw()


func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("from") == b.get("from") and a.get("slot") == b.get("slot") and a.get("port") == b.get("port") and a.get("side") == b.get("side")


## What lies under p: a desk module or a plugged port module.
func _pick_at(p: Vector2) -> Dictionary:
	var run := _lab()
	for side in ["in", "out"]:
		var i := _slot_under(p, side)
		var desk: Dictionary = run.desk_inputs if side == "in" else run.desk_outputs
		if i >= 0 and desk.has(i):
			return {"from": "desk", "side": side, "slot": i, "kind": desk[i], "port": -1}
		var m := _port_under(p, side, false)
		if m != null and m.device != "":
			return {"from": "port", "side": side, "slot": -1, "kind": m.device, "port": m.id}
	return {}


## Perform the move for a picked module dropped at p. Returns true when p was a valid target
## (even if the move was refused — the refusal is shown as a note).
func _try_drop(pick: Dictionary, p: Vector2) -> bool:
	var run := _lab()
	var sim := _sim()
	var side: String = pick["side"]
	var other := "out" if side == "in" else "in"
	var ok := true
	var handled := false
	var target_port := _port_under(p, side)
	var target_slot := _slot_under(p, side)
	if tray_rect().has_point(p):
		if side == "out":
			sim.last_error = "Only a quest's stick goes in the tray"
			ok = false
		elif pick["from"] == "desk":
			ok = run.file_from_desk(sim, int(pick["slot"]))
		else:
			ok = run.file_from_port(sim, int(pick["port"]))
		if not ok:
			_show_note(sim.last_error if sim.last_error != "" else "Not finished yet", p)
		sim.changed.emit()
		return true
	if _port_under(p, other) != null or _slot_under(p, other) >= 0:
		_show_note("That module belongs on the %s side" % ("input" if side == "in" else "output"), p)
		return true
	if target_port != null:
		handled = true
		if pick["from"] == "desk":
			ok = run.plug_from_desk(sim, side, int(pick["slot"]), target_port.id)
		elif int(pick["port"]) != target_port.id:
			# port → port: through the desk (the job drive moves itself; others swap via a free slot)
			if side == "out" and pick["kind"] == "job":
				ok = sim.insert_device(target_port.id, "job")
				run.sync_desk(sim)
			else:
				ok = run.unplug_to_desk(sim, int(pick["port"]))
				if ok:
					var s := _slot_of(run, side, str(pick["kind"]))
					ok = run.plug_from_desk(sim, side, s, target_port.id)
	elif target_slot >= 0 or desk_rect(side).has_point(p):
		handled = true
		if pick["from"] == "desk":
			ok = target_slot >= 0 and run.move_on_desk(side, int(pick["slot"]), target_slot)
		else:
			ok = run.unplug_to_desk(sim, int(pick["port"]), target_slot if target_slot >= 0 and not _desk(run, side).has(target_slot) else -1)
	elif _is_sealed_bay(p):
		handled = true
		ok = false
		sim.last_error = "This port is still sealed"
	if handled:
		if not ok:
			_show_note(sim.last_error if sim.last_error != "" else "Cannot plug that here", p)
		elif target_port != null:
			AudioBus.event("usb_insert")
		elif pick["from"] == "port":
			AudioBus.event("usb_remove")
		sim.changed.emit()
	return handled


func _desk(run: LabRun, side: String) -> Dictionary:
	return run.desk_inputs if side == "in" else run.desk_outputs


func _slot_of(run: LabRun, side: String, kind: String) -> int:
	var d := _desk(run, side)
	for s in d:
		if d[s] == kind:
			return s
	return -1


func _is_sealed_bay(p: Vector2) -> bool:
	var sim := _sim()
	var cell := Vector2i(floori(p.x / T), floori(p.y / T))
	return sim.is_reserved(cell) or sim.is_reserved(cell + Vector2i(1, 0)) or sim.is_reserved(cell - Vector2i(1, 0))


func _show_note(text: String, p: Vector2) -> void:
	_note = text
	_note_pos = p
	_note_start = Time.get_ticks_msec() / 1000.0


# ------------------------------------------------------------------ frame

func _process(_delta: float) -> void:
	var run := _lab()
	if run == null:
		return
	if not run.new_devices.is_empty() and run.new_devices != _pulse_kinds:
		_pulse_kinds = run.new_devices.duplicate()
		_pulse_start = Time.get_ticks_msec() / 1000.0
	var sim := _sim()
	if sim != null and run.has_psu():
		var key := [run.power_capacity(), sim.power_demand()]
		if key != _psu_key:
			var was_over: bool = _psu_key.size() == 2 and int(_psu_key[1]) > int(_psu_key[0])
			_psu_key = key
			if int(key[1]) > int(key[0]) and not was_over and not HudKit.REDUCED_MOTION:
				_psu_over_start = Time.get_ticks_msec() / 1000.0
			queue_redraw()
		if _psu_over_start >= 0.0:
			queue_redraw()
	var now := Time.get_ticks_msec() / 1000.0
	var animating := not run.quests_ready().is_empty() or (_pulse_start >= 0.0 and now - _pulse_start < PULSE_S * 2.0) or (_note_start >= 0.0 and now - _note_start < NOTE_S) or not _drag.is_empty() or not _selected.is_empty()
	if animating:
		queue_redraw()


func redraw() -> void:
	queue_redraw()


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var run := _lab()
	var sim := _sim()
	if run == null or sim == null:
		return
	_draw_sealed_bays(sim)
	var now := Time.get_ticks_msec() / 1000.0
	for side in ["in", "out"]:
		_draw_desk(run, side, now)
	_draw_tray(run, now)
	if run.has_psu():
		_draw_psu(run, sim)
	# drop targets while dragging / selected
	var active := _drag if _dragging else _selected
	if not active.is_empty():
		var side: String = active["side"]
		var target := _port_under(_mouse, side)
		for m in _ports(side):
			var fc := _port_face_center(m)
			var hot: bool = target != null and target.id == m.id
			draw_arc(fc, 20.0 if hot else 16.0, 0.0, TAU, 40, Color(Palette.STATE_VALID, 0.9 if hot else 0.35), 1.5, true)
		var ts := _slot_under(_mouse, side)
		if ts >= 0:
			SystemsDraw.rrect_outline(self, slot_rect(side, ts), 6.0, Color(Palette.STATE_VALID, 0.8), 1.5)
		if side == "in":
			var q := Devices.quest_of(str(active["kind"]))
			var fits := q >= 0 and run.quest_progress(q).filled
			var tr := tray_rect()
			var over := tr.has_point(_mouse)
			SystemsDraw.rrect_outline(self, tr.grow(2.0), 11.0, Color(Palette.STATE_VALID if fits else Palette.STATE_BLOCKED, (0.95 if over else 0.5) if fits else (0.6 if over else 0.2)), 1.5)
		if _dragging:
			_draw_module(str(active["kind"]), side, _mouse - Vector2(48.0, 28.0), 0.7)
	if _note_start >= 0.0:
		var el := now - _note_start
		if el < NOTE_S:
			_draw_note(clampf(1.0 - maxf(el - (NOTE_S - 0.3), 0.0) / 0.3, 0.0, 1.0))
		else:
			_note_start = -1.0


## The laptop's power adapter lies on the desk under the output mat once the Lab has one (L16+,
## SYSTEMS_EXPANSION §4, STYLE_GUIDE §14.6): Module M chassis, gold tab, icon_power, a gauge with
## one cell per power unit (gold → amber at 75 % → red + overflow chevrons), silk "PSU · cap" and
## a copper cable into the laptop's east edge.
func psu_rect() -> Rect2:
	var d := desk_rect("out")
	return Rect2(Vector2(d.position.x + (DESK_W - 128.0) * 0.5, d.end.y + 36.0), Vector2(128, 64))


func _draw_psu(run: LabRun, sim: Simulation) -> void:
	var r := psu_rect()
	var cap := run.power_capacity()
	var dem := sim.power_demand()
	# cable: brick → down the desk edge → into the laptop's east edge near the bottom
	var y := minf(_board_px().y - 24.0, r.position.y + 40.0)
	var cable := PackedVector2Array([r.position + Vector2(0, 40), Vector2(r.position.x - 16.0, r.position.y + 40.0), Vector2(r.position.x - 16.0, y), Vector2(_board_px().x + 6.0, y)])
	draw_polyline(cable, Palette.MATERIAL_VENT, 5.0, true)
	draw_polyline(cable, Palette.MATERIAL_COPPER_DIM, 3.0, true)
	SystemsDraw.rrect(self, Rect2(Vector2(_board_px().x, y - 5.0), Vector2(8, 10)), 1.5, Palette.MATERIAL_FRAME)
	# chassis (the canonical Module M shell) + gold tab + power icon
	var shell := Art.tex("machine/shell_module_m.svg")
	if shell != null:
		var pad := Art.pad("machine/shell_module_m.svg")
		draw_texture_rect(shell, Rect2(r.position - Vector2(pad, pad), shell.get_size() / Art.SCALE), false)
	SystemsDraw.rrect(self, Rect2(r.position + Vector2(16, 8), Vector2(24, 3)), 1.0, Palette.MATERIAL_GOLD)
	var icon := Art.icon("icon_power")
	if icon != null:
		draw_texture_rect(icon, Rect2(r.position + Vector2(14, 18), Vector2(20, 20)), false, Palette.MATERIAL_GOLD)
	var rows := 1 if cap <= 8 else (2 if cap <= 16 else 4)
	var chev := 1.0
	if _psu_over_start >= 0.0:
		var el := Time.get_ticks_msec() / 1000.0 - _psu_over_start
		if el < 0.4:
			chev = 0.35 + 0.65 * absf(cos(el / 0.2 * PI))  # two 200 ms pulses (MOTION_SYSTEM §8)
		else:
			_psu_over_start = -1.0
	SystemsDraw.gauge(self, r.position + Vector2(40, 18 if rows <= 2 else 12), 72.0, cap, dem, rows, chev)
	draw_string(_font, r.position + Vector2(16, 55), "PSU · %d" % cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(Palette.MATERIAL_SILK, 0.55))
	# LED: idle / blocked (>= 75 %) / error (> 100 %)
	var led := "error" if dem > cap else ("blocked" if dem * 4 >= cap * 3 else "idle")
	var lt := Art.tex(Art.led_file(led))
	if lt != null:
		var lp := Art.pad(Art.led_file(led))
		draw_texture_rect(lt, Rect2(r.position + Vector2(110, 6) - Vector2(lp, lp), lt.get_size() / Art.SCALE), false)


func _port_face_center(m: Machine) -> Vector2:
	var o := Vector2(m.cell) * T
	return o + (Vector2(2.0, 32.0) if m.type == "usb_input" else Vector2(126.0, 32.0))


func _draw_module(kind: String, side: String, pos: Vector2, alpha: float) -> void:
	if kind == "monitor":
		SystemsDraw.monitor(self, pos, "", [], Palette.DATA_NUMBER, {"alpha": alpha})
	elif side == "out":
		SystemsDraw.data_module(self, pos, kind, {"flip": true, "alpha": alpha, "glyph": "JOB" if kind == "job" else "JOB2", "acc": Palette.FAMILY_IO, "fill": 0.0})
	else:
		SystemsDraw.data_module(self, pos, kind, stick_opts(_lab(), kind, {"alpha": alpha}))


## A quest stick's look: "Q6" silk, the store filled with its quest's progress, green once filled.
static func stick_opts(run: LabRun, kind: String, opts: Dictionary = {}) -> Dictionary:
	var o := {"glyph": SystemsDraw.kind_glyph(kind), "acc": SystemsDraw._kind_accent(kind), "cursor": -1}
	o.merge(opts, true)
	var q := Devices.quest_of(kind)
	if run != null and q >= 0:
		o["tag"] = "Q%d" % (q + 1)
		o["done"] = run.quest_progress(q).filled
		if not o.has("cursor") or int(o["cursor"]) < 0 or o["done"]:
			o["fill"] = run.quest_fill(q)
	return o


## COMPLETED tray (under the input mat): a sunken mat with a success rim, the count filed so far
## and the last filed stick resting in it. It breathes while a filled quest waits to be filed.
func _draw_tray(run: LabRun, now: float) -> void:
	var r := tray_rect()
	SystemsDraw.rrect(self, r, 10.0, Palette.SURFACE_SUNKEN)
	var ready := not run.quests_ready().is_empty()
	var a := 0.35
	if ready:
		a = 0.55 + 0.4 * (0.5 + 0.5 * sin(TAU * now / READY_S)) if not HudKit.REDUCED_MOTION else 0.9
	SystemsDraw.rrect_outline(self, r, 10.0, Color(Palette.STATE_SUCCESS, a), 1.0 if not ready else 1.5)
	draw_string(_font, r.position + Vector2(14.0, 22.0), "COMPLETED", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.STATE_SUCCESS if ready else Palette.TEXT_MUTED)
	draw_string(_font, r.position + Vector2(r.size.x - 14.0, 22.0), "%d" % run.files, HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Palette.TEXT_MUTED)
	draw_rect(Rect2(r.position + Vector2(14.0, 30.0), Vector2(r.size.x - 28.0, 1.0)), Palette.SURFACE_BORDER)
	var slot := Rect2(r.position + Vector2(10.0, HEADER), Vector2(DESK_W - 20.0, SLOT_H - 8.0))
	if run.last_filed >= 0:
		var kinds := LabDef.quest_kinds(run.last_filed)
		var kind := Devices.stick(kinds[0] if not kinds.is_empty() else "bit", run.last_filed)
		SystemsDraw.data_module(self, slot.position + Vector2(6.0, 6.0), kind, {
			"glyph": SystemsDraw.kind_glyph(kind), "acc": SystemsDraw._kind_accent(kind), "alpha": 0.45,
			"tag": "Q%d" % (run.last_filed + 1), "done": true, "fill": 1.0,
		})
	else:
		SystemsDraw.rrect_dashed(self, slot, 6.0, Color(Palette.STATE_SUCCESS, 0.5), 1.0)
		SystemsDraw.text_center(self, slot, "drop a finished stick", 9.0, Color(Palette.TEXT_MUTED, 0.9))


func _draw_desk(run: LabRun, side: String, now: float) -> void:
	var r := desk_rect(side)
	SystemsDraw.rrect(self, r, 10.0, Palette.SURFACE_SUNKEN)
	SystemsDraw.rrect_outline(self, r, 10.0, Palette.SURFACE_BORDER, 1.0)
	draw_string(_font, r.position + Vector2(14.0, 22.0), "INPUT MODULES" if side == "in" else "OUTPUT DEVICES", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.TEXT_MUTED)
	draw_rect(Rect2(r.position + Vector2(14.0, 30.0), Vector2(r.size.x - 28.0, 1.0)), Palette.SURFACE_BORDER)
	var desk := _desk(run, side)
	for i in run.desk_slot_count(side):
		var s := slot_rect(side, i)
		if desk.has(i):
			SystemsDraw.rrect_outline(self, s, 6.0, Color(Palette.BOARD_SILK, 0.5), 1.0)
			var picked: bool = (not _drag.is_empty() and _dragging and _drag["from"] == "desk" and _drag["side"] == side and int(_drag["slot"]) == i)
			var sel: bool = (not _selected.is_empty() and _selected["from"] == "desk" and _selected["side"] == side and int(_selected["slot"]) == i)
			_draw_module(str(desk[i]), side, _module_pos(side, i), 0.3 if picked else 1.0)
			if sel:
				SystemsDraw.rrect_outline(self, s.grow(2.0), 7.0, Palette.STATE_SELECT, 1.5)
			if _pulse_start >= 0.0 and _pulse_kinds.has(str(desk[i])):
				var el := now - _pulse_start
				if el < PULSE_S * 2.0:
					SystemsDraw.rrect_outline(self, s, 6.0, Color(Palette.STATE_VALID, absf(sin(PI * el / PULSE_S))), 1.5)
		else:
			SystemsDraw.rrect_dashed(self, s, 6.0, Color(Palette.BOARD_SILK, 0.8), 1.0)


## Sealed bays: dashed 2x1 footprint + label + a capped port face at the laptop edge.
func _draw_sealed_bays(sim: Simulation) -> void:
	var seen := {}
	for c in sim.reserved:
		var cell: Vector2i = c
		var left := cell - Vector2i(1, 0)
		if sim.reserved.has(left) and not seen.has(left):
			continue  # handled with its left neighbour
		if seen.has(cell):
			continue
		seen[cell] = true
		seen[cell + Vector2i(1, 0)] = true
		var r := Rect2(Vector2(cell) * T + Vector2(2.0, 2.0), Vector2(2.0 * T - 4.0, T - 4.0))
		SystemsDraw.rrect_dashed(self, r, 6.0, Color(Palette.BOARD_SILK, 0.9), 1.0)
		var label := sim.reserved_label(cell)
		var parts := label.split(" · ")
		var west := cell.x == 0
		var tx := r.position.x + (20.0 if west else 16.0)
		draw_string(_font, Vector2(tx, r.position.y + 24.0), parts[0] if parts.size() > 0 else label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.BOARD_SILK)
		if parts.size() > 1:
			draw_string(_font, Vector2(tx, r.position.y + 38.0), parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.BOARD_SILK)
		var fx := Vector2(cell) * T + (Vector2(-6.0, 14.0) if west else Vector2(118.0, 14.0))
		SystemsDraw.rrect(self, Rect2(fx, Vector2(16.0, 36.0)), 2.0, Palette.MACHINE_FRAME_HOVER)
		SystemsDraw.rrect(self, Rect2(fx + Vector2(2.0, 2.0), Vector2(12.0, 32.0)), 1.5, Palette.MATERIAL_PLATE)
		SystemsDraw.rrect_outline(self, Rect2(fx + Vector2(2.0, 2.0), Vector2(12.0, 32.0)), 1.5, Palette.MACHINE_FRAME, 1.0)
		for sy in [7.0, 31.0]:
			draw_circle(fx + Vector2(8.0, sy), 2.0, Palette.MATERIAL_FRAME)


func _draw_note(a: float) -> void:
	var size := _font.get_string_size(_note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var r := Rect2(_note_pos + Vector2(12.0, -34.0), size + Vector2(16.0, 10.0))
	SystemsDraw.rrect(self, r, 4.0, Color(Palette.SURFACE_PANEL, 0.95 * a))
	SystemsDraw.rrect_outline(self, r, 4.0, Color(Palette.STATE_BLOCKED, 0.9 * a), 1.0)
	draw_string(_font, r.position + Vector2(8.0, 16.0), _note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Palette.TEXT_PRIMARY, a))
