class_name PacketLayer
extends Node2D
## Packets as continuous motion over a discrete simulation (docs/MOTION_SYSTEM.md §1).
##
## Every tick each visible packet gets a LOGICAL location:
##   wire   — slot i of n on a connection path: arc = L·(i+1)/(n+1) (anchors at 0 and L,
##            so every step along a wire covers the same distance → constant velocity)
##   dock   — waiting in an input queue, just inside the input port
##   out    — result waiting in an output slot (docked at the output port)
##   queued — output blocked: held PKT_QUEUE_OFFSET outside the output port
## Between two ticks a packet moves from its previous location to its current one along a
## transition polyline built from the real geometry (sub-path of the wire incl. every
## chamfered corner, → port anchor → core …), at a constant speed: t = tick fraction.
## Values are never drawn inside a machine: a value fades into the input port, and when the
## job finishes the transformed result appears at the output port and leaves. The machine's
## ActivityArea progress shows the work in between.

const T := Palette.TILE
const QUEUE_STACK := 6.0  # px between packets stacked inside an input queue
const DOCK_IN := 10.0  # px a docked packet sits inside its port
const EXIT_IN := 12.0  # px inside the output port where a finished value waits to leave
const LONG_LABEL := 5  # labels longer than this flip into a small tag above the packet
const LABEL_SIZE := 9  # close-tier packet value font size
const TAG_ABOVE := 14.0  # tag offset above the packet centre
const TAG_RADIUS := 3  # tag corner radius
const TAG_PAD := 3.0  # horizontal padding inside the tag
const TAG_ROW_PAD := 1.0  # vertical padding inside the tag

var _tier := "normal"  # CameraRig zoom tier ("far" | "normal" | "close")
var _last_tick := -1  # simulation tick whose transitions are cached
var _loc := {}  # packet id -> logical location {k, pos, conn, arc} (current tick)
var _moves := {}  # packet id -> {packet, poly: PackedVector2Array, state, conn, arc0, arc1, fade}
var _paths := {}  # connection id -> PackedVector2Array (simplified + chamfered draw path)
var _lane_paths := {}  # "cid:lane" -> PackedVector2Array (offset lane path)
var _tag_style: StyleBoxFlat = null
var _path_lens := {}  # connection id -> length of its draw path (px)
var _consumed := {}  # this tick: packet id -> the machine that took it (deliver/output/discard)
var _emitted := {}  # this tick: packet id -> its emit event
var _comets := {}  # connection id -> comet arcs (px), rebuilt once per frame / tick fraction
var _comet_frame := -1
var _comet_t := -1.0


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


## Layout edits replace wires/queues wholesale: drop every cached location and path.
func _on_board_reset(_v: Variant = null) -> void:
	_paths.clear()
	_lane_paths.clear()
	_path_lens.clear()
	_loc.clear()
	_moves.clear()
	_last_tick = -1


func _process(_delta: float) -> void:
	_capture()
	queue_redraw()


## Visual tick fraction: continuous while running; a paused board shows its current state.
static func frac() -> float:
	return clampf(SimulationManager.alpha, 0.0, 1.0) if SimulationManager.running else 1.0


# ------------------------------------------------------------------ tick capture

## On a new tick: compute every packet's logical location and the transition polyline from
## its previous location.
func _capture() -> void:
	var sim := SimulationManager.sim
	if sim == null or sim.tick == _last_tick:
		return
	if sim.tick < _last_tick or sim.tick == 0:
		_loc.clear()
	_last_tick = sim.tick
	_index_events(sim)
	var now := _locations(sim)  # id -> {k, pos, conn, arc, packet, machine}
	var moves := {}
	for pid in now:
		var cur: Dictionary = now[pid]
		var prev: Dictionary = _loc[pid] if _loc.has(pid) else _spawn(sim, cur)
		moves[pid] = _transition(prev, cur)
	# packets that left the board this tick (consumed by a sink, discarded): glide into the
	# machine core and fade.
	for pid in _loc:
		if now.has(pid):
			continue
		var prev: Dictionary = _loc[pid]
		if prev.get("packet") == null:
			continue
		var mid := _consumer(sim, pid)
		var into_pos: Vector2
		if prev["k"] == "wire" and sim.connections.has(int(prev["conn"])):
			# taken straight off a wire (a job started / a sink consumed it): into the port
			var c: Connection = sim.connections[int(prev["conn"])]
			if not sim.machines.has(c.to_id):
				continue
			mid = c.to_id
			into_pos = _dock(sim.machines[c.to_id], c.to_port, DOCK_IN)
		elif prev["k"] == "dock":
			into_pos = prev["pos"]  # a queued value taken into a job: vanish where it waited
		elif mid >= 0:
			into_pos = _core(mid)
		else:
			continue
		var into := {"k": "core", "pos": into_pos, "packet": prev["packet"], "machine": mid}
		var mv := _transition(prev, into)
		mv["fade"] = true
		moves[pid] = mv
	_loc = now
	_moves = moves


## This tick's events by packet id, first match per kind group (one pass instead of a scan per
## packet): "consumed" = the first deliver / output / discard, "emit" = the first emit.
func _index_events(sim: Simulation) -> void:
	_consumed = {}
	_emitted = {}
	for e in sim.events:
		var pid := int(e.get("packet", -1))
		if pid < 0:
			continue
		var k: String = e.get("kind", "")
		if k == "emit":
			if not _emitted.has(pid):
				_emitted[pid] = e
		elif k == "deliver" or k == "output" or k == "discard":
			if not _consumed.has(pid):
				_consumed[pid] = int(e.get("machine", -1))


## Where a packet that disappeared this tick went (deliver/output/discard events).
func _consumer(_sim: Simulation, pid: int) -> int:
	return int(_consumed.get(pid, -1))


## Logical locations of every packet visible on the board at the current tick.
func _locations(sim: Simulation) -> Dictionary:
	var out := {}
	for cid in sim.sorted_connection_ids():
		var c: Connection = sim.connections[cid]
		var path := _path(cid)
		if path.size() < 2:
			continue
		var n: int = c.slots.size()
		var plen := _path_len(cid)
		for e in c.all_packets():
			out[e["packet"].id] = {"k": "wire", "conn": cid, "lane": e["lane"], "arc": plen * float(int(e["slot"]) + 1) / float(n + 1), "packet": e["packet"]}
	for mid in sim.sorted_machine_ids():
		var m: Machine = sim.machines[mid]
		for port in m.inq:
			var j := 0
			for p in m.inq[port]:
				out[p.id] = {"k": "dock", "pos": _dock(m, port, DOCK_IN + float(j) * QUEUE_STACK), "packet": p, "machine": mid}
				j += 1
		# A job's value is NOT drawn: it disappeared into the input port and reappears,
		# transformed, at the output when the job finishes (the ActivityArea shows the work).
		for port in m.outq:
			var op: Packet = m.outq[port]
			if op == null:
				continue
			if m.state == Machine.State.BLOCKED:
				out[op.id] = {"k": "queued", "pos": _dock(m, port, -float(Palette.PKT_QUEUE_OFFSET)), "packet": op, "machine": mid, "port": port}
			else:
				out[op.id] = {"k": "out", "pos": _dock(m, port, DOCK_IN), "packet": op, "machine": mid, "port": port}
	return out


## Where a packet first seen this tick comes from: a machine's result appears at that
## machine's core; a fresh source packet at the source core; anything else where it is.
func _spawn(sim: Simulation, cur: Dictionary) -> Dictionary:
	var p: Packet = cur["packet"]
	if _emitted.has(p.id):
		var e: Dictionary = _emitted[p.id]
		var mid := int(e.get("machine", -1))
		if sim.machines.has(mid):
			# a job result appears just inside the port it leaves from and fades in on its
			# way onto the wire (the value itself was never drawn inside the machine)
			var src: Machine = sim.machines[mid]
			var from_job: bool = not src.inq.is_empty()  # machines with inputs emit job results; sources do not
			return {"k": "core", "pos": _dock(src, str(e.get("port", "out")), EXIT_IN), "packet": p, "machine": mid, "appear": from_job}
	if cur.has("port") and sim.machines.has(int(cur["machine"])):
		# a fresh value in an output slot (sources): appears just inside that port
		return {"k": "core", "pos": _dock(sim.machines[int(cur["machine"])], str(cur["port"]), EXIT_IN), "packet": p, "machine": cur["machine"]}
	if cur.has("machine"):
		return {"k": "core", "pos": _core(int(cur["machine"])), "packet": p, "machine": cur["machine"]}
	return cur


## Transition polyline from one logical location to the next, along the real geometry.
## Multi-lane wires ride their lane offset path (arc lengths stay those of the centre
## path — the difference is negligible).
func _transition(a: Dictionary, b: Dictionary) -> Dictionary:
	var poly := PackedVector2Array()
	var state := "normal"
	var ka: String = a["k"]
	var kb: String = b["k"]
	if ka == "wire" and kb == "wire" and a["conn"] == b["conn"]:
		var cid := int(a["conn"])
		var path := _path(cid)
		if _lanes_of(cid) > 1:
			path = _lane_path(cid, int(a.get("lane", 0)))
		poly = SignalGeom.sub_poly_arc(path, float(a["arc"]), float(b["arc"]))
	elif ka == "wire":
		# leaving the wire into a port: rest of the wire to its end anchor, then inside
		var cid := int(a["conn"])
		var path := _path(cid)
		if _lanes_of(cid) > 1:
			path = _lane_path(cid, int(a.get("lane", 0)))
		poly = SignalGeom.sub_poly_arc(path, float(a["arc"]), _path_len(cid))
		poly.append(b["pos"])
		state = "entering"
	elif kb == "wire":
		# undocking onto a wire: from inside the port to the anchor, then along the wire
		var cid := int(b["conn"])
		var path := _path(cid)
		if _lanes_of(cid) > 1:
			path = _lane_path(cid, int(b.get("lane", 0)))
		poly.append(a["pos"])
		poly.append_array(SignalGeom.sub_poly_arc(path, 0.0, float(b["arc"])))
		state = "leaving"
	else:
		poly.append(a["pos"])
		poly.append(b["pos"])
		match kb:
			"core": state = "processing"
			"queued": state = "queued"
	if poly.is_empty():
		poly.append(_point(b))
	var mv := {"packet": b["packet"], "poly": poly, "state": state, "to": b, "from_k": a["k"], "appear": a.get("appear", false)}
	if ka == "wire" and kb == "wire" and a["conn"] == b["conn"]:
		mv["arc0"] = float(a["arc"])  # along its own wire: the comet arc interpolates exactly
	return mv


func _point(loc: Dictionary) -> Vector2:
	if loc["k"] == "wire":
		var cid := int(loc["conn"])
		var path := _path(cid)
		if _lanes_of(cid) > 1:
			path = _lane_path(cid, int(loc.get("lane", 0)))
		var plen := maxf(_path_len(cid), 1e-9)
		return SignalGeom.sample(path, clampf(float(loc["arc"]) / plen, 0.0, 1.0))[0]
	return loc["pos"]


## Constant-speed position along a transition at tick fraction t.
static func _along(poly: PackedVector2Array, t: float) -> Vector2:
	if poly.size() == 1:
		return poly[0]
	return SignalGeom.sample(poly, clampf(t, 0.0, 1.0))[0]


# ------------------------------------------------------------------ geometry helpers

func _path(cid: int) -> PackedVector2Array:
	if not _paths.has(cid):
		var sim := SimulationManager.sim
		if sim == null or not sim.connections.has(cid):
			return PackedVector2Array()
		_paths[cid] = _build_path(sim.connections[cid])
		_path_lens[cid] = SignalGeom.poly_len(_paths[cid])
	return _paths[cid]


func _path_len(cid: int) -> float:
	_path(cid)
	return float(_path_lens.get(cid, 0.0))


## Lane count of a connection (1 when unknown).
func _lanes_of(cid: int) -> int:
	var sim := SimulationManager.sim
	if sim != null and sim.connections.has(cid):
		return sim.connections[cid].lanes
	return 1


## Offset lane path for a connection lane: the centre draw path shifted perpendicular by
## SignalGeom.lane_offsets(width, lanes)[lane], cached like `_paths`. Arc lengths along a
## lane are (nearly) those of the centre path, so the same arcs are reused.
func _lane_path(cid: int, lane: int) -> PackedVector2Array:
	var key := "%d:%d" % [cid, lane]
	if not _lane_paths.has(key):
		var sim := SimulationManager.sim
		if sim == null or not sim.connections.has(cid):
			return PackedVector2Array()
		var c: Connection = sim.connections[cid]
		_lane_paths[key] = SignalGeom.offset_poly(_path(cid), SignalGeom.lane_offsets(c.width, c.lanes)[lane])
	return _lane_paths[key]


## The input port a job's packet arrived through (the last machine on its path), or "".
func _input_port_of(m: Machine, p: Packet) -> String:
	var sim := SimulationManager.sim
	for port in m.inq:
		var c: Connection = sim.connection_at_port(m.id, port)
		if c != null and _loc.has(p.id) and _loc[p.id].get("conn", -1) == c.id:
			return port
	for port in m.inq:
		return port
	return ""


## A point `inset` px inside (negative: outside) the machine along a port's axis.
func _dock(m: Machine, port: String, inset: float) -> Vector2:
	var inward := -Vector2(Catalog.side_vec(m.port_geom(port)["side"]))
	return MachineView.port_world(m, port) + inward * inset


## World centre of a machine's function region (ActivityArea), or its footprint centre.
func _core(mid: int) -> Vector2:
	var mv := get_parent().get_node_or_null("MachineLayer/Machine_%d" % mid) as MachineView
	if mv != null:
		return mv.core_world()
	var sim := SimulationManager.sim
	if sim != null and sim.machines.has(mid):
		var m: Machine = sim.machines[mid]
		return (Vector2(m.cell) + Vector2(Catalog.size_of(m.type, m.rot)) * 0.5) * T
	return Vector2.ZERO


## Same draw path as ConnectionView: [port anchor] + tile centres + [anchor], simplified and
## chamfered (SignalGeom.chamfer_for) with the Signal System V1 geometry.
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
	return SignalGeom.chamfer(raw, SignalGeom.chamfer_for(c.width, c.lanes))


# ------------------------------------------------------------------ queries

## Comet-head arc lengths (px along the connection path) for packets travelling on
## `conn_id`, from the same interpolation the sprites use (ConnectionView.packet_positions).
func comet_arcs(conn_id: int) -> Array:
	_capture()
	var t := frac()
	var f := Engine.get_process_frames()
	if f != _comet_frame or t != _comet_t:
		_comet_frame = f
		_comet_t = t
		_build_comets(t)
	return _comets.get(conn_id, [])


## Every wire's comet arcs in one pass over the moves (each wire asks once per frame). A value
## gliding along its own wire sits at the interpolated arc; one joining a wire is projected.
func _build_comets(t: float) -> void:
	_comets = {}
	for pid in _moves:
		var mv: Dictionary = _moves[pid]
		var to: Dictionary = mv["to"]
		if to["k"] != "wire":
			continue
		var cid := int(to["conn"])
		var path := _path(cid)
		if _lanes_of(cid) > 1:
			path = _lane_path(cid, int(to.get("lane", 0)))
		var plen := _path_len(cid)
		if plen <= 0.0:
			continue
		var arc: float
		if mv.has("arc0"):
			arc = lerpf(float(mv["arc0"]), float(to["arc"]), clampf(t, 0.0, 1.0))
		else:
			arc = SignalGeom.project(path, _along(mv["poly"], t)) * plen
		if not _comets.has(cid):
			_comets[cid] = []
		(_comets[cid] as Array).append(arc)


## World positions of every drawn packet, packet id -> Vector2 (tools' hit testing).
func drawn_packet_positions() -> Dictionary:
	_capture()
	var out := {}
	var t := frac()
	for pid in _moves:
		if not _moves[pid].get("fade", false):
			out[pid] = _along(_moves[pid]["poly"], t)
	return out


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if SimulationManager.sim == null:
		return
	_capture()
	var t := frac()
	for pid in _moves:
		var mv: Dictionary = _moves[pid]
		var pos := _along(mv["poly"], t)
		var state: String = mv["state"]
		var scale_k := 1.0
		var mod := Color.WHITE
		if mv.get("fade", false):
			scale_k = lerpf(1.0, 0.6, t)
			mod = Color(1, 1, 1, lerpf(Palette.PKT_ENTERING_OPACITY, 0.0, t))
			state = "entering"
		elif state == "entering":
			mod = Color(1, 1, 1, lerpf(1.0, Palette.PKT_ENTERING_OPACITY, t))
		elif state == "processing":
			mod = Color(1, 1, 1, 0.6)
		var label := true
		if mv.get("appear", false):
			# a machine's result: appears at the output port as it leaves
			mod = Color(1, 1, 1, t)
			scale_k = lerpf(0.6, 1.0, t)
		var to: Dictionary = mv["to"]
		if to["k"] == "wire" and _lanes_of(int(to["conn"])) > 1 and not mv.get("fade", false):
			_draw_bead(mv, pos, t, mod)
		else:
			_draw_packet(mv["packet"], pos, state, scale_k, mod, label)


## Raw packets are the IO-green RawToken pill (no sprite, no halo, design/reference/systems_v1.js
## rawToken); everything else keeps the width-tagged sprite chip.
func _draw_packet(p: Packet, pos: Vector2, state: String, scale_k: float, mod: Color, label := true) -> void:
	if p.is_raw():
		var rst := "normal"
		if state == "queued":
			rst = "queued"
		elif state == "entering" and mod.a > 0.999:
			rst = "entering"
		SystemsDraw.raw_token(self, pos, _tier, rst, p.raw.glyph(), TclTheme.font(SystemsDraw.FONT), mod.a)
		return
	var w: int = p.data.width
	var tex := Art.tex(Art.packet_file(w, _tier, state))
	if tex == null:
		return
	var design := Vector2(tex.get_width(), tex.get_height()) / Art.SCALE
	var rect := Rect2(pos - design * 0.5 * scale_k, design * scale_k)
	draw_texture_rect(tex, rect, false, mod)
	if _tier == "close" and label:
		_draw_label(p, pos, design * scale_k)


## Multi-lane bead: a packet riding a lane of a bus wire draws a short tail + capsule head
## instead of the chip sprite (the lane cores are too thin for a chip). The tail is the last
## SIG_BEAD_TAIL px of the lane path behind the head; the head is a capsule along the path
## with a data-colour centre line. The transform is reset before returning.
func _draw_bead(mv: Dictionary, pos: Vector2, t: float, mod: Color) -> void:
	var to: Dictionary = mv["to"]
	var cid := int(to["conn"])
	var lane := int(to.get("lane", 0))
	var sim := SimulationManager.sim
	if sim == null or not sim.connections.has(cid):
		return
	var c: Connection = sim.connections[cid]
	var p: Packet = mv["packet"]
	var lane_path := _lane_path(cid, lane)
	var plen := maxf(SignalGeom.poly_len(lane_path), 1e-9)
	var head_arc: float
	if mv.has("arc0"):
		head_arc = lerpf(float(mv["arc0"]), float(to["arc"]), clampf(t, 0.0, 1.0))
	else:
		head_arc = SignalGeom.project(lane_path, pos) * plen
	var data_col := Palette.FAMILY_IO if p.is_raw() else Palette.datatype(c.width)
	var tail_len := float(Palette.SIG_BEAD_TAIL_DENSE) if c.lanes > 2 else float(Palette.SIG_BEAD_TAIL)
	var tail := SignalGeom.sub_poly_arc(lane_path, maxf(head_arc - tail_len, 0.0), head_arc)
	if tail.size() >= 2:
		draw_polyline(tail, Color(data_col, 0.35 * mod.a), SignalGeom.lane_core_width(c.lanes) + 1.0, true)
	var s := SignalGeom.sample(lane_path, clampf(head_arc / plen, 0.0, 1.0))
	var dir: Vector2 = s[1]
	var hl := 6.0 if c.lanes > 2 else 9.0
	var hh := 2.4 if c.lanes > 2 else 3.6
	draw_set_transform(pos, dir.angle(), Vector2.ONE)
	SystemsDraw.rrect(self, Rect2(Vector2(-hl * 0.5, -hh * 0.5), Vector2(hl, hh)), hh * 0.5, Color(Palette.TEXT_PRIMARY, mod.a))
	draw_line(Vector2(-(hl - 3.0) * 0.5, 0.0), Vector2((hl - 3.0) * 0.5, 0.0), Color(data_col, mod.a), hh - 1.2, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Close tier: the packet's bits as 0 / 1, DATA_NUMBER (DATA_BOOLEAN for width 1), centred on
## the chip. Bits always read as bits — a letter or a number is a raw token (drawn above), so an
## encoder or decoder visibly changes what travels: H → 00111 → K. Labels longer than 5
## characters go in a small tag 14 px above the packet instead (MACHINE_SCREEN fill, 1 px
## MATERIAL_FRAME stroke, radius 3).
func _draw_label(p: Packet, pos: Vector2, size: Vector2) -> void:
	var text := ViewMode.format(p.data, ViewMode.Mode.BIN)
	var pw: int = p.data.width
	if pw <= 5:
		text = text.replace(" ", "")  # compact on the chip (10101 fits; the panels keep 1 0101)
	var color := Palette.DATA_NUMBER if pw > 1 else Palette.DATA_BOOLEAN
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
