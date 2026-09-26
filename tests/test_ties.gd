class_name TieTests
extends RefCounted
## Group C3b acceptance tests: tie-off inputs (compare B, gate B, the Selector) and the
## mux->Selector migration, through the real Simulation phases with hand-fed packets.


static func run(t) -> void:
	_compare_unwired(t)
	_compare_wired(t)
	_compare_fifo(t)
	_and_tie(t)
	_xor_wired(t)
	_selector_both(t)
	_selector_both_tied(t)
	_selector_chosen_tied(t)
	_migration(t)
	_catalog_checks(t)


static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(24, 12)
	return sim


## Append a packet with that ctx straight to m.inq[port] (same helper as test_primitives).
static func _feed(sim: Simulation, m: Machine, port: String, bin: String, ctx: int) -> Packet:
	var p := Packet.new(sim.new_packet_id(), BitVector.from_bin(bin), sim.tick)
	p.ctx = ctx
	m.inq[port].append(p)
	return p


## Step until `m` has an output (or `limit` steps pass) and return it (outq["out"] head).
static func _run_until_out(sim: Simulation, m: Machine, limit := 40) -> Packet:
	for i in limit:
		sim.step()
		if m.outq["out"] != null:
			return m.outq["out"]
	return null


## Wire an empty input machine to `port` so it counts as CONNECTED (tie-off disabled).
static func _wire_input(sim: Simulation, m: Machine, port: String, cell: Vector2i) -> void:
	var src := sim.place("input", cell, 0, {}, m.width)
	sim.connect_ports(src.id, "out", m.id, port)


## Compare with B unwired: B is tied to k.
static func _compare_unwired(t) -> void:
	var sim := _sim()
	var m := sim.place("compare", Vector2i(2, 2), 0, {"op": ">", "k": 3}, 3)
	_feed(sim, m, "in", "101", 0)
	var p := _run_until_out(sim, m)
	t.check(p != null and p.data.equals(BitVector.from_bin("1")), "compare B unwired: 101 > 3 -> 1 (got %s)" % str(p.data if p != null else "-"))
	m.pop_output("out")
	_feed(sim, m, "in", "010", 1)
	var p2 := _run_until_out(sim, m)
	t.check(p2 != null and p2.data.equals(BitVector.from_bin("0")), "compare B unwired: 010 > 3 -> 0 (got %s)" % str(p2.data if p2 != null else "-"))


## Compare with B wired: it waits for both inputs of the record.
static func _compare_wired(t) -> void:
	var sim := _sim()
	var m := sim.place("compare", Vector2i(2, 2), 0, {"op": "<"}, 3)
	_wire_input(sim, m, "b", Vector2i(2, 6))
	_feed(sim, m, "in", "101", 0)
	_feed(sim, m, "b", "110", 0)
	var p := _run_until_out(sim, m)
	t.check(p != null and p.data.equals(BitVector.from_bin("1")) and p.ctx == 0, "compare B wired: 101 < 110 -> 1 ctx 0 (got %s)" % str(p.data if p != null else "-"))


## Compare FIFO with one waiting port (B tied): the queue is taken in arrival order.
static func _compare_fifo(t) -> void:
	var sim := _sim()
	var m := sim.place("compare", Vector2i(2, 2), 0, {"op": ">", "k": 0}, 3)
	_feed(sim, m, "in", "001", 5)
	_feed(sim, m, "in", "010", 2)
	var p := _run_until_out(sim, m)
	t.check(p != null and p.ctx == 5, "compare FIFO: the first waiting value (ctx 5) is taken first (got ctx %d)" % (p.ctx if p != null else -99))


## AND with B unwired reads Tie B (k).
static func _and_tie(t) -> void:
	var sim := _sim()
	var m := sim.place("and_gate", Vector2i(2, 2), 0, {"k": 6}, 3)
	_feed(sim, m, "a", "011", 0)
	var p := _run_until_out(sim, m)
	t.check(p != null and p.data.equals(BitVector.from_bin("010")), "AND B unwired k=6: 011 & 110 = 010 (got %s)" % str(p.data if p != null else "-"))


## XOR with B wired waits for both inputs.
static func _xor_wired(t) -> void:
	var sim := _sim()
	var m := sim.place("xor_gate", Vector2i(2, 2), 0, {}, 3)
	_wire_input(sim, m, "b", Vector2i(2, 6))
	_feed(sim, m, "a", "101", 0)
	_feed(sim, m, "b", "011", 0)
	var p := _run_until_out(sim, m)
	t.check(p != null and p.data.equals(BitVector.from_bin("110")), "XOR B wired: 101 ^ 011 = 110 (got %s)" % str(p.data if p != null else "-"))


## Selector take both (default): consumes SEL and both inputs of one record.
static func _selector_both(t) -> void:
	var sim := _sim()
	var m := sim.place("mux", Vector2i(2, 2), 0, {}, 3)
	_wire_input(sim, m, "a", Vector2i(2, 6))
	_wire_input(sim, m, "b", Vector2i(2, 8))
	_feed(sim, m, "a", "001", 0)
	_feed(sim, m, "b", "110", 0)
	_feed(sim, m, "sel", "1", 0)
	var p := _run_until_out(sim, m)
	t.check(p != null and p.data.equals(BitVector.from_bin("110")) and p.ctx == 0, "selector take both: sel 1 picks B=110 ctx 0 (got %s)" % str(p.data if p != null else "-"))
	t.check(m.inq["a"].is_empty() and m.inq["b"].is_empty(), "selector take both consumes A and B")


## Selector take both, A wired, B unwired: B reads its tie param.
static func _selector_both_tied(t) -> void:
	var sim := _sim()
	var m := sim.place("mux", Vector2i(2, 2), 0, {"b": 0}, 3)
	_wire_input(sim, m, "a", Vector2i(2, 6))
	_feed(sim, m, "a", "101", 2)
	_feed(sim, m, "sel", "1", 2)
	var p := _run_until_out(sim, m)
	t.check(p != null and p.data.equals(BitVector.of(0, 3)), "selector take both, B unwired b=0: sel 1 picks B=000 (got %s)" % str(p.data if p != null else "-"))
	m.pop_output("out")
	_feed(sim, m, "a", "101", 3)
	_feed(sim, m, "sel", "0", 3)
	var p2 := _run_until_out(sim, m)
	t.check(p2 != null and p2.data.equals(BitVector.from_bin("101")), "selector take both, B unwired: sel 0 picks A=101 (got %s)" % str(p2.data if p2 != null else "-"))


## Selector take chosen, B unwired: consumes only the chosen input (a tie value here).
static func _selector_chosen_tied(t) -> void:
	var sim := _sim()
	var m := sim.place("mux", Vector2i(2, 2), 0, {"take": "chosen", "b": 5}, 3)
	_wire_input(sim, m, "a", Vector2i(2, 6))
	_feed(sim, m, "a", "111", 4)
	_feed(sim, m, "sel", "1", 4)
	var p := _run_until_out(sim, m)
	t.check(p != null and p.data.equals(BitVector.from_bin("101")) and p.ctx == 4, "selector take chosen, B unwired b=5: sel 1 emits 101 ctx 4 (got %s)" % str(p.data if p != null else "-"))
	t.check(m.inq["a"].size() == 1, "selector take chosen leaves A untouched")


## Migration: old mux saves get take=chosen; fresh selectors default to take=both.
static func _migration(t) -> void:
	var sim := _sim()
	sim.load_player_layout({"machines": [{"type": "mux", "cell": [2, 2], "rot": 0, "params": {}, "width": 3}], "connections": []})
	var m: Machine = null
	for id in sim.machines:
		m = sim.machines[id]
	t.check(m != null and str(m.params.get("take", "")) == "chosen", "migration: an old mux save gets take=chosen (got %s)" % str(m.params.get("take", "?") if m != null else "no machine"))
	var sim2 := _sim()
	var m2 := sim2.place("mux", Vector2i(2, 2), 0, {}, 3)
	t.check(str(m2.params.get("take", "")) == "both", "a fresh selector defaults to take=both (got %s)" % str(m2.params.get("take", "?")))


static func _catalog_checks(t) -> void:
	t.check(Catalog.def("not_gate")["name"] == "Inverter", "not_gate is named Inverter (got %s)" % Catalog.def("not_gate")["name"])
	t.check(Catalog.default_params("delay")["ticks"] == 1, "delay defaults to 1 tick (got %s)" % str(Catalog.default_params("delay")["ticks"]))
	t.check(Catalog.port_def("latch", "in")["tie"] == "d", "latch in port ties to d (got %s)" % str(Catalog.port_def("latch", "in").get("tie", "")))
	t.check(Catalog.port_def("compare", "b")["tie"] == "k", "compare b port ties to k (got %s)" % str(Catalog.port_def("compare", "b").get("tie", "")))