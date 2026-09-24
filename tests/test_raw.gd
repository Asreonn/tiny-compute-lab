class_name RawTests
extends RefCounted
## Slice D1 acceptance tests: the raw boundary (RawValue), per-socket packet lineage and the
## Number/Character Encoder + Decoder logic. Each case calls t.check(cond, what);
## run() is invoked from tests/run_tests.gd.

static func run(t) -> void:
	_raw_value(t)
	_packet(t)
	_sources(t)
	_connect_error(t)
	_number_encoder(t)
	_char_encoder(t)
	_decoders(t)
	_full_chain(t)
	_gate_lineage(t)


# --- RawValue ------------------------------------------------------------------

static func _raw_value(t) -> void:
	var a := RawValue.text("H")
	t.check(a.equals(RawValue.text("H")), "RawValue.text equal values compare equal")
	t.check(not a.equals(RawValue.text("K")), "RawValue.text different chars differ")
	t.check(not a.equals(RawValue.number(72)), "RawValue.equals requires the same kind")
	t.check(a.glyph() == "H" and a.kind_name() == "TEXT", "TEXT glyph is the char, kind_name is TEXT")
	var n := RawValue.number(42)
	t.check(n.glyph() == "42" and n.kind_name() == "NUMBER", "NUMBER glyph is the digits, kind_name is NUMBER")
	t.check(RawValue.key(3).kind == RawValue.Kind.KEY, "key() sets Kind.KEY")
	t.check(RawValue.sensor(7).kind == RawValue.Kind.SENSOR, "sensor() sets Kind.SENSOR")
	t.check(RawValue.number(1).equals(RawValue.number(1)), "NUMBER equality")
	t.check(not RawValue.key(1).equals(RawValue.sensor(1)), "KEY 1 and SENSOR 1 differ (kind matters)")
	t.check(a._to_string() == "TEXT(H)", "RawValue._to_string is kind(glyph)")


# --- Packet / lineage -----------------------------------------------------------

static func _packet(t) -> void:
	var r := RawValue.text("H")
	var p := Packet.make_raw(1, r, 5)
	t.check(p.is_raw(), "make_raw produces a raw packet")
	t.check(p.data == null, "a raw packet carries no BitVector")
	t.check(p.raw == r, "a raw packet keeps its RawValue")
	t.check(p.label() == "H", "a raw packet labels as its glyph")
	t.check(not Packet.new(2, BitVector.of(5, 3), 0).is_raw(), "a bit packet is not raw")

	p.origins[7] = {"seq": 0, "value": r}
	var d := p.derive_raw(2, RawValue.number(9))
	t.check(d.is_raw() and d.raw.glyph() == "9", "derive_raw makes a raw packet with the new value")
	t.check(d.origins.has(7) and d.origins[7]["seq"] == 0, "derive_raw copies origins")
	t.check(d.origins[7]["value"] == r, "derive_raw keeps the origin value")
	d.origins[7]["seq"] = 99
	t.check(p.origins[7]["seq"] == 0, "derive_raw copies origin dicts (no aliasing)")

	var b := p.derive(3, BitVector.of(1, 3))
	t.check(not b.is_raw() and b.data.unsigned() == 1, "derive makes a bit packet (raw stays null)")
	t.check(b.origins.has(7) and b.origins[7]["seq"] == 0, "derive copies origins")

	var other := Packet.new(4, BitVector.of(0, 3), 0)
	other.origins[9] = {"seq": 2, "value": RawValue.key(1)}
	other.origins[7] = {"seq": 5, "value": RawValue.key(2)}
	b.merge_origins(other)
	t.check(b.origins.has(9) and b.origins.size() == 2, "merge_origins adds missing keys")
	t.check(b.origins[7]["seq"] == 5, "merge_origins keeps the newer entry (higher seq) on conflict")
	var older := Packet.new(5, BitVector.of(0, 3), 0)
	older.origins[7] = {"seq": 1, "value": RawValue.key(3)}
	b.merge_origins(older)
	t.check(b.origins[7]["seq"] == 5, "…and never replaces it with an older one")


# --- Sources stamp lineage -------------------------------------------------------

static func _sources(t) -> void:
	var sim := Simulation.new()
	var src := sim.place("usb_input", Vector2i(0, 0), 0, {}, 3)
	src.stream = [RawValue.text("H"), RawValue.text("K")]
	src.interval = 1
	var sink := sim.place("usb_output", Vector2i(2, 0), 0, {}, 1)
	t.check(sim.connect_ports(src.id, "out", sink.id, "in") != null, "a raw source connects to a * sink")
	sim.reset_run()
	for i in 20:
		sim.step()
	t.check(sink.received.size() >= 2, "the raw source delivered its whole stream")
	if sink.received.size() >= 2:
		var p0: Packet = sink.received[0]
		var p1: Packet = sink.received[1]
		t.check(p0.is_raw() and p0.raw.glyph() == "H", "first raw packet is TEXT H")
		t.check(p0.origins.has(src.id) and p0.origins[src.id]["seq"] == 0, "first raw packet origin seq 0")
		t.check(p0.origins[src.id]["value"] is RawValue and (p0.origins[src.id]["value"] as RawValue).equals(RawValue.text("H")), "first raw packet origin value is H")
		t.check(p1.is_raw() and p1.origins[src.id]["seq"] == 1, "second raw packet origin seq 1")

	# A BitVector source is unchanged: same packet kind, data and origin stamp.
	var bsim := Simulation.new()
	var bsrc := bsim.place("usb_input", Vector2i(0, 0), 0, {}, 3)
	bsrc.stream = [BitVector.of(5, 3)]
	bsim.step()
	var bp: Packet = bsrc.outq["out"]
	t.check(bp != null and not bp.is_raw() and bp.data.equals(BitVector.of(5, 3)), "a bit source still emits its BitVector")
	t.check(bp.origins.has(bsrc.id) and bp.origins[bsrc.id]["seq"] == 0, "a bit source stamps its origin")
	t.check(bp.origins[bsrc.id]["value"] is BitVector, "a bit source origin value is a BitVector")

	# a1_plus_two must run exactly as before: same tick count and identical event log.
	var a := _run_a1()
	var b := _run_a1()
	t.check(a["pass"] and b["pass"], "a1_plus_two still passes with reference solution")
	t.check(a["ticks"] == 26, "a1_plus_two still resolves at tick 26 (source timing unchanged)")
	t.check(a["ticks"] == b["ticks"] and a["outputs"] == b["outputs"] and a["log"] == b["log"], "bit sources still produce identical runs")


static func _run_a1() -> Dictionary:
	var sim := Simulation.new()
	var run := MissionRun.new(Missions.by_id("a1_plus_two"))
	run.build_board(sim)
	Solutions.build(sim, "a1_plus_two")
	sim.reset_run()
	var log := PackedStringArray()
	while run.status == MissionRun.Status.RUNNING and sim.tick < 2000:
		sim.step()
		for e in sim.events:
			log.append("%d:%s" % [sim.tick, str(e)])
	return {"ticks": sim.tick, "outputs": sim.outputs_total, "pass": run.status == MissionRun.Status.PASS, "log": log}


# --- connect_error --------------------------------------------------------------

static func _connect_error(t) -> void:
	var sim := Simulation.new()
	var enc := sim.place("number_encoder", Vector2i(2, 0), 0, {}, 3)
	var add := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	var sink := sim.place("usb_output", Vector2i(2, 4), 0, {}, 1)
	var raw_src := sim.place("usb_input", Vector2i(0, 0), 0, {}, 3)
	raw_src.stream = [RawValue.number(5)]
	var bit_src := sim.place("usb_input", Vector2i(0, 2), 0, {}, 3)
	bit_src.stream = [BitVector.of(5, 3)]
	var dec := sim.place("number_decoder", Vector2i(0, 4), 0, {}, 3)

	t.check(sim.connect_error(dec.id, "out", add.id, "in") == "Raw data must be encoded first", "raw out -> 3-bit in says encode first")
	t.check(sim.connect_error(bit_src.id, "out", enc.id, "in") == "This input needs raw data (from a Decoder or USB module)", "3-bit out -> encoder in asks for raw data")
	t.check(sim.connect_error(raw_src.id, "out", enc.id, "in") == "", "a raw source connects to an encoder raw input")
	t.check(sim.connect_error(dec.id, "out", enc.id, "in") == "", "raw out -> raw in is allowed")
	t.check(sim.connect_error(dec.id, "out", sink.id, "in") == "", "raw out -> * sink is allowed")
	t.check(sim.connect_error(bit_src.id, "out", sink.id, "in") == "", "* sink still accepts bits")
	t.check(sim.connect_ports(raw_src.id, "out", enc.id, "in") != null, "the raw source -> encoder wire commits")


# --- Encoders -------------------------------------------------------------------

static func _number_encoder(t) -> void:
	var r5 := _raw_to_bits("number_encoder", 3, RawValue.number(5))
	t.check(_got_bits(r5).equals(BitVector.from_bin("101")), "number_encoder 5 -> 3-bit 101")
	t.check(int(r5["codec"].last_carry) == 0, "number_encoder 5 has no overflow")

	var r9 := _raw_to_bits("number_encoder", 3, RawValue.number(9))
	t.check(_got_bits(r9).equals(BitVector.from_bin("001")), "number_encoder 9 -> 3-bit 001 (masked)")
	t.check(int(r9["codec"].last_carry) == 1, "number_encoder 9 sets the overflow LED")

	var rk := _raw_to_bits("number_encoder", 3, RawValue.key(3))
	t.check(_got_bits(rk).equals(BitVector.from_bin("011")), "number_encoder accepts a raw KEY")
	t.check(int(rk["codec"].last_carry) == 0, "KEY 3 has no overflow")

	var rt := _raw_to_bits("number_encoder", 3, RawValue.text("H"))
	t.check(rt["sink"].received.is_empty() and int(rt["codec"].dropped) == 1, "a TEXT value on a number encoder is dropped")


static func _char_encoder(t) -> void:
	var h := _raw_to_bits("char_encoder", 5, RawValue.text("H"))
	t.check(_got_bits(h).equals(BitVector.from_bin("00111")), "char_encoder 5-bit H -> 00111")

	var lower := _raw_to_bits("char_encoder", 5, RawValue.text("a"))
	t.check(lower["sink"].received.is_empty(), "5-bit lowercase 'a' produces no output")
	t.check(int(lower["codec"].dropped) == 1, "5-bit lowercase 'a' is counted as dropped")

	var ascii := _raw_to_bits("char_encoder", 8, RawValue.text("a"))
	t.check(_got_bits(ascii).equals(BitVector.from_bin("01100001")), "8-bit char_encoder 'a' -> 01100001")


# --- Decoders -------------------------------------------------------------------

static func _decoders(t) -> void:
	var n := _bits_to_raw("number_decoder", 3, BitVector.from_bin("101"), {})
	var np: Packet = n["sink"].received[0]
	t.check(np.is_raw() and np.raw.kind == RawValue.Kind.NUMBER and int(np.raw.value) == 5, "number_decoder 101 -> raw NUMBER 5")

	var s := _bits_to_raw("number_decoder", 3, BitVector.from_bin("111"), {"signed": "Signed"})
	var sp: Packet = s["sink"].received[0]
	t.check(sp.is_raw() and int(sp.raw.value) == -1, "signed number_decoder 111 -> raw NUMBER -1")

	var c := _bits_to_raw("char_decoder", 5, BitVector.from_bin("01010"), {})
	var cp: Packet = c["sink"].received[0]
	t.check(cp.is_raw() and cp.raw.kind == RawValue.Kind.TEXT and str(cp.raw.value) == "K", "char_decoder 01010 -> raw TEXT K")


# --- End to end -----------------------------------------------------------------

static func _full_chain(t) -> void:
	var sim := Simulation.new()
	var src := sim.place("usb_input", Vector2i(0, 0), 0, {}, 5)
	src.stream = [RawValue.text("H")]
	var enc := sim.place("char_encoder", Vector2i(2, 0), 0, {}, 5)
	var add := sim.place("add", Vector2i(4, 0), 0, {"k": 3}, 5)
	var dec := sim.place("char_decoder", Vector2i(6, 0), 0, {}, 5)
	var sink := sim.place("usb_output", Vector2i(8, 0), 0, {}, 1)
	t.check(sim.connect_ports(src.id, "out", enc.id, "in") != null, "chain: raw source -> char_encoder")
	t.check(sim.connect_ports(enc.id, "out", add.id, "in") != null, "chain: char_encoder -> add")
	t.check(sim.connect_ports(add.id, "out", dec.id, "in") != null, "chain: add -> char_decoder")
	t.check(sim.connect_ports(dec.id, "out", sink.id, "in") != null, "chain: char_decoder -> * sink")
	sim.reset_run()
	for i in 40:
		sim.step()
		if not sink.received.is_empty():
			break
	t.check(not sink.received.is_empty(), "the full raw -> bits -> raw chain reaches the sink")
	if sink.received.is_empty():
		return
	var p: Packet = sink.received[0]
	t.check(p.is_raw() and p.raw.kind == RawValue.Kind.TEXT and p.raw.glyph() == "K", "chain output is raw TEXT K (H + 3 in TCL-5)")
	t.check(p.origins.has(src.id), "chain output carries the source origin")
	t.check(p.origins[src.id]["seq"] == 0, "chain origin seq is 0")
	t.check((p.origins[src.id]["value"] as RawValue).equals(RawValue.text("H")), "chain origin value is the source RawValue H")


static func _gate_lineage(t) -> void:
	var sim := Simulation.new()
	var data_src := sim.place("usb_input", Vector2i(0, 4), 0, {}, 3)
	data_src.stream = [BitVector.of(5, 3)]
	var ctrl_src := sim.place("usb_input", Vector2i(0, 2), 0, {}, 1)
	ctrl_src.stream = [BitVector.from_bool(true)]
	var gate := sim.place("gate", Vector2i(2, 4), 0, {}, 3)
	t.check(sim.connect_ports(data_src.id, "out", gate.id, "in") != null, "gate lineage: data source wired")
	t.check(sim.connect_ports(ctrl_src.id, "out", gate.id, "ctrl") != null, "gate lineage: control source wired")
	sim.reset_run()
	var out: Packet = null
	for i in 20:
		sim.step()
		if gate.outq["out"] != null:
			out = gate.outq["out"]
			break
	t.check(out != null, "the gate passed the data packet")
	if out == null:
		return
	t.check(out.origins.has(data_src.id) and out.origins.has(ctrl_src.id), "gate output carries both origin ids")
	t.check(out.origins[data_src.id]["seq"] == 0 and out.origins[ctrl_src.id]["seq"] == 0, "both origin seqs are 0")


# --- helpers --------------------------------------------------------------------

## Wire a raw source into a codec, its output into a "*" sink, and run until one arrives.
static func _raw_to_bits(type: String, width: int, value: RawValue) -> Dictionary:
	var sim := Simulation.new()
	var src := sim.place("usb_input", Vector2i(0, 0), 0, {}, 1)
	src.stream = [value]
	var codec := sim.place(type, Vector2i(2, 0), 0, {"width": width}, width)
	var sink := sim.place("usb_output", Vector2i(4, 0), 0, {}, 1)
	sim.connect_ports(src.id, "out", codec.id, "in")
	sim.connect_ports(codec.id, "out", sink.id, "in")
	sim.reset_run()
	for i in 30:
		sim.step()
		if not sink.received.is_empty():
			break
	return {"sim": sim, "codec": codec, "sink": sink}


## Wire a bit source into a decoder, its raw output into a "*" sink, and run until one arrives.
static func _bits_to_raw(type: String, width: int, value: BitVector, params: Dictionary) -> Dictionary:
	var sim := Simulation.new()
	var src := sim.place("usb_input", Vector2i(0, 0), 0, {}, width)
	src.stream = [value]
	var codec_params := params.duplicate()
	codec_params["width"] = width
	var codec := sim.place(type, Vector2i(2, 0), 0, codec_params, width)
	var sink := sim.place("usb_output", Vector2i(4, 0), 0, {}, 1)
	sim.connect_ports(src.id, "out", codec.id, "in")
	sim.connect_ports(codec.id, "out", sink.id, "in")
	sim.reset_run()
	for i in 30:
		sim.step()
		if not sink.received.is_empty():
			break
	return {"sim": sim, "codec": codec, "sink": sink}


static func _got_bits(r: Dictionary) -> BitVector:
	var sink: Machine = r["sink"]
	if sink.received.is_empty():
		return BitVector.zero(1)
	return (sink.received[0] as Packet).data
