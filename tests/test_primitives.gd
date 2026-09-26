class_name PrimitiveTests
extends RefCounted
## Group C3a acceptance tests: the primitive components (bit switch, fork, distributor, join,
## latch, constant, clock, probe) through the real Simulation phases, with hand-fed packets.


static func run(t) -> void:
	_bit_switch(t)
	_fork_backpressure(t)
	_fork_connected_only(t)
	_distributor(t)
	_join(t)
	_latch(t)
	_constant(t)
	_clock(t)
	_probe_pass_through(t)


static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(24, 12)
	return sim


static func _feed(sim: Simulation, m: Machine, port: String, bin: String, ctx: int) -> Packet:
	var p := Packet.new(sim.new_packet_id(), BitVector.from_bin(bin), sim.tick)
	p.ctx = ctx
	m.inq[port].append(p)
	return p


## Bit Switch: EN=1 passes D, EN=0 outputs 0 of the same width; the record is kept.
static func _bit_switch(t) -> void:
	var sim := _sim()
	var bs := sim.place("bit_switch", Vector2i(2, 2), 0, {}, 3)
	_feed(sim, bs, "in", "101", 0)
	_feed(sim, bs, "ctrl", "1", 0)
	for i in 6:
		sim.step()
	var p: Packet = bs.outq["out"]
	t.check(p != null and p.data.equals(BitVector.from_bin("101")) and p.ctx == 0, "EN=1 passes D=101 through (got %s)" % str(p.data if p != null else "-"))
	bs.pop_output("out")
	_feed(sim, bs, "in", "101", 1)
	_feed(sim, bs, "ctrl", "0", 1)
	for i in 6:
		sim.step()
	var p2: Packet = bs.outq["out"]
	t.check(p2 != null and p2.data.equals(BitVector.of(0, 3)) and p2.ctx == 1, "EN=0 outputs 000 of width 3 (got %s)" % str(p2.data if p2 != null else "-"))


## Fork: a full branch holds the next copy back, so the whole fan-out is limited.
static func _fork_backpressure(t) -> void:
	var sim := _sim()
	var fork := sim.place("fork", Vector2i(6, 2), 0, {}, 3)
	var ng := sim.place("not_gate", Vector2i(10, 1), 0, {}, 3)
	var probe := sim.place("probe", Vector2i(10, 5), 0, {}, 3)
	sim.connect_ports(fork.id, "a", ng.id, "in")
	sim.connect_ports(fork.id, "b", probe.id, "in")
	for i in 12:
		_feed(sim, fork, "in", "101", -1)
		sim.step()
	for i in 60:
		sim.step()
	t.check(probe.counter < 12, "the blocked NOT branch limits the whole fan-out (probe saw %d of 12)" % probe.counter)
	t.check(not fork.inq["in"].is_empty() or fork.waiting_results() > 0, "the fork still holds values behind the blocked branch")


## Fork: copies go to connected outputs only.
static func _fork_connected_only(t) -> void:
	var sim := _sim()
	var fork := sim.place("fork", Vector2i(2, 2), 0, {}, 3)
	var probe := sim.place("probe", Vector2i(6, 2), 0, {}, 3)
	sim.connect_ports(fork.id, "b", probe.id, "in")
	for i in 5:
		_feed(sim, fork, "in", "101", -1)
		sim.step()
	for i in 30:
		sim.step()
	t.check(probe.counter == 5, "only the wired b output receives copies (probe saw %d of 5)" % probe.counter)


## Distributor: deals A, B, C in turn to the connected outputs.
static func _distributor(t) -> void:
	var sim := _sim()
	var d := sim.place("distributor", Vector2i(2, 2), 0, {}, 3)
	var pa := sim.place("probe", Vector2i(6, 1), 0, {}, 3)
	var pb := sim.place("probe", Vector2i(6, 3), 0, {}, 3)
	var pc := sim.place("probe", Vector2i(6, 5), 0, {}, 3)
	sim.connect_ports(d.id, "a", pa.id, "in")
	sim.connect_ports(d.id, "b", pb.id, "in")
	sim.connect_ports(d.id, "c", pc.id, "in")
	for i in 6:
		_feed(sim, d, "in", "101", -1)
		sim.step()
	for i in 40:
		sim.step()
	t.check(pa.counter == 2 and pb.counter == 2 and pc.counter == 2, "distributor deals A, B, C in turn (got %d/%d/%d)" % [pa.counter, pb.counter, pc.counter])


## Join: takes values from the connected inputs in turn and sends them on as one stream.
static func _join(t) -> void:
	var sim := _sim()
	var ia := sim.place("input", Vector2i(1, 0), 0, {}, 3)
	var ib := sim.place("input", Vector2i(0, 2), 0, {}, 3)
	var ic := sim.place("input", Vector2i(1, 4), 0, {}, 3)
	var j := sim.place("join", Vector2i(4, 2), 0, {}, 3)
	var probe := sim.place("probe", Vector2i(8, 2), 0, {}, 3)
	sim.connect_ports(ia.id, "out", j.id, "a")
	sim.connect_ports(ib.id, "out", j.id, "b")
	sim.connect_ports(ic.id, "out", j.id, "c")
	sim.connect_ports(j.id, "out", probe.id, "in")
	_feed(sim, j, "a", "001", -1)
	_feed(sim, j, "a", "010", -1)
	_feed(sim, j, "b", "011", -1)
	_feed(sim, j, "c", "100", -1)
	_feed(sim, j, "c", "101", -1)
	for i in 40:
		sim.step()
	t.check(probe.counter == 5, "join takes every fed value (probe saw %d of 5)" % probe.counter)
	var last: BitVector = probe.memory[0] if not probe.memory.is_empty() else BitVector.zero(3)
	t.check(last.equals(BitVector.from_bin("101")), "the last value taken is the second C (got %s)" % str(last))


## Latch: EN=1 stores D, EN=0 re-emits the stored value; an unwired D stores the tie value.
static func _latch(t) -> void:
	var sim := _sim()
	var src := sim.place("input", Vector2i(0, 2), 0, {}, 3)
	var l := sim.place("latch", Vector2i(3, 2), 0, {}, 3)
	sim.connect_ports(src.id, "out", l.id, "in")
	_feed(sim, l, "in", "101", 0)
	_feed(sim, l, "ctrl", "1", 0)
	for i in 6:
		sim.step()
	var p: Packet = l.outq["out"]
	t.check(p != null and p.data.equals(BitVector.from_bin("101")), "EN=1 stores and outputs D=101 (got %s)" % str(p.data if p != null else "-"))
	l.pop_output("out")
	_feed(sim, l, "in", "011", 1)
	_feed(sim, l, "ctrl", "0", 1)
	for i in 6:
		sim.step()
	var p2: Packet = l.outq["out"]
	t.check(p2 != null and p2.data.equals(BitVector.from_bin("101")), "EN=0 holds the stored 101 (got %s)" % str(p2.data if p2 != null else "-"))
	var sim2 := _sim()
	var l2 := sim2.place("latch", Vector2i(2, 2), 0, {"d": 3}, 3)
	_feed(sim2, l2, "ctrl", "1", 0)
	for i in 6:
		sim2.step()
	var p3: Packet = l2.outq["out"]
	t.check(p3 != null and p3.data.equals(BitVector.from_bin("011")), "an unwired D stores the tie value d=3 (got %s)" % str(p3.data if p3 != null else "-"))


## Constant: emits its fixed value every tick; the packets are context-free.
static func _constant(t) -> void:
	var sim := _sim()
	var c := sim.place("constant", Vector2i(2, 2), 0, {"value": 5}, 3)
	var probe := sim.place("probe", Vector2i(6, 2), 0, {}, 3)
	sim.connect_ports(c.id, "out", probe.id, "in")
	for i in 20:
		sim.step()
	t.check(probe.counter >= 5, "the constant keeps emitting its value (probe saw %d)" % probe.counter)
	var last: BitVector = probe.memory[0] if not probe.memory.is_empty() else BitVector.zero(3)
	t.check(last.equals(BitVector.from_bin("101")), "the constant's value is 101 (got %s)" % str(last))
	var head: Packet = c.outq["out"]
	t.check(head != null and head.ctx == -1, "constant packets are context-free")


## Clock: emits a 1-bit pulse every Period ticks.
static func _clock(t) -> void:
	var sim := _sim()
	var c := sim.place("clock", Vector2i(2, 2), 0, {"period": 5}, 1)
	var probe := sim.place("probe", Vector2i(6, 2), 0, {}, 1)
	sim.connect_ports(c.id, "out", probe.id, "in")
	for i in 50:
		sim.step()
	t.check(probe.counter >= 8 and probe.counter <= 11, "the clock pulses every 5 ticks (probe saw %d in 50)" % probe.counter)
	var last: BitVector = probe.memory[0] if not probe.memory.is_empty() else BitVector.zero(1)
	t.check(last.equals(BitVector.of(1, 1)), "clock pulses are 1-bit ones (got %s)" % str(last))


## Probe: counts what passes and forwards it; a wired output keeps the chain moving.
static func _probe_pass_through(t) -> void:
	var sim := _sim()
	var src := sim.place("input", Vector2i(0, 2), 0, {}, 3)
	var probe := sim.place("probe", Vector2i(4, 2), 0, {}, 3)
	var ng := sim.place("not_gate", Vector2i(8, 2), 0, {}, 3)
	var sink := sim.place("probe", Vector2i(12, 2), 0, {}, 3)
	sim.connect_ports(src.id, "out", probe.id, "in")
	sim.connect_ports(probe.id, "out", ng.id, "in")
	sim.connect_ports(ng.id, "out", sink.id, "in")
	for i in 3:
		_feed(sim, probe, "in", "101", -1)
	for i in 20:
		sim.step()
	t.check(probe.counter == 3, "the probe counted all 3 fed values (got %d)" % probe.counter)
	t.check(ng.processed >= 3, "the NOT gate received all 3 values (processed %d)" % ng.processed)