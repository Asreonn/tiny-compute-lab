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

## The active run: MissionRun (tutorial) or LabRun (lab). Duck-typed on purpose so the lab
## and the tutorial share the Simulation without the core depending on either (docs §6).
var mission = null
var default_width := 0  # mission configuration; never a global constant
var campaign_timing := false  # campaign dwell times + 2 wire slots per tile (Catalog timing profiles)
var last_error := ""  # player-facing reason of the last refused edit (place/move/rotate/connect)
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
	m.campaign_timing = campaign_timing
	machines[m.id] = m
	# Wires crossing the new footprint are re-routed around it; if one cannot be, the
	# placement is refused — an existing wire is never silently deleted.
	var plan := _reroute_plan(_wires_through(m.footprint()))
	if plan.has("fail"):
		machines.erase(m.id)
		last_error = "Would cut the wire %s" % _wire_name(int(plan["fail"]))
		return null
	_next_machine_id += 1
	_apply_plan(plan)
	changed.emit()
	return m


func add_machine(m: Machine) -> void:
	m.id = _next_machine_id
	m.campaign_timing = campaign_timing
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
	last_error = placement_error(m.type, m.cell, nr, id)
	if last_error != "":
		return false
	return _relayout(m, m.cell, nr)


## Move a machine to a new cell. Refuses locked machines and invalid placement (the
## existing tiles are ignored via placement_error's ignore_id), reroutes every wire that
## touches the machine, and emits changed. Returns false without touching the board when
## the move is refused.
func move(id: int, cell: Vector2i) -> bool:
	if not machines.has(id) or machines[id].locked:
		return false
	var m: Machine = machines[id]
	last_error = placement_error(m.type, cell, m.rot, id)
	if last_error != "":
		return false
	return _relayout(m, cell, m.rot)


## Move/rotate a machine only if every affected wire (its own + wires crossing the new
## footprint) can be re-routed; otherwise nothing changes and last_error explains why.
func _relayout(m: Machine, cell: Vector2i, rot: int) -> bool:
	var old_cell := m.cell
	var old_rot := m.rot
	m.cell = cell
	m.rot = rot
	var ids := _wires_through(m.footprint())
	for cid in sorted_connection_ids():
		var c: Connection = connections[cid]
		if (c.from_id == m.id or c.to_id == m.id) and not cid in ids:
			ids.append(cid)
	var plan := _reroute_plan(ids)
	if plan.has("fail"):
		m.cell = old_cell
		m.rot = old_rot
		last_error = "Would cut the wire %s" % _wire_name(int(plan["fail"]))
		return false
	_apply_plan(plan)
	changed.emit()
	return true


## Connection ids whose routed tiles overlap `cells`.
func _wires_through(cells: Array) -> Array:
	var out := []
	for cid in sorted_connection_ids():
		for cell in connections[cid].cells:
			if cell in cells:
				out.append(cid)
				break
	return out


## New routes for `ids` on the current board, or {"fail": cid} when one has no route.
func _reroute_plan(ids: Array) -> Dictionary:
	var plan := {}
	for cid in ids:
		var c: Connection = connections[cid]
		var r := route_between(c.from_id, c.from_port, c.to_id, c.to_port, cid)
		if not r["ok"]:
			return {"fail": cid}
		plan[cid] = r["cells"]
	return plan


func _apply_plan(plan: Dictionary) -> void:
	for cid in plan:
		connections[cid].cells = plan[cid]
		connections[cid].reset()


func _wire_name(cid: int) -> String:
	var c: Connection = connections[cid]
	return "%s → %s" % [machines[c.from_id].label, machines[c.to_id].label]


## Set one machine parameter. If the param changes the width of any port that currently
## has a wire, the change is REFUSED (wires are never deleted) and false is returned.
## Returns true when applied.
func set_param(id: int, key: String, value: Variant) -> bool:
	if not machines.has(id):
		return false
	var m: Machine = machines[id]
	for p in m.ports():
		var w: Variant = p["width"]
		if typeof(w) != TYPE_STRING:
			continue
		var s: String = str(w)
		var used := (s.begins_with("P:") or s.begins_with("R:")) and s.substr(2) == key
		if used and connection_at_port(id, p["id"]) != null:
			last_error = "Unwire the ports first — the widths would change"
			return false
	m.params[key] = value
	changed.emit()
	return true


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


# ============================================================ devices

## Plug a data module into a lab socket (docs/SYSTEMS_EXPANSION.md §2). Refused when the
## socket's existing wire would become incompatible (a raw <-> bits change or a bits width
## change) — a wire is never silently broken; `last_error` explains it. The stream comes from
## the mission's contract (`stream_for_device`), or from `stream_override` for a specific
## socket (the lab's per-source stream).
func insert_device(machine_id: int, kind: String, stream_override: Dictionary = {}) -> bool:
	if not machines.has(machine_id) or not Devices.has(kind):
		return false
	var m: Machine = machines[machine_id]
	if not m.socket:
		return false
	var spec: Dictionary = stream_override if not stream_override.is_empty() else _device_stream_spec(kind)
	var stream := Devices.make_stream(kind, spec)
	var raw: bool = Devices.out_kind(kind) == "raw"
	var new_width := m.width
	if not raw:
		new_width = int(spec.get("width", 0))
		if new_width < 1 and not stream.is_empty() and stream[0] is BitVector:
			new_width = (stream[0] as BitVector).width
		if new_width < 1:
			new_width = m.width
	var conn := connection_at_port(machine_id, "out")
	if conn != null:
		var old_role := m.port_role("out")
		var new_role: String = Catalog.ROLE_RAW if raw else Catalog.ROLE_DATA
		var old_width: int = m.port_width("out")
		var new_w: int = 0 if raw else new_width
		if old_role != new_role or (new_role == Catalog.ROLE_DATA and old_width != new_w):
			last_error = "Unplug the wire first: the %s emits %s" % [Devices.display_name(kind), _device_emits_desc(kind, new_width)]
			return false
	m.device = kind
	m.last_device = kind
	m.stream = stream
	m.width = new_width
	m.interval = int(spec.get("interval", 4))
	m.pattern = spec.get("pattern", [])
	m.pattern_idx = 0
	m.fifo.clear()
	m.gen_seq = 0
	m.next_emit = tick + 1
	events.append({"kind": "device", "machine": machine_id, "device": kind})
	changed.emit()
	return true


## Unplug the module: no data flows, but the wire stays and the output role follows
## `last_device`, so the wire is never invalidated.
func remove_device(machine_id: int) -> bool:
	if not machines.has(machine_id):
		return false
	var m: Machine = machines[machine_id]
	if not m.socket:
		return false
	m.device = ""
	m.stream = []
	m.pattern = []
	m.fifo.clear()
	m.gen_seq = 0
	events.append({"kind": "device", "machine": machine_id, "device": ""})
	changed.emit()
	return true


## The current run's stream for a module kind, or {} when the mission has no contract for it.
func _device_stream_spec(kind: String) -> Dictionary:
	if mission != null and mission.has_method("stream_for_device"):
		var spec = mission.stream_for_device(kind)
		if spec is Dictionary:
			return spec
	return {}


## Player-facing description of what a module emits: "raw TEXT" or "3-bit words".
func _device_emits_desc(kind: String, width: int) -> String:
	var d: Dictionary = Devices.KINDS[kind]
	if str(d["out"]) == "bits":
		return "%d-bit words" % width
	return "raw " + RawValue.KIND_NAMES[int(d["raw_kind"])]


# ============================================================ wiring

func connection_at_port(mid: int, port: String) -> Connection:
	var k := "%d:%s" % [mid, port]
	return connections.get(_conn_at_port.get(k, -1), null)


func output_connected(m: Machine, port: String) -> bool:
	return connection_at_port(m.id, port) != null


## Why a connection from (a, pa) to (b, pb) is impossible, or "" when it is valid.
## `ignore`: connection ids that are about to be replaced (rewiring) and do not count as
## occupying their ports.
func connect_error(a: int, pa: String, b: int, pb: String, ignore: Array = []) -> String:
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
	# Raw links only join raw ports (docs/ARCHITECTURE.md §0 rule 7); a raw value can never
	# enter a compute machine. "*" sinks (the lab USB Output) take raw or bits.
	var raw_a: bool = ga["role"] == Catalog.ROLE_RAW
	var raw_b: bool = gb["role"] == Catalog.ROLE_RAW
	if raw_a or raw_b:
		if raw_a and not raw_b and str(mb.port_width_spec(pb)) != "*":
			return "Raw data must be encoded first"
		if raw_b and not raw_a and str(ma.port_width_spec(pa)) != "*":
			return "This input needs raw data (from a Decoder or USB module)"
	elif str(ma.port_width_spec(pa)) != "*" and str(mb.port_width_spec(pb)) != "*" and ga["width"] != gb["width"]:
		return "%d-bit output cannot connect to a %d-bit input. Use a width converter." % [ga["width"], gb["width"]]
	var ca := connection_at_port(a, pa)
	if ca != null and not ca.id in ignore:
		return "Output already wired"
	var cb := connection_at_port(b, pb)
	if cb != null and not cb.id in ignore:
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


## route: the exact tiles to use (the wire tool's WYSIWYG preview); null = auto-route.
func connect_ports(a: int, pa: String, b: int, pb: String, route: Variant = null) -> Connection:
	last_error = connect_error(a, pa, b, pb)
	if last_error != "":
		return null
	var cells: Array[Vector2i] = []
	if route == null:
		var r := route_between(a, pa, b, pb)
		if not r["ok"]:
			last_error = "No route"
			return null
		cells = r["cells"]
	else:
		cells.assign(route)
		last_error = route_error(a, pa, b, pb, cells)
		if last_error != "":
			return null
	var spt := Catalog.CAMPAIGN_SLOTS_PER_TILE if campaign_timing else 1
	var c := Connection.new(_next_conn_id, a, pa, b, pb, cells, machines[a].port_width(pa), spt)
	_next_conn_id += 1
	connections[c.id] = c
	_conn_at_port["%d:%s" % [a, pa]] = c.id
	_conn_at_port["%d:%s" % [b, pb]] = c.id
	# A "*" port resolves to the width of the wire that was just connected (source width).
	if str(machines[b].port_width_spec(pb)) == "*":
		machines[b].port_width_override[pb] = c.width
	if str(machines[a].port_width_spec(pa)) == "*":
		machines[a].port_width_override[pa] = c.width
	changed.emit()
	return c


## Wires a new (a, pa) -> (b, pb) connection would replace: the wire already on the source
## output and the wire already on the target input (rewiring, player QoL).
func replaced_by(a: int, pa: String, b: int, pb: String) -> Array:
	var out := []
	for c in [connection_at_port(a, pa), connection_at_port(b, pb)]:
		if c != null and not c.id in out:
			out.append(c.id)
	return out


## Rewire: validate the new connection as if the replaced wires were gone, and only if it is
## valid remove them and connect — atomically. On failure nothing changes (last_error says why).
func rewire(a: int, pa: String, b: int, pb: String, route: Variant = null) -> Connection:
	var old := replaced_by(a, pa, b, pb)
	last_error = connect_error(a, pa, b, pb, old)
	if last_error != "":
		return null
	# Resolve the route BEFORE removing anything, so a failure leaves the board untouched.
	var cells: Array[Vector2i] = []
	if route == null:
		var r := route_between(a, pa, b, pb)
		if not r["ok"]:
			last_error = "No route"
			return null
		cells = r["cells"]
	else:
		cells.assign(route)
	last_error = route_error(a, pa, b, pb, cells)
	if last_error != "":
		return null
	for cid in old:
		disconnect_wire(cid, false)
	return connect_ports(a, pa, b, pb, cells)


## Why an explicit route cannot be used, or "": it must start on the tile outside the source
## port, end on the tile outside the target port, step between 4-neighbours, stay on the board
## and never cross a machine.
func route_error(a: int, pa: String, b: int, pb: String, cells: Array) -> String:
	var ga: Dictionary = machines[a].port_geom(pa)
	var gb: Dictionary = machines[b].port_geom(pb)
	if cells.is_empty():
		return "" if ga["outside"] == gb["cell"] and gb["outside"] == ga["cell"] else "No route"
	if cells[0] != ga["outside"] or cells[cells.size() - 1] != gb["outside"]:
		return "No route"
	var occ := occupancy()
	for i in cells.size():
		var c: Vector2i = cells[i]
		if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y or occ.has(c):
			return "Route blocked"
		if i > 0 and absi(c.x - cells[i - 1].x) + absi(c.y - cells[i - 1].y) != 1:
			return "No route"
	return ""


func disconnect_wire(cid: int, notify := true) -> void:
	if not connections.has(cid):
		return
	var c: Connection = connections[cid]
	_conn_at_port.erase("%d:%s" % [c.from_id, c.from_port])
	_conn_at_port.erase("%d:%s" % [c.to_id, c.to_port])
	# A "*" port goes back to width 0 once its wire is gone.
	if machines.has(c.to_id) and str(machines[c.to_id].port_width_spec(c.to_port)) == "*":
		machines[c.to_id].port_width_override.erase(c.to_port)
	if machines.has(c.from_id) and str(machines[c.from_id].port_width_spec(c.from_port)) == "*":
		machines[c.from_id].port_width_override.erase(c.from_port)
	connections.erase(cid)
	if notify:
		changed.emit()


func _reroute(cid: int) -> void:
	var c: Connection = connections[cid]
	var r := route_between(c.from_id, c.from_port, c.to_id, c.to_port, cid)
	if r["ok"]:
		c.cells = r["cells"]
		c.reset()
	# no route: keep the wire as it is (a wire is never silently deleted)


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
			elif c != null:
				# BLOCKED means congestion: a wire exists but its entry is full. An output with
				# no wire is simply waiting (OUTPUT_READY), not blocked.
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
				var mid: int = locked_by_index[li]
				map[i] = mid
				var lm: Machine = machines[mid]
				if md.has("last_device"):
					lm.last_device = str(md["last_device"])
				var dev := str(md.get("device", ""))
				if dev != "":
					insert_device(mid, dev)  # false is ignored: the fresh board already has the socket
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
