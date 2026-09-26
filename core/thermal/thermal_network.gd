class_name ThermalNetwork
extends RefCounted
## The thermal path (P7a): heat-producing machines push through transport tiles (pipes /
## spreaders / trunks / manifolds) into sinks (fins / radiators) that dump it out of the
## computer, fed by blowers. Pure and deterministic — machines iterate by ascending id, tiles
## in index order y*size.x+x, and nothing here touches the SceneTree. ThermalGrid rebuilds it
## with the layout and calls allocate() every tick (P7b).

const TRANSPORT := ["thermal_spreader", "heat_pipe", "heat_pipe_heavy", "thermal_trunk"]
const MANIFOLD := "thermal_manifold"
const SINKS := ["fin_stack", "radiator", "radiator_large"]
const BLOWERS := ["blower", "blower_hp", "fan_bank"]
const CONTACT_CAP := {"S": 600, "M": 1200, "L": 2400}

var sim: Simulation
var _machines := {}  # mid -> Machine
var _occ := {}  # tile -> machine id (actual footprints)
var _tile_machine := {}  # network tile -> machine id (transport / manifold)
var _network_of := {}  # tile -> network id
var _networks := {}  # network id -> {tiles, lowest, sinks: [mid], stage, airflow}
var _sink_info := {}  # mid -> {id, network, capacity, effective, airflow, need, exhaust_out, inlets, footprint}
var _blower_eff := {}  # blower mid -> effective airflow
var _machine_contact := {}  # mid -> {contact_tile, network, cap}
var _parents := {}  # tile -> parent tile (towards the sinks)


## Build the network for a board. Geometry is read at rotation 0 (rotation is ignored for now).
static func build(sim) -> ThermalNetwork:
	var tn := ThermalNetwork.new()
	tn.sim = sim
	tn._build()
	return tn


func _build() -> void:
	_collect()
	_detect_networks()
	_compute_sinks()
	_compute_blowers()
	_compute_airflow()
	_compute_machines()
	_compute_parents()


# ---------------------------------------------------------------- geometry

func _collect() -> void:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		_machines[id] = m
		for c in m.footprint():
			_occ[c] = id


func _detect_networks() -> void:
	var tiles := {}
	for mid in _machines:
		var m: Machine = _machines[mid]
		if m.type in TRANSPORT or m.type == MANIFOLD:
			for c in m.footprint():
				tiles[c] = mid
	var keys := tiles.keys()
	keys.sort_custom(func(a, b): return _idx(a) < _idx(b))
	var seen := {}
	for t in keys:
		if seen.has(t):
			continue
		var comp := {}
		var q := [t]
		seen[t] = true
		while not q.is_empty():
			var c: Vector2i = q.pop_front()
			comp[c] = true
			for n in _nbrs(c):
				if tiles.has(n) and not seen.has(n):
					seen[n] = true
					q.append(n)
		var lowest := 1 << 30
		for c in comp:
			lowest = mini(lowest, _idx(c))
		var nid := "n%d" % lowest
		_networks[nid] = {"tiles": comp, "lowest": lowest, "sinks": [], "stage": 0, "airflow": 0}
		for c in comp:
			_network_of[c] = nid
			_tile_machine[c] = tiles[c]


func _compute_sinks() -> void:
	for mid in _machines:
		var m: Machine = _machines[mid]
		if not m.type in SINKS:
			continue
		var s: Vector2i = Catalog.size_of(m.type, 0)
		var inlets := []
		for y in s.y:
			inlets.append(Vector2i(m.cell.x - 1, m.cell.y + y))
		var exhausts := []
		for x in s.x:
			exhausts.append(Vector2i(m.cell.x + x, m.cell.y - 1))
		var exhaust_out := true
		for e in exhausts:
			if e.y >= 0:
				exhaust_out = false
		var nid := ""
		for it in inlets:
			if _network_of.has(it):
				nid = _network_of[it]
				break
		_sink_info[mid] = {
			"id": mid, "network": nid, "capacity": int(m.def().get("capacity", 0)),
			"effective": 0, "airflow": 0, "need": int(m.def().get("airflow_need", 0)),
			"exhaust_out": exhaust_out, "inlets": inlets, "footprint": m.footprint(),
		}
		if nid != "":
			_networks[nid]["sinks"].append(mid)


func _compute_blowers() -> void:
	for mid in _machines:
		var m: Machine = _machines[mid]
		if not m.type in BLOWERS:
			continue
		var airflow := int(m.def().get("airflow", 0))
		var s: Vector2i = Catalog.size_of(m.type, 0)
		var blocked := false
		for x in s.x:
			if _machine_at(Vector2i(m.cell.x + x, m.cell.y + s.y)) >= 0:
				blocked = true
				break
		if blocked:
			airflow /= 2
		_blower_eff[mid] = airflow


func _compute_airflow() -> void:
	for mid in _sink_info:
		var info: Dictionary = _sink_info[mid]
		var footprint := {}
		for c in info["footprint"]:
			footprint[c] = true
		var airflow := 0
		for bid in _blower_eff:
			var b: Machine = _machines[bid]
			var s: Vector2i = Catalog.size_of(b.type, 0)
			var feeds := false
			for x in s.x:
				if footprint.has(Vector2i(b.cell.x + x, b.cell.y - 1)):
					feeds = true
					break
			if feeds:
				airflow += int(_blower_eff[bid])
		var need := int(info["need"])
		var capped := mini(airflow, need) if need > 0 else airflow
		info["airflow"] = capped
		var capacity := int(info["capacity"])
		var effective := capacity
		if need > 0:
			effective = capacity * capped / need
		info["effective"] = effective
		var nid: String = info["network"]
		if nid != "":
			_networks[nid]["stage"] += effective
			_networks[nid]["airflow"] += capped
			_networks[nid]["need"] = int(_networks[nid].get("need", 0)) + need


func _compute_machines() -> void:
	for mid in _machines:
		var m: Machine = _machines[mid]
		if m.locked:
			continue
		if m.type in TRANSPORT or m.type == MANIFOLD or m.type in SINKS or m.type in BLOWERS:
			continue
		if int(m.def().get("heat", 0)) <= 0 and m.heat() <= 0:
			continue
		var s: Vector2i = Catalog.size_of(m.type, m.rot)  # the contact row follows the rotated footprint
		var contact_tile := Vector2i(-1, -1)
		var nid := ""
		for x in s.x:
			var c := Vector2i(m.cell.x + x, m.cell.y - 1)
			if _network_of.has(c):
				contact_tile = c
				nid = _network_of[c]
				break
		var cap := int(m.def().get("contact_cap", -1))
		if cap < 0:
			cap = int(CONTACT_CAP[m.def()["size"]])
		_machine_contact[mid] = {"contact_tile": contact_tile, "network": nid, "cap": cap}


func _compute_parents() -> void:
	for nid in _networks:
		var tiles: Dictionary = _networks[nid]["tiles"]
		var start := []
		for sid in _networks[nid]["sinks"]:
			for it in _sink_info[sid]["inlets"]:
				if _network_of.get(it, "") == nid:
					start.append(it)
		start.sort_custom(func(a, b): return _idx(a) < _idx(b))
		var parent := {}
		var q := []
		for s in start:
			parent[s] = s
			q.append(s)
		while not q.is_empty():
			var c: Vector2i = q.pop_front()
			for n in _nbrs(c):
				if tiles.has(n) and not parent.has(n):
					parent[n] = c
					q.append(n)
		for t in parent:
			_parents[t] = parent[t]


# ---------------------------------------------------------------- queries

## Every sink: {id, network, capacity, effective, airflow, need, exhaust_out}.
func sinks() -> Array:
	var out := []
	for mid in _sink_info:
		var info: Dictionary = _sink_info[mid]
		out.append({
			"id": mid, "network": info["network"], "capacity": info["capacity"],
			"effective": info["effective"], "airflow": info["airflow"], "need": info["need"],
			"exhaust_out": info["exhaust_out"],
		})
	return out


## The network a machine is connected to (a heat machine's contact network, a sink's attached
## network), or "" when it is not connected.
func network_of(mid) -> String:
	if _machine_contact.has(mid):
		return _machine_contact[mid]["network"]
	if _sink_info.has(mid):
		return _sink_info[mid]["network"]
	return ""


## A heat machine's thermal contact capacity (its def's, or the size-derived default).
func contact_cap(mid) -> int:
	if _machine_contact.has(mid):
		return _machine_contact[mid]["cap"]
	return 0


## Flow tree path from a feed tile to its sink inlet tile (the inlet's parent is itself).
func _path_to_sink(feed: Vector2i) -> Array:
	var path := []
	var cur := feed
	while true:
		path.append(cur)
		var p: Vector2i = _parents.get(cur, cur)
		if p == cur:
			break
		cur = p
	return path


## The capacity of a network tile (its part's def capacity), 0 for any other tile.
func tile_cap(t: Vector2i) -> int:
	return _tile_cap(t)


## The blowers that feed a sink (directly south of it), ascending id.
func blowers_of(sid: int) -> Array:
	var out := []
	if not _sink_info.has(sid):
		return out
	var footprint := {}
	for c in _sink_info[sid]["footprint"]:
		footprint[c] = true
	for bid in _blower_eff:
		var b: Machine = _machines[bid]
		for x in Catalog.size_of(b.type, 0).x:
			if footprint.has(Vector2i(b.cell.x + x, b.cell.y - 1)):
				out.append(bid)
				break
	return out


func _tile_class(t: Vector2i) -> String:
	var mid: int = _tile_machine.get(t, -1)
	if mid < 0:
		return ""
	return _machines[mid].type


func _tile_cap(t: Vector2i) -> int:
	var mid: int = _tile_machine.get(t, -1)
	if mid < 0:
		return 0
	return int(_machines[mid].def().get("capacity", 0))


func _machine_at(c: Vector2i) -> int:
	return _occ.get(c, -1)


# ---------------------------------------------------------------- allocation

## offers: machine id -> heat offered this tick (already capped by the caller at its contact
## cap). Returns {"removal": {mid: int}, "dump": {sink mid: int}, "stages": {mid: [...]},
## "flow": {tile: heat offered through it}} (the flow feeds the view's heat wash).
func allocate(offers: Dictionary) -> Dictionary:
	var tile_flow := {}
	var paths := {}
	var removal := {}
	# pass 1: every connected machine's path and the total flow through each tile
	for mid in offers:
		if not _machine_contact.has(mid):
			continue
		var feed: Dictionary = _machine_contact[mid]
		var nid: String = feed["network"]
		if nid == "" or _networks[nid]["sinks"].is_empty():
			continue
		var path := _path_to_sink(feed["contact_tile"])
		paths[mid] = path
		for t in path:
			tile_flow[t] = int(tile_flow.get(t, 0)) + int(offers[mid])
	# pass 2: each machine keeps offer × the tightest tile on its path (cap / total flow there)
	for mid in offers:
		if not paths.has(mid):
			removal[mid] = 0
			continue
		var factor := 1.0
		for t in paths[mid]:
			var cap := _tile_cap(t)
			var flow := int(tile_flow.get(t, 0))
			if flow > cap:
				factor = minf(factor, float(cap) / float(flow))
		removal[mid] = int(float(int(offers[mid])) * factor)
	# per-network sink scaling: if the network's total removal exceeds its sink stage, scale
	# every removal down (integer floor; the rounding remainder goes to nobody)
	var net_removal := {}
	for mid in removal:
		var nid: String = _machine_contact.get(mid, {}).get("network", "")
		if nid != "":
			net_removal[nid] = int(net_removal.get(nid, 0)) + int(removal[mid])
	var scaled := {}
	for mid in removal:
		var nid: String = _machine_contact.get(mid, {}).get("network", "")
		var stage := int(_networks.get(nid, {}).get("stage", 0))
		if nid != "" and int(net_removal.get(nid, 0)) > stage:
			# stage 0 (a radiator with no airflow) dumps nothing
			scaled[mid] = int(removal[mid]) * stage / int(net_removal[nid])
		else:
			scaled[mid] = removal[mid]
	var net_scaled := {}
	for mid in scaled:
		var nid: String = _machine_contact.get(mid, {}).get("network", "")
		if nid != "":
			net_scaled[nid] = int(net_scaled.get(nid, 0)) + int(scaled[mid])
	# dump: each sink's share of its network's total removal, split by effective capacity
	var dump := {}
	for nid in _networks:
		var sinks_arr: Array = _networks[nid]["sinks"]
		if sinks_arr.is_empty():
			continue
		var stage := int(_networks[nid]["stage"])
		var total := int(net_scaled.get(nid, 0))
		for sid in sinks_arr:
			var eff := int(_sink_info[sid]["effective"])
			dump[sid] = total * eff / stage if stage > 0 else 0
	# stages: root-first contact, merged tile classes, sinks, airflow
	var stages := {}
	for mid in offers:
		stages[mid] = _stages_for(mid, offers, paths, tile_flow, net_scaled)
	return {"removal": scaled, "dump": dump, "stages": stages, "flow": tile_flow}


func _stages_for(mid, offers: Dictionary, paths: Dictionary, tile_flow: Dictionary, net_scaled: Dictionary) -> Array:
	var out := []
	if not _machine_contact.has(mid):
		return out
	var feed: Dictionary = _machine_contact[mid]
	out.append({"stage": "contact", "cap": int(feed["cap"]), "flow": int(offers.get(mid, 0))})
	var path: Array = paths.get(mid, [])
	var i := 0
	while i < path.size():
		var cls := _tile_class(path[i])
		var cap := _tile_cap(path[i])
		var flow := int(tile_flow.get(path[i], 0))
		var j := i
		while j + 1 < path.size() and _tile_class(path[j + 1]) == cls:
			j += 1
			cap = mini(cap, _tile_cap(path[j]))
			flow = maxi(flow, int(tile_flow.get(path[j], 0)))
		out.append({"stage": cls, "cap": cap, "flow": flow})
		i = j + 1
	var nid: String = feed["network"]
	if nid != "" and not _networks[nid]["sinks"].is_empty():
		out.append({"stage": "sinks", "cap": int(_networks[nid]["stage"]), "flow": int(net_scaled.get(nid, 0))})
		out.append({"stage": "airflow", "cap": int(_networks[nid].get("need", 0)), "flow": int(_networks[nid]["airflow"])})
	return out


# ---------------------------------------------------------------- helpers

func _idx(c: Vector2i) -> int:
	return c.y * sim.size.x + c.x


func _nbrs(c: Vector2i) -> Array:
	return [c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)]