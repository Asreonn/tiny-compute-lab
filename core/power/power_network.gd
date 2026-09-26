class_name PowerNetwork
extends RefCounted
## The power path (docs/FACTORY_SYSTEMS.md §5): source → controller/VRM → linear copper chains →
## distribution boards → chassis contacts. The tightest stage on a machine's path slows it. Pure and
## deterministic — machines iterate by ascending id, tiles in index order y*size.x+x, and
## nothing here touches the SceneTree. No Simulation / LabRun integration yet: this is the
## standalone core the Lab will call later (P5a).

const COPPER := ["power_rail", "power_rail_heavy", "power_plane", "power_plane_heavy"]
const BOARDS := ["power_board"]  # a variant counts by its base Machine.type
const PAD_CAP := 8
const TIER_CAP := {"ctrl": 12, "basic": 32, "eff": 32, "hc": 96}
const CLASS_CAP := {"power_rail": 16, "power_rail_heavy": 48, "power_plane": 64, "power_plane_heavy": 192}
const SPLIT_MSG := "Copper splits only at a Distribution Board"

var sim: Simulation
var supply := 0
var onboard := 0
## id -> {id, kind, cap, load, parent, children, live}
var nodes := {}

var _copper := {}  # tile -> copper machine id
var _chain_of_tile := {}  # tile -> chain id ("c<lowest tile index>")
var _chains := {}  # chain id -> {lowest, feed, index: {tile: int}, order: [tiles], caps, loads, machines, boards}
var _chain_feeds := {}  # chain id -> {parent node id: feed tile}
var _boards := {}  # machine id -> {cell, input, terminals: {N, E, S}}
var _controller := -1
var _feeds := {}  # machine id -> {kind, chain, tap_index, tap_tile, pads, demand, path}
var _edges := {}  # node id -> [child node ids, ascending]


## Build the network for a board. supply / onboard are the lab's PSU capacity and the
## controller's onboard budget (0 = unlimited for each).
static func build(sim, supply: int, onboard: int) -> PowerNetwork:
	var pn := PowerNetwork.new()
	pn.sim = sim
	pn.supply = supply
	pn.onboard = onboard
	pn._build()
	return pn


func _build() -> void:
	_collect_geometry()
	_detect_chains()
	_make_nodes()
	_make_edges()
	_bfs()
	_chain_paths()
	_machine_feeds()
	_compute_loads()


# ---------------------------------------------------------------- geometry

func _collect_geometry() -> void:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type in COPPER:
			for c in m.footprint():
				_copper[c] = id
		elif m.type == "power_controller":
			if _controller < 0:
				_controller = id
		elif m.type in BOARDS:
			_boards[id] = {
				"cell": m.cell,
				"input": m.cell + Vector2i(-1, 0),
				"terminals": {
					"N": m.cell + Vector2i(0, -1),
					"E": m.cell + Vector2i(2, 0),
					"S": m.cell + Vector2i(0, 1),
				},
			}


func _detect_chains() -> void:
	var tiles := _copper.keys()
	tiles.sort_custom(func(a, b): return _idx(a) < _idx(b))
	var seen := {}
	for t in tiles:
		if seen.has(t):
			continue
		var comp := {}
		var q := [t]
		seen[t] = true
		while not q.is_empty():
			var c: Vector2i = q.pop_front()
			comp[c] = true
			for n in _nbrs(c):
				if _copper.has(n) and not seen.has(n):
					seen[n] = true
					q.append(n)
		var lowest := 1 << 30
		for c in comp:
			lowest = mini(lowest, _idx(c))
		var cid := "c%d" % lowest
		_chains[cid] = {"lowest": lowest, "tiles": comp, "valid": true}
		for c in comp:
			_chain_of_tile[c] = cid
	# a copper tile with 3+ copper neighbours kills its whole chain (copper never branches)
	for cid in _chains:
		var ok := true
		for c in _chains[cid]["tiles"]:
			if _copper_nbr_count(c) >= 3:
				ok = false
				break
		_chains[cid]["valid"] = ok


func _make_nodes() -> void:
	var ctrl_cap := 0
	if _controller >= 0:
		var tier := str(sim.machines[_controller].params.get("tier", "ctrl"))
		ctrl_cap = int(TIER_CAP.get(tier, TIER_CAP["ctrl"]))
	_add_node("source", "source", supply)
	_add_node("ctrl", "ctrl", ctrl_cap)
	_add_node("onboard", "onboard", onboard)
	for cid in _chains:
		if _chains[cid]["valid"]:
			_add_node(cid, "chain", 0)
	for bid in _boards:
		_add_node("b%d" % bid, "board", _board_cap(bid))


func _add_node(id: String, kind: String, cap: int) -> void:
	nodes[id] = {"id": id, "kind": kind, "cap": cap, "load": 0, "parent": "", "children": [], "live": false}


func _board_cap(bid: int) -> int:
	return int(sim.machines[bid].def().get("capacity", 0))


# ---------------------------------------------------------------- tree

func _make_edges() -> void:
	_edges["source"] = ["ctrl"]
	var ctrl_children := ["onboard"]
	if _controller >= 0:
		var m: Machine = sim.machines[_controller]
		for term in [m.cell + Vector2i(2, 0), m.cell + Vector2i(1, 2)]:
			var cid: String = _chain_of_tile.get(term, "")
			if cid != "" and nodes.has(cid):
				ctrl_children.append(cid)
				_set_feed(cid, "ctrl", term)
	_edges["ctrl"] = ctrl_children
	# chains feed the boards whose input tile they carry
	for bid in _boards:
		var b: Dictionary = _boards[bid]
		var cid: String = _chain_of_tile.get(b["input"], "")
		if cid != "" and nodes.has(cid):
			if not _edges.has(cid):
				_edges[cid] = []
			_edges[cid].append("b%d" % bid)
			if not _chains[cid].has("boards"):
				_chains[cid]["boards"] = []
			_chains[cid]["boards"].append({"bid": bid, "feed_tile": b["input"]})
	# boards feed the chains on their output terminals
	for bid in _boards:
		var b: Dictionary = _boards[bid]
		var out := []
		for side in ["N", "E", "S"]:
			var term: Vector2i = b["terminals"][side]
			var cid: String = _chain_of_tile.get(term, "")
			if cid != "" and nodes.has(cid):
				out.append(cid)
				_set_feed(cid, "b%d" % bid, term)
		_edges["b%d" % bid] = out
	for nid in _edges:
		_edges[nid].sort_custom(func(a, b): return _node_key(a) < _node_key(b))


func _set_feed(cid: String, parent: String, tile: Vector2i) -> void:
	if not _chain_feeds.has(cid):
		_chain_feeds[cid] = {}
	if not _chain_feeds[cid].has(parent):
		_chain_feeds[cid][parent] = tile


## BFS from source in ascending node-id order; each node gets one parent (first found).
func _bfs() -> void:
	var parent := {"source": ""}
	var q := ["source"]
	while not q.is_empty():
		var nid: String = q.pop_front()
		for c in _edges.get(nid, []):
			if not parent.has(c):
				parent[c] = nid
				q.append(c)
	for nid in nodes:
		nodes[nid]["live"] = parent.has(nid)
		nodes[nid]["parent"] = parent.get(nid, "")
		var kids := []
		for c in _edges.get(nid, []):
			if parent.get(c, "") == nid:
				kids.append(c)
		nodes[nid]["children"] = kids


## Path index inside a chain: BFS distance in tiles from the tile the chain is fed at.
func _chain_paths() -> void:
	for cid in _chains:
		if not nodes.has(cid) or not nodes[cid]["live"]:
			continue
		var parent: String = nodes[cid]["parent"]
		var feed: Vector2i = _chain_feeds.get(cid, {}).get(parent, Vector2i(-1, -1))
		var index := {feed: 0}
		var order := [feed]
		var q := [feed]
		while not q.is_empty():
			var c: Vector2i = q.pop_front()
			for n in _nbrs(c):
				if _chain_of_tile.get(n, "") == cid and not index.has(n):
					index[n] = index[c] + 1
					order.append(n)
					q.append(n)
		order.sort_custom(func(a, b): return _idx(a) < _idx(b))
		var caps := {}
		for t in order:
			caps[t] = int(CLASS_CAP[sim.machines[_copper[t]].type])
		_chains[cid]["feed"] = feed
		_chains[cid]["index"] = index
		_chains[cid]["order"] = order
		_chains[cid]["caps"] = caps
		_chains[cid]["loads"] = {}
		nodes[cid]["cap"] = caps[feed]


# ---------------------------------------------------------------- attachment

func _machine_feeds() -> void:
	for mid in sim.sorted_machine_ids():
		var m: Machine = sim.machines[mid]
		if m.locked or _is_power_part(m) or m.power_demand() <= 0:
			continue
		var demand := m.power_demand()
		var cand := {}  # chain id -> tapped contact tiles on it
		for c in _contacts(m):
			var cid: String = _chain_of_tile.get(c, "")
			if cid != "" and nodes.has(cid):
				if not cand.has(cid):
					cand[cid] = []
				cand[cid].append(c)
		var live := []
		for cid in cand:
			if nodes[cid]["live"]:
				live.append(cid)
		if live.is_empty():
			_feeds[mid] = {"kind": "onboard", "chain": "", "tap_index": -1, "tap_tile": Vector2i(-1, -1),
				"pads": 0, "demand": demand, "path": ["source", "ctrl", "onboard"]}
			continue
		live.sort_custom(func(a, b): return _node_key(a) < _node_key(b))
		var cid: String = live[0]
		var tiles: Array = cand[cid]
		var best: Vector2i = tiles[0]
		for t in tiles:
			if _chains[cid]["index"][t] < _chains[cid]["index"][best]:
				best = t
		var path := []
		var cur: String = cid
		while cur != "":
			path.push_front(cur)
			cur = nodes[cur]["parent"]
		_feeds[mid] = {"kind": "chain", "chain": cid, "tap_index": _chains[cid]["index"][best],
			"tap_tile": best, "pads": tiles.size(), "demand": demand, "path": path}
		if not _chains[cid].has("machines"):
			_chains[cid]["machines"] = []
		_chains[cid]["machines"].append({"tap_index": _chains[cid]["index"][best], "demand": demand})


func _contacts(m: Machine) -> Array:
	var s := Catalog.size_of(m.type, m.rot)
	var out := []
	for x in s.x:
		out.append(Vector2i(m.cell.x + x, m.cell.y + s.y))
	return out


func _is_power_part(m: Machine) -> bool:
	return str(m.def().get("family", "")) == "power"


# ---------------------------------------------------------------- loads

func _compute_loads() -> void:
	var memo := {}
	var onboard_load := 0
	for mid in _feeds:
		if _feeds[mid]["kind"] == "onboard":
			onboard_load += int(_feeds[mid]["demand"])
	nodes["onboard"]["load"] = onboard_load
	for cid in _chains:
		if nodes.has(cid) and nodes[cid]["live"]:
			nodes[cid]["load"] = _chain_load(cid, memo)
	# per-tile loads: everything downstream of index i
	for cid in _chains:
		if not nodes.has(cid) or not nodes[cid]["live"]:
			continue
		var ch: Dictionary = _chains[cid]
		var loads := {}
		for e in ch.get("machines", []):
			for i in range(0, int(e["tap_index"]) + 1):
				loads[i] = int(loads.get(i, 0)) + int(e["demand"])
		for e in ch.get("boards", []):
			var bl := _board_load(int(e["bid"]), memo)
			var fi := int(ch["index"][e["feed_tile"]])
			for i in range(0, fi + 1):
				loads[i] = int(loads.get(i, 0)) + bl
		var tile_loads := {}
		for t in ch["order"]:
			tile_loads[t] = int(loads.get(ch["index"][t], 0))
		ch["loads"] = tile_loads
	for bid in _boards:
		var nid := "b%d" % bid
		if nodes.has(nid) and nodes[nid]["live"]:
			nodes[nid]["load"] = _board_load(bid, memo)
	var ctrl_load := onboard_load
	for cid in nodes["ctrl"]["children"]:
		if nodes[cid]["kind"] == "chain":
			ctrl_load += int(nodes[cid]["load"])
	nodes["ctrl"]["load"] = ctrl_load
	nodes["source"]["load"] = ctrl_load


func _chain_load(cid: String, memo: Dictionary) -> int:
	if memo.has(cid):
		return memo[cid]
	var ch: Dictionary = _chains[cid]
	var total := 0
	for e in ch.get("machines", []):
		total += int(e["demand"])
	for e in ch.get("boards", []):
		total += _board_load(int(e["bid"]), memo)
	memo[cid] = total
	return total


func _board_load(bid: int, memo: Dictionary) -> int:
	var nid := "b%d" % bid
	if memo.has(nid):
		return memo[nid]
	var total := 0
	for cid in nodes[nid]["children"]:
		if nodes[cid]["kind"] == "chain":
			total += _chain_load(cid, memo)
	memo[nid] = total
	return total


# ---------------------------------------------------------------- queries

## The node path root→machine: {"node", "cap", "load"} entries (a chain-fed machine ends with
## its pads node "p<mid>").
func path(mid: int) -> Array:
	var feed = _feeds.get(mid)
	if feed == null:
		return []
	var out := []
	for nid in feed["path"]:
		out.append({"node": nid, "cap": int(nodes[nid]["cap"]), "load": int(nodes[nid]["load"])})
	if feed["kind"] == "chain":
		out.append({"node": "p%d" % mid, "cap": PAD_CAP * int(feed["pads"]), "load": int(feed["demand"])})
	return out


## The single tightest stage on the machine's path: {} when nothing is overloaded.
## {"node", "cap", "load"}; ties go to the first stage on the path.
func bottleneck(mid: int) -> Dictionary:
	var feed = _feeds.get(mid)
	if feed == null:
		return {}
	var stages := []
	stages.append({"node": "source", "cap": int(nodes["source"]["cap"]), "load": int(nodes["source"]["load"])})
	stages.append({"node": "ctrl", "cap": int(nodes["ctrl"]["cap"]), "load": int(nodes["ctrl"]["load"])})
	if feed["kind"] == "onboard":
		stages.append({"node": "onboard", "cap": int(nodes["onboard"]["cap"]), "load": int(nodes["onboard"]["load"])})
	else:
		var path_nodes: Array = feed["path"]
		var i := 2  # source, ctrl
		while i < path_nodes.size():
			var nid: String = path_nodes[i]
			var ch: Dictionary = _chains[nid]
			var limit := int(feed["tap_index"])
			if i < path_nodes.size() - 1:
				var bid := int(str(path_nodes[i + 1]).substr(1))
				limit = int(ch["index"][_boards[bid]["input"]])
			for t in ch["order"]:
				if int(ch["index"][t]) <= limit:
					stages.append({"node": nid, "cap": int(ch["caps"][t]), "load": int(ch["loads"][t])})
			if i + 1 < path_nodes.size():
				var bnid: String = path_nodes[i + 1]
				stages.append({"node": bnid, "cap": int(nodes[bnid]["cap"]), "load": int(nodes[bnid]["load"])})
			i += 2
		stages.append({"node": "p%d" % mid, "cap": PAD_CAP * int(feed["pads"]), "load": int(feed["demand"])})
	var best := {}
	var best_ratio := INF
	for s in stages:
		if int(s["cap"]) > 0 and int(s["load"]) > int(s["cap"]):
			var ratio := float(s["cap"]) / float(s["load"])
			if ratio < best_ratio:
				best_ratio = ratio
				best = s
	return best


## Work rate with the single tightest stage applied (never compounded, floored at 1).
func work_rate(mid: int, r: int) -> int:
	var b := bottleneck(mid)
	if b.is_empty():
		return r
	return maxi(1, r * int(b["cap"]) / int(b["load"]))


## "normal" < 75 %, "near" 75–100 %, "over" > 100 %; "normal" when the cap is 0 (unlimited).
func state(node_id: String) -> String:
	var n = nodes.get(node_id)
	if n == null:
		return "normal"
	var cap := int(n["cap"])
	if cap <= 0:
		return "normal"
	var load := int(n["load"])
	if load > cap:
		return "over"
	return "near" if load * 4 >= cap * 3 else "normal"


## The node that feeds a machine: its chain id, or "onboard".
func feeder_of(mid: int) -> String:
	var feed = _feeds.get(mid)
	if feed == null:
		return ""
	return str(feed["chain"]) if feed["kind"] == "chain" else "onboard"


# ---------------------------------------------------------------- view queries

## One copper tile against its class cap: "normal" < 75 %, "near" 75–100 %, "over" > 100 %.
## A tile that is not on a live chain is "normal".
func tile_state(tile: Vector2i) -> String:
	var cid: String = _chain_of_tile.get(tile, "")
	if cid == "" or not nodes.has(cid) or not nodes[cid]["live"]:
		return "normal"
	var ch: Dictionary = _chains[cid]
	var cap := int(ch.get("caps", {}).get(tile, 0))
	var load := int(ch.get("loads", {}).get(tile, 0))
	if cap <= 0:
		return "normal"
	if load > cap:
		return "over"
	return "near" if load * 4 >= cap * 3 else "normal"


## The contact tiles (directly south of the machine) that feed it from its live chain.
func tapped_contacts(mid: int) -> Array:
	var feed = _feeds.get(mid)
	if feed == null or feed["kind"] != "chain":
		return []
	var out := []
	for c in _contacts(sim.machines[mid]):
		if _chain_of_tile.get(c, "") == feed["chain"]:
			out.append(c)
	return out


## Copper tiles that sit on a power part's terminal: {"tile", "dir"}, `dir` pointing from the
## copper tile toward the part (controller E / S outputs, board W input and N / E / S outputs).
func terminal_tiles() -> Array:
	var out := []
	var terms := []
	if _controller >= 0:
		var cell: Vector2i = sim.machines[_controller].cell
		terms.append([cell + Vector2i(2, 0), Vector2i.LEFT])
		terms.append([cell + Vector2i(1, 2), Vector2i.UP])
	for bid in _boards:
		var b: Dictionary = _boards[bid]
		terms.append([b["input"], Vector2i.RIGHT])
		terms.append([b["terminals"]["N"], Vector2i.DOWN])
		terms.append([b["terminals"]["E"], Vector2i.LEFT])
		terms.append([b["terminals"]["S"], Vector2i.UP])
	for e in terms:
		if _copper.has(e[0]):
			out.append({"tile": e[0], "dir": e[1]})
	return out


# ---------------------------------------------------------------- placement

## Why a copper tile may not be placed at `cell`, or "" when it is fine: copper never branches
## by itself — a tile with 3+ copper neighbours (the new one or a neighbour) is refused.
static func placement_error(sim, type: String, cell: Vector2i) -> String:
	if not type in COPPER:
		return ""
	var copper := {}
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type in COPPER:
			for c in m.footprint():
				copper[c] = true
	if copper.has(cell):
		return ""
	copper[cell] = true
	var check := [cell]
	for n in _nbrs4(cell):
		if copper.has(n):
			check.append(n)
	for t in check:
		if _copper_nbrs(t, copper) >= 3:
			return SPLIT_MSG
	return ""


# ---------------------------------------------------------------- helpers

## Numeric ordering key of a node id: onboard, then chains by their lowest tile index, then boards
## by machine id (plain string order would put "c123" before "c45").
func _node_key(nid: String) -> int:
	if nid.begins_with("c"):
		return 1_000_000 + int(nid.substr(1))
	if nid.begins_with("b"):
		return 2_000_000_000 + int(nid.substr(1))
	return 0

func _idx(c: Vector2i) -> int:
	return c.y * sim.size.x + c.x


func _nbrs(c: Vector2i) -> Array:
	return _nbrs4(c)


func _copper_nbr_count(c: Vector2i) -> int:
	return _copper_nbrs(c, _copper)


static func _nbrs4(c: Vector2i) -> Array:
	return [c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)]


static func _copper_nbrs(c: Vector2i, copper: Dictionary) -> int:
	var n := 0
	for d in _nbrs4(c):
		if copper.has(d):
			n += 1
	return n