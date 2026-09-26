class_name FieldTests
extends RefCounted
## Job C3c acceptance tests: Field Splitter / Field Joiner (pure bit slicing) through the real
## Simulation phases, with hand-fed packets and wired probe sinks.


static func run(t) -> void:
	_port_widths(t)
	_splitter_slicing(t)
	_splitter_unconnected_never_blocks(t)
	_splitter_leftover_dropped(t)
	_splitter_config_error(t)
	_joiner_concat(t)
	_joiner_record_pairing(t)
	_joiner_unconnected_zero(t)
	_round_trip(t)
	_connect_error_unconfigured(t)
	_set_param_refused_wired(t)


static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(24, 12)
	return sim


static func _feed(sim: Simulation, m: Machine, port: String, bin: String, ctx: int) -> Packet:
	var p := Packet.new(sim.new_packet_id(), BitVector.from_bin(bin), sim.tick)
	p.ctx = ctx
	m.inq[port].append(p)
	return p


## Place a field_joiner at (1,2) with `fields`, wire f0/f1 to input sources (so they count as
## connected) and out to a probe(5). Returns {joiner, probe}.
static func _joiner_setup(sim: Simulation, fields: String, wire_f0 := true, wire_f1 := true) -> Dictionary:
	var j := sim.place("field_joiner", Vector2i(1, 2), 0, {"fields": fields}, 5)
	var probe := sim.place("probe", Vector2i(3, 2), 0, {}, 5)
	sim.connect_ports(j.id, "out", probe.id, "in")
	if wire_f0:
		var src_f0 := sim.place("input", Vector2i(0, 0), 0, {}, 2)
		sim.connect_ports(src_f0.id, "out", j.id, "f0")
	if wire_f1:
		var src_f1 := sim.place("input", Vector2i(0, 4), 0, {}, 3)
		sim.connect_ports(src_f1.id, "out", j.id, "f1")
	return {"joiner": j, "probe": probe}


## 1. Port widths resolve from the "fields" param.
static func _port_widths(t) -> void:
	var sim := _sim()
	var sp := sim.place("field_splitter", Vector2i(1, 2), 0, {"fields": "6 3 4 3"}, 16)
	t.check(sp.port_width("f0") == 6 and sp.port_width("f1") == 3 and sp.port_width("f2") == 4 and sp.port_width("f3") == 3, "splitter f0..f3 widths are 6/3/4/3, got %d/%d/%d/%d" % [sp.port_width("f0"), sp.port_width("f1"), sp.port_width("f2"), sp.port_width("f3")])
	var j := sim.place("field_joiner", Vector2i(5, 2), 0, {"fields": "6 3 4 3"}, 16)
	t.check(j.port_width("out") == 16, "joiner out width is the field sum 16, got %d" % j.port_width("out"))
	var sp2 := sim.place("field_splitter", Vector2i(9, 2), 0, {"fields": "2 1"}, 3)
	t.check(sp2.port_width("f2") == 0, "unconfigured f2 width is 0, got %d" % sp2.port_width("f2"))


## 2. Splitter slices a 16-bit word into fields MSB first.
static func _splitter_slicing(t) -> void:
	var sim := _sim()
	var sp := sim.place("field_splitter", Vector2i(1, 2), 0, {"fields": "6 3 4 3"}, 16)
	var p0 := sim.place("probe", Vector2i(2, 0), 0, {}, 6)
	var p1 := sim.place("probe", Vector2i(4, 2), 0, {}, 3)
	var p2 := sim.place("probe", Vector2i(4, 3), 0, {}, 4)
	var p3 := sim.place("probe", Vector2i(2, 5), 0, {}, 3)
	sim.connect_ports(sp.id, "f0", p0.id, "in")
	sim.connect_ports(sp.id, "f1", p1.id, "in")
	sim.connect_ports(sp.id, "f2", p2.id, "in")
	sim.connect_ports(sp.id, "f3", p3.id, "in")
	_feed(sim, sp, "in", "1011010110011101", 0)
	for i in 40:
		sim.step()
	t.check(p0.counter == 1 and p0.memory[0].equals(BitVector.from_bin("101101")), "f0 sees 101101 (got %s)" % str(p0.memory[0] if not p0.memory.is_empty() else "-"))
	t.check(p1.counter == 1 and p1.memory[0].equals(BitVector.from_bin("011")), "f1 sees 011 (got %s)" % str(p1.memory[0] if not p1.memory.is_empty() else "-"))
	t.check(p2.counter == 1 and p2.memory[0].equals(BitVector.from_bin("0011")), "f2 sees 0011 (got %s)" % str(p2.memory[0] if not p2.memory.is_empty() else "-"))
	t.check(p3.counter == 1 and p3.memory[0].equals(BitVector.from_bin("101")), "f3 sees 101 (got %s)" % str(p3.memory[0] if not p3.memory.is_empty() else "-"))


## 3. A splitter never blocks on unconnected fields.
static func _splitter_unconnected_never_blocks(t) -> void:
	var sim := _sim()
	var sp := sim.place("field_splitter", Vector2i(1, 2), 0, {"fields": "2 3"}, 5)
	var probe := sim.place("probe", Vector2i(3, 2), 0, {}, 3)
	sim.connect_ports(sp.id, "f1", probe.id, "in")
	for i in 3:
		_feed(sim, sp, "in", "10110", -1)
	for i in 40:
		sim.step()
	t.check(probe.counter == 3, "splitter with only f1 wired keeps flowing (probe saw %d)" % probe.counter)


## 4. Leftover low bits are dropped.
static func _splitter_leftover_dropped(t) -> void:
	var sim := _sim()
	var sp := sim.place("field_splitter", Vector2i(1, 2), 0, {"fields": "2 1"}, 5)
	var p0 := sim.place("probe", Vector2i(2, 0), 0, {}, 2)
	var p1 := sim.place("probe", Vector2i(4, 2), 0, {}, 1)
	sim.connect_ports(sp.id, "f0", p0.id, "in")
	sim.connect_ports(sp.id, "f1", p1.id, "in")
	_feed(sim, sp, "in", "10110", 0)
	for i in 40:
		sim.step()
	t.check(p0.memory[0].equals(BitVector.from_bin("10")), "f0 sees 10 (got %s)" % str(p0.memory[0] if not p0.memory.is_empty() else "-"))
	t.check(p1.memory[0].equals(BitVector.from_bin("1")), "f1 sees 1 (got %s)" % str(p1.memory[0] if not p1.memory.is_empty() else "-"))


## 5. Fields needing more bits than the input is a config error; the value stays queued.
static func _splitter_config_error(t) -> void:
	var sim := _sim()
	var sp := sim.place("field_splitter", Vector2i(1, 2), 0, {"fields": "2 2"}, 3)
	_feed(sim, sp, "in", "101", 0)
	for i in 10:
		sim.step()
	t.check(sp.state == Machine.State.ERROR, "splitter with fields wider than the input errors")
	t.check(not sp.inq["in"].is_empty(), "the fed value stays queued after the config error")


## 6. Joiner concatenates fields, f0 in the high bits.
static func _joiner_concat(t) -> void:
	var sim := _sim()
	var s := _joiner_setup(sim, "2 3")
	var j: Machine = s["joiner"]
	var probe: Machine = s["probe"]
	_feed(sim, j, "f0", "10", 0)
	_feed(sim, j, "f1", "011", 0)
	for i in 40:
		sim.step()
	t.check(probe.counter == 1 and probe.memory[0].equals(BitVector.from_bin("10011")), "joiner of 10 and 011 is 10011 (got %s)" % str(probe.memory[0] if not probe.memory.is_empty() else "-"))


## 7. The joiner pairs fields of the same record, not the older-queued one.
static func _joiner_record_pairing(t) -> void:
	var sim := _sim()
	var s := _joiner_setup(sim, "2 3")
	var j: Machine = s["joiner"]
	var probe: Machine = s["probe"]
	_feed(sim, j, "f0", "11", 1)
	_feed(sim, j, "f0", "01", 0)
	_feed(sim, j, "f1", "000", 0)
	for i in 40:
		sim.step()
	t.check(probe.counter == 1 and probe.memory[0].equals(BitVector.from_bin("01000")), "record 0 pairs with record 0 to give 01000 (got %s)" % str(probe.memory[0] if not probe.memory.is_empty() else "-"))


## 8. An unconnected field reads as 0 of its width.
static func _joiner_unconnected_zero(t) -> void:
	var sim := _sim()
	var s := _joiner_setup(sim, "2 3", false, true)
	var j: Machine = s["joiner"]
	var probe: Machine = s["probe"]
	_feed(sim, j, "f1", "111", 0)
	for i in 40:
		sim.step()
	t.check(probe.counter == 1 and probe.memory[0].equals(BitVector.from_bin("00111")), "f1 111 with unconnected f0 gives 00111 (got %s)" % str(probe.memory[0] if not probe.memory.is_empty() else "-"))


## 9. Round trip: splitter -> all fields -> joiner -> probe.
static func _round_trip(t) -> void:
	var sim := _sim()
	var sp := sim.place("field_splitter", Vector2i(1, 2), 0, {"fields": "6 3 4 3"}, 16)
	var j := sim.place("field_joiner", Vector2i(4, 2), 0, {"fields": "6 3 4 3"}, 16)
	var probe := sim.place("probe", Vector2i(6, 2), 0, {}, 16)
	sim.connect_ports(sp.id, "f0", j.id, "f0")
	sim.connect_ports(sp.id, "f1", j.id, "f1")
	sim.connect_ports(sp.id, "f2", j.id, "f2")
	sim.connect_ports(sp.id, "f3", j.id, "f3")
	sim.connect_ports(j.id, "out", probe.id, "in")
	_feed(sim, sp, "in", "1011010110011101", 0)
	_feed(sim, sp, "in", "0101010101010101", 1)
	_feed(sim, sp, "in", "1111000011110000", 2)
	for i in 40:
		sim.step()
	t.check(probe.counter == 3, "round trip delivers all 3 values (probe saw %d)" % probe.counter)
	t.check(probe.memory[0].equals(BitVector.from_bin("1111000011110000")), "the last value round-trips intact (got %s)" % str(probe.memory[0] if not probe.memory.is_empty() else "-"))


## 10. connect_error refuses an unconfigured field port.
static func _connect_error_unconfigured(t) -> void:
	var sim := _sim()
	var sp := sim.place("field_splitter", Vector2i(1, 2), 0, {"fields": "2 1"}, 3)
	var probe := sim.place("probe", Vector2i(4, 2), 0, {}, 3)
	var err := sim.connect_error(sp.id, "f3", probe.id, "in")
	t.check(err != "", "connecting an unconfigured field is refused (got '%s')" % err)


## 11. set_param("fields") is refused while a field port is wired.
static func _set_param_refused_wired(t) -> void:
	var sim := _sim()
	var s := _joiner_setup(sim, "2 3")
	var j: Machine = s["joiner"]
	t.check(sim.set_param(j.id, "fields", "3 2") == false, "changing fields while field ports are wired is refused")