class_name DeskView
extends Node2D
## The desk around the laptop (docs/SYSTEMS_EXPANSION.md §2.2; player request 2026-09-25).
##
## Beside the laptop lie two FREE desk areas: INPUT STICKS (left) and OUTPUT STICKS (right). The
## sticks lie loose on them with a little physics, like USB sticks on a real desk: drag one around,
## flick it and it slides, bumps the others and the edges and settles with a slight tilt; tap the
## desk and the sticks nearby hop away; click a stick and it hops. A small place to play while the
## quests fill.
##
## Drop a stick on an open port to plug it in (a stick already there pops back out onto the desk);
## drag a plugged stick out onto the desk to unplug it. Under the output area lies the COMPLETED
## tray: drop a filled quest's Job stick (or any of its sticks) there to file the quest. The PSU
## brick lies under the input area. Click-then-click still plugs without dragging. Sealed port
## bays are drawn here too (dashed footprint + label + capped port face).
##
## Pure view + input: every change goes through LabRun (plug_from_desk / unplug_to_desk / file_*).
## The physics is view-only; where the sticks lie is kept in LabRun.desk_pos (saved).

const T := Palette.TILE
const AREA_W := 300.0
const GAP := 32.0             # between the plugged module overhang and the desk area
const MODULE_OVERHANG := 112.0
const HEADER := 34.0
const DRAG_START := 4.0       # px of movement before a press becomes a drag
const NOTE_S := 1.8           # refusal note lifetime
const PULSE_S := 0.3          # "New" pulse (2 pulses)
const TRAY_H := 112.0
const READY_S := 1.6          # the tray's "a quest is ready" breathing period
const PSU_H := 64.0
const RIPPLE_S := 0.5
# desk physics (view only, fixed step)
const STEP := 1.0 / 120.0
const R := 26.0               # a stick is a capsule: two circles of radius R ...
const HALF := 30.0            # ... HALF px either side of its centre, along its axis
# the sticks are HEAVY (player request): they slide a little, barely bounce, never fly
const FRICTION := 6.0         # 1/s: a flicked stick slides a short way, then stops
const SPIN_DAMP := 8.0
const LEVEL := 6.0            # soft spring back toward lying level (keeps the silk readable)
const TILT_REST := 0.3        # a stick only rests once it lies within this tilt (rad)
const E_WALL := 0.12
const E_BODY := 0.1
const MAX_THROW := 650.0
const FOLLOW := 9.0           # 1/s: a held stick trails the hand a little (its weight)
const HOME := 1500.0          # px/s² toward the area for a stick that is off it
const SLEEP_V := 4.0

## A stick lying on a desk area.
class Body:
	extends RefCounted
	var kind := ""
	var side := "in"
	var pos := Vector2.ZERO   # centre, world space
	var vel := Vector2.ZERO
	var rot := 0.0
	var spin := 0.0
	var lift := 0.0           # hop height (visual)
	var lift_v := 0.0
	var held := false
	var outside := false      # off its area (popped out of a port / let go over the board)
	var rest := 0.0
	var asleep := false


var _bodies: Dictionary = {}  # kind -> Body
var _order: Array = []        # draw order (kinds), the last one on top
var _acc := 0.0
var _rng := RandomNumberGenerator.new()
var _plugged_at: Dictionary = {}  # kind -> where its stick sits while plugged (a stick popping out starts there)
var _spawn_at: Dictionary = {}    # kind -> [pos, vel] asked for by a drop
var _drag := {}               # {kind, from: "desk"|"port", side, slot, port, start, offset}
var _dragging := false
var _selected := {}           # click-click pick (same shape as _drag)
var _mouse := Vector2.ZERO
var _mouse_prev := Vector2.ZERO
var _mouse_vel := Vector2.ZERO
var _note := ""
var _note_pos := Vector2.ZERO
var _note_start := -1.0
var _pulse_kinds := PackedStringArray()
var _pulse_start := -1.0
var _ripples: Array = []      # [pos, start]
var _save_t := 0.0
var _font: Font
var _psu_key := []  # [capacity, demand] last drawn (the gauge redraws when they change)
var _psu_over_start := -1.0  # overload onset: the overflow chevrons pulse twice, then hold
var _static: DeskLayer
var _fixtures: DeskLayer
var _fixtures_key := []
var _sticks_key := []


func _ready() -> void:
	z_index = 5
	_font = TclTheme.font("ExtraBold")
	_rng.seed = 4242
	_static = DeskLayer.new()
	_static.name = "Static"
	_static.painter = _draw_static
	_static.show_behind_parent = true  # the mats lie under the sticks
	add_child(_static)
	_fixtures = DeskLayer.new()
	_fixtures.name = "Fixtures"
	_fixtures.painter = _draw_fixtures
	_fixtures.show_behind_parent = true  # the tray and the PSU lie under the sticks too
	add_child(_fixtures)


func _lab() -> LabRun:
	var r = SimulationManager.run
	return r as LabRun if r is LabRun else null


func _sim() -> Simulation:
	return SimulationManager.sim


func _board_px() -> Vector2:
	var sim := _sim()
	return Vector2(sim.size) * T if sim != null else Vector2.ZERO


# ------------------------------------------------------------------ geometry

## A free desk area in world space (the input one leaves room for the PSU, the output one for
## the COMPLETED tray).
func area_rect(side: String) -> Rect2:
	var b := _board_px()
	var run := _lab()
	var below := TRAY_H + 24.0 if side == "out" else (PSU_H + 40.0 if run != null and run.has_psu() else 0.0)
	var h := maxf(b.y - below, 420.0)
	var x := -MODULE_OVERHANG - GAP - AREA_W if side == "in" else b.x + MODULE_OVERHANG + GAP
	return Rect2(Vector2(x, 0.0), Vector2(AREA_W, h))


## Where sticks can lie: the area under its header.
func _inner(side: String) -> Rect2:
	var a := area_rect(side)
	return Rect2(a.position + Vector2(6.0, HEADER), a.size - Vector2(12.0, HEADER + 6.0))


## The COMPLETED tray under the output area.
func tray_rect() -> Rect2:
	var a := area_rect("out")
	return Rect2(Vector2(a.position.x, a.end.y + 24.0), Vector2(AREA_W, TRAY_H))


## The laptop's power adapter lies under the input area once the Lab has one (L16+).
func psu_rect() -> Rect2:
	var a := area_rect("in")
	return Rect2(Vector2(a.position.x + (AREA_W - 128.0) * 0.5, a.end.y + 24.0), Vector2(128, 64))


## Where a stick lies on its desk (tools and smokes); Vector2.INF when it is not on a desk.
func body_pos(kind: String) -> Vector2:
	return (_bodies[kind] as Body).pos if _bodies.has(kind) else Vector2.INF


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


## The centre of a plugged stick (where one popping out of the port starts).
func _stick_center(m: Machine) -> Vector2:
	var at := SystemsDraw.PORT_STICK_IN if m.type == "usb_input" else SystemsDraw.PORT_STICK_OUT
	return Vector2(m.cell) * T + at + Vector2(48.0, 28.0)


func _port_face_center(m: Machine) -> Vector2:
	var o := Vector2(m.cell) * T
	return o + (Vector2(2.0, 32.0) if m.type == "usb_input" else Vector2(126.0, 32.0))


# ------------------------------------------------------------------ bodies

## Keep one body per stick lying on a desk: a new one pops out of the port it just left, lands
## where a drop put it, comes back from the save, or (a new quest's stick) drops in from above.
func _sync_bodies(run: LabRun) -> void:
	var want := {}
	for side in ["in", "out"]:
		var d: Dictionary = run.desk_inputs if side == "in" else run.desk_outputs
		for slot in d:
			want[str(d[slot])] = side
	for k in _bodies.keys():
		if not want.has(k) or (_bodies[k] as Body).side != want[k]:
			_bodies.erase(k)
			_order.erase(k)
	for k in want:
		if not _bodies.has(k):
			_bodies[k] = _spawn(run, k, want[k])
			_order.append(k)
	# remember where plugged sticks sit (for the next pop-out)
	_plugged_at.clear()
	for side in ["in", "out"]:
		for m in _ports(side):
			if m.device != "":
				_plugged_at[m.device] = _stick_center(m)


func _spawn(run: LabRun, kind: String, side: String) -> Body:
	var b := Body.new()
	b.kind = kind
	b.side = side
	var inner := _inner(side)
	if _spawn_at.has(kind):
		b.pos = _spawn_at[kind][0]
		b.vel = _spawn_at[kind][1]
		b.outside = not inner.grow(-R).has_point(b.pos)
		_spawn_at.erase(kind)
	elif _plugged_at.has(kind):
		b.pos = _plugged_at[kind]
		b.vel = (inner.get_center() - b.pos).normalized() * 380.0
		b.spin = _rng.randf_range(-0.6, 0.6)
		b.outside = true
	elif run.desk_pos.has(kind) and run.desk_pos[kind] is Array and (run.desk_pos[kind] as Array).size() == 3:
		var p: Array = run.desk_pos[kind]
		b.pos = inner.position + Vector2(float(p[0]), float(p[1]))
		b.rot = float(p[2])
		b.asleep = true
	else:
		# dropped onto the desk from above, somewhere free
		b.pos = Vector2(inner.position.x + _rng.randf_range(R + HALF, inner.size.x - R - HALF), inner.position.y + R + 4.0)
		b.vel = Vector2(_rng.randf_range(-30.0, 30.0), _rng.randf_range(120.0, 180.0))
		b.spin = _rng.randf_range(-0.3, 0.3)
	if not b.outside:
		b.pos = b.pos.clamp(inner.position + Vector2(R + HALF, R), inner.end - Vector2(R + HALF, R))
	return b


func _circles(b: Body) -> Array:
	var ax := Vector2.RIGHT.rotated(b.rot) * HALF
	return [b.pos - ax, b.pos + ax]


func _step(dt: float) -> void:
	var list: Array = []
	for k in _order:
		list.append(_bodies[k])
	for b: Body in list:
		if b.held:
			b.vel = ((_mouse + _drag.get("offset", Vector2.ZERO)) - b.pos) * FOLLOW
			b.pos += b.vel * dt
			b.rot += b.spin * dt
			b.spin *= exp(-SPIN_DAMP * dt)
			continue
		if b.asleep:
			continue
		if b.outside:
			b.vel += (_inner(b.side).get_center() - b.pos).normalized() * HOME * dt
			b.vel *= exp(-2.0 * dt)
			if _inner(b.side).grow(-(R + HALF)).has_point(b.pos):
				b.outside = false
		else:
			b.vel *= exp(-FRICTION * dt)
		b.spin *= exp(-SPIN_DAMP * dt)
		b.spin -= wrapf(b.rot, -PI, PI) * LEVEL * dt
		b.pos += b.vel * dt
		b.rot += b.spin * dt
		if b.lift > 0.0 or b.lift_v != 0.0:
			b.lift_v -= 1800.0 * dt
			b.lift += b.lift_v * dt
			if b.lift <= 0.0:
				b.lift = 0.0
				b.lift_v = 0.0
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Body = list[i]
			var c: Body = list[j]
			if a.side == c.side and not a.outside and not c.outside:
				_collide(a, c)
	for b: Body in list:
		if not b.held and not b.outside:
			_walls(b)
	for b: Body in list:
		if b.held or b.outside or b.lift > 0.0:
			b.rest = 0.0
			b.asleep = false
			continue
		if b.vel.length() < SLEEP_V and absf(b.spin) < 0.05 and absf(wrapf(b.rot, -PI, PI)) < TILT_REST:
			b.rest += dt
			if b.rest > 0.4 and not b.asleep:
				b.asleep = true
				b.vel = Vector2.ZERO
				b.spin = 0.0
		else:
			b.rest = 0.0
			b.asleep = false


func _collide(a: Body, b: Body) -> void:
	var ia := 0.0 if a.held else 1.0
	var ib := 0.0 if b.held else 1.0
	var s := ia + ib
	if s <= 0.0:
		return
	for ca: Vector2 in _circles(a):
		for cb: Vector2 in _circles(b):
			var d := cb - ca
			var dist := d.length()
			if dist >= 2.0 * R or dist < 0.001:
				continue
			var n := d / dist
			var pen := 2.0 * R - dist
			a.pos -= n * pen * ia / s
			b.pos += n * pen * ib / s
			var rv := (b.vel - a.vel).dot(n)
			if rv < 0.0:
				var jimp := -(1.0 + E_BODY) * rv / s
				a.vel -= n * jimp * ia
				b.vel += n * jimp * ib
				# an off-centre hit turns the stick a little
				a.spin -= (ca - a.pos).cross(n * jimp) * 0.0012 * ia
				b.spin += (cb - b.pos).cross(n * jimp) * 0.0012 * ib
				if jimp > 90.0:
					AudioBus.event("desk_bump")
			a.asleep = false
			b.asleep = false


func _walls(b: Body) -> void:
	var r := _inner(b.side)
	for c: Vector2 in _circles(b):
		var push := Vector2.ZERO
		if c.x - R < r.position.x:
			push.x = r.position.x - (c.x - R)
		elif c.x + R > r.end.x:
			push.x = r.end.x - (c.x + R)
		if c.y - R < r.position.y:
			push.y = r.position.y - (c.y - R)
		elif c.y + R > r.end.y:
			push.y = r.end.y - (c.y + R)
		if push == Vector2.ZERO:
			continue
		b.pos += push
		var n := push.normalized()
		var vn := b.vel.dot(n)
		if vn < 0.0:
			b.vel -= n * vn * (1.0 + E_WALL)
			b.spin += (c - b.pos).cross(n) * vn * 0.00008
			if -vn > 110.0:
				AudioBus.event("desk_bump")


## The stick lying under p (topmost first), or null.
func _body_at(p: Vector2) -> Body:
	for i in range(_order.size() - 1, -1, -1):
		var b: Body = _bodies[_order[i]]
		var local := (p - b.pos).rotated(-b.rot)
		if Rect2(-60.0, -30.0, 120.0, 60.0).has_point(local):
			return b
	return null


func _raise(kind: String) -> void:
	_order.erase(kind)
	_order.append(kind)


## Tap the desk: a ripple, and the sticks nearby hop away from the finger.
func _poke(side: String, p: Vector2) -> void:
	_ripples.append([p, Time.get_ticks_msec() / 1000.0])
	AudioBus.event("desk_tap")
	for k in _order:
		var b: Body = _bodies[k]
		if b.side != side or b.held:
			continue
		var d := b.pos - p
		var dist := d.length()
		if dist > 170.0:
			continue
		var f := 1.0 - dist / 170.0
		b.vel += (d.normalized() if dist > 0.5 else Vector2.UP) * 200.0 * f
		b.spin += _rng.randf_range(-1.0, 1.0) * f
		b.lift_v = maxf(b.lift_v, 70.0 * f)
		b.asleep = false


## Save where the sticks lie (area-relative) once they rest.
func _store_positions(run: LabRun) -> void:
	var keep := {}
	for k in _bodies:
		var b: Body = _bodies[k]
		keep[k] = true
		if b.asleep and not b.outside:
			var inner := _inner(b.side)
			run.desk_pos[k] = [snappedf(b.pos.x - inner.position.x, 0.1), snappedf(b.pos.y - inner.position.y, 0.1), snappedf(b.rot, 0.001)]
	for k in run.desk_pos.keys():
		if not keep.has(k):
			run.desk_pos.erase(k)


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
			if _drag["from"] == "desk" and _bodies.has(_drag["kind"]):
				var b: Body = _bodies[_drag["kind"]]
				b.held = true
				b.asleep = false
				b.outside = false
				_raise(b.kind)
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
			for side in ["in", "out"]:
				if area_rect(side).has_point(p):
					_poke(side, p)  # a tap on the desk
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
		var body: Body = _bodies.get(_drag["kind"]) if _drag["from"] == "desk" else null
		if _dragging:
			_try_drop(_drag, p)
			if body != null and _bodies.has(body.kind):
				# let go on the desk: it keeps the throw; anywhere else it slides back home
				body.held = false
				body.vel = _mouse_vel.limit_length(MAX_THROW)
				body.outside = not _inner(body.side).grow(-R).has_point(body.pos)
		else:
			_selected = {} if (not _selected.is_empty() and _same(_selected, _drag)) else _drag.duplicate()
			if body != null:
				# a click: the stick hops and turns a little
				body.lift_v = 90.0
				body.spin += _rng.randf_range(-0.6, 0.6)
				body.asleep = false
				_raise(body.kind)
				AudioBus.event("desk_tap")
		_drag = {}
		_dragging = false
		get_viewport().set_input_as_handled()
		queue_redraw()


func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("from") == b.get("from") and a.get("kind") == b.get("kind") and a.get("port") == b.get("port") and a.get("side") == b.get("side")


## What lies under p: a stick on a desk or a plugged port stick.
func _pick_at(p: Vector2) -> Dictionary:
	var run := _lab()
	var b := _body_at(p)
	if b != null:
		return {"from": "desk", "side": b.side, "slot": _slot_of(run, b.side, b.kind), "kind": b.kind, "port": -1, "offset": b.pos - p}
	for side in ["in", "out"]:
		var m := _port_under(p, side, false)
		if m != null and m.device != "":
			return {"from": "port", "side": side, "slot": -1, "kind": m.device, "port": m.id}
	return {}


## Perform the move for a picked stick dropped at p. Returns true when p was a valid target
## (even if the move was refused — the refusal is shown as a note).
func _try_drop(pick: Dictionary, p: Vector2) -> bool:
	var run := _lab()
	var sim := _sim()
	var side: String = pick["side"]
	var other := "out" if side == "in" else "in"
	var from_desk: bool = pick["from"] == "desk"
	var slot := _slot_of(run, side, str(pick["kind"])) if from_desk else -1
	# the COMPLETED tray takes a filled quest's sticks from either side
	if tray_rect().has_point(p):
		var filed := run.file_from_desk(sim, slot, side) if from_desk else run.file_from_port(sim, int(pick["port"]))
		if not filed:
			_show_note(sim.last_error if sim.last_error != "" else "Not finished yet", p)
		sim.changed.emit()
		return true
	if _port_under(p, other) != null or area_rect(other).has_point(p):
		_show_note("That stick belongs on the %s side" % ("input" if side == "in" else "output"), p)
		return true
	var ok := true
	var handled := false
	var target_port := _port_under(p, side)
	if target_port != null:
		handled = true
		if from_desk:
			ok = run.plug_from_desk(sim, side, slot, target_port.id)
		elif int(pick["port"]) != target_port.id:
			# port → port: a Job stick moves itself; others swap through the desk
			if side == "out" and Devices.is_job(str(pick["kind"])):
				ok = sim.insert_device(target_port.id, str(pick["kind"]))
				run.sync_desk(sim)
			else:
				ok = run.unplug_to_desk(sim, int(pick["port"]))
				if ok:
					ok = run.plug_from_desk(sim, side, _slot_of(run, side, str(pick["kind"])), target_port.id)
	elif area_rect(side).has_point(p):
		handled = true
		if not from_desk:
			ok = run.unplug_to_desk(sim, int(pick["port"]))
			if ok:
				_spawn_at[str(pick["kind"])] = [p, _mouse_vel.limit_length(MAX_THROW) * 0.6]
	elif _is_sealed_bay(p):
		handled = true
		ok = false
		sim.last_error = "This port is still sealed"
	if handled:
		if not ok:
			_show_note(sim.last_error if sim.last_error != "" else "Cannot plug that here", p)
		elif target_port != null:
			AudioBus.event("usb_insert")
		elif not from_desk:
			AudioBus.event("usb_remove")
		if not (from_desk and target_port == null):
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

func _process(delta: float) -> void:
	var run := _lab()
	if run == null:
		return
	_sync_bodies(run)
	if delta > 0.0:
		_mouse_vel = _mouse_vel.lerp((_mouse - _mouse_prev) / delta, 0.5)
	_mouse_prev = _mouse
	_acc = minf(_acc + delta, STEP * 8.0)
	while _acc >= STEP:
		_step(STEP)
		_acc -= STEP
	_save_t += delta
	if _save_t >= 1.0:
		_save_t = 0.0
		_store_positions(run)
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
			_fixtures.queue_redraw()
		if _psu_over_start >= 0.0:
			_fixtures.queue_redraw()
	var ready := not run.quests_ready().is_empty()
	var fkey := [run.files, run.last_filed, ready, run.has_psu()]
	if fkey != _fixtures_key or (ready and not HudKit.REDUCED_MOTION):
		_fixtures_key = fkey
		_fixtures.queue_redraw()
	var now := Time.get_ticks_msec() / 1000.0
	while not _ripples.is_empty() and now - float(_ripples[0][1]) > RIPPLE_S:
		_ripples.pop_front()
	var moving := false
	for k in _bodies:
		if not (_bodies[k] as Body).asleep:
			moving = true
			break
	var animating := moving or not _ripples.is_empty() or (_pulse_start >= 0.0 and now - _pulse_start < PULSE_S * 2.0) or (_note_start >= 0.0 and now - _note_start < NOTE_S) or not _drag.is_empty() or not _selected.is_empty()
	# the sticks wear their quest's progress: redraw when a desk stick's quest fills further
	var skey := []
	for k in _order:
		var q := Devices.quest_of(str(k))
		skey.append(run.quest_fill(q) if q >= 0 else 0.0)
	if animating or skey != _sticks_key:
		_sticks_key = skey
		queue_redraw()


func redraw() -> void:
	queue_redraw()
	_static.queue_redraw()
	_fixtures.queue_redraw()


## The static desk (sealed bays, the two mats): redrawn with the layout only, never per frame.
func _draw_static(ci: CanvasItem) -> void:
	var run := _lab()
	var sim := _sim()
	if run == null or sim == null:
		return
	_draw_sealed_bays(ci, sim)
	for side in ["in", "out"]:
		_draw_area(ci, side)


## The COMPLETED tray and the PSU brick: redrawn when what they show changes (the tray also
## while a filled quest waits and it breathes; the PSU during its overload pulse).
func _draw_fixtures(ci: CanvasItem) -> void:
	var run := _lab()
	var sim := _sim()
	if run == null or sim == null:
		return
	_draw_tray(ci, run, Time.get_ticks_msec() / 1000.0)
	if run.has_psu():
		_draw_psu(ci, run, sim)


## A desk layer drawn by one DeskView painter (own canvas item, own redraw).
class DeskLayer extends Node2D:
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var run := _lab()
	var sim := _sim()
	if run == null or sim == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for rp in _ripples:
		var el := now - float(rp[1])
		var k := el / RIPPLE_S
		draw_arc(rp[0], 8.0 + 52.0 * k, 0.0, TAU, 40, Color(Palette.BOARD_SILK, 0.5 * (1.0 - k)), 1.5, true)
	# the sticks: shadows first, then the bodies (the held one on top)
	for k in _order:
		_draw_shadow(_bodies[k])
	for k in _order:
		_draw_body(run, _bodies[k], now)
	# drop targets while dragging / selected
	var active := _drag if _dragging else _selected
	if not active.is_empty():
		var side: String = active["side"]
		var target := _port_under(_mouse, side)
		for m in _ports(side):
			var fc := _port_face_center(m)
			var hot: bool = target != null and target.id == m.id
			draw_arc(fc, 20.0 if hot else 16.0, 0.0, TAU, 40, Color(Palette.STATE_VALID, 0.9 if hot else 0.35), 1.5, true)
		var q := Devices.quest_of(str(active["kind"]))
		var fits := q >= 0 and run.quest_progress(q).filled
		var tr := tray_rect()
		var over := tr.has_point(_mouse)
		SystemsDraw.rrect_outline(self, tr.grow(2.0), 11.0, Color(Palette.STATE_VALID if fits else Palette.STATE_BLOCKED, (0.95 if over else 0.5) if fits else (0.6 if over else 0.2)), 1.5)
		if _dragging and active["from"] == "port":
			_draw_module(str(active["kind"]), side, _mouse - Vector2(48.0, 28.0), 0.7)
	if _note_start >= 0.0:
		var el := now - _note_start
		if el < NOTE_S:
			_draw_note(clampf(1.0 - maxf(el - (NOTE_S - 0.3), 0.0) / 0.3, 0.0, 1.0))
		else:
			_note_start = -1.0


## A free desk area: a sunken mat with a faint dot grid and its label.
func _draw_area(ci: CanvasItem, side: String) -> void:
	var r := area_rect(side)
	SystemsDraw.rrect(ci, r, 10.0, Palette.SURFACE_SUNKEN)
	SystemsDraw.rrect_outline(ci, r, 10.0, Palette.SURFACE_BORDER, 1.0)
	ci.draw_string(_font, r.position + Vector2(14.0, 22.0), "INPUT STICKS" if side == "in" else "OUTPUT STICKS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.TEXT_MUTED)
	var dot := Color(Palette.BOARD_SILK, 0.35)
	var y := r.position.y + HEADER + 16.0
	while y < r.end.y - 8.0:
		var x := r.position.x + 16.0
		while x < r.end.x - 8.0:
			ci.draw_rect(Rect2(Vector2(x, y) - Vector2(0.75, 0.75), Vector2(1.5, 1.5)), dot)
			x += 32.0
		y += 32.0


func _draw_shadow(b: Body) -> void:
	var off := Vector2(4.0, 6.0) + Vector2(0.5, 0.8) * b.lift + (Vector2(4.0, 6.0) if b.held else Vector2.ZERO)
	draw_set_transform(b.pos + off, b.rot, Vector2.ONE)
	SystemsDraw.rrect(self, Rect2(-48.0, -26.0, 96.0, 54.0), 8.0, Color(Palette.BG_VOID, 0.35 if not b.held else 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_body(run: LabRun, b: Body, now: float) -> void:
	var sc := 1.0 + b.lift * 0.0015 + (0.05 if b.held else 0.0)
	draw_set_transform(b.pos - Vector2(0.0, b.lift * 0.5), b.rot, Vector2(sc, sc))
	_draw_module(b.kind, b.side, Vector2(-48.0, -28.0), 1.0)
	var box := Rect2(-52.0, -32.0, 104.0, 64.0)
	var sel: bool = not _selected.is_empty() and _selected["from"] == "desk" and _selected["kind"] == b.kind
	if sel:
		SystemsDraw.rrect_outline(self, box, 7.0, Palette.STATE_SELECT, 1.5)
	if _pulse_start >= 0.0 and _pulse_kinds.has(b.kind):
		var el := now - _pulse_start
		if el < PULSE_S * 2.0:
			SystemsDraw.rrect_outline(self, box, 7.0, Color(Palette.STATE_VALID, absf(sin(PI * el / PULSE_S))), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_module(kind: String, side: String, pos: Vector2, alpha: float) -> void:
	if kind == "monitor":
		SystemsDraw.monitor(self, pos, "", [], Palette.DATA_NUMBER, {"alpha": alpha})
	elif side == "out":
		SystemsDraw.data_module(self, pos, kind, stick_opts(_lab(), kind, {"flip": true, "alpha": alpha, "glyph": "JOB", "acc": Palette.FAMILY_IO, "fill": 0.0}))
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


## COMPLETED tray (under the output area): a sunken mat with a success rim, the count filed so
## far and the last filed Job stick resting in it. It breathes while a filled quest waits.
func _draw_tray(ci: CanvasItem, run: LabRun, now: float) -> void:
	var r := tray_rect()
	SystemsDraw.rrect(ci, r, 10.0, Palette.SURFACE_SUNKEN)
	var ready := not run.quests_ready().is_empty()
	var a := 0.35
	if ready:
		a = 0.55 + 0.4 * (0.5 + 0.5 * sin(TAU * now / READY_S)) if not HudKit.REDUCED_MOTION else 0.9
	SystemsDraw.rrect_outline(ci, r, 10.0, Color(Palette.STATE_SUCCESS, a), 1.0 if not ready else 1.5)
	ci.draw_string(_font, r.position + Vector2(14.0, 22.0), "COMPLETED", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.STATE_SUCCESS if ready else Palette.TEXT_MUTED)
	ci.draw_string(_font, r.position + Vector2(r.size.x - 14.0, 22.0), "%d" % run.files, HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Palette.TEXT_MUTED)
	ci.draw_rect(Rect2(r.position + Vector2(14.0, 30.0), Vector2(r.size.x - 28.0, 1.0)), Palette.SURFACE_BORDER)
	var slot := Rect2(r.position + Vector2(10.0, 38.0), Vector2(r.size.x - 20.0, 66.0))
	if run.last_filed >= 0:
		var kind := run.quest_job(run.last_filed)
		SystemsDraw.data_module(ci, slot.get_center() - Vector2(48.0, 28.0), kind, {
			"flip": true, "glyph": "JOB", "acc": Palette.FAMILY_IO, "alpha": 0.45,
			"tag": "Q%d" % (run.last_filed + 1), "done": true, "fill": 1.0,
		})
	else:
		SystemsDraw.rrect_dashed(ci, slot, 6.0, Color(Palette.STATE_SUCCESS, 0.5), 1.0)
		SystemsDraw.text_center(ci, slot, "drop a full Job stick here", 9.0, Color(Palette.TEXT_MUTED, 0.9))


## The laptop's power adapter under the input area (SYSTEMS_EXPANSION §4, STYLE_GUIDE §14.6):
## Module M chassis, gold tab, icon_power, a gauge with one cell per power unit (gold → amber at
## 75 % → red + overflow chevrons), silk "PSU · cap" and a copper cable into the laptop's west edge.
func _draw_psu(ci: CanvasItem, run: LabRun, sim: Simulation) -> void:
	var r := psu_rect()
	var cap := run.power_capacity()
	var dem := sim.power_demand()
	# cable: brick → along the desk edge → into the laptop's west edge near the bottom
	var y := minf(_board_px().y - 24.0, r.position.y + 40.0)
	var ex := -8.0
	var cable := PackedVector2Array([r.position + Vector2(128, 40), Vector2(r.end.x + 16.0, r.position.y + 40.0), Vector2(r.end.x + 16.0, y), Vector2(ex, y)])
	ci.draw_polyline(cable, Palette.MATERIAL_VENT, 5.0, true)
	ci.draw_polyline(cable, Palette.MATERIAL_COPPER_DIM, 3.0, true)
	SystemsDraw.rrect(ci, Rect2(Vector2(ex - 2.0, y - 5.0), Vector2(8, 10)), 1.5, Palette.MATERIAL_FRAME)
	# chassis (the canonical Module M shell) + gold tab + power icon
	var shell := Art.tex("machine/shell_module_m.svg")
	if shell != null:
		var pad := Art.pad("machine/shell_module_m.svg")
		ci.draw_texture_rect(shell, Rect2(r.position - Vector2(pad, pad), shell.get_size() / Art.SCALE), false)
	SystemsDraw.rrect(ci, Rect2(r.position + Vector2(16, 8), Vector2(24, 3)), 1.0, Palette.MATERIAL_GOLD)
	var icon := Art.icon("icon_power")
	if icon != null:
		ci.draw_texture_rect(icon, Rect2(r.position + Vector2(14, 18), Vector2(20, 20)), false, Palette.MATERIAL_GOLD)
	var rows := 1 if cap <= 8 else (2 if cap <= 16 else 4)
	var chev := 1.0
	if _psu_over_start >= 0.0:
		var el := Time.get_ticks_msec() / 1000.0 - _psu_over_start
		if el < 0.4:
			chev = 0.35 + 0.65 * absf(cos(el / 0.2 * PI))  # two 200 ms pulses (MOTION_SYSTEM §8)
		else:
			_psu_over_start = -1.0
	SystemsDraw.gauge(ci, r.position + Vector2(40, 18 if rows <= 2 else 12), 72.0, cap, dem, rows, chev)
	ci.draw_string(_font, r.position + Vector2(16, 55), "PSU · %d" % cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(Palette.MATERIAL_SILK, 0.55))
	# LED: idle / blocked (>= 75 %) / error (> 100 %)
	var led := "error" if dem > cap else ("blocked" if dem * 4 >= cap * 3 else "idle")
	var lt := Art.tex(Art.led_file(led))
	if lt != null:
		var lp := Art.pad(Art.led_file(led))
		ci.draw_texture_rect(lt, Rect2(r.position + Vector2(110, 6) - Vector2(lp, lp), lt.get_size() / Art.SCALE), false)


## Sealed bays: dashed 2x1 footprint + label + a capped port face at the laptop edge.
func _draw_sealed_bays(ci: CanvasItem, sim: Simulation) -> void:
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
		SystemsDraw.rrect_dashed(ci, r, 6.0, Color(Palette.BOARD_SILK, 0.9), 1.0)
		var label := sim.reserved_label(cell)
		var parts := label.split(" · ")
		var west := cell.x == 0
		var tx := r.position.x + (20.0 if west else 16.0)
		ci.draw_string(_font, Vector2(tx, r.position.y + 24.0), parts[0] if parts.size() > 0 else label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.BOARD_SILK)
		if parts.size() > 1:
			ci.draw_string(_font, Vector2(tx, r.position.y + 38.0), parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.BOARD_SILK)
		var fx := Vector2(cell) * T + (Vector2(-6.0, 14.0) if west else Vector2(118.0, 14.0))
		SystemsDraw.rrect(ci, Rect2(fx, Vector2(16.0, 36.0)), 2.0, Palette.MACHINE_FRAME_HOVER)
		SystemsDraw.rrect(ci, Rect2(fx + Vector2(2.0, 2.0), Vector2(12.0, 32.0)), 1.5, Palette.MATERIAL_PLATE)
		SystemsDraw.rrect_outline(ci, Rect2(fx + Vector2(2.0, 2.0), Vector2(12.0, 32.0)), 1.5, Palette.MACHINE_FRAME, 1.0)
		for sy in [7.0, 31.0]:
			ci.draw_circle(fx + Vector2(8.0, sy), 2.0, Palette.MATERIAL_FRAME)


func _draw_note(a: float) -> void:
	var size := _font.get_string_size(_note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var r := Rect2(_note_pos + Vector2(12.0, -34.0), size + Vector2(16.0, 10.0))
	SystemsDraw.rrect(self, r, 4.0, Color(Palette.SURFACE_PANEL, 0.95 * a))
	SystemsDraw.rrect_outline(self, r, 4.0, Color(Palette.STATE_BLOCKED, 0.9 * a), 1.0)
	draw_string(_font, r.position + Vector2(8.0, 16.0), _note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Palette.TEXT_PRIMARY, a))
