class_name ContractTests
extends RefCounted
## Slice D3 acceptance tests: contracts + the Contract Drive + the L1–L11 lab table and the
## IO at the grid edges (docs/SYSTEMS_EXPANSION.md §2, §3, §10). Each case calls
## t.check(cond, what); run() is invoked from tests/run_tests.gd.

static func run(t) -> void:
	_ops(t)
	_judge(t)
	_describe(t)
	_lab_levels(t)
	_constraints(t)
	_drive_move(t)
	_paired(t)
	_l13_needs_buffer(t)
	_l20_multiplies_fail(t)
	_cpu(t)


# --- helpers --------------------------------------------------------------------

static func _map(ops: Array) -> Contract:
	var c := Contract.new()
	c.kind = "map"
	c.ops = ops
	return c


static func _bits(v: Variant, bv: BitVector) -> bool:
	return v is BitVector and (v as BitVector).equals(bv)


static func _raw(v: Variant, r: RawValue) -> bool:
	return v is RawValue and (v as RawValue).equals(r)


static func _drop(v: Variant) -> bool:
	return v is String and str(v) == Contract.DROP


static func _origin(v: Variant, seq := 0) -> Dictionary:
	return {7: {"seq": seq, "value": v}}


static func _pkt_bits(data: BitVector, origins := {}) -> Packet:
	var p := Packet.new(1, data, 0)
	p.origins = origins
	return p


static func _pkt_raw(r: RawValue, origins := {}) -> Packet:
	var p := Packet.make_raw(1, r, 0)
	p.origins = origins
	return p


static func _io(sim: Simulation) -> Dictionary:
	var socket := -1
	var drive := -1
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "usb_input" and m.cell.y == LabDef.PORT_ROWS[0]:
			socket = id
		elif m.type == "usb_output" and Devices.is_job(m.device):
			drive = id
	return {"socket": socket, "drive": drive}


# --- every op -------------------------------------------------------------------

static func _ops(t) -> void:
	t.check(_bits(_map([{"op": "add", "k": 3}]).expect_from(BitVector.from_bin("010")), BitVector.from_bin("101")), "add keeps the width (010 + 3 = 101)")
	t.check(_bits(_map([{"op": "sub", "k": 1}]).expect_from(BitVector.from_bin("010")), BitVector.from_bin("001")), "sub")
	t.check(_bits(_map([{"op": "mul", "k": 3}]).expect_from(BitVector.from_bin("010")), BitVector.from_bin("110")), "mul")
	t.check(_bits(_map([{"op": "mod", "k": 26}]).expect_from(BitVector.from_bin("11111")), BitVector.of(5, 5)), "mod (31 mod 26 = 5)")
	t.check(_bits(_map([{"op": "slice", "lo": 0, "len": 3}]).expect_from(BitVector.from_bin("10101")), BitVector.from_bin("101")), "slice keeps the low bits")
	t.check(_bits(_map([{"op": "encode_num", "width": 3}]).expect_from(RawValue.number(5)), BitVector.from_bin("101")), "encode_num masks to the width")
	t.check(_bits(_map([{"op": "encode_char", "width": 5}]).expect_from(RawValue.text("H")), Charset.encode("H", 5)), "encode_char uses the charset of the width")
	t.check(_drop(_map([{"op": "encode_char", "width": 5}]).expect_from(RawValue.text("a"))), "encode_char drops an unencodable char")
	t.check(_raw(_map([{"op": "decode_num"}]).expect_from(BitVector.from_bin("101")), RawValue.number(5)), "decode_num")
	t.check(_raw(_map([{"op": "decode_char"}]).expect_from(Charset.encode("K", 5)), RawValue.text("K")), "decode_char")
	t.check(_bits(_map([{"op": "keep_if", "cmp": ">", "k": 4}]).expect_from(BitVector.from_bin("110")), BitVector.from_bin("110")), "keep_if > keeps a 3-bit word above 4")
	t.check(_drop(_map([{"op": "keep_if", "cmp": ">", "k": 4}]).expect_from(BitVector.from_bin("010"))), "keep_if > drops a 3-bit word at or below 4")
	t.check(_raw(_map([{"op": "keep_if", "cmp": ">", "k": 4}]).expect_from(RawValue.sensor(6)), RawValue.sensor(6)), "keep_if > on a raw value")
	t.check(_raw(_map([{"op": "keep_if", "cmp": "<", "k": 4}]).expect_from(RawValue.number(2)), RawValue.number(2)), "keep_if <")
	t.check(_raw(_map([{"op": "keep_if", "cmp": "=", "k": 4}]).expect_from(RawValue.number(4)), RawValue.number(4)), "keep_if =")
	t.check(_drop(_map([{"op": "add", "k": 1}]).expect_from(RawValue.number(1))), "add on a raw value drops")
	t.check(_drop(_map([{"op": "decode_num"}]).expect_from(RawValue.number(1))), "decode on a raw value drops")
	t.check(_drop(_map([{"op": "encode_num", "width": 3}]).expect_from(BitVector.from_bin("010"))), "encode on bits drops")
	var caesar := _map([{"op": "encode_char", "width": 5}, {"op": "add", "k": 3}, {"op": "decode_char"}])
	t.check(_raw(caesar.expect_from(RawValue.text("H")), RawValue.text("K")), "chain: encode → add 3 → decode (H → K)")
	t.check(_drop(caesar.expect_from(RawValue.text("a"))), "chain drops an unencodable char")


# --- deliver / map / filter judging ---------------------------------------------

static func _judge(t) -> void:
	var dc := Contract.from_level({"contract": {"kind": "deliver", "value": "010", "count": 10}})
	t.check(dc.judge(_pkt_bits(BitVector.from_bin("010")), []), "deliver accepts the exact value")
	t.check(not dc.judge(_pkt_bits(BitVector.from_bin("011")), []), "deliver rejects a wrong value")
	t.check(not dc.judge(_pkt_bits(BitVector.from_bin("0100")), []), "deliver rejects a wrong width")
	t.check(not dc.judge(_pkt_raw(RawValue.text("A")), []), "deliver rejects a raw payload")
	t.check(dc.accept_width == 3, "a BIN deliver value fixes the accepted width")

	var mc := Contract.from_level({"contract": {"kind": "map", "ops": [{"op": "add", "k": 3}], "count": 5, "accept_format": "bits", "accept_width": 3}})
	t.check(mc.judge(_pkt_bits(BitVector.from_bin("101"), _origin(BitVector.from_bin("010"))), [7]), "map accepts origin + 3")
	t.check(not mc.judge(_pkt_bits(BitVector.from_bin("100"), _origin(BitVector.from_bin("010"))), [7]), "map rejects a wrong value")
	t.check(not mc.judge(_pkt_bits(BitVector.from_bin("101")), [7]), "map rejects a packet with no primary origin (null)")
	t.check(mc.expected_for(_pkt_bits(BitVector.from_bin("101")), [7]) == null, "expected_for is null without a primary origin")
	t.check(not mc.judge(_pkt_bits(BitVector.from_bin("10100"), _origin(BitVector.from_bin("010"))), [7]), "map rejects a wrong width")
	t.check(not mc.judge(_pkt_raw(RawValue.number(5), _origin(BitVector.from_bin("010"))), [7]), "map rejects a raw payload")

	var fc := Contract.from_level({"contract": {"kind": "filter", "ops": [{"op": "encode_num", "width": 3}, {"op": "keep_if", "cmp": ">", "k": 4}], "count": 3, "accept_format": "bits", "accept_width": 3}})
	t.check(fc.judge(_pkt_bits(BitVector.from_bin("110"), _origin(RawValue.sensor(6))), [7]), "filter accepts a kept value")
	t.check(_drop(fc.expected_for(_pkt_bits(BitVector.from_bin("010"), _origin(RawValue.sensor(2))), [7])), "filter says a low reading must not arrive (DROP)")
	t.check(not fc.judge(_pkt_bits(BitVector.from_bin("010"), _origin(RawValue.sensor(2))), [7]), "filter rejects a value that should have been dropped")

	# A text contract only accepts a raw TEXT payload.
	var tc := Contract.from_level({"contract": {"kind": "map", "ops": [{"op": "encode_char", "width": 5}, {"op": "add", "k": 3}, {"op": "decode_char"}], "count": 2, "accept_format": "text"}})
	t.check(tc.judge(_pkt_raw(RawValue.text("K"), _origin(RawValue.text("H"))), [7]), "text contract accepts the decoded char")
	t.check(not tc.judge(_pkt_bits(Charset.encode("K", 5), _origin(RawValue.text("H"))), [7]), "text contract rejects a bits payload")


# --- describe -------------------------------------------------------------------

static func _describe(t) -> void:
	t.check(Contract.from_level({"contract": {"kind": "deliver", "value": "010", "count": 20}}).describe() == "deliver 010 × 20", "deliver text")
	t.check(Contract.from_level({"contract": {"kind": "map", "ops": [{"op": "add", "k": 3}], "accept_format": "bits", "accept_width": 3}}).describe() == "map x → x + 3 (3-bit)", "map text")
	t.check(Contract.from_level({"contract": {"kind": "map", "ops": [{"op": "encode_char", "width": 5}, {"op": "add", "k": 3}, {"op": "decode_char"}], "accept_format": "text"}}).describe() == "Caesar +3 (text)", "Caesar text")
	t.check(Contract.from_level({"contract": {"kind": "filter", "ops": [{"op": "encode_num", "width": 3}, {"op": "keep_if", "cmp": ">", "k": 4}], "accept_format": "bits", "accept_width": 3}, "streams": {"sensor": {}}}).describe() == "keep sensor > 4", "filter text")


# --- the whole lab table --------------------------------------------------------

static func _lab_levels(t) -> void:
	t.check(LabDef.count() == 28, "the lab has 28 levels (got %d)" % LabDef.count())
	for idx in range(LabDef.count()):
		var sim := Simulation.new()
		var run := LabRun.new()
		run.level = idx
		run.build_board(sim)
		var io := _io(sim)
		t.check(io["socket"] >= 0 and sim.machines[io["socket"]].cell == LabDef.SOCKET_CELL, "L%d socket sits at column 0, row 1" % (idx + 1))
		t.check(io["drive"] >= 0 and sim.machines[io["drive"]].cell == LabDef.drive_cell(sim.size), "L%d drive sits at the east edge" % (idx + 1))
		Solutions.lab_solution(sim, idx)
		sim.reset_run()
		while run.level <= idx and sim.tick < 4000:
			sim.step()
		t.check(run.level > idx, "L%d reference solution completes (level %d, delivered %d, rejected %d, tick %d)" % [idx + 1, run.level, run.delivered, run.rejected, sim.tick])


# --- constraints are what make the naive solutions fail -------------------------

static func _constraints(t) -> void:
	# L10 (idx 9): a single Add without a Buffer loses burst values → max_lost 0 restarts the
	# window forever, so the level never completes.
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = 9
	run.build_board(sim)
	var io := _io(sim)
	sim.insert_device(io["socket"], "bit")
	# right next to the socket: a short wire + the 2-slot FIFO cannot absorb a 12-value burst
	var a := sim.place("add", Vector2i(3, LabDef.PORT_ROWS[0]), 0, {"k": 1}, 3)
	sim.connect_ports(io["socket"], "out", a.id, "in")
	sim.connect_ports(a.id, "out", io["drive"], "in")
	sim.reset_run()
	while run.level == 9 and sim.tick < 4000:
		sim.step()
	t.check(run.level == 9, "L10 without a Buffer never completes (level %d)" % run.level)

	# L11 (idx 10): a single Multiply (6 campaign ticks) is too slow for min_rate 4/s.
	var sim2 := Simulation.new()
	var run2 := LabRun.new()
	run2.level = 10
	run2.build_board(sim2)
	var io2 := _io(sim2)
	sim2.insert_device(io2["socket"], "bit")
	var m := sim2.place("multiply", Vector2i(6, 5), 0, {"k": 3}, 3)
	sim2.connect_ports(io2["socket"], "out", m.id, "in")
	sim2.connect_ports(m.id, "out", io2["drive"], "in")
	sim2.reset_run()
	while run2.level == 10 and sim2.tick < 4000:
		sim2.step()
	t.check(run2.level == 10, "L11 with one Multiply never completes (level %d, rate %.2f/s)" % [run2.level, run2.rate()])
	t.check(run2.rate() < 4.0, "one Multiply sustains less than 4 values/s (got %.2f)" % run2.rate())


# --- the drive follows the east edge --------------------------------------------

static func _drive_move(t) -> void:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.build_board(sim)
	var io := _io(sim)
	var drive: Machine = sim.machines[io["drive"]]
	t.check(drive.cell == Vector2i(26, 1), "L1 drive starts at (26, 1)")
	sim.connect_ports(io["socket"], "out", drive.id, "in")
	t.check(sim.connections.size() == 1, "the socket is wired to the drive")
	# Walk the levels up to L6, whose grow widens the board.
	for i in 5:
		run._advance(sim)
	t.check(run.level == 5, "five advances reach L6 (got %d)" % run.level)
	t.check(sim.size == Vector2i(32, 18), "L6 grows the board to 32x18 (got %s)" % sim.size)
	t.check(drive.cell == Vector2i(30, 1), "the drive moved to the new east edge (got %s)" % drive.cell)
	t.check(drive.locked, "the drive stays locked after the move")
	t.check(sim.connection_at_port(drive.id, "in") != null, "the incoming wire survived the move")
	t.check(sim.connections.size() == 1, "the move kept exactly one wire (got %d)" % sim.connections.size())


## L12 paired: text + key meet in step; a missing stream or a seq mismatch cannot be judged.
static func _paired(t) -> void:
	var c := Contract.from_level(LabDef.level(11))
	t.check(c.kind == "paired" and c.pair == ["text", "key"], "L12 is a paired text + key contract")
	var enc := Charset.encode("X", 5)
	# X (23) + key 5 = 28 → mod 26 = 2 → C
	var p := Packet.make_raw(1, RawValue.text("C"), 0)
	p.origins = {10: {"seq": 4, "value": RawValue.text("X")}, 11: {"seq": 4, "value": RawValue.key(5)}}
	t.check(c.judge(p, [10, 11]), "a letter shifted by its own key is accepted (X + 5 → C)")
	var off := Packet.make_raw(2, RawValue.text("C"), 0)
	off.origins = {10: {"seq": 4, "value": RawValue.text("X")}, 11: {"seq": 5, "value": RawValue.key(5)}}
	t.check(not c.judge(off, [10, 11]), "a letter that met another key (seq 4 vs 5) is rejected")
	var alone := Packet.make_raw(3, RawValue.text("C"), 0)
	alone.origins = {10: {"seq": 4, "value": RawValue.text("X")}}
	t.check(not c.judge(alone, [10, 11]), "a constant shift without the key stream is rejected")
	var swapped := Packet.make_raw(4, RawValue.text("C"), 0)
	swapped.origins = {11: {"seq": 7, "value": RawValue.text("X")}, 10: {"seq": 7, "value": RawValue.key(5)}}
	t.check(c.judge(swapped, [10, 11]), "the sticks may sit in either socket")
	t.check(enc != null and c.describe() == "Caesar + key (text)", "describe: %s" % c.describe())


## L13's demand is real: the L12 layout (no Buffer) loses letters in the bursts and never finishes.
static func _l13_needs_buffer(t) -> void:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = 12
	run.build_board(sim)
	Solutions.lab_solution(sim, 11)
	sim.reset_run()
	var lost := 0
	for i in 2000:
		sim.step()
		for e in sim.events:
			if str(e.get("kind", "")) == "lost":
				lost += 1
		if run.level > 12:
			break
	t.check(run.level == 12 and lost > 0, "L13 without a Buffer loses letters (%d) and does not complete" % lost)


## L20: two Multiplies fit the 6-power cap but cannot reach 4/s; the shift can.
static func _l20_multiplies_fail(t) -> void:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = 19
	run.build_board(sim)
	var io := _io(sim)
	sim.remove_device(io["socket"])
	sim.insert_device(io["socket"], "bit")
	var sp := sim.place("splitter", Vector2i(4, 2), 0, {}, 5)
	var m1 := sim.place("multiply", Vector2i(8, 1), 0, {"k": 4}, 5)
	var m2 := sim.place("multiply", Vector2i(8, 4), 0, {"k": 4}, 5)
	var mg := sim.place("merger", Vector2i(12, 2), 0, {}, 5)
	sim.connect_ports(io["socket"], "out", sp.id, "in")
	sim.connect_ports(sp.id, "a", m1.id, "in")
	sim.connect_ports(sp.id, "b", m2.id, "in")
	sim.connect_ports(m1.id, "out", mg.id, "a")
	sim.connect_ports(m2.id, "out", mg.id, "b")
	sim.connect_ports(mg.id, "out", io["drive"], "in")
	t.check(sim.power_demand() <= 6, "two Multiplies + routing fit the cap (%d)" % sim.power_demand())
	sim.reset_run()
	for i in 2000:
		sim.step()
	t.check(run.level == 19 and run.delivered >= 30 and run.rate() < 4.0, "…but make only %.1f/s: L20 stays open" % run.rate())


## L27 / L28: the accumulator trace, and OUT really has to gate the output.
static func _cpu(t) -> void:
	var c := Contract.from_level(LabDef.level(26))
	var want := [5, 17, 14, 34, 27, 28, 62, 7, 12]  # ADD 5, ADD 12, SUB 3, ADD 20, SUB 7, ADD 1, SUB 30, ADD 9, (again) ADD 5
	var got := []
	for s in want.size():
		var p := Packet.new(1, BitVector.of(0, 6), 0)
		p.origins = {1: {"seq": s, "value": BitVector.of(1, 1)}}
		got.append((c.expected_for(p, [1]) as BitVector).unsigned())
	t.check(got == want, "the CPU trace wraps at 6 bits and repeats the program (%s)" % str(got))
	var c2 := Contract.from_level(LabDef.level(27))
	var p2 := Packet.new(1, BitVector.of(0, 6), 0)
	p2.origins = {1: {"seq": 0, "value": BitVector.of(1, 1)}}
	t.check(c2.expected_for(p2, [1]) is String, "a non-OUT instruction must not reach the drive")
	p2.origins = {1: {"seq": 1, "value": BitVector.of(1, 1)}}
	t.check((c2.expected_for(p2, [1]) as BitVector).unsigned() == 13, "OUT after ADD 10, ADD 3 shows 13")
	# the ungated L27 CPU on the L28 board keeps restarting its window
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = 27
	run.build_board(sim)
	Solutions.lab_solution(sim, 26)
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "rom":
			m.params["table"] = "10 67 134 64 194 20 65 139"
	sim.reset_run()
	for i in 2500:
		sim.step()
	t.check(run.level == 27 and run.rejected > 0 and run.delivered < 12, "without the OUT gate L28 never completes (rejected %d, window %d)" % [run.rejected, run.delivered])

