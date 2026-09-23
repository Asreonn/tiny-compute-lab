class_name Simulation
extends RefCounted
## The whole board as pure data + the deterministic tick. No nodes, no rendering, no
## SceneTree ordering: machines and connections are always iterated by ascending id.
##
## Tick order (documented in docs/ARCHITECTURE.md):
##   1. clear per-tick flags
##   2. DELIVER   — each wire hands its head packet to the target port if it has room
##   3. MOVE      — each wire shifts packets one slot forward (conveyor)
##   4. PROCESS   — each busy machine advances its job; finished results land in output slots
##   5. EMIT      — each machine pushes output-slot packets onto its wire if the entry is free
##   6. START     — idle machines consume inputs and start jobs (sources emit, sinks validate)
##   7. STATE     — machine visual states are derived (BLOCKED / PROCESSING / …)
##   8. VALIDATE  — mission pass/fail checks
##   9. METRICS   — rates, latency, bottleneck

signal changed  # layout changed (place/remove/connect/…)

const TICKS_PER_SEC := 10
const RATE_WINDOW := 30
const STALL_TICKS := 60

var size := Vector2i(20, 12)
var machines: Dictionary = {}  # id -> Machine
var connections: Dictionary = {}  # id -> Connection
var _next_machine_id := 1
var _next_conn_id := 1
var _next_packet_id := 1
var tick := 0

# port index: "mid:port" -> connection id
var _conn_at_port: Dictionary = {}

var mission: MissionRun = null
var default_width := 0  # mission configuration; never a global constant
var events: Array = []  # [{kind, ...}] produced this tick for the view/debugger

# metrics
var _in_times: Array[int] = []
var _out_times: Array[int] = []
var latency_sum := 0
var latency_n := 0
var latency_min := 0
var latency_max := 0
var outputs_total := 0
var first_output_tick := -1
var last_output_tick := -1
var last_activity_tick := 0


# ============================================================ layout

func clear() -> void:
	machines.clear()
	connections.clear()
	_conn_at_port.clear()
	_next_machine_id = 1
	_next_conn_id = 1
	reset_run()
	changed.emit()


func sorted_machine_ids() -> Array:
	var ids := machines.keys()
	ids.sort()
	return ids


func sorted_connection_ids() -> Array:
	var ids := connections.keys()
	ids.sort()
	return ids


func occupancy(ignore_id: int = -1) -> Dictionary:
	var occ := {}
	for id in machines:
		if id == ignore_id:
			continue
		for c in machines[id].footprint():
			occ[c] = id
	return occ


func wire_tiles(ignore_conn: int = -1) -> Dictionary:
	var w := {}
	for id in connections:
		if id == ignore_conn:
			continue
		for c in connections[id].cells:
			w[c] = id
	return w


func machine_at(c: Vector2i) -> Machine:
	for id in sorted_machine_ids():
		if c in machines[id].footprint():
			return machines[id]
	return null


## Returns "" when placement is valid, otherwise a player-facing reason.
func placement_error(type: String, cell: Vector2i, rot: int, ignore_id: int = -1) -> String:
	var s := Catalog.size_of(type, rot)
	var occ := occupancy(ignore_id)
	for y in s.y:
		for x in s.x:
			var c := cell + Vector2i(x, y)
			if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
				return "Outside the board"
			if occ.has(c):
				return "Tile occupied by " + machines[occ[c]].label
	if mission != null and not mission.allows(type):
		return "Not available in this mission"
	return ""


## width 0 means the simulation's mission default_width; a resolved width < 1 is an error.
func place(type: String, cell: Vector2i, rot: int = 0, params: Dictionary = {}, width: int = 0) -> Machine:
	var w := width if width != 0 else default_width
	if w < Catalog.MIN_WIDTH:
		push_error("Simulation.place: no width for %s (default_width is %d)" % [type, default_width])
		return null
	if placement_error(type, cell, rot) != "":
		return null
	var m := Machine.new(_next_machine_id, type, cell, w, rot, params)
	_next_machine_id += 1
	machines[m.id] = m
	_reroute_blocked()
	changed.emit()
	return m


func add_machine(m: Machine) -> void:
	m.id = _next_machine_id
	m.label = "%s #%d" % [Catalog.def(m.type)["name"], m.id]
	_next_machine_id += 1
	machines[m.id] = m


func remove(id: int) -> bool:
	if not machines.has(id) or machines[id].locked:
		return false
	for cid in sorted_connection_ids():
		var c: Connection = connections[cid]
		if c.from_id == id or c.to_id == id:
			disconnect_wire(cid, false)
	machines.erase(id)
	changed.emit()
	return true


func rotate(id: int) -> bool:
	if not machines.has(id) or machines[id].locked:
		return false
	var m: Machine = machines[id]
	var nr := (m.rot + 1) % 4
	if placement_error(m.type, m.cell, nr, id) != "":
		return false
	m.rot = nr
	_reroute_machine(id)
	changed.emit()
	return true


## Move a machine to a new cell. Refuses locked machines and invalid placement (the
## existing tiles are ignored via placement_error's ignore_id), reroutes every wire that
## touches the machine, and emits changed. Returns false without touching the board when
## the move is refused.
func move(id: int, cell: Vector2i) -> bool:
	if not machines.has(id) or machines[id].locked:
		return false
	var m: Machine = machines[id]
	if placement_error(m.type, cell, m.rot, id) != "":
		return false
	m.cell = cell
	_reroute_machine(id)
	changed.emit()
	return true


func set_param(id: int, key: String, value: Variant) -> void:
	if machines.has(id):
		machines[id].params[key] = value
		changed.emit()


## Change an instance width. Refuses locked machines and out-of-range widths.
## Disconnects every wire whose endpoints no longer match and returns their ids.
func set_width(id: int, w: int) -> Array:
	var removed: Array = []
	if not machines.has(id):
		return removed
	var m: Machine = machines[id]
	if m.locked:
		return removed
	if w < Catalog.MIN_WIDTH or w > Catalog.MAX_WIDTH:
		return removed
	m.width = w
	for cid in sorted_connection_ids():
		var c: Connection = connections[cid]
		if c.from_id != id and c.to_id != id:
			continue
		var wa: int = machines[c.from_id].port_width(c.from_port)
		var wb: int = machines[c.to_id].port_width(c.to_port)
		if wa != wb:
			removed.append(cid)
	for cid in removed:
		disconnect_wire(cid, false)
	changed.emit()
	return removed


# ============================================================ wiring

func connection_at_port(mid: int, port: String) -> Connection:
	var k := "%d:%s" % [mid, port]
	return connections.get(_conn_at_port.get(k, -1), null)


func output_connected(m: Machine, port: String) -> bool:
	return connection_at_port(m.id, port) != null


## Why a connection from (a, pa) to (b, pb) is impossible, or "" when it is valid.
func connect_error(a: int, pa: String, b: int, pb: String) -> String:
	if not machines.has(a) or not machines.has(b):
		return "Missing machine"
	if a == b:
		return "Cannot wire a machine to itself"
	var ma: Machine = machines[a]
	var mb: Machine = machines[b]
	var ga := ma.port_geom(pa)
	var gb := mb.port_geom(pb)
	if ga["dir"] != Catalog.DIR_OUT:
		return "Wires start at an output port"
	if gb["dir"] == Catalog.DIR_OUT:
		return "Target must be an input or control port"
	if ga["width"] != gb["width"]:
		return "%d-bit output cannot connect to a %d-bit input. Use a width converter." % [ga["width"], gb["width"]]
	if connection_at_port(a, pa) != null:
		return "Output already wired"
	if connection_at_port(b, pb) != null:
		return "Input already wired"
	return ""


## Compute a route between two ports (used for the drag preview too).
func route_between(a: int, pa: String, b: int, pb: String, ignore_conn: int = -1) -> Dictionary:
	var ga: Dictionary = machines[a].port_geom(pa)
	var gb: Dictionary = machines[b].port_geom(pb)
	# touching ports: wire of zero tiles
	if ga["outside"] == gb["cell"] and gb["outside"] == ga["cell"]:
		return {"ok": true, "cells": [] as Array[Vector2i]}
	var sd: Vector2i = Catalog.side_vec(ga["side"])
	var gd: Vector2i = -Catalog.side_vec(gb["side"])
	var cells := Router.route(size, occupancy(), wire_tiles(ignore_conn), ga["outside"], sd, gb["outside"], gd)
	return {"ok": not cells.is_empty(), "cells": cells}


func connect_ports(a: int, pa: String, b: int, pb: String) -> Connection:
	if connect_error(a, pa, b, pb) != "":
		return null
	var r := route_between(a, pa, b, pb)
	if not r["ok"]:
		return null
	var c := Connection.new(_next_conn_id, a, pa, b, pb, r["cells"], machines[a].port_width(pa))
	_next_conn_id += 1
	connections[c.id] = c
	_conn_at_port["%d:%s" % [a, pa]] = c.id
	_conn_at_port["%d:%s" % [b, pb]] = c.id
	changed.emit()
	return c


func disconnect_wire(cid: int, notify := true) -> void:
	if not connections.has(cid):
		return
	var c: Connection = connections[cid]
	_conn_at_port.erase("%d:%s" % [c.from_id, c.from_port])
	_conn_at_port.erase("%d:%s" % [c.to_id, c.to_port])
	connections.erase(cid)
	if notify:
		changed.emit()


func _reroute(cid: int) -> void:
	var c: Connection = connections[cid]
	var r := route_between(c.from_id, c.from_port, c.to_id, c.to_port, cid)
	if r["ok"]:
		c.cells = r["cells"]
		c.reset()
	else:
		disconnect_wire(cid, false)


func _reroute_machine(id: int) -> void:
	for cid in sorted_connection_ids():
		if connections.has(cid) and (connections[cid].from_id == id or connections[cid].to_id == id):
			_reroute(cid)


## After a placement, any wire running through the new footprint is re-routed.
func _reroute_blocked() -> void:
	var occ := occupancy()
	for cid in sorted_connection_ids():
		if not connections.has(cid):
			continue
		for cell in connections[cid].cells:
			if occ.has(cell):
				_reroute(cid)
				break


# ============================================================ run

func new_packet_id() -> int:
	var i := _next_packet_id
	_next_packet_id += 1
	return i


func reset_run() -> void:
	tick = 0
	_next_packet_id = 1
	for id in machines:
		machines[id].reset()
	for id in connections:
		connections[id].reset()
	if mission != null:
		mission.reset(self)
	events = []
	_in_times = []
	_out_times = []
	latency_sum = 0
	latency_n = 0
	latency_min = 0
	latency_max = 0
	outputs_total = 0
	first_output_tick = -1
	last_output_tick = -1
	last_activity_tick = 0


func step() -> void:
	if mission != null and mission.status != MissionRun.Status.RUNNING:
		return
	tick += 1
	events = []
	var mids := sorted_machine_ids()
	var cids := sorted_connection_ids()
	var activity := false
	# 1. clear flags
	for id in mids:
		machines[id].received_ports = PackedStringArray()
		machines[id].sent_ports = PackedStringArray()
	for id in cids:
		connections[id].blocked = false
		connections[id].moved_this_tick = false
	# 2. deliver
	for id in cids:
		var c: Connection = connections[id]
		var h := c.head()
		if h == null:
			continue
		var target: Machine = machines[c.to_id]
		if target.can_accept(c.to_port):
			target.accept(c.to_port, c.pop_head())
			events.append({"kind": "deliver", "packet": h.id, "machine": target.id, "port": c.to_port})
			activity = true
		else:
			c.blocked = true
	# 3. move
	for id in cids:
		connections[id].advance()
		activity = activity or connections[id].moved_this_tick
	# 4. process
	for id in mids:
		var m: Machine = machines[id]
		var had := not m.job.is_empty()
		m.advance(self)
		if had and m.job.is_empty():
			events.append({"kind": "complete", "machine": id})
			activity = true
	# 5. emit
	var blocked_now := {}
	for id in mids:
		var m: Machine = machines[id]
		for port in m.outq:
			var p: Packet = m.outq[port]
			if p == null:
				continue
			var c := connection_at_port(id, port)
			if c != null and c.entry_free():
				c.push(p)
				m.outq[port] = null
				m.sent_ports.append(port)
				events.append({"kind": "emit", "packet": p.id, "machine": id, "port": port})
				activity = true
			else:
				blocked_now[id] = true
	# 6. start
	for id in mids:
		var m: Machine = machines[id]
		var had := not m.job.is_empty()
		var before := m.emitted
		m.start(self)
		if (not had and not m.job.is_empty()) or m.emitted != before:
			activity = true
			if m.type == "input" and m.emitted != before:
				_in_times.append(tick)
	# 7. state
	for id in mids:
		var m: Machine = machines[id]
		m.update_state(blocked_now.has(id) and m.type != "input")
		if m.type == "input" and blocked_now.has(id):
			m.state = Machine.State.BLOCKED
	if activity:
		last_activity_tick = tick
	# 8. validate
	if mission != null:
		mission.after_tick(self)
	# 9. metrics
	_trim(_in_times)
	_trim(_out_times)


func _trim(a: Array[int]) -> void:
	while not a.is_empty() and a[0] <= tick - RATE_WINDOW:
		a.pop_front()


func packets_in_flight() -> int:
	var n := 0
	for id in connections:
		n += connections[id].packet_count()
	for id in machines:
		n += machines[id].packets_inside().size()
	return n


# ---- hooks called by machines

func note_output(m: Machine, p: Packet) -> void:
	var lat := tick - p.created_tick
	latency_sum += lat
	latency_n += 1
	latency_min = lat if latency_n == 1 else min(latency_min, lat)
	latency_max = max(latency_max, lat)
	outputs_total += 1
	if first_output_tick < 0:
		first_output_tick = tick
	last_output_tick = tick
	_out_times.append(tick)
	events.append({"kind": "output", "packet": p.id, "machine": m.id})
	if mission != null:
		mission.on_output(self, m, p)


func note_overflow(m: Machine, p: Packet) -> void:
	events.append({"kind": "overflow", "packet": p.id, "machine": m.id})
	if mission != null:
		mission.on_overflow(self, m, p)


func note_discard(m: Machine, p: Packet) -> void:
	events.append({"kind": "discard", "packet": p.id, "machine": m.id})


# ============================================================ metrics

func input_rate() -> float:
	return float(_in_times.size()) * TICKS_PER_SEC / float(min(max(tick, 1), RATE_WINDOW))


func output_rate() -> float:
	return float(_out_times.size()) * TICKS_PER_SEC / float(min(max(tick, 1), RATE_WINDOW))


func avg_latency() -> float:
	return float(latency_sum) / float(latency_n) if latency_n > 0 else 0.0


## Packets per second across the whole run (first → last output).
func throughput() -> float:
	if outputs_total < 2 or last_output_tick <= first_output_tick:
		return 0.0
	return float(outputs_total - 1) * TICKS_PER_SEC / float(last_output_tick - first_output_tick)


func total_power() -> int:
	var p := 0
	for id in machines:
		p += machines[id].power()
	return p


func component_count() -> int:
	var n := 0
	for id in machines:
		if not machines[id].locked:
			n += 1
	return n


## The machine most often busy with a full input queue (only when it matters).
func bottleneck() -> Machine:
	var best: Machine = null
	var best_v := 0
	for id in sorted_machine_ids():
		var m: Machine = machines[id]
		if m.type in ["input", "usb_input", "output", "terminal_output"]:
			continue
		if m.starved_full_ticks > best_v:
			best_v = m.starved_full_ticks
			best = m
	if best != null and tick > 0 and float(best_v) / float(tick) >= 0.2:
		return best
	return null


# ============================================================ persistence

func layout_to_dict() -> Dictionary:
	var ms := []
	var idx := {}
	for id in sorted_machine_ids():
		idx[id] = ms.size()
		ms.append(machines[id].to_dict())
	var cs := []
	for id in sorted_connection_ids():
		var c: Connection = connections[id]
		cs.append({"from": idx[c.from_id], "from_port": c.from_port, "to": idx[c.to_id], "to_port": c.to_port})
	return {"size": [size.x, size.y], "machines": ms, "connections": cs}


## Loads player machines + wires on top of the current board (locked IO stays).
func load_player_layout(d: Dictionary) -> void:
	var map := {}
	var locked_by_index := []
	for id in sorted_machine_ids():
		if machines[id].locked:
			locked_by_index.append(id)
	var li := 0
	var i := 0
	for md in d.get("machines", []):
		if md.get("locked", false):
			if li < locked_by_index.size():
				map[i] = locked_by_index[li]
				li += 1
		else:
			var m := place(md["type"], Vector2i(md["cell"][0], md["cell"][1]), int(md.get("rot", 0)), md.get("params", {}), int(md.get("width", 0)))
			if m != null:
				map[i] = m.id
		i += 1
	for cd in d.get("connections", []):
		if map.has(int(cd["from"])) and map.has(int(cd["to"])):
			connect_ports(map[int(cd["from"])], cd["from_port"], map[int(cd["to"])], cd["to_port"])
	changed.emit()
