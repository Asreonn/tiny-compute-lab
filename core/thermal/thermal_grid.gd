class_name ThermalGrid
extends RefCounted
## The board heat field (docs/SYSTEMS_EXPANSION.md §5): one int per tile, the temperature above
## ambient in tenths of °C (display = 25 + t/10 °C). Pure data and integer maths; the Simulation
## steps it once per tick after the machines worked. Energy is conserved exactly by the diffusion
## and equalisation passes; only dissipation removes heat.

enum Stage { NORMAL, WARM, HOT, THROTTLING, CRITICAL }
const STAGE_NAMES := ["NORMAL", "WARM", "HOT", "THROTTLING", "CRITICAL"]
## Entry temperature of each stage; a stage is left 50 below its entry (hysteresis).
const ENTER := [0, 250, 450, 600, 750]
const EXIT_GAP := 50

const K_BOARD := 8  # /64 per tile edge
const D_AMBIENT := 8  # /1024 per tick
const D_EDGE := 32  # /1024 per board side a tile lies on (the chassis leaks a little)
## Cooling machines: [dissipation bonus /1024, Chebyshev radius, scales with the power it gets].
## LEGACY: radius cooling for unattached blowers/radiators keeps the pre-overhaul levels
## solvable; the progression rewrite (P13) removes it.
const COOLERS := {
	"heatsink": [128, 1, false],
	"blower": [160, 2, true],
	"radiator": [256, 2, true],
}

var size := Vector2i.ZERO
var t := PackedInt32Array()  # temperature above ambient, tenths of °C
var dissipation := PackedInt32Array()  # d per tile on the last step (the thermal overlay reads it)
var _base_d := PackedInt32Array()
var _kx := PackedInt32Array()  # conductance of edge (x,y)-(x+1,y)
var _ky := PackedInt32Array()  # conductance of edge (x,y)-(x,y+1)
var _bodies: Array[PackedInt32Array] = []  # isothermal groups: machine footprints
var _sig := -1  # layout hash the topology was built for
var _box := Rect2i()  # every tile with t != 0 lies inside (empty = a cold board)
var net: ThermalNetwork = null  # the thermal path model for the current layout
var last_alloc := {}  # the last allocate() result (the thermal overlay reads it)
var last_offers := {}  # the last tick's offers (the thermal overlay reads it)
var _sink_tiles := {}  # tile -> true for every sink footprint (legacy blower check)
var _net_tiles := {}  # tile -> true for every transport/manifold footprint (legacy radiator check)


func _init(board: Vector2i) -> void:
	size = board
	t.resize(size.x * size.y)
	t.fill(0)
	_base_d.resize(t.size())
	for y in size.y:
		for x in size.x:
			var sides := int(x == 0) + int(x == size.x - 1) + int(y == 0) + int(y == size.y - 1)
			_base_d[y * size.x + x] = D_AMBIENT + sides * D_EDGE
	dissipation = _base_d.duplicate()


func idx(c: Vector2i) -> int:
	return c.y * size.x + c.x


func at(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return 0
	return t[idx(c)]


## Hottest tile of a machine's footprint.
func machine_temp(m: Machine) -> int:
	var hi := 0
	var s := Catalog.size_of(m.type, m.rot)
	for y in s.y:
		for x in s.x:
			hi = maxi(hi, at(m.cell + Vector2i(x, y)))
	return hi


## The stage for `temp` given the current one (enter at ENTER, leave 50 lower).
static func stage_for(temp: int, current: int) -> int:
	var s := current
	while s < Stage.CRITICAL and temp >= int(ENTER[s + 1]):
		s += 1
	while s > Stage.NORMAL and temp < int(ENTER[s]) - EXIT_GAP:
		s -= 1
	return s


## Display °C of a tenths-above-ambient value.
static func celsius(temp: int) -> float:
	return 25.0 + temp / 10.0


## One tick: generate → diffuse → equalise → network removal → dissipate. `mids` are the machine
## ids in ascending order; each machine's work_done this tick drives its heat.
##
## Only the warm part of the board is visited: `_box` bounds every tile that may hold heat, so a
## cold board costs nothing and a hot corner costs its own size. Every skipped tile and edge is
## exactly 0 → 0, so the result is bit-identical to a full pass.
func step(sim, mids: Array) -> void:
	_ensure_topology(sim, mids)
	var w := size.x
	# 1. generate
	for id in mids:
		var m: Machine = sim.machines[id]
		var h := m.heat_this_tick()  # idle baseline + work done (DATA_FACTORY §2.0b)
		if h <= 0:
			continue
		var cells := _cells_sorted(m)
		var q := h / cells.size()
		t[cells[0]] += h - q * cells.size()
		for c in cells:
			t[c] += q
			_include(c % w, c / w)
	# 4a. the dissipation map (bonus of every cooler; the thermal overlay reads it)
	dissipation = _base_d.duplicate()
	for id in mids:
		var m: Machine = sim.machines[id]
		if not COOLERS.has(m.type):
			continue
		# LEGACY: radius cooling for unattached blowers/radiators keeps the pre-overhaul levels
		# solvable; the progression rewrite (P13) removes it. Attached cooling runs through the
		# ThermalNetwork instead, and the new parts (fin_stack / radiator_large / blower_hp /
		# fan_bank) never get a radius bonus.
		if m.type == "blower" and _feeds_sink(m):
			continue
		if m.type == "radiator" and _inlet_on_network(m):
			continue
		var spec: Array = COOLERS[m.type]
		var bonus: int = spec[0]
		if spec[2]:
			bonus = bonus * sim.work_rate(m) / Machine.WORK_PER_TICK
		if bonus <= 0:
			continue
		var s0 := m.cell
		var s1 := m.cell + Catalog.size_of(m.type, m.rot) - Vector2i.ONE
		var r2: int = spec[1]
		for y in range(maxi(0, s0.y - r2), mini(size.y - 1, s1.y + r2) + 1):
			for x in range(maxi(0, s0.x - r2), mini(size.x - 1, s1.x + r2) + 1):
				dissipation[y * w + x] += bonus
	if not _box.has_area():
		return  # a cold board stays cold
	# 2. diffuse (per-edge flux, truncated toward zero, applied symmetrically) over the warm box
	# plus a one-tile rim: heat moves at most one tile per tick
	var b := _box.grow(1).intersection(Rect2i(Vector2i.ZERO, size))
	var x0 := b.position.x
	var x1 := b.end.x
	var y1 := b.end.y
	var nt := t.duplicate()
	for y in range(b.position.y, y1):
		var row := y * w
		for x in range(x0, x1):
			var i := row + x
			if x + 1 < x1:
				var kx := _kx[i]
				if kx > 0:
					var diff := t[i] - t[i + 1]
					if diff != 0:
						var v := diff * kx
						var f := v / 64 if v >= 0 else -((-v) / 64)
						nt[i] -= f
						nt[i + 1] += f
			if y + 1 < y1:
				var ky := _ky[i]
				if ky > 0:
					var diff2 := t[i] - t[i + w]
					if diff2 != 0:
						var v2 := diff2 * ky
						var f2 := v2 / 64 if v2 >= 0 else -((-v2) / 64)
						nt[i] -= f2
						nt[i + w] += f2
	t = nt
	_box = b
	# 3. equalise machine bodies (a long chain may carry heat past the box)
	for body in _bodies:
		var s := 0
		for c in body:
			s += t[c]
		if s == 0:
			continue
		var q2 := s / body.size()
		var r := s - q2 * body.size()
		for j in body.size():
			t[body[j]] = q2 + (1 if j < r else 0)
			_include(body[j] % w, body[j] / w)
	# 3.5 network removal: every connected machine offers a quarter of its body heat to the path;
	# sinks dump it out of the computer or recirculate it into their exhaust tiles. Removal only
	# lowers tiles (no box growth); recirculated dump tiles must be _include()d.
	last_offers = {}
	last_alloc = {}
	if net != null:
		var offers := {}
		for id in mids:
			var m: Machine = sim.machines[id]
			if net.network_of(id) == "":
				continue
			var cells := _cells_sorted(m)
			var body := 0
			for c in cells:
				body += t[c]
			if body <= 0:
				continue
			var offer := mini(net.contact_cap(id), body / 4)
			if offer <= 0:
				continue
			offers[id] = offer
		last_offers = offers
		if not offers.is_empty():
			var alloc := net.allocate(offers)
			last_alloc = alloc
			var removal: Dictionary = alloc["removal"]
			for id in offers:
				var rem := int(removal.get(id, 0))
				if rem <= 0:
					continue
				var cells := _cells_sorted(sim.machines[id])
				var body := 0
				for c in cells:
					body += t[c]
				var taken := 0
				for c in cells:
					var d := t[c] * rem / body
					t[c] -= d
					taken += d
				var left := rem - taken
				if left > 0:
					t[cells[0]] = maxi(0, t[cells[0]] - left)
			var dump: Dictionary = alloc["dump"]
			for sid in dump:
				var dv := int(dump[sid])
				if dv <= 0:
					continue
				var m: Machine = sim.machines[sid]
				var s: Vector2i = Catalog.size_of(m.type, 0)
				var exhausts := []
				for x in s.x:
					exhausts.append(Vector2i(m.cell.x + x, m.cell.y - 1))
				var out := true
				for e in exhausts:
					if e.y >= 0:
						out = false
				if out:
					continue  # the heat leaves the computer
				var inside := []
				for e in exhausts:
					if e.y >= 0 and e.x >= 0 and e.x < size.x:
						inside.append(e)
				if inside.is_empty():
					continue
				var q := dv / inside.size()
				var r := dv - q * inside.size()
				for j in inside.size():
					var e: Vector2i = inside[j]
					t[idx(e)] += q + (1 if j < r else 0)
					_include(e.x, e.y)
	# 4b. dissipate (rounded up so every warm tile keeps cooling), shrinking the box to the tiles
	# still warm
	var lo := Vector2i(size.x, size.y)
	var hi := Vector2i(-1, -1)
	for y in range(_box.position.y, _box.end.y):
		var row2 := y * w
		for x in range(_box.position.x, _box.end.x):
			var i2 := row2 + x
			var ti := t[i2]
			if ti > 0:
				ti -= (ti * mini(dissipation[i2], 1024) + 1023) / 1024
				t[i2] = ti
			if ti != 0:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	_box = Rect2i(lo, hi - lo + Vector2i.ONE) if hi.x >= 0 else Rect2i()


## Grow the warm box to cover tile (x, y).
func _include(x: int, y: int) -> void:
	if not _box.has_area():
		_box = Rect2i(x, y, 1, 1)
	else:
		_box = _box.expand(Vector2i(x, y))


func _cells_sorted(m: Machine) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in m.footprint():
		if c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y:
			out.append(idx(c))
	out.sort()
	if out.is_empty():
		out.append(0)
	return out


## The layout changed outside a step (an edit): rebuild the topology and the ThermalNetwork now.
func sync_topology(sim) -> void:
	_ensure_topology(sim, sim.sorted_machine_ids())


## Rebuild edge conductances and isothermal bodies when the layout changed.
func _ensure_topology(sim, mids: Array) -> void:
	var key := []
	for id in mids:
		var m: Machine = sim.machines[id]
		key.append_array([id, m.def_id(), m.cell, m.rot])
	var sig := key.hash()
	if sig == _sig:
		return
	_sig = sig
	_build_topology(sim, mids)
	net = ThermalNetwork.build(sim)


func _build_topology(sim, mids: Array) -> void:
	var n := size.x * size.y
	_kx.resize(n)
	_ky.resize(n)
	_kx.fill(K_BOARD)
	_ky.fill(K_BOARD)
	_bodies = []
	_sink_tiles = {}
	_net_tiles = {}
	for id in mids:
		var m: Machine = sim.machines[id]
		if m.type in ThermalNetwork.TRANSPORT or m.type == ThermalNetwork.MANIFOLD:
			# transport tiles are raised hardware now: no isothermal bodies, no pipe edges
			for c in m.footprint():
				_net_tiles[c] = true
			continue
		if m.type in ThermalNetwork.SINKS:
			for c in m.footprint():
				_sink_tiles[c] = true
		if m.footprint().size() > 1:
			_bodies.append(_cells_sorted(m))


## True when any tile directly north of the blower belongs to a sink footprint (it feeds the
## network model instead of using its legacy radius bonus).
func _feeds_sink(m: Machine) -> bool:
	for x in Catalog.size_of(m.type, 0).x:
		if _sink_tiles.has(Vector2i(m.cell.x + x, m.cell.y - 1)):
			return true
	return false


## True when any inlet tile (west of the left column) is a transport/manifold tile (the radiator
## is attached to the network model instead of using its legacy radius bonus).
func _inlet_on_network(m: Machine) -> bool:
	for y in Catalog.size_of(m.type, 0).y:
		if _net_tiles.has(Vector2i(m.cell.x - 1, m.cell.y + y)):
			return true
	return false
