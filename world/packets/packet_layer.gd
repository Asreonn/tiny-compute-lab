class_name PacketLayer
extends Node2D
## Slice A4b item 4: draws every packet visible in the simulation each frame and feeds
## interpolated arc positions into each ConnectionView.packet_positions so the wire comets
## follow the packets. Read-only over the Simulation: on-wire positions come from
## Connection.slots, transitions from Simulation.events (emit/deliver), the input/output
## queues from Machine.inq/outq. Everything is tick-locked to SimulationManager.alpha with
## a single cubic-out easing (docs/MOTION_SYSTEM.md §1).
##
## Drawing rules (docs/STYLE_GUIDE.md §8, docs/VISUAL_SYSTEM.md §10):
##   wire packet (state "normal") / "leaving" at the output anchor · "entering" shrinks
##   1 -> 0.6 at PKT_ENTERING_OPACITY · input-queue chips stacked 6 px inside the port ·
##   blocked output held PKT_QUEUE_OFFSET along the outgoing wire · a job's input packet is
##   NOT drawn (the activity area shows the work). The sprite tier (far|normal|close)
##   follows CameraRig.zoom_tier_changed.

const T := Palette.TILE
const QUEUE_STACK := 6.0  # px between packets stacked inside an input queue
const ENTER_MIN_SCALE := 0.6  # entering packets shrink 1 -> 0.6 into the socket
const LONG_LABEL := 5  # labels longer than this flip into a small tag above the packet
const LABEL_SIZE := 9  # close-tier packet value font size
const TAG_ABOVE := 14.0  # tag offset above the packet centre
const TAG_RADIUS := 3  # tag corner radius
const TAG_PAD := 3.0  # horizontal padding inside the tag
const TAG_ROW_PAD := 1.0  # vertical padding inside the tag

var _tier := "normal"  # CameraRig zoom tier ("far" | "normal" | "close")
var _last_tick := -1  # last simulation tick whose arc positions we captured
var _positions := {}  # packet id -> {conn: int, prev: float, cur: float} arc px on the path
var _paths := {}  # connection id -> PackedVector2Array (simplified + chamfered draw path)
var _tag_style: StyleBoxFlat = null


func _ready() -> void:
	var rig: Node = get_parent().get_node_or_null("CameraRig") if get_parent() != null else null
	if rig != null and rig.has_signal("zoom_tier_changed"):
		rig.zoom_tier_changed.connect(_on_tier)
	SimulationManager.mission_loaded.connect(_on_board_reset)
	SimulationManager.layout_changed.connect(_on_board_reset)
	_tag_style = StyleBoxFlat.new()
	_tag_style.bg_color = Palette.MACHINE_SCREEN
	_tag_style.border_color = Palette.MATERIAL_FRAME
	_tag_style.set_border_width_all(1)
	_tag_style.set_corner_radius_all(TAG_RADIUS)
	_tag_style.anti_aliasing = true


func _on_tier(tier: String) -> void:
	if tier != _tier:
		_tier = tier
		queue_redraw()


## Layout edits replace wires/queues wholesale: drop every cached position and path.
func _on_board_reset(_v: Variant = null) -> void:
	_paths.clear()
	_positions.clear()
	_last_tick = -1


func _process(_delta: float) -> void:
	_ensure_intervals()
	queue_redraw()


## Capture the tick boundary: store prev/cur arc positions for every packet currently on a
## wire. prev is where the packet was one tick ago (its last captured cur), the output
## anchor (0.0) for packets emitted this tick, or the next slot behind it on a fresh board.
func _ensure_intervals() -> void:
	var sim := SimulationManager.sim
	if sim == null or sim.tick == _last_tick:
		return
	_last_tick = sim.tick
	var emitted := {}
	for e in sim.events:
		if str(e.get("kind", "")) == "emit":
			emitted[int(e.get("packet", -1))] = true
	var old := _positions
	var fresh := {}
	for cid in sim.sorted_connection_ids():
		var c: Connection = sim.connections[cid]
		if not _paths.has(cid):
			_paths[cid] = _build_path(c)
		var path: PackedVector2Array = _paths.get(cid, PackedVector2Array())
		if path.size() < 2:
			continue
		var n: int = c.slots.size()
		for i in n:
			var p: Packet = c.slots[i]
			if p == null:
				continue
			var cur := _slot_arc(path, c.cells, i)
			var prev := cur
			if emitted.has(p.id):
				prev = 0.0
			elif old.has(p.id) and int(old[p.id]["conn"]) == cid:
				prev = float(old[p.id]["cur"])
			elif i + 1 < n:
				prev = _slot_arc(path, c.cells, i + 1)
			fresh[p.id] = {"conn": cid, "prev": prev, "cur": cur}
	_positions = fresh


## Comet-head arc lengths (px along the chamfered path) for every packet on `conn_id`, using
## the same tick-locked interpolation the packet sprites use. Wired into each
## ConnectionView.packet_positions so comets follow the packets.
func comet_arcs(conn_id: int) -> Array:
	_ensure_intervals()
	var sim := SimulationManager.sim
	if sim == null or not _paths.has(conn_id):
		return []
	var path: PackedVector2Array = _paths[conn_id]
	var plen := SignalGeom.poly_len(path)
	if plen <= 0.0:
		return []
	var a := _ease(SimulationManager.alpha)
	var out: Array = []
	for pid in _positions:
		var rec: Dictionary = _positions[pid]
		if int(rec["conn"]) != conn_id:
			continue
		out.append(clampf(lerpf(rec["prev"], rec["cur"], a), 0.0, plen))
	return out


## World positions of every packet the layer currently draws, packet id -> Vector2.
## This is the same position math as _draw (tick-locked interpolation), exposed for the
## tools' hit testing (packet = within 10 px of its drawn position).
func drawn_packet_positions() -> Dictionary:
	var sim := SimulationManager.sim
	if sim == null:
		return {}
	_ensure_intervals()
	var a := _ease(SimulationManager.alpha)
	var delivering := {}
	for e in sim.events:
		var kind := str(e.get("kind", ""))
		if kind == "deliver":
			delivering[int(e.get("packet", -1))] = e
	var out := {}
	# 1. on-wire packets
	for cid in sim.sorted_connection_ids():
		var c: Connection = sim.connections[cid]
		if not _paths.has(cid):
			_paths[cid] = _build_path(c)
		var path: PackedVector2Array = _paths.get(cid, PackedVector2Array())
		var plen := maxf(SignalGeom.poly_len(path), 1e-9)
		if path.size() < 2 or plen <= 0.0:
			continue
		for i in c.slots.size():
			var p: Packet = c.slots[i]
			if p == null:
				continue
			var arc: float = _slot_arc(path, c.cells, i)
			if _positions.has(p.id):
				arc = lerpf(_positions[p.id]["prev"], _positions[p.id]["cur"], a)
			out[p.id] = SignalGeom.sample(path, clampf(arc / plen, 0.0, 1.0))[0]
	# 2. entering (this tick's delivered packets gliding into the socket)
	for pid in delivering:
		var e: Dictionary = delivering[pid]
		var mid := int(e.get("machine", -1))
		var port := str(e.get("port", ""))
		if not sim.machines.has(mid):
			continue
		var m: Machine = sim.machines[mid]
		var p: Packet = _in_queue(m, pid)
		if p == null:
			continue
		var from := _wire_head_pos(sim, m, port)
		out[pid] = from.lerp(MachineView.port_world(m, port), a)
	# 3. machine queues (stacked inputs; blocked outputs held on the wire)
	for mid in sim.sorted_machine_ids():
		var m: Machine = sim.machines[mid]
		for port in m.inq:
			var queue: Array = m.inq[port]
			if queue.is_empty():
				continue
			var anchor := MachineView.port_world(m, port)
			var inward := -Vector2(Catalog.side_vec(m.port_geom(port)["side"]))
			var j := 0
			for p in queue:
				if delivering.has(p.id):
					continue
				out[p.id] = anchor + inward * (float(j) * QUEUE_STACK)
				j += 1
		if m.state != Machine.State.BLOCKED:
			continue
		for port in m.outq:
			var p: Packet = m.outq[port]
			if p == null:
				continue
			var anchor := MachineView.port_world(m, port)
			var outward := Vector2(Catalog.side_vec(m.port_geom(port)["side"]))
			out[p.id] = anchor + outward * float(Palette.PKT_QUEUE_OFFSET)
	return out


# ------------------------------------------------------------------ per frame draw

func _draw() -> void:
	var sim := SimulationManager.sim
	if sim == null:
		return
	_ensure_intervals()
	var a := _ease(SimulationManager.alpha)
	var emitted := {}
	var delivering := {}
	for e in sim.events:
		var kind := str(e.get("kind", ""))
		if kind == "emit":
			emitted[int(e.get("packet", -1))] = true
		elif kind == "deliver":
			delivering[int(e.get("packet", -1))] = e
	# 1. on-wire packets ("normal" travelling, "leaving" just after emit)
	for cid in sim.sorted_connection_ids():
		var c: Connection = sim.connections[cid]
		if not _paths.has(cid):
			_paths[cid] = _build_path(c)
		var path: PackedVector2Array = _paths.get(cid, PackedVector2Array())
		var plen := maxf(SignalGeom.poly_len(path), 1e-9)
		if path.size() < 2 or plen <= 0.0:
			continue
		for i in c.slots.size():
			var p: Packet = c.slots[i]
			if p == null:
				continue
			var arc: float = _slot_arc(path, c.cells, i)
			if _positions.has(p.id):
				arc = lerpf(_positions[p.id]["prev"], _positions[p.id]["cur"], a)
			var pos: Vector2 = SignalGeom.sample(path, clampf(arc / plen, 0.0, 1.0))[0]
			_draw_packet(p, pos, "leaving" if emitted.has(p.id) else "normal", 1.0, Color.WHITE)
	# 2. entering: this tick's delivered packets glide from the wire head slot to the input
	#    anchor, shrinking into the socket at PKT_ENTERING_OPACITY (tick-locked)
	for pid in delivering:
		var e: Dictionary = delivering[pid]
		var mid := int(e.get("machine", -1))
		var port := str(e.get("port", ""))
		if not sim.machines.has(mid):
			continue
		var m: Machine = sim.machines[mid]
		var p: Packet = _in_queue(m, pid)
		if p == null:
			continue
		var from := _wire_head_pos(sim, m, port)
		var to := MachineView.port_world(m, port)
		var pos := from.lerp(to, a)
		_draw_packet(p, pos, "entering", lerpf(1.0, ENTER_MIN_SCALE, a), Color(1, 1, 1, Palette.PKT_ENTERING_OPACITY))
	# 3. machine queues: input queues stack inward 6 px apart; a blocked output holds its
	#    packet PKT_QUEUE_OFFSET down the wire. A job's input packet is not drawn.
	for mid in sim.sorted_machine_ids():
		var m: Machine = sim.machines[mid]
		for port in m.inq:
			var queue: Array = m.inq[port]
			if queue.is_empty():
				continue
			var anchor := MachineView.port_world(m, port)
			var inward := -Vector2(Catalog.side_vec(m.port_geom(port)["side"]))
			var j := 0
			for p in queue:
				if delivering.has(p.id):
					continue  # the entering animation owns this packet for the whole tick
				_draw_packet(p, anchor + inward * (float(j) * QUEUE_STACK), "normal", 1.0, Color.WHITE)
				j += 1
		if m.state != Machine.State.BLOCKED:
			continue
		for port in m.outq:
			var p: Packet = m.outq[port]
			if p == null:
				continue
			var anchor := MachineView.port_world(m, port)
			var outward := Vector2(Catalog.side_vec(m.port_geom(port)["side"]))
			_draw_packet(p, anchor + outward * float(Palette.PKT_QUEUE_OFFSET), "queued", 1.0, Color.WHITE)


## Sprite (tier + state) centred at pos, plus the close-tier value label.
func _draw_packet(p: Packet, pos: Vector2, state: String, scale_k: float, mod: Color) -> void:
	var tex := Art.tex(Art.packet_file(p.data.width, _tier, state))
	if tex == null:
		return
	var design := Vector2(tex.get_width(), tex.get_height()) / Art.SCALE
	var rect := Rect2(pos - design * 0.5 * scale_k, design * scale_k)
	draw_texture_rect(tex, rect, false, mod)
	if _tier == "close":
		_draw_label(p, pos, design * scale_k)


## Close tier: the packet value in the HUD view mode, DATA_NUMBER (DATA_BOOLEAN for width
## 1), centred on the chip. Labels longer than 5 characters go in a small tag 14 px above
## the packet instead (MACHINE_SCREEN fill, 1 px MATERIAL_FRAME stroke, radius 3).
func _draw_label(p: Packet, pos: Vector2, size: Vector2) -> void:
	var text := ViewMode.format(p.data, _view_mode())
	var color := Palette.DATA_NUMBER if p.data.width > 1 else Palette.DATA_BOOLEAN
	var f := TclTheme.font("ExtraBold")
	var ascent := f.get_ascent(LABEL_SIZE)
	var descent := f.get_descent(LABEL_SIZE)
	if text.length() > LONG_LABEL:
		var h := ascent + descent + TAG_ROW_PAD * 2.0
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_SIZE).x + TAG_PAD * 2.0
		var rect := Rect2(Vector2(pos.x - w * 0.5, pos.y - size.y * 0.5 - TAG_ABOVE - h), Vector2(w, h))
		if _tag_style != null:
			draw_style_box(_tag_style, rect)
		var base := Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + (ascent - descent) * 0.5)
		draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)
	else:
		var base := Vector2(pos.x - size.x * 0.5, pos.y + (ascent - descent) * 0.5)
		draw_string(f, base, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, LABEL_SIZE, color)


## Display view mode for packet labels: SimulationManager.view_mode, defaulting to the
## mission's first view mode (then BIN).
func _view_mode() -> int:
	var vm: int = SimulationManager.view_mode
	if vm >= ViewMode.Mode.BIN:
		return vm
	var md: MissionDef = SimulationManager.mission
	if md != null and not md.view_modes.is_empty():
		return int(md.view_modes[0])
	return ViewMode.Mode.BIN


## World position the deliver event's packet is coming from: the head slot of the source
## wire, or the input anchor for a zero-tile wire.
func _wire_head_pos(sim: Simulation, m: Machine, port: String) -> Vector2:
	var cv: Connection = sim.connection_at_port(m.id, port)
	if cv == null:
		return MachineView.port_world(m, port)
	if not _paths.has(cv.id):
		_paths[cv.id] = _build_path(cv)
	var path: PackedVector2Array = _paths.get(cv.id, PackedVector2Array())
	var plen := maxf(SignalGeom.poly_len(path), 1e-9)
	if path.size() < 2 or plen <= 0.0:
		return MachineView.port_world(m, port)
	var arc := _slot_arc(path, cv.cells, cv.slots.size() - 1)
	return SignalGeom.sample(path, clampf(arc / plen, 0.0, 1.0))[0]


## Find a packet that lives inside a machine queue (used for entering packets).
func _in_queue(m: Machine, pid: int) -> Packet:
	for port in m.inq:
		for p in m.inq[port]:
			if p.id == pid:
				return p
	if not m.job.is_empty() and m.job.get("input", null) != null and m.job["input"].id == pid:
		return m.job["input"]
	for port in m.outq:
		if m.outq[port] != null and m.outq[port].id == pid:
			return m.outq[port]
	return null


## Same draw path as ConnectionView._build_path: [port anchor] + tile centres + [anchor],
## simplified and chamfered (bus 18, trace 14) with the Signal System V1 geometry.
func _build_path(c: Connection) -> PackedVector2Array:
	var sim := SimulationManager.sim
	if sim == null or not sim.machines.has(c.from_id) or not sim.machines.has(c.to_id):
		return PackedVector2Array()
	var fm: Machine = sim.machines[c.from_id]
	var tm: Machine = sim.machines[c.to_id]
	var pts := PackedVector2Array()
	pts.append(MachineView.port_world(fm, c.from_port))
	for cell in c.cells:
		pts.append(Vector2(cell) * T + Vector2.ONE * (T * 0.5))
	pts.append(MachineView.port_world(tm, c.to_port))
	var raw := SignalGeom.simplify(pts)
	var bus := bool(fm.port_geom(c.from_port).get("bus", false)) and bool(tm.port_geom(c.to_port).get("bus", false))
	return SignalGeom.chamfer(raw, Palette.SIG_BUS_CHAMFER if bus else Palette.SIG_CHAMFER)


## Arc length (px along the path) of slot i: the centre of the routed tile, or the wire's
## delivery end for a zero-tile stretch.
func _slot_arc(path: PackedVector2Array, cells: Array, i: int) -> float:
	var plen := SignalGeom.poly_len(path)
	if plen <= 0.0:
		return 0.0
	if i >= 0 and i < cells.size():
		var centre := Vector2(cells[i]) * T + Vector2.ONE * (T * 0.5)
		return clampf(SignalGeom.project(path, centre) * plen, 0.0, plen)
	return plen


## Cubic-out easing applied to SimulationManager.alpha (docs/MOTION_SYSTEM.md §1: one easing).
static func _ease(a: float) -> float:
	var x := 1.0 - clampf(a, 0.0, 1.0)
	return 1.0 - x * x * x