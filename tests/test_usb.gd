class_name UsbTests
extends RefCounted
## Slice D2 acceptance tests: the USB socket, the data-module registry (Devices) and the
## 2-slot overrun FIFO (docs/SYSTEMS_EXPANSION.md §2). Each case calls t.check(cond, what);
## run() is invoked from tests/run_tests.gd.

static func run(t) -> void:
	_devices(t)
	_socket_emit(t)
	_overrun(t)
	_insert_remove(t)
	_save_roundtrip(t)
	_lab_streams(t)


# --- Device registry ------------------------------------------------------------

static func _devices(t) -> void:
	t.check(Devices.has("bit") and Devices.has("text") and Devices.has("number") and Devices.has("key") and Devices.has("sensor"), "every module kind is registered")
	t.check(not Devices.has("nope"), "an unknown kind is not registered")
	t.check(Devices.out_kind("bit") == "bits" and Devices.out_kind("text") == "raw", "bit emits bits, text emits raw")
	t.check(Devices.display_name("bit") == "Bit module" and Devices.display_name("sensor") == "Sensor module", "display names")
	t.check(Devices.out_kind("") == "bits", "no module keeps the normal data role")

	var bits := Devices.make_stream("bit", {"values": ["010"], "width": 3})
	t.check(bits.size() == 1 and bits[0] is BitVector and (bits[0] as BitVector).equals(BitVector.from_bin("010")), "bit stream: 010 -> a 3-bit BitVector")
	t.check((bits[0] as BitVector).width == 3, "bit stream keeps the declared width")
	var ch := Devices.make_stream("bit", {"values": ["H"], "width": 5})
	t.check(ch.size() == 1 and (ch[0] as BitVector).equals(Charset.encode("H", 5)), "bit stream: a single char is charset-encoded")

	var text := Devices.make_stream("text", {"values": ["HI"]})
	t.check(text.size() == 2, "text stream: \"HI\" -> 2 values")
	t.check(text[0] is RawValue and (text[0] as RawValue).kind == RawValue.Kind.TEXT and str((text[0] as RawValue).value) == "H", "text stream[0] is TEXT H")
	t.check(str((text[1] as RawValue).value) == "I", "text stream[1] is TEXT I")

	var num := Devices.make_stream("number", {"values": [5, 9]})
	t.check(num.size() == 2 and (num[0] as RawValue).kind == RawValue.Kind.NUMBER and int((num[0] as RawValue).value) == 5, "number stream carries NUMBER values")
	t.check((Devices.make_stream("key", {"values": [3]})[0] as RawValue).kind == RawValue.Kind.KEY, "key stream carries KEY values")
	t.check((Devices.make_stream("sensor", {"values": [7]})[0] as RawValue).kind == RawValue.Kind.SENSOR, "sensor stream carries SENSOR values")


# --- Socket emission ------------------------------------------------------------

static func _socket_emit(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	var src := sim.place("usb_input", Vector2i(1, 5), 0, {}, 3)
	src.socket = true
	t.check(sim.insert_device(src.id, "bit", {"values": ["010"], "width": 3, "interval": 4}), "the Bit module plugs into an unwired socket")
	t.check(src.device == "bit" and src.last_device == "bit" and src.width == 3, "the bit module sets the socket width")
	var out := sim.place("usb_output", Vector2i(9, 5), 0, {}, 1)
	t.check(sim.connect_ports(src.id, "out", out.id, "in") != null, "a bit socket wires to the USB Output")
	sim.reset_run()
	for i in 40:
		sim.step()
	t.check(out.received.size() >= 3, "the socket emitted at least 3 values (got %d)" % out.received.size())
	if out.received.size() < 3:
		return
	var p0: Packet = out.received[0]
	var p1: Packet = out.received[1]
	var p2: Packet = out.received[2]
	t.check(not p0.is_raw() and p0.data.equals(BitVector.from_bin("010")), "the first value is 010")
	t.check(p0.origins.has(src.id) and p0.origins[src.id]["seq"] == 0, "the first origin seq is 0")
	t.check(p1.origins[src.id]["seq"] == 1 and p2.origins[src.id]["seq"] == 2, "the origins advance 1, 2 …")
	t.check(p1.created_tick - p0.created_tick == 4, "the socket emits every 4 ticks (got %d)" % (p1.created_tick - p0.created_tick))


# --- Overrun --------------------------------------------------------------------

static func _overrun(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	var src := sim.place("usb_input", Vector2i(1, 5), 0, {}, 3)
	src.socket = true
	sim.insert_device(src.id, "bit", {"values": ["010"], "width": 3, "interval": 4})
	sim.reset_run()
	var max_fifo := 0
	for i in 33:
		sim.step()
		max_fifo = maxi(max_fifo, src.fifo.size())
	# Generations at ticks 1,5,…,33 = 9 values: 1 waits in the output slot, 2 fit the FIFO, so
	# the overrun rule drops the other 6 — one per extra value.
	t.check(src.lost == 6, "9 generated values with no wire drop 6 (got %d)" % src.lost)
	t.check(max_fifo <= 2, "the FIFO never exceeds 2 slots (got %d)" % max_fifo)
	t.check(src.outq["out"] != null, "the head value waits in the output slot")

	var out := sim.place("usb_output", Vector2i(9, 5), 0, {}, 1)
	t.check(sim.connect_ports(src.id, "out", out.id, "in") != null, "wiring the blocked socket succeeds")
	var lost_before := src.lost
	for i in 20:
		sim.step()
	t.check(out.received.size() >= 2, "emission resumes once the socket is unblocked (got %d)" % out.received.size())
	t.check(src.lost == lost_before, "a draining socket stops overrunning")


# --- Insert / remove ------------------------------------------------------------

static func _insert_remove(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	var src := sim.place("usb_input", Vector2i(1, 5), 0, {}, 3)
	src.socket = true
	t.check(sim.insert_device(src.id, "text", {"values": ["HI"], "interval": 2}), "a Text module plugs into an unwired socket")
	t.check(src.port_role("out") == Catalog.ROLE_RAW and src.port_width("out") == 0, "a raw module makes the socket output raw")
	t.check(src.device == "text" and src.last_device == "text", "the plugged module is recorded")
	t.check(not sim.insert_device(src.id, "nope"), "an unknown module kind is refused")
	t.check(not sim.insert_device(999, "bit"), "an unknown machine is refused")

	# A bit socket wired to an Add refuses a raw module: the wire would become incompatible.
	var sim2 := Simulation.new()
	sim2.size = Vector2i(20, 12)
	var s2 := sim2.place("usb_input", Vector2i(1, 5), 0, {}, 3)
	s2.socket = true
	t.check(sim2.insert_device(s2.id, "bit", {"values": ["010"], "width": 3, "interval": 4}), "the bit module plugs in")
	var add := sim2.place("add", Vector2i(9, 5), 0, {"k": 2}, 3)
	t.check(sim2.connect_ports(s2.id, "out", add.id, "in") != null, "the bit socket wires to an Add")
	t.check(not sim2.insert_device(s2.id, "text", {"values": ["HI"], "interval": 2}), "a raw module over a bits wire is refused")
	t.check(sim2.last_error == "Unplug the wire first: the Text module emits raw TEXT", "the refusal explains itself, got '%s'" % sim2.last_error)
	t.check(s2.device == "bit" and sim2.connections.size() == 1, "the refused insert changes nothing")

	t.check(sim2.remove_device(s2.id), "the module can be unplugged")
	t.check(s2.device == "" and s2.stream.is_empty(), "unplugging clears the module and its stream")
	t.check(sim2.connections.size() == 1, "unplugging keeps the wire")
	t.check(s2.port_role("out") == Catalog.ROLE_DATA, "the wire's role follows the last module")
	sim2.reset_run()
	for i in 20:
		sim2.step()
	t.check(s2.outq["out"] == null and add.inq["in"].is_empty(), "an unplugged socket emits nothing")


# --- Save / restore -------------------------------------------------------------

static func _save_roundtrip(t) -> void:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.build_board(sim)
	var src := _source_at(sim, Vector2i(0, 1))
	t.check(src != null and src.socket and src.device == "bit", "the L1 source is a bit socket")
	t.check(sim.remove_device(src.id), "the L1 module can be unplugged")
	t.check(sim.insert_device(src.id, "number", {"values": [7], "interval": 3}), "a Number module can be plugged in")
	var d := sim.layout_to_dict()

	var sim2 := Simulation.new()
	var run2 := LabRun.new()
	run2.build_board(sim2)
	sim2.load_player_layout(d)
	var src2 := _source_at(sim2, Vector2i(0, 1))
	t.check(src2 != null and src2.device == "number", "load_player_layout restores the plugged module (got '%s')" % ("" if src2 == null else src2.device))
	t.check(src2 != null and src2.port_role("out") == Catalog.ROLE_RAW, "the restored socket is raw again")


# --- Lab contract streams -------------------------------------------------------

static func _lab_streams(t) -> void:
	t.check(LabDef.stream_spec(0, "bit").get("values", []) == ["010"], "L1's bit contract is 010")
	t.check(LabDef.stream_spec(2, "bit").get("values", []) == ["010"], "L2/L3 inherit the latest contract")
	t.check(LabDef.stream_spec(3, "bit").get("values", []) == LabDef.WORDS_3, "L4's bit contract is the 8-word moving target")
	t.check(LabDef.stream_spec(4, "number").get("values", []) == [3, 6, 1, 4, 7, 2, 5, 0], "L5 adds the Number module stream")
	t.check(LabDef.stream_spec(5, "text").get("values", []) == ["HELLOCOMPUTE"], "L6 adds the Text module stream")
	t.check(LabDef.stream_spec(6, "text").get("values", []) == ["XYZZYBITWAVE"], "L7 overrides the Text stream")
	t.check(int(LabDef.stream_spec(7, "bit").get("width", 0)) == 5, "L8's bit contract is 5-bit")
	t.check(LabDef.stream_spec(8, "sensor").get("values", []) == [2, 6, 5, 1, 7, 3, 4, 0, 6, 2], "L9 adds the Sensor stream")
	t.check((LabDef.stream_spec(9, "bit").get("pattern", []) as Array).size() == 12 and int(LabDef.stream_spec(9, "bit")["pattern"][11]) == 60, "L10 makes the bit stream bursty (12-value bursts)")
	t.check(int(LabDef.stream_spec(10, "bit").get("interval", 0)) == 2, "L11 speeds the bit stream up")

	var sim := Simulation.new()
	var run := LabRun.new()
	run.build_board(sim)
	var src := _source_at(sim, Vector2i(0, 1))
	t.check(src != null and src.socket and src.device == "bit", "the L1 source is a bit socket")
	t.check(src != null and src.stream.size() == 1 and (src.stream[0] as BitVector).equals(BitVector.from_bin("010")), "the L1 socket carries the 010 stream")
	t.check(run.stream_for_device("bit").get("values", []) == ["010"], "LabRun exposes the current contract stream")
	t.check(run.devices_owned() == PackedStringArray(["bit"]), "the lab owns the Bit module")


# --- helpers --------------------------------------------------------------------

static func _source_at(sim: Simulation, cell: Vector2i) -> Machine:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "usb_input" and m.cell == cell:
			return m
	return null
