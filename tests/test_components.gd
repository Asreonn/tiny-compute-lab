class_name ComponentTests
extends RefCounted
## Group G acceptance tests (docs/SYSTEMS_EXPANSION.md §11): the behaviour of each new component
## through the real Simulation phases, with hand-fed packets.


static func run(t) -> void:
	_adder(t)
	_mux(t)
	_cond_router(t)
	_if_bit(t)


static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	return sim


static func _feed(sim: Simulation, m: Machine, port: String, bin: String, origin := {}) -> Packet:
	var p := Packet.new(sim.new_packet_id(), BitVector.from_bin(bin), sim.tick)
	p.origins = origin
	m.inq[port].append(p)
	return p


## Steps until `m` has something in `port`'s output slot (or `limit` steps pass).
static func _run_until_out(sim: Simulation, m: Machine, limit := 20) -> Dictionary:
	for i in limit:
		sim.step()
		for port in m.outq:
			if m.outq[port] != null:
				return {"port": port, "packet": m.outq[port]}
	return {}


static func _adder(t) -> void:
	var sim := _sim()
	var a := sim.place("adder", Vector2i(2, 2), 0, {}, 5)
	_feed(sim, a, "a", "00110", {1: {"seq": 3, "value": RawValue.text("G")}})
	var out := _run_until_out(sim, a, 8)
	t.check(out.is_empty(), "the Adder waits for both inputs")
	_feed(sim, a, "b", "00101", {2: {"seq": 3, "value": RawValue.key(5)}})
	out = _run_until_out(sim, a)
	var p: Packet = out.get("packet")
	t.check(p != null and p.data.equals(BitVector.from_bin("01011")), "6 + 5 = 11 at 5 bits")
	t.check(p != null and p.origins.has(1) and p.origins.has(2), "the sum carries both lineages")
	var sim2 := _sim()
	var a2 := sim2.place("adder", Vector2i(2, 2), 0, {}, 3)
	_feed(sim2, a2, "a", "110")
	_feed(sim2, a2, "b", "011")
	var p2: Packet = _run_until_out(sim2, a2).get("packet")
	t.check(p2 != null and p2.data.equals(BitVector.from_bin("001")) and a2.last_carry == 1, "6 + 3 wraps to 1 at 3 bits and flags the carry")


static func _mux(t) -> void:
	var sim := _sim()
	var m := sim.place("mux", Vector2i(2, 2), 0, {}, 3)
	_feed(sim, m, "a", "001")
	_feed(sim, m, "b", "110")
	_feed(sim, m, "sel", "1")
	var o := _run_until_out(sim, m)
	t.check(o.get("port") == "out" and (o["packet"] as Packet).data.equals(BitVector.from_bin("110")), "select 1 takes B")
	t.check(m.inq["a"].size() == 1, "the unselected input waits")
	var sim2 := _sim()
	var m2 := sim2.place("mux", Vector2i(2, 2), 0, {}, 3)
	_feed(sim2, m2, "sel", "0")
	t.check(_run_until_out(sim2, m2, 6).is_empty(), "no value on the selected input: nothing moves")


static func _cond_router(t) -> void:
	var cases := [[">", 3, "101", "a"], [">", 5, "101", "b"], ["<", 2, "001", "a"], ["=", 4, "100", "a"], ["bit", 4, "10011", "a"], ["bit", 4, "01011", "b"]]
	for c in cases:
		var sim := _sim()
		var w: int = (c[2] as String).length()
		var r := sim.place("cond_router", Vector2i(2, 2), 0, {"op": c[0], "k": c[1]}, w)
		_feed(sim, r, "in", c[2])
		var o := _run_until_out(sim, r)
		t.check(o.get("port", "") == c[3], "router %s %d on %s goes to %s (got %s)" % [c[0], c[1], c[2], c[3], o.get("port", "-")])


static func _if_bit(t) -> void:
	var c := Contract.from_level(LabDef.level(13))
	t.check(c.expect_from(BitVector.from_bin("10011")) is BitVector and (c.expect_from(BitVector.from_bin("10011")) as BitVector).equals(BitVector.from_bin("100")), "tag set: payload 011 + 1 = 100")
	t.check((c.expect_from(BitVector.from_bin("00101")) as BitVector).equals(BitVector.from_bin("010")), "tag clear: payload 101 × 2 = 010 (wraps)")
	t.check(c.describe() == "by tag: b4 ? x+1 : x×2", "describe: %s" % c.describe())
