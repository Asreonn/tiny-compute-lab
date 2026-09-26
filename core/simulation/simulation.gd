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
## Power capacity / demand cached once per step, before the process phase (deterministic).
var _cap := 0
var _demand := 0
## The power network (P5b): rebuilt from the mission's supply/onboard once per layout change.
var power_net: PowerNetwork = null
var _power_dirty := true
var _quiet := 0  # > 0 while a batch edit runs (apply_layout): `changed` fires once at the end
## The board heat field (SYSTEMS_EXPANSION §5); null until a run with heat steps.
var thermal: ThermalGrid = null
## Sealed port bays: cell -> view label (docs/SYSTEMS_EXPANSION.md §2.1). Reserved tiles are
## not buildable and wires cannot route through them. Mission boards leave it empty.
var reserved: Dictionary = {}
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
	reserved.clear()
	_next_machine_id = 1
	_next_conn_id = 1
	reset_run()
	_power_dirty = true
	_emit_changed()


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
		var m: Machine = machines[id]
		if Rect2i(m.cell, Catalog.size_of(m.type, m.rot)).has_point(c):
			return m
	return null


## True when `cell` is a sealed port bay (reserved): not buildable, wires cannot cross it.
func is_reserved(cell: Vector2i) -> bool:
	return reserved.has(cell)


## The view label of a sealed bay, e.g. "USB 2 · opens at L12"; "" when not reserved.
func reserved_label(cell: Vector2i) -> String:
	return str(reserved.get(cell, ""))


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
			if reserved.has(c):
				return "Sealed USB bay"
	if mission != null and not mission.allows(type):
		return "Not available in this mission"
	var pe := PowerNetwork.placement_error(self, type, cell)
	if pe != "":
		return pe
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
	_emit_changed()
	return m


func add_machine(m: Machine) -> void:
	m.id = _next_machine_id
	m.campaign_timing = campaign_timing
	m.label = "%s #%d" % [m.def()["name"], m.id]
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
	_emit_changed()
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
	if not machines.has(id) or not machines[id].movable():
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
	_emit_changed()
	return true


## Machine tiles plus reserved (sealed bay) tiles: what the router treats as walls.
func _routing_blocked() -> Dictionary:
	var b := occupancy()
	for c in reserved:
		b[c] = -1
	return b


## Connection ids whose routed tiles overlap `cells`.
func _wires_through(cells: Array) -> Array:
	var out := []
	for cid in sorted_connection_ids():
		for cell in connections[cid].cells:
			if cell in cells:
				out.append(cid)
				break
	return out


## Connected-move preview (SYSTEMS_EXPANSION §9): the route every affected wire (the machine's
## own and those crossing its new footprint) would take if machine `id` stood at `cell` / `rot`.
## Changes nothing. {ok, routes: {cid: cells}, fail: [cids], error}.
func relayout_preview(id: int, cell: Vector2i, rot: int) -> Dictionary:
	if not machines.has(id):
		return {"ok": false, "routes": {}, "fail": [], "error": "No such machine"}
	var m: Machine = machines[id]
	var err := placement_error(m.type, cell, rot, id)
	var routes := {}
	var fail := []
	if err == "":
		var old_cell := m.cell
		var old_rot := m.rot
		m.cell = cell
		m.rot = rot
		var ids := _wires_through(m.footprint())
		for cid in sorted_connection_ids():
			var c: Connection = connections[cid]
			if (c.from_id == id or c.to_id == id) and not cid in ids:
				ids.append(cid)
		for cid in ids:
			var c2: Connection = connections[cid]
			var r := route_between(c2.from_id, c2.from_port, c2.to_id, c2.to_port, cid)
			if r["ok"]:
				routes[cid] = r["cells"]
			else:
				fail.append(cid)
		m.cell = old_cell
		m.rot = old_rot
		if not fail.is_empty():
			err = "Would cut the wire %s" % _wire_name(int(fail[0]))
	return {"ok": err == "", "routes": routes, "fail": fail, "error": err}


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
	_emit_changed()
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
	_emit_changed()
	return removed


# ============================================================ upgrades

## The largest of {1, 2, 4, 8} that is <= n and <= cap; 1 when none fits.
static func _snap_lanes(n: int, cap: int) -> int:
	for k in [8, 4, 2, 1]:
		if n >= k and cap >= k:
			return k
	return 1


## Upgrade a machine's lanes (FACTORY_SYSTEMS §3.1): snap n to {1, 2, 4, 8} ≤ the def's
## max_lanes, store params["lanes"] = str(n), and clear the machine's running jobs/backlog like
## a param change. Refused (false + last_error) when the machine is locked, its def has one lane,
## or the run's max_lanes() gate is lower. One layout change: `changed` fires once.
func set_machine_lanes(id: int, n: int) -> bool:
	if not machines.has(id):
		return false
	var m: Machine = machines[id]
	if m.locked:
		last_error = "This machine is locked"
		return false
	var cap := maxi(1, int(m.def().get("max_lanes", 1)))
	if cap <= 1:
		last_error = "This machine has one lane"
		return false
	var v := _snap_lanes(n, cap)
	if mission != null and mission.has_method("max_lanes") and v > int(mission.max_lanes()):
		last_error = "Unlocks later"
		return false
	m.params["lanes"] = str(v)
	m.reset()  # a lane change clears running jobs / backlog like a param change
	_emit_changed()
	return true


## Upgrade a machine's efficiency (FACTORY_SYSTEMS §3.1): "efficient" trades one processing tick
## for ¾ power and ½ heat. Refused (false + last_error) when the run has not unlocked it yet.
func set_machine_efficiency(id: int, efficient: bool) -> bool:
	if not machines.has(id):
		return false
	if mission != null and mission.has_method("efficiency_unlocked") and not mission.efficiency_unlocked():
		last_error = "Unlocks later"
		return false
	var m: Machine = machines[id]
	m.params["efficiency"] = "efficient" if efficient else "standard"
	_emit_changed()
	return true


## Pure preview of an upgrade (FACTORY_SYSTEMS §7.3): for a machine and a proposed change
## {lanes?, width?, clock?, efficiency?} return {"rate_before", "rate_after", "power_before",
## "power_after", "heat_before", "heat_after"} where rate = lanes × clock work rate /
## (processing ticks × 12) × TICKS_PER_SEC (values per Lab second), power = power_demand() and
## heat = heat() × heat_mult() × lanes. Changes nothing: the "after" machine is a temporary
## Machine.new with the same type / params / width.
func upgrade_preview(id: int, change: Dictionary) -> Dictionary:
	if not machines.has(id):
		return {}
	var m: Machine = machines[id]
	var after := Machine.new(id, m.def_id(), m.cell, m.width, m.rot, m.params.duplicate(true))
	after.campaign_timing = m.campaign_timing
	if change.has("lanes"):
		after.params["lanes"] = str(int(change["lanes"]))
	if change.has("width"):
		after.width = int(change["width"])
	if change.has("clock"):
		after.params["clock"] = str(change["clock"])
	if change.has("efficiency"):
		var e: Variant = change["efficiency"]
		after.params["efficiency"] = "efficient" if (e is bool and bool(e)) or str(e) == "efficient" else "standard"
	return {
		"rate_before": m.rate_per_sec(),
		"rate_after": after.rate_per_sec(),
		"power_before": m.power_demand(),
		"power_after": after.power_demand(),
		"heat_before": m.heat() * m.heat_mult() * m.lanes(),
		"heat_after": after.heat() * after.heat_mult() * after.lanes(),
	}


# ============================================================ devices

## Plug a data module into a lab socket (docs/SYSTEMS_EXPANSION.md §2). Refused when the
## socket's existing wire would become incompatible (a raw <-> bits change or a bits width
## change) — a wire is never silently broken; `last_error` explains it. The stream comes from
## the mission's contract (`stream_for_device`), or from `stream_override` for a specific
## socket (the lab's per-source stream).
func insert_device(machine_id: int, kind: String, stream_override: Dictionary = {}) -> bool:
	if not machines.has(machine_id):
		return false
	var m: Machine = machines[machine_id]
	if m.type == "usb_output":
		return _insert_output_device(m, kind)
	if not Devices.has(kind):
		return false
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
	m.burst = maxi(1, int(spec.get("burst", 1)))
	m.pattern = spec.get("pattern", [])
	m.pattern_idx = 0
	m.fifo.clear()
	m.gen_seq = 0
	m.next_emit = tick + 1
	events.append({"kind": "device", "machine": machine_id, "device": kind})
	_emit_changed()
	return true


## Plug an output device ("job"|"monitor"|"") into an output port. There is exactly one
## job drive: plugging it elsewhere unplugs the previous port first. An empty port accepts
## nothing (Machine.can_accept returns false), so a wire into it stalls.
func _insert_output_device(m: Machine, kind: String) -> bool:
	if kind != "" and not Devices.has_output(kind):
		return false
	if kind != "" and kind != "monitor":
		# each drive is a single physical device: plugging it here unplugs it elsewhere
		for id in sorted_machine_ids():
			var o: Machine = machines[id]
			if o.type == "usb_output" and o.id != m.id and o.device == kind:
				o.device = ""
	m.device = kind
	if kind != "":
		m.last_device = kind
	events.append({"kind": "device", "machine": m.id, "device": kind})
	_emit_changed()
	return true


## Unplug the module: no data flows, but the wire stays and the output role follows
## `last_device`, so the wire is never invalidated.
func remove_device(machine_id: int) -> bool:
	if not machines.has(machine_id):
		return false
	var m: Machine = machines[machine_id]
	if m.type == "usb_output":
		m.device = ""
		events.append({"kind": "device", "machine": machine_id, "device": ""})
		_emit_changed()
		return true
	if not m.socket:
		return false
	m.device = ""
	m.stream = []
	m.pattern = []
	m.burst = 1
	m.fifo.clear()
	m.gen_seq = 0
	events.append({"kind": "device", "machine": machine_id, "device": ""})
	_emit_changed()
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
	var d: Dictionary = Devices.KINDS[Devices.base(kind)]
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
	var cells := Router.route(size, _routing_blocked(), wire_tiles(ignore_conn), ga["outside"], sd, gb["outside"], gd)
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
	_emit_changed()
	return c


## Set the number of parallel conveyors (lanes) on a wire; false when the wire does not
## exist. Counts snap to the valid set {1, 2, 4, 8} (Connection.set_lanes). Refused when the
## run's max_bus_lanes() gate is lower (FACTORY_SYSTEMS §2.1).
func set_wire_lanes(cid: int, n: int) -> bool:
	if not connections.has(cid):
		return false
	if mission != null and mission.has_method("max_bus_lanes") and n > int(mission.max_bus_lanes()):
		last_error = "Unlocks later"
		return false
	connections[cid].set_lanes(n)
	_emit_changed()
	return true


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
	var occ := _routing_blocked()
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
		_emit_changed()


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
	thermal = null
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
		connections[id].saturated = false
	var delivered := {}  # connection id -> packets delivered this tick (saturation detection)
	# 2. deliver — one head per lane, so a multi-lane wire hands out more than one packet/tick
	for id in cids:
		var c: Connection = connections[id]
		var target: Machine = machines[c.to_id]
		for k in c.lanes:
			var h := c.head()
			if h == null:
				break
			if target.can_accept(c.to_port):
				target.accept(c.to_port, c.pop_head())
				delivered[id] = int(delivered.get(id, 0)) + 1
				events.append({"kind": "deliver", "packet": h.id, "machine": target.id, "port": c.to_port})
				activity = true
			else:
				c.blocked = true
				break
	# 3. move
	for id in cids:
		connections[id].advance()
		activity = activity or connections[id].moved_this_tick
	# 4. process (brownout inputs cached once per step)
	_cap = power_capacity()
	_demand = power_demand()
	if mission != null and mission.has_method("uses_power_network") and mission.uses_power_network():
		if power_net == null or _power_dirty or power_net.supply != _cap:
			power_net = PowerNetwork.build(self, _cap, mission.onboard_capacity() if mission.has_method("onboard_capacity") else 0)
		_power_dirty = false
	else:
		power_net = null
	for id in mids:
		var m: Machine = machines[id]
		var had := not m.jobs.is_empty()
		m.advance(self)
		if had and m.jobs.is_empty():
			events.append({"kind": "complete", "machine": id})
			activity = true
	# 4b. heat: after the machines worked; the stage sets next tick's thermal factor
	if thermal_enabled():
		_step_thermal(mids)
	# 5. emit
	var blocked_now := {}
	for id in mids:
		var m: Machine = machines[id]
		for port in m.outq:
			var c := connection_at_port(id, port)
			if m.outq[port] == null:
				continue
			if c != null and c.entry_free():
				# A multi-lane wire takes several packets per tick: push the head, then the
				# backlog, as long as the wire still has a free entry (P1a lanes).
				while m.outq[port] != null and c.entry_free():
					var p: Packet = m.pop_output(port)
					c.push(p)
					m.sent_ports.append(port)
					events.append({"kind": "emit", "packet": p.id, "machine": id, "port": port})
					activity = true
				# Saturated as well: every lane took a value this tick and more still waits upstream
				# (the output line, or a socket's FIFO that overruns instead of blocking).
				if c.free_entries() == 0 and (m.outq[port] != null or (m.socket and not m.fifo.is_empty())):
					c.saturated = true
			if c == null or m.outq[port] == null:
				continue
			# BLOCKED means congestion: a wire exists but its entry is full. An output with
			# no wire is simply waiting (OUTPUT_READY), not blocked.
			blocked_now[id] = true
			# Saturated: the wire flowed this tick (delivered ≥ 1) yet its entry is full —
			# the multi-lane wire itself is the bandwidth bottleneck (FACTORY_SYSTEMS §2.2).
			if delivered.has(c.id) and int(delivered[c.id]) > 0:
				c.saturated = true
	for id in cids:
		connections[id].note_saturation(connections[id].saturated)
	# 6. start
	for id in mids:
		var m: Machine = machines[id]
		var had := not m.jobs.is_empty()
		var before := m.emitted
		m.start(self)
		if (not had and not m.jobs.is_empty()) or m.emitted != before:
			activity = true
			if m.type == "input" and m.emitted != before:
				_in_times.append(tick)
	# 7. state
	for id in mids:
		var m: Machine = machines[id]
		m.update_state(blocked_now.has(id) and m.type != "input")
		if m.type == "input" and blocked_now.has(id):
			m.state = Machine.State.BLOCKED
		if not m.locked:
			m.note_compute_bound(m.jobs.size() >= m.lanes() and m.queued_count() >= m.total_in_capacity())
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


## Lab power capacity (the PSU; SYSTEMS_EXPANSION §4). 0 = unlimited (tutorial missions).
func power_capacity() -> int:
	if mission != null and mission.has_method("power_capacity"):
		return int(mission.power_capacity())
	return 0


## Σ power demand (rated power × clock multiplier) of every player machine (locked IO draws none).
func power_demand() -> int:
	var d := 0
	for id in sorted_machine_ids():
		var m: Machine = machines[id]
		if not m.locked:
			d += m.power_demand()
	return d


## Work units a machine applies this tick: its clock rate, scaled evenly by a brownout when the
## demand exceeds the capacity (integer floor, at least 1), then by its thermal factor (THROTTLING
## ×½ with the same floor, CRITICAL 0).
func work_rate(m: Machine) -> int:
	var r := m.clock_rate()
	if power_net != null:
		r = power_net.work_rate(m.id, r)
	elif _cap > 0 and _demand > _cap:
		r = maxi(1, r * _cap / _demand)
	if m.thermal_den > 0 and m.thermal_num != m.thermal_den:
		if m.thermal_num <= 0:
			return 0  # CRITICAL: paused, the job is kept
		r = maxi(1, r * m.thermal_num / m.thermal_den)
	return r


## Heat is simulated only when the run asks for it (the Lab from L17 "Heat"; tests).
func thermal_enabled() -> bool:
	return mission != null and mission.has_method("thermal_enabled") and mission.thermal_enabled()


func _step_thermal(mids: Array) -> void:
	if thermal == null or thermal.size != size:
		thermal = ThermalGrid.new(size)
	thermal.step(self, mids)
	for id in mids:
		var m: Machine = machines[id]
		m.temp = thermal.machine_temp(m)
		var prev := m.heat_stage
		m.heat_stage = ThermalGrid.stage_for(m.temp, m.heat_stage)
		m.thermal_num = 1
		m.thermal_den = 1
		if m.heat_stage == ThermalGrid.Stage.THROTTLING:
			m.thermal_den = 2
		elif m.heat_stage == ThermalGrid.Stage.CRITICAL:
			m.thermal_num = 0
		if m.heat_stage != prev:
			events.append({"kind": "heat", "machine": id, "stage": m.heat_stage})


# ============================================================ bottlenecks (FACTORY_SYSTEMS §7.4)

func wire_bound(cid: int) -> bool:
	return connections.has(cid) and connections[cid].saturation_ratio() >= 0.5


func compute_bound(mid: int) -> bool:
	return machines.has(mid) and machines[mid].compute_bound_ratio() >= 0.5


## Slowed by power: a running job whose work rate is below its clock rate while the thermal
## factor is untouched.
func power_bound(mid: int) -> bool:
	if not machines.has(mid):
		return false
	var m: Machine = machines[mid]
	return not m.jobs.is_empty() and m.thermal_num == m.thermal_den and work_rate(m) < m.clock_rate()


func heat_bound(mid: int) -> bool:
	return machines.has(mid) and machines[mid].heat_stage >= ThermalGrid.Stage.THROTTLING


## The first bound met walking UPSTREAM from machine `target_id` (the target first, then the
## wires into it by ascending id, then their sources, …): {kind: bandwidth|compute|power|heat,
## machine, connection, text}, or {} when nothing on the way is bound.
func first_bound(target_id: int) -> Dictionary:
	if not machines.has(target_id):
		return {}
	var seen := {target_id: true}
	var q := [target_id]
	while not q.is_empty():
		var mid: int = q.pop_front()
		var m: Machine = machines[mid]
		if heat_bound(mid):
			return {"kind": "heat", "machine": mid, "connection": -1, "text": "HEAT-BOUND · %s (%s)" % [m.label, ThermalGrid.STAGE_NAMES[m.heat_stage]]}
		if power_bound(mid):
			return {"kind": "power", "machine": mid, "connection": -1, "text": "POWER-BOUND · %s" % m.label}
		if compute_bound(mid):
			return {"kind": "compute", "machine": mid, "connection": -1, "text": "COMPUTE-BOUND · %s (%d/%d lanes)" % [m.label, m.jobs.size(), m.lanes()]}
		for cid in sorted_connection_ids():
			var c: Connection = connections[cid]
			if c.to_id != mid:
				continue
			if wire_bound(cid):
				var src: Machine = machines[c.from_id]
				return {"kind": "bandwidth", "machine": -1, "connection": cid, "text": "BANDWIDTH-BOUND · wire %s → %s (%s ×%d)" % [src.label, m.label, Connection.class_title(c.width), c.lanes]}
			if not seen.has(c.from_id):
				seen[c.from_id] = true
				q.append(c.from_id)
	return {}


func overloaded() -> bool:
	if power_net != null:
		for nid in power_net.nodes:
			if power_net.state(nid) == "over":
				return true
		return false
	return _cap > 0 and _demand > _cap


## The tightest power stage on machine `mid`'s path (P5b), {} when the network is off.
func power_bottleneck(mid: int) -> Dictionary:
	if power_net == null:
		return {}
	return power_net.bottleneck(mid)


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
		cs.append({"from": idx[c.from_id], "from_port": c.from_port, "to": idx[c.to_id], "to_port": c.to_port, "lanes": c.lanes})
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
	var used := {}
	for md in d.get("machines", []):
		if md.get("locked", false):
			var mid := _locked_match(md, locked_by_index, li, used)
			if mid >= 0:
				used[mid] = true
				map[i] = mid
				var lm: Machine = machines[mid]
				if md.has("last_device"):
					lm.last_device = str(md["last_device"])
				var dev := str(md.get("device", ""))
				if dev != "":
					insert_device(mid, dev)  # false is ignored: the fresh board already has the socket
				elif bool(md.get("socket", false)) and lm.device != "":
					remove_device(mid)  # the player had moved this port's module to the desk
				li += 1
		else:
			var m := place(md["type"], Vector2i(md["cell"][0], md["cell"][1]), int(md.get("rot", 0)), md.get("params", {}), int(md.get("width", 0)))
			if m != null:
				map[i] = m.id
		i += 1
	for cd in d.get("connections", []):
		if map.has(int(cd["from"])) and map.has(int(cd["to"])):
			var nc := connect_ports(map[int(cd["from"])], cd["from_port"], map[int(cd["to"])], cd["to_port"])
			if nc != null and cd.has("lanes"):
				nc.set_lanes(int(cd["lanes"]))  # no per-wire emit: the batch is quiet
	_emit_changed()


func _emit_changed() -> void:
	_power_dirty = true
	if _quiet == 0:
		changed.emit()


## Brings the board to layout `d` in place (undo / redo). Player machines and wires that match
## the target are kept — with their packets — the rest is removed, then the missing machines are
## placed and wired and the socket devices re-applied. Locked machines are matched by creation
## order, like load_player_layout. `changed` fires once.
func apply_layout(d: Dictionary) -> void:
	_quiet += 1
	var pool := {}  # machine key -> [ids] of current player machines
	var locked_by_index := []
	for id in sorted_machine_ids():
		var m: Machine = machines[id]
		if m.locked:
			locked_by_index.append(id)
		else:
			var k := _layout_key(m.to_dict())
			if not pool.has(k):
				pool[k] = []
			pool[k].append(id)
	var map := {}
	var used_locked := {}
	var create := []  # target indices still to place
	var li := 0
	var entries: Array = d.get("machines", [])
	for i in entries.size():
		var md: Dictionary = entries[i]
		if md.get("locked", false):
			var lmid := _locked_match(md, locked_by_index, li, used_locked)
			if lmid >= 0:
				used_locked[lmid] = true
				map[i] = lmid
			li += 1
		else:
			var k2 := _layout_key(md)
			if pool.has(k2) and not (pool[k2] as Array).is_empty():
				map[i] = (pool[k2] as Array).pop_front()
			else:
				create.append(i)
	for k3 in pool:
		for id in pool[k3]:
			remove(id)
	# wires the target does not have go before any placement, so a new machine never routes
	# around a wire that is about to disappear
	var conns: Array = d.get("connections", [])
	var keep := {}
	var target_lanes := {}  # "f:fport>t:tport" -> lanes the target layout wants
	for cd in conns:
		if map.has(int(cd["from"])) and map.has(int(cd["to"])):
			keep["%d:%s>%d:%s" % [map[int(cd["from"])], cd["from_port"], map[int(cd["to"])], cd["to_port"]]] = true
			target_lanes["%d:%s>%d:%s" % [map[int(cd["from"])], cd["from_port"], map[int(cd["to"])], cd["to_port"]]] = int(cd.get("lanes", 1))
	for cid in sorted_connection_ids():
		var c: Connection = connections[cid]
		var k := "%d:%s>%d:%s" % [c.from_id, c.from_port, c.to_id, c.to_port]
		if not keep.has(k):
			disconnect_wire(cid, false)
		elif target_lanes.has(k) and c.lanes != int(target_lanes[k]):
			c.set_lanes(int(target_lanes[k]))
	for i in create:
		var md: Dictionary = entries[i]
		var m := place(md["type"], Vector2i(md["cell"][0], md["cell"][1]), int(md.get("rot", 0)), md.get("params", {}), int(md.get("width", 0)))
		if m != null:
			map[i] = m.id
	# socket devices (a Job drive moving ports is resolved by insert_device itself)
	for i in entries.size():
		var md: Dictionary = entries[i]
		if not md.get("locked", false) or not map.has(i):
			continue
		var lm: Machine = machines[map[i]]
		if md.has("last_device"):
			lm.last_device = str(md["last_device"])
		var dev := str(md.get("device", ""))
		if dev != lm.device:
			if dev != "":
				insert_device(lm.id, dev)
			elif lm.device != "":
				remove_device(lm.id)
	# connect the missing wires
	var have := {}
	for cid in sorted_connection_ids():
		var c2: Connection = connections[cid]
		have["%d:%s>%d:%s" % [c2.from_id, c2.from_port, c2.to_id, c2.to_port]] = true
	for cd in conns:
		if map.has(int(cd["from"])) and map.has(int(cd["to"])):
			var k4 := "%d:%s>%d:%s" % [map[int(cd["from"])], cd["from_port"], map[int(cd["to"])], cd["to_port"]]
			if not have.has(k4):
				var nc := connect_ports(map[int(cd["from"])], cd["from_port"], map[int(cd["to"])], cd["to_port"])
				if nc != null:
					nc.set_lanes(int(cd.get("lanes", 1)))
	_quiet -= 1
	_emit_changed()


static func _layout_key(md: Dictionary) -> String:
	var c: Array = md.get("cell", [0, 0])
	return "%s|%d,%d|%d|%d|%s" % [md.get("type", ""), int(c[0]), int(c[1]), int(md.get("rot", 0)), int(md.get("width", 0)), JSON.stringify(_int_floats(md.get("params", {})), "", true)]


## JSON round-trips turn ints into floats (k 1 → 1.0); keys compare integral floats as ints.
static func _int_floats(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)):
		return int(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _int_floats(v[k])
		return out
	if v is Array:
		return (v as Array).map(_int_floats)
	return v


# ------------------------------------------------------------------ groups (multi-select)

## Moving the unlocked machines `ids` together by `delta`: each must land on free tiles (the
## group's own tiles count as free) and every affected wire (theirs and those crossing their new
## footprints) must re-route. Changes nothing. {ok, routes: {cid: cells}, fail: [cids], error}.
func group_preview(ids: Array, delta: Vector2i) -> Dictionary:
	var group := _group_of(ids)
	if group.is_empty():
		return {"ok": false, "routes": {}, "fail": [], "error": "Nothing to move"}
	var err := _group_placement_error(group, delta)
	if err != "":
		return {"ok": false, "routes": {}, "fail": [], "error": err}
	var old := {}
	var cells := []
	for id in group:
		var m: Machine = machines[id]
		old[id] = m.cell
		m.cell += delta
		cells.append_array(m.footprint())
	var affected := _wires_through(cells)
	for cid in sorted_connection_ids():
		var c: Connection = connections[cid]
		if (group.has(c.from_id) or group.has(c.to_id)) and not cid in affected:
			affected.append(cid)
	var routes := {}
	var fail := []
	for cid in affected:
		var c2: Connection = connections[cid]
		var r := route_between(c2.from_id, c2.from_port, c2.to_id, c2.to_port, cid)
		if r["ok"]:
			routes[cid] = r["cells"]
		else:
			fail.append(cid)
	for id in group:
		machines[id].cell = old[id]
	if not fail.is_empty():
		err = "Would cut the wire %s" % _wire_name(int(fail[0]))
	return {"ok": err == "", "routes": routes, "fail": fail, "error": err}


## Commit a group move (exactly group_preview's plan) or change nothing (last_error says why).
func move_group(ids: Array, delta: Vector2i) -> bool:
	var pv := group_preview(ids, delta)
	if not bool(pv["ok"]):
		last_error = str(pv["error"])
		return false
	for id in _group_of(ids):
		machines[id].cell += delta
	_apply_plan(pv["routes"])
	_emit_changed()
	return true


## Copies of the unlocked machines `ids` shifted by `delta` (type, rotation, parameters, width)
## plus the wires that ran between them. All or nothing: returns the new ids in the order of
## `ids`, or [] (last_error says why). `changed` fires once.
func duplicate_group(ids: Array, delta: Vector2i) -> Array:
	var group := _group_of(ids)
	if group.is_empty():
		last_error = "Nothing to duplicate"
		return []
	for id in group:
		var m: Machine = machines[id]
		var e := placement_error(m.type, m.cell + delta, m.rot)
		if e != "":
			last_error = e
			return []
	_quiet += 1
	var map := {}
	var order := []
	for id in ids:
		if not group.has(id):
			continue
		var m: Machine = machines[id]
		var c := place(m.def_id(), m.cell + delta, m.rot, m.params.duplicate(true), m.width)
		if c == null:
			for nid in map.values():
				remove(nid)
			_quiet -= 1
			if last_error == "":
				last_error = placement_error(m.type, m.cell + delta, m.rot)
			return []
		map[id] = c.id
		order.append(c.id)
	for cid in sorted_connection_ids():
		var w: Connection = connections[cid]
		if map.has(w.from_id) and map.has(w.to_id):
			connect_ports(map[w.from_id], w.from_port, map[w.to_id], w.to_port)
	_quiet -= 1
	_emit_changed()
	return order


## Clipboard snapshot of the unlocked machines in `ids` and the wires between them (Ctrl+C / X):
## {"machines": [{type, cell (relative to the group's top-left), rot, params, width}],
##  "wires": [{from, from_port, to, to_port}] (indices into machines)}. Survives the originals.
func copy_group(ids: Array) -> Dictionary:
	var group := _group_of(ids)
	if group.is_empty():
		return {}
	var origin := Vector2i(1 << 30, 1 << 30)
	for id in group:
		var c: Vector2i = machines[id].cell
		origin = Vector2i(mini(origin.x, c.x), mini(origin.y, c.y))
	var idx := {}
	var ms := []
	for id in sorted_machine_ids():
		if not group.has(id):
			continue
		var m: Machine = machines[id]
		idx[id] = ms.size()
		ms.append({"type": m.def_id(), "cell": m.cell - origin, "rot": m.rot, "params": m.params.duplicate(true), "width": m.width})
	var ws := []
	for cid in sorted_connection_ids():
		var w: Connection = connections[cid]
		if idx.has(w.from_id) and idx.has(w.to_id):
			ws.append({"from": idx[w.from_id], "from_port": w.from_port, "to": idx[w.to_id], "to_port": w.to_port})
	return {"machines": ms, "wires": ws}


## Place a clipboard snapshot with its top-left at `at` (Ctrl+V), wires included. All or nothing:
## [] (and last_error) when any machine does not fit. Returns the new ids in clipboard order.
func paste_group(clip: Dictionary, at: Vector2i) -> Array:
	var ms: Array = clip.get("machines", [])
	if ms.is_empty():
		last_error = "The clipboard is empty"
		return []
	for e in ms:
		var err := placement_error(str(e["type"]), at + (e["cell"] as Vector2i), int(e["rot"]))
		if err != "":
			last_error = err
			return []
	_quiet += 1
	var out := []
	for e in ms:
		var m := place(str(e["type"]), at + (e["cell"] as Vector2i), int(e["rot"]), (e["params"] as Dictionary).duplicate(true), int(e["width"]))
		if m == null:
			for nid in out:
				remove(nid)
			_quiet -= 1
			return []
		out.append(m.id)
	for w in clip.get("wires", []):
		connect_ports(out[int(w["from"])], str(w["from_port"]), out[int(w["to"])], str(w["to_port"]))
	_quiet -= 1
	_emit_changed()
	return out


## Remove every unlocked machine of `ids` (their wires go with them); `changed` fires once.
func remove_group(ids: Array) -> int:
	_quiet += 1
	var n := 0
	for id in _group_of(ids):
		if remove(id):
			n += 1
	_quiet -= 1
	if n > 0:
		_emit_changed()
	return n


func _group_of(ids: Array) -> Dictionary:
	var g := {}
	for id in ids:
		if machines.has(int(id)) and not machines[int(id)].locked:
			g[int(id)] = true
	return g


func _group_placement_error(group: Dictionary, delta: Vector2i) -> String:
	var occ := {}
	for id in machines:
		if group.has(id):
			continue
		for c in machines[id].footprint():
			occ[c] = id
	for id in group:
		var m: Machine = machines[id]
		for c in m.footprint():
			var n: Vector2i = c + delta
			if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
				return "Outside the board"
			if occ.has(n):
				return "Tile occupied by " + machines[occ[n]].label
			if reserved.has(n):
				return "Sealed USB bay"
	return ""


## The locked machine a saved locked entry belongs to: the one of the same type on the same cell
## (port racks can open in a different order than they were saved), else the `li`-th by creation
## order (older saves), never one already matched. -1 when there is none.
func _locked_match(md: Dictionary, locked_by_index: Array, li: int, used: Dictionary) -> int:
	var pr := int(md.get("port_row", -1))
	if pr >= 0:
		for id in locked_by_index:
			var m: Machine = machines[id]
			if not used.has(id) and m.def_id() == str(md.get("type", "")) and m.port_row == pr:
				return id
	var c: Array = md.get("cell", [])
	if c.size() == 2:
		var cell := Vector2i(int(c[0]), int(c[1]))
		for id in locked_by_index:
			var m: Machine = machines[id]
			if not used.has(id) and m.def_id() == str(md.get("type", "")) and m.cell == cell:
				return id
	if li < locked_by_index.size() and not used.has(locked_by_index[li]):
		return locked_by_index[li]
	return -1

