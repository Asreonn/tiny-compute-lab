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
const K_PIPE := 24  # /64 along a heat pipe and into its end pads; pipe sides are insulated (0)
const D_AMBIENT := 8  # /1024 per tick
const D_EDGE := 32  # /1024 per board side a tile lies on (the chassis leaks a little)
## Cooling machines: [dissipation bonus /1024, Chebyshev radius, scales with the power it gets].
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
var _ea := PackedInt32Array()  # conducting edges (k > 0): tile a, tile b, conductance
var _eb := PackedInt32Array()
var _ek := PackedInt32Array()
var _bodies: Array[PackedInt32Array] = []  # isothermal groups: machine footprints, pipe chains
var _sig := -1  # layout hash the topology was built for


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
	for c in m.footprint():
		hi = maxi(hi, at(c))
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


## Heat pipe axis from its rotation: true = horizontal (E–W).
static func pipe_horizontal(m: Machine) -> bool:
	return m.rot % 2 == 0


## One tick: generate → diffuse → equalise → dissipate. `mids` are the machine ids in ascending
## order; each machine's work_done this tick drives its heat.
func step(sim, mids: Array) -> void:
	_ensure_topology(sim, mids)
	var n := t.size()
	# 1. generate
	for id in mids:
		var m: Machine = sim.machines[id]
		if m.work_done <= 0:
			continue
		var h := Catalog.heat(m.type) * m.heat_mult() * m.work_done / maxi(1, m.clock_rate())
		if h <= 0:
			continue
		var cells := _cells_sorted(m)
		var q := h / cells.size()
		t[cells[0]] += h - q * cells.size()
		for c in cells:
			t[c] += q
	# 2. diffuse (per-edge flux, truncated toward zero, applied symmetrically)
	var nt := t.duplicate()
	for e in _ea.size():
		var a := _ea[e]
		var b := _eb[e]
		var diff := t[a] - t[b]
		if diff == 0:
			continue
		var v := diff * _ek[e]
		var f := v / 64 if v >= 0 else -((-v) / 64)
		nt[a] -= f
		nt[b] += f
	t = nt
	# 3. equalise machine bodies and heat-pipe chains
	for body in _bodies:
		var s := 0
		for c in body:
			s += t[c]
		var q2 := s / body.size()
		var r := s - q2 * body.size()
		for j in body.size():
			t[body[j]] = q2 + (1 if j < r else 0)
	# 4. dissipate (rounded up so every warm tile keeps cooling)
	dissipation = _base_d.duplicate()
	for id in mids:
		var m: Machine = sim.machines[id]
		if not COOLERS.has(m.type):
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
				dissipation[y * size.x + x] += bonus
	for i in n:
		if t[i] > 0:
			t[i] -= (t[i] * mini(dissipation[i], 1024) + 1023) / 1024


func _cells_sorted(m: Machine) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in m.footprint():
		if c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y:
			out.append(idx(c))
	out.sort()
	if out.is_empty():
		out.append(0)
	return out


## Rebuild edge conductances and isothermal bodies when the layout changed.
func _ensure_topology(sim, mids: Array) -> void:
	var key := []
	for id in mids:
		var m: Machine = sim.machines[id]
		key.append_array([id, m.type, m.cell, m.rot])
	var sig := key.hash()
	if sig == _sig:
		return
	_sig = sig
	_build_topology(sim, mids)
	_ea.clear()
	_eb.clear()
	_ek.clear()
	for y in size.y:
		for x in size.x:
			var i := y * size.x + x
			if x + 1 < size.x and _kx[i] > 0:
				_ea.append(i)
				_eb.append(i + 1)
				_ek.append(_kx[i])
			if y + 1 < size.y and _ky[i] > 0:
				_ea.append(i)
				_eb.append(i + size.x)
				_ek.append(_ky[i])


func _build_topology(sim, mids: Array) -> void:
	var n := size.x * size.y
	_kx.resize(n)
	_ky.resize(n)
	_kx.fill(K_BOARD)
	_ky.fill(K_BOARD)
	_bodies = []
	var pipe := {}  # tile index -> true if horizontal
	for id in mids:
		var m: Machine = sim.machines[id]
		if m.type == "heat_pipe":
			pipe[idx(m.cell)] = pipe_horizontal(m)
		elif m.footprint().size() > 1:
			_bodies.append(_cells_sorted(m))
	if pipe.is_empty():
		return
	# pipe edges: along the axis (pipe-pipe or into an end pad) = K_PIPE, across = insulated
	for i in pipe:
		var x: int = i % size.x
		var y: int = i / size.x
		if x + 1 < size.x:
			_kx[i] = _pipe_edge(pipe, i, i + 1, true)
		if x > 0:
			_kx[i - 1] = _pipe_edge(pipe, i - 1, i, true)
		if y + 1 < size.y:
			_ky[i] = _pipe_edge(pipe, i, i + size.x, false)
		if y > 0:
			_ky[i - size.x] = _pipe_edge(pipe, i - size.x, i, false)
	# chains: pipes joined by an edge that runs along either pipe's axis (straights and elbows)
	var seen := {}
	var keys := pipe.keys()
	keys.sort()
	for start in keys:
		if seen.has(start):
			continue
		var chain := PackedInt32Array()
		var stack := [start]
		while not stack.is_empty():
			var c: int = stack.pop_back()
			if seen.has(c):
				continue
			seen[c] = true
			chain.append(c)
			var cx: int = c % size.x
			var cy: int = c / size.x
			for nb in [[c - 1, cx > 0, true], [c + 1, cx + 1 < size.x, true], [c - size.x, cy > 0, false], [c + size.x, cy + 1 < size.y, false]]:
				if nb[1] and pipe.has(nb[0]) and not seen.has(nb[0]) and (pipe[c] == nb[2] or pipe[nb[0]] == nb[2]):
					stack.append(nb[0])
		chain.sort()
		if chain.size() > 1:
			_bodies.append(chain)


## Conductance of the edge a→b (b is right of / below a) when at least one side is a heat pipe.
static func _pipe_edge(pipe: Dictionary, a: int, b: int, horizontal_edge: bool) -> int:
	var pa = pipe.get(a)
	var pb = pipe.get(b)
	if pa != null and pb != null:
		return K_PIPE if (pa == horizontal_edge or pb == horizontal_edge) else 0
	var p = pa if pa != null else pb
	return K_PIPE if p == horizontal_edge else 0
