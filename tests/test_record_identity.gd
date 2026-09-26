class_name RecordIdentityTests
extends RefCounted
## C3-core (docs/DATA_FACTORY.md §3.1, §2.0b): record identity is safe, timing is physical, and
## powered parts keep an idle baseline. Parts with several inputs combine only values of the same
## record; context-free values fit any record; a value whose partner record can never arrive is
## discarded as an ORPHAN — but never while the partner is still on its way.


static func run(t) -> void:
	_pairs_by_record(t)
	_context_free_fits(t)
	_orphans_after_a_drop(t)
	_no_false_orphans(t)
	_state_is_context_free(t)
	_idle_baseline(t)


static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(24, 12)
	return sim


static func _feed(sim: Simulation, m: Machine, port: String, bin: String, ctx: int) -> Packet:
	var p := Packet.new(sim.new_packet_id(), BitVector.from_bin(bin), sim.tick)
	p.ctx = ctx
	m.inq[port].append(p)
	return p


## An AND whose inputs arrive in different orders pairs record 1 with record 1, never 2 with 1.
static func _pairs_by_record(t) -> void:
	var sim := _sim()
	var g := sim.place("and_gate", Vector2i(2, 2), 0, {}, 3)
	_feed(sim, g, "a", "110", 2)
	_feed(sim, g, "a", "011", 1)
	_feed(sim, g, "b", "111", 1)
	var got := g.take_record(["a", "b"], sim)
	var pa: Packet = got.get("a")
	t.check(pa != null and pa.ctx == 1 and pa.data.equals(BitVector.from_bin("011")), "the oldest complete record pairs (record 1 with record 1)")
	t.check(g.inq["a"].size() == 1 and (g.inq["a"][0] as Packet).ctx == 2, "record 2 keeps waiting for its partner")
	t.check(g.take_record(["a", "b"], sim).is_empty(), "no partner for record 2 yet: nothing is combined")


## A context-free value (a constant, stored state) fits any record; the result keeps the record.
static func _context_free_fits(t) -> void:
	var sim := _sim()
	var g := sim.place("and_gate", Vector2i(2, 2), 0, {}, 3)
	_feed(sim, g, "a", "101", 5)
	_feed(sim, g, "b", "111", -1)
	var out: Packet = null
	for i in 10:
		sim.step()
		if g.outq["out"] != null:
			out = g.outq["out"]
			break
	t.check(out != null and out.ctx == 5 and out.data.equals(BitVector.from_bin("101")), "record 5 AND a context-free value = record 5")


## A small board: src → Splitter (copy) → [Gate (ctrl stream) → AND.a] and [→ AND.b].
static func _branch_board(gate_ctrl: Array, delay_ticks := 0) -> Dictionary:
	var sim := _sim()
	var src := sim.place("input", Vector2i(1, 2), 0, {}, 3)
	src.stream = [BitVector.from_bin("010"), BitVector.from_bin("011"), BitVector.from_bin("100"), BitVector.from_bin("101")]
	src.interval = 4
	var sp := sim.place("splitter", Vector2i(4, 2), 0, {"mode": "Duplicate"}, 3)
	var and_g := sim.place("and_gate", Vector2i(14, 2), 0, {}, 3)
	sim.connect_ports(src.id, "out", sp.id, "in")
	sim.connect_ports(sp.id, "b", and_g.id, "b")
	if gate_ctrl.is_empty():
		var d := sim.place("delay", Vector2i(9, 2), 0, {"ticks": delay_ticks}, 3)
		sim.connect_ports(sp.id, "a", d.id, "in")
		sim.connect_ports(d.id, "out", and_g.id, "a")
	else:
		var ctl := sim.place("input", Vector2i(1, 7), 0, {}, 1)
		var bits: Array = []
		for b in gate_ctrl:
			bits.append(BitVector.of(int(b), 1))
		ctl.stream = bits
		ctl.interval = 4
		var gate := sim.place("gate", Vector2i(9, 2), 0, {}, 3)
		sim.connect_ports(sp.id, "a", gate.id, "in")
		sim.connect_ports(ctl.id, "out", gate.id, "ctrl")
		sim.connect_ports(gate.id, "out", and_g.id, "a")
	sim.reset_run()
	return {"sim": sim, "and": and_g}


static func _drain(sim: Simulation, m: Machine, ticks: int) -> Array:
	var out: Array = []
	for i in ticks:
		sim.step()
		if m.outq["out"] != null:
			out.append(m.pop_output("out"))
	return out


## The Gate drops records 1 and 3 on branch A: their copies waiting on AND.b can never be
## completed and are discarded as orphans; records 0 and 2 still pair.
static func _orphans_after_a_drop(t) -> void:
	var b := _branch_board([1, 0, 1, 0])
	var sim: Simulation = b["sim"]
	var and_g: Machine = b["and"]
	var res := _drain(sim, and_g, 300)
	var ctxs: Array = []
	for p in res:
		ctxs.append((p as Packet).ctx)
	t.check(ctxs == [0, 2], "only the records that passed the Gate are combined (%s)" % [ctxs])
	t.check(and_g.orphans == 2 and and_g.inq["b"].is_empty(), "the dropped records' partners are orphans (%d)" % and_g.orphans)


## A slow branch (a long Delay) holds the partners upstream: the waiting values are never
## orphaned, the AND waits (that costs time), and every record pairs.
static func _no_false_orphans(t) -> void:
	var b := _branch_board([], 30)
	var sim: Simulation = b["sim"]
	var and_g: Machine = b["and"]
	var res := _drain(sim, and_g, 400)
	t.check(res.size() == 4 and and_g.orphans == 0, "a deep branch only delays: 4 results, 0 orphans (%d, %d)" % [res.size(), and_g.orphans])


## A Register's output is stored state: context-free, so a feedback loop pairs it with any record.
static func _state_is_context_free(t) -> void:
	var sim := _sim()
	var r := sim.place("register", Vector2i(2, 2), 0, {"mode": "echo"}, 3)
	for i in 4:
		sim.step()
	var seed: Packet = r.outq["out"]
	t.check(seed != null and seed.ctx == -1, "the Register's seed is context-free")
	r.pop_output("out")
	_feed(sim, r, "in", "101", 7)
	var echo: Packet = null
	for i in 6:
		sim.step()
		if r.outq["out"] != null:
			echo = r.outq["out"]
			break
	t.check(echo != null and echo.ctx == -1 and echo.data.equals(BitVector.from_bin("101")), "the echoed state is context-free too")


## Idle baseline: an idle powered part still makes idle_pct of its full-rate heat; full load is
## unchanged; power draw blends the same way (the rails still see the peak demand).
static func _idle_baseline(t) -> void:
	var sim := _sim()
	var m := sim.place("multiply", Vector2i(2, 2), 0, {"k": 2, "lanes": "2"}, 3)
	var full := m.heat() * m.heat_mult() * m.lanes()
	m.work_done = 0
	t.check(m.idle_pct() == 12, "the default idle baseline is 12 %% (data-driven, got %d)" % m.idle_pct())
	t.check(m.heat_this_tick() == full * 12 / 100, "idle heat = 12 %% of full-rate heat (%d of %d)" % [m.heat_this_tick(), full])
	m.work_done = m.lanes() * m.clock_rate()
	t.check(m.heat_this_tick() == full, "full load heat is unchanged (%d)" % m.heat_this_tick())
	var d := m.power_demand()
	t.check(m.power_draw() == d, "full load draws the whole demand (%d)" % d)
	m.work_done = 0
	t.check(m.power_draw() == (d * 12 + 50) / 100, "idle draw = 12 %% of the demand, rounded (%d of %d)" % [m.power_draw(), d])
	var io := sim.place("usb_input", Vector2i(10, 2), 0, {}, 3)
	io.locked = true
	t.check(io.idle_pct() == 0 and io.heat_this_tick() == 0, "locked and unpowered parts have no idle baseline")
