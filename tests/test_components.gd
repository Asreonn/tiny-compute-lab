class_name ComponentTests
extends RefCounted
## Group G acceptance tests (docs/SYSTEMS_EXPANSION.md §11): the behaviour of each new component
## through the real Simulation phases, with hand-fed packets.


static func run(t) -> void:
	_adder(t)
	_mux(t)
	_cond_router(t)
	_if_bit(t)
	_width_converters(t)
	_gates(t)
	_combiner(t)
	_register(t)
	_memory(t)
	_rom_alu_pc_decoder(t)
	_history_contracts(t)


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


static func _width_converters(t) -> void:
	var cases := [["zero_extend", 3, 5, "101", "00101"], ["sign_extend", 3, 5, "101", "11101"], ["sign_extend", 3, 5, "011", "00011"], ["truncate", 5, 3, "10110", "110"]]
	for c in cases:
		var sim := _sim()
		var m := sim.place(c[0], Vector2i(2, 2), 0, {"to": c[2]}, c[1])
		t.check(m.port_width("out") == c[2], "%s: the output port is %d bits" % [c[0], c[2]])
		_feed(sim, m, "in", c[3])
		var p: Packet = _run_until_out(sim, m).get("packet")
		t.check(p != null and p.data.equals(BitVector.from_bin(c[4])), "%s %s → %s (got %s)" % [c[0], c[3], c[4], str(p.data) if p != null else "-"])
	var sim2 := _sim()
	var bad := sim2.place("zero_extend", Vector2i(2, 2), 0, {"to": 2}, 5)
	_feed(sim2, bad, "in", "10101")
	for i in 4:
		sim2.step()
	t.check(bad.state == Machine.State.ERROR and bad.error_text != "", "extending to fewer bits is a configuration error (%s)" % bad.error_text)


static func _gates(t) -> void:
	for c in [["and_gate", "11001100", "10101010", "10001000"], ["or_gate", "11001100", "10101010", "11101110"], ["xor_gate", "11001100", "10101010", "01100110"]]:
		var sim := _sim()
		var g := sim.place(c[0], Vector2i(2, 2), 0, {}, 8)
		_feed(sim, g, "a", c[1], {1: {"seq": 0, "value": RawValue.text("h")}})
		_feed(sim, g, "b", c[2], {2: {"seq": 0, "value": RawValue.key(223)}})
		var p: Packet = _run_until_out(sim, g).get("packet")
		t.check(p != null and p.data.equals(BitVector.from_bin(c[3])) and p.origins.size() == 2, "%s %s %s = %s with both lineages" % [c[0], c[1], c[2], c[3]])
	var sim2 := _sim()
	var n := sim2.place("not_gate", Vector2i(2, 2), 0, {}, 4)
	_feed(sim2, n, "in", "1010")
	var pn: Packet = _run_until_out(sim2, n).get("packet")
	t.check(pn != null and pn.data.equals(BitVector.from_bin("0101")), "NOT 1010 = 0101")
	# 'h' (0x68) AND 0xDF = 'H' (0x48)
	var h := Charset.encode("h", 8)
	t.check(Charset.decode(h.band(BitVector.of(223, 8))) == "H", "ASCII: h AND 0xDF = H")


static func _combiner(t) -> void:
	var sim := _sim()
	var c := sim.place("bus_combiner", Vector2i(2, 2), 0, {"lo": 3}, 5)
	t.check(c.port_width("hi") == 2 and c.port_width("lo") == 3 and c.port_width("out") == 5, "a 5-bit combiner takes 2 high + 3 low bits")
	_feed(sim, c, "lo", "011")
	t.check(_run_until_out(sim, c, 6).is_empty(), "the combiner waits for both parts")
	_feed(sim, c, "hi", "10")
	var p: Packet = _run_until_out(sim, c).get("packet")
	t.check(p != null and p.data.equals(BitVector.from_bin("10011")), "hi 10 : lo 011 = 10011")


static func _outs(sim: Simulation, m: Machine, ticks: int) -> Array:
	var got := []
	for i in ticks:
		sim.step()
		if m.outq.get("out") != null:
			got.append((m.outq["out"] as Packet).data.unsigned())
			m.outq["out"] = null  # nothing wired: collect by hand
	return got


static func _register(t) -> void:
	var sim := _sim()
	var r := sim.place("register", Vector2i(2, 2), 0, {"mode": "echo", "init": 5}, 4)
	var first := _outs(sim, r, 4)
	t.check(first == [5], "an echo register seeds its loop with the initial value (%s)" % str(first))
	_feed(sim, r, "in", "0011")
	t.check(_outs(sim, r, 4) == [3], "an echo register passes each write on")
	var sim2 := _sim()
	var h := sim2.place("register", Vector2i(2, 2), 0, {"mode": "on read", "init": 0}, 4)
	_feed(sim2, h, "in", "1001")
	t.check(_outs(sim2, h, 6).is_empty(), "an on-read register keeps writes to itself")
	_feed(sim2, h, "read", "1")
	_feed(sim2, h, "read", "1")
	var reads := _outs(sim2, h, 12)
	t.check(reads == [9, 9], "every READ pulse sends the stored value again (%s)" % str(reads))


static func _memory(t) -> void:
	var sim := _sim()
	var ram := sim.place("ram", Vector2i(2, 2), 0, {}, 3)
	# write 5 to cell 9, then read cell 9 and cell 2
	for op in [["1001", "101", "1"], ["1001", "000", "0"], ["0010", "000", "0"]]:
		_feed(sim, ram, "a", op[0])
		_feed(sim, ram, "d", op[1])
		_feed(sim, ram, "we", op[2])
	var got := _outs(sim, ram, 20)
	t.check(got == [5, 0], "RAM: a write stores, reads return the cell (unwritten = 0) (%s)" % str(got))
	var bank := sim.place("register_bank", Vector2i(2, 6), 0, {}, 4)
	t.check(bank.port_width("a") == 2 and ram.port_width("a") == 4, "the bank takes 2-bit addresses, RAM 4-bit")


static func _rom_alu_pc_decoder(t) -> void:
	var sim := _sim()
	var rom := sim.place("rom", Vector2i(2, 2), 0, {"table": "6 4 7 1", "out": 3}, 2)
	for a in ["00", "10", "11"]:
		_feed(sim, rom, "in", a)
	t.check(_outs(sim, rom, 16) == [6, 7, 1], "ROM looks the address up in its table")
	t.check(MemoryLogicProbe.parse("6, 4,x 7") == [6, 4, 0, 7], "the table text accepts commas; junk reads as 0")
	var alu := sim.place("alu", Vector2i(2, 6), 0, {"op0": "ADD", "op1": "SUB"}, 5)
	for c in [["00111", "00010", "0"], ["00111", "00010", "1"]]:
		_feed(sim, alu, "a", c[0])
		_feed(sim, alu, "b", c[1])
		_feed(sim, alu, "op", c[2])
	t.check(_outs(sim, alu, 20) == [9, 5], "ALU: OP 0 adds, OP 1 subtracts")
	var pc := sim.place("program_counter", Vector2i(8, 2), 0, {"start": 6}, 3)
	for i in 3:
		_feed(sim, pc, "in", "1")
	t.check(_outs(sim, pc, 16) == [6, 7, 0], "the program counter counts from its start and wraps")
	var dec := sim.place("instruction_decoder", Vector2i(10, 6), 0, {}, 8)
	t.check(dec.port_width("a") == 1 and dec.port_width("b") == 1, "the decoder's outputs are 1-bit control lines")


static func _history_contracts(t) -> void:
	var sum := Contract.from_level(LabDef.level(21))
	var vals := [2, 5, 7, 0, 3, 6, 1, 4]  # WORDS_3
	var run := 0
	var ok := true
	for s in 20:
		run += vals[s % 8]
		var p := Packet.new(1, BitVector.of(0, 5), 0)
		p.origins = {1: {"seq": s, "value": BitVector.of(vals[s % 8], 3)}}
		var e: Variant = sum.expected_for(p, [1])
		ok = ok and e is BitVector and (e as BitVector).unsigned() == run % 32
	t.check(ok, "prefix_sum expects the running total mod 32 at every seq")
	# ram_program against a brute-force run of the same program
	var ram := Contract.from_level(LabDef.level(24))
	var prog: Array = ram.stream
	var mem := {}
	var ok2 := true
	for s in 30:
		var w: int = (prog[s % prog.size()] as BitVector).unsigned()
		var addr := (w >> 3) & 15
		var p2 := Packet.new(1, BitVector.of(0, 3), 0)
		p2.origins = {1: {"seq": s, "value": prog[s % prog.size()]}}
		var e2: Variant = ram.expected_for(p2, [1])
		if (w >> 7) & 1 == 1:
			ok2 = ok2 and e2 is String
			mem[addr] = w & 7
		else:
			ok2 = ok2 and e2 is BitVector and (e2 as BitVector).unsigned() == int(mem.get(addr, 0))
	t.check(ok2, "ram_program matches a brute-force run over three cycles")
	var play := Contract.from_level(LabDef.level(25))
	var p3 := Packet.new(1, BitVector.of(0, 4), 0)
	p3.origins = {1: {"seq": 10, "value": BitVector.of(1, 1)}}
	t.check((play.expected_for(p3, [1]) as BitVector).unsigned() == 8, "seq_table: pulse 10 plays note 10 % 8 = 2 → 8")

