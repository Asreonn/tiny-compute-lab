class_name Solutions
extends RefCounted
## Reference solutions for every mission. Used by the headless tests (and handy for
## debugging): each builds a layout on a board prepared by MissionRun.build_board().

static func _io(sim: Simulation) -> Dictionary:
	var ins := []
	var outs := []
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type in ["input", "usb_input"]:
			ins.append(id)
		elif m.type in ["output", "terminal_output"]:
			outs.append(id)
	return {"in": ins, "out": outs}


static func _w(sim: Simulation, a: int, pa: String, b: int, pb: String) -> void:
	var c := sim.connect_ports(a, pa, b, pb)
	assert(c != null, "wire failed %d.%s -> %d.%s: %s" % [a, pa, b, pb, sim.connect_error(a, pa, b, pb)])


static func _p(sim: Simulation, type: String, cell: Vector2i, params := {}, rot := 0) -> int:
	var m := sim.place(type, cell, rot, params)
	assert(m != null, "place failed %s at %s: %s" % [type, cell, sim.placement_error(type, cell, rot)])
	return m.id


## Place a machine at an explicit width (the lab's contracts need exact widths).
static func _pw(sim: Simulation, type: String, cell: Vector2i, width: int, params := {}) -> int:
	var m := sim.place(type, cell, 0, params, width)
	assert(m != null, "place failed %s at %s: %s" % [type, cell, sim.placement_error(type, cell, 0)])
	return m.id


static func build(sim: Simulation, mission_id: String) -> void:
	var io := _io(sim)
	var i: int = io["in"][0]
	var o: int = io["out"][0]
	match mission_id:
		"a1_plus_two", "a2_wrap":
			var a := _p(sim, "add", Vector2i(6, 3), {"k": 2})
			_w(sim, i, "out", a, "in")
			_w(sim, a, "out", o, "in")
		"b1_read":
			_w(sim, i, "out", o, "in")
		"b2_shift":
			var a := _p(sim, "add", Vector2i(6, 3), {"k": 3})
			_w(sim, i, "out", a, "in")
			_w(sim, a, "out", o, "in")
		"b3_caesar":
			var a := _p(sim, "add", Vector2i(4, 4), {"k": 3})
			var md := _p(sim, "modulo", Vector2i(8, 4), {"k": 26})
			_w(sim, i, "out", a, "in")
			_w(sim, a, "out", md, "in")
			_w(sim, md, "out", o, "in")
		"boot":
			_w(sim, i, "out", o, "in")
		"double":
			var m := _p(sim, "multiply", Vector2i(6, 3), {"k": 2})
			_w(sim, i, "out", m, "in")
			_w(sim, m, "out", o, "in")
		"offset":
			var a := _p(sim, "add", Vector2i(6, 3), {"k": 10})
			_w(sim, i, "out", a, "in")
			_w(sim, a, "out", o, "in")
		"pipeline":
			var m := _p(sim, "multiply", Vector2i(5, 4), {"k": 2})
			var a := _p(sim, "add", Vector2i(9, 4), {"k": 5})
			_w(sim, i, "out", m, "in")
			_w(sim, m, "out", a, "in")
			_w(sim, a, "out", o, "in")
		"decision":
			var c := _p(sim, "compare", Vector2i(6, 3), {"op": ">", "k": 20})
			_w(sim, i, "out", c, "in")
			_w(sim, c, "out", o, "in")
		"filter":
			var s := _p(sim, "splitter", Vector2i(4, 4), {"mode": "Duplicate"})
			var c := _p(sim, "compare", Vector2i(8, 6), {"op": ">", "k": 10})
			var g := _p(sim, "gate", Vector2i(10, 4))
			_w(sim, i, "out", s, "in")
			_w(sim, s, "a", g, "in")
			_w(sim, s, "b", c, "in")
			_w(sim, c, "out", g, "ctrl")
			_w(sim, g, "out", o, "in")
		"fork":
			var o2: int = io["out"][1]
			var s := _p(sim, "splitter", Vector2i(4, 4), {"mode": "Duplicate"})
			var m := _p(sim, "multiply", Vector2i(8, 2), {"k": 2})
			var a := _p(sim, "add", Vector2i(8, 7), {"k": 1})
			_w(sim, i, "out", s, "in")
			_w(sim, s, "a", m, "in")
			_w(sim, s, "b", a, "in")
			_w(sim, m, "out", o, "in")
			_w(sim, a, "out", o2, "in")
		"traffic":
			var b := _p(sim, "buffer", Vector2i(3, 3), {"capacity": 8})
			var m := _p(sim, "multiply", Vector2i(6, 3), {"k": 3})
			_w(sim, i, "out", b, "in")
			_w(sim, b, "out", m, "in")
			_w(sim, m, "out", o, "in")
		"parallel":
			var s := _p(sim, "splitter", Vector2i(4, 5))
			var p1 := _p(sim, "processor", Vector2i(8, 2))
			var p2 := _p(sim, "processor", Vector2i(8, 7))
			var mg := _p(sim, "merger", Vector2i(12, 5))
			_w(sim, i, "out", s, "in")
			_w(sim, s, "a", p1, "in")
			_w(sim, s, "b", p2, "in")
			_w(sim, p1, "out", mg, "a")
			_w(sim, p2, "out", mg, "b")
			_w(sim, mg, "out", o, "in")
		"optimize":
			var s := _p(sim, "splitter", Vector2i(4, 5))
			var m1 := _p(sim, "multiply", Vector2i(8, 3), {"k": 3})
			var m2 := _p(sim, "multiply", Vector2i(8, 8), {"k": 3})
			var mg := _p(sim, "merger", Vector2i(12, 5))
			var a := _p(sim, "add", Vector2i(15, 5), {"k": 1})
			_w(sim, i, "out", s, "in")
			_w(sim, s, "a", m1, "in")
			_w(sim, s, "b", m2, "in")
			_w(sim, m1, "out", mg, "a")
			_w(sim, m2, "out", mg, "b")
			_w(sim, mg, "out", a, "in")
			_w(sim, a, "out", o, "in")


# ---------------------------------------------------------------- Lab

static func _lab_io(sim: Simulation) -> Dictionary:
	var socket := -1
	var drive := -1
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "usb_input":
			if socket < 0:
				socket = id  # the first input port drives the contract's primary origin
		elif m.type == "usb_output":
			if m.device == "job":
				drive = id
			elif drive < 0:
				drive = id
	return {"socket": socket, "drive": drive}


## The input port on `row` (the Lab racks sit at rows 1 / 4 / 7 / 10).
static func _lab_socket(sim: Simulation, row: int) -> int:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "usb_input" and m.cell.y == row:
			return id
	return -1


static func _lab_plug(sim: Simulation, socket: int, kind: String) -> void:
	sim.remove_device(socket)
	assert(sim.insert_device(socket, kind), "plug %s failed: %s" % [kind, sim.last_error])


## Reference layout for every Lab level, using ONLY the machines unlocked by then and inside
## the board size (docs/SYSTEMS_EXPANSION.md §10). `sim` must be a fresh LabRun.build_board board.
static func lab_solution(sim: Simulation, level_idx: int) -> void:
	var io := _lab_io(sim)
	var s: int = io["socket"]
	var d: int = io["drive"]
	match level_idx:
		0:  # L1: hand the 010s back unchanged
			_lab_plug(sim, s, "bit")
			_w(sim, s, "out", d, "in")
		1:  # L2: 010 + 2 = 100
			_lab_plug(sim, s, "bit")
			var a := _pw(sim, "add", Vector2i(7, 5), 3, {"k": 2})
			_w(sim, s, "out", a, "in")
			_w(sim, a, "out", d, "in")
		2:  # L3: 010 + 7 = 001 (wraps)
			_lab_plug(sim, s, "bit")
			var a := _pw(sim, "add", Vector2i(7, 5), 3, {"k": 7})
			_w(sim, s, "out", a, "in")
			_w(sim, a, "out", d, "in")
		3:  # L4: add 3 to every arriving word
			_lab_plug(sim, s, "bit")
			var a := _pw(sim, "add", Vector2i(7, 5), 3, {"k": 3})
			_w(sim, s, "out", a, "in")
			_w(sim, a, "out", d, "in")
		4:  # L5: encode number, add 1
			_lab_plug(sim, s, "number")
			var e := _p(sim, "number_encoder", Vector2i(5, 5), {"width": 3})
			var a := _pw(sim, "add", Vector2i(9, 5), 3, {"k": 1})
			_w(sim, s, "out", e, "in")
			_w(sim, e, "out", a, "in")
			_w(sim, a, "out", d, "in")
		5:  # L6: encode char, Caesar +3, decode
			_lab_plug(sim, s, "text")
			var e := _p(sim, "char_encoder", Vector2i(4, 5), {"width": 5})
			var a := _pw(sim, "add", Vector2i(8, 5), 5, {"k": 3})
			var dc := _p(sim, "char_decoder", Vector2i(12, 5), {"width": 5})
			_w(sim, s, "out", e, "in")
			_w(sim, e, "out", a, "in")
			_w(sim, a, "out", dc, "in")
			_w(sim, dc, "out", d, "in")
		6:  # L7: Caesar +3 with wrap
			_lab_plug(sim, s, "text")
			var e := _p(sim, "char_encoder", Vector2i(4, 5), {"width": 5})
			var a := _pw(sim, "add", Vector2i(8, 5), 5, {"k": 3})
			var mo := _pw(sim, "modulo", Vector2i(12, 5), 5, {"k": 26})
			var dc := _p(sim, "char_decoder", Vector2i(16, 5), {"width": 5})
			_w(sim, s, "out", e, "in")
			_w(sim, e, "out", a, "in")
			_w(sim, a, "out", mo, "in")
			_w(sim, mo, "out", dc, "in")
			_w(sim, dc, "out", d, "in")
		7:  # L8: low 3 bits of every 5-bit word
			_lab_plug(sim, s, "bit")
			var bs := _pw(sim, "bit_splitter", Vector2i(7, 5), 5, {"lo": 3})
			_w(sim, s, "out", bs, "in")
			_w(sim, bs, "lo", d, "in")
		8:  # L9: keep sensor readings above 4
			_lab_plug(sim, s, "sensor")
			var e := _p(sim, "number_encoder", Vector2i(5, 5), {"width": 3})
			# one output takes one wire: a Duplicate splitter feeds both the comparator and the gate
			var sp := _pw(sim, "splitter", Vector2i(8, 5), 3, {"mode": "Duplicate"})
			var c := _pw(sim, "compare", Vector2i(12, 5), 3, {"op": ">", "k": 4})
			var g := _pw(sim, "gate", Vector2i(15, 6), 3)
			_w(sim, s, "out", e, "in")
			_w(sim, e, "out", sp, "in")
			_w(sim, sp, "a", c, "in")
			_w(sim, sp, "b", g, "in")
			_w(sim, c, "out", g, "ctrl")
			_w(sim, g, "out", d, "in")
		9:  # L10: buffer the bursts so nothing is lost
			_lab_plug(sim, s, "bit")
			var b := _pw(sim, "buffer", Vector2i(5, 5), 3, {"capacity": 8})
			var a := _pw(sim, "add", Vector2i(9, 5), 3, {"k": 1})
			_w(sim, s, "out", b, "in")
			_w(sim, b, "out", a, "in")
			_w(sim, a, "out", d, "in")
		10:  # L11: four parallel multiplies to sustain the rate
			_lab_plug(sim, s, "bit")
			_lab_rush_hour(sim, s, d)
		11:  # L12: text + key through two encoders into one Adder, wrap, decode
			var s2 := _lab_socket(sim, 4)
			_lab_plug(sim, s, "text")
			_lab_plug(sim, s2, "key")
			var ce := _p(sim, "char_encoder", Vector2i(4, 1), {"width": 5})
			var ne := _p(sim, "number_encoder", Vector2i(4, 4), {"width": 5})
			var ad := _pw(sim, "adder", Vector2i(9, 2), 5)
			var mo := _pw(sim, "modulo", Vector2i(14, 2), 5, {"k": 26})
			var dc := _p(sim, "char_decoder", Vector2i(18, 2), {"width": 5})
			_w(sim, s, "out", ce, "in")
			_w(sim, s2, "out", ne, "in")
			_w(sim, ce, "out", ad, "a")
			_w(sim, ne, "out", ad, "b")
			_w(sim, ad, "out", mo, "in")
			_w(sim, mo, "out", dc, "in")
			_w(sim, dc, "out", d, "in")
		12:  # L13: as L12, with two Buffers that swallow the text bursts so no letter is lost
			var s2 := _lab_socket(sim, 4)
			_lab_plug(sim, s, "text")
			_lab_plug(sim, s2, "key")
			var ce := _p(sim, "char_encoder", Vector2i(3, 1), {"width": 5})
			var bu := _pw(sim, "buffer", Vector2i(6, 1), 5, {"capacity": 8})
			var bu2 := _pw(sim, "buffer", Vector2i(9, 1), 5, {"capacity": 8})
			var ne := _p(sim, "number_encoder", Vector2i(4, 4), {"width": 5})
			var ad := _pw(sim, "adder", Vector2i(13, 2), 5)
			var mo := _pw(sim, "modulo", Vector2i(17, 2), 5, {"k": 26})
			var dc := _p(sim, "char_decoder", Vector2i(21, 2), {"width": 5})
			_w(sim, s, "out", ce, "in")
			_w(sim, ce, "out", bu, "in")
			_w(sim, bu, "out", bu2, "in")
			_w(sim, s2, "out", ne, "in")
			_w(sim, bu2, "out", ad, "a")
			_w(sim, ne, "out", ad, "b")
			_w(sim, ad, "out", mo, "in")
			_w(sim, mo, "out", dc, "in")
			_w(sim, dc, "out", d, "in")
		13:  # L14: route by the tag bit, transform each lane, merge
			_lab_plug(sim, s, "bit")
			var cr := _pw(sim, "cond_router", Vector2i(3, 1), 5, {"op": "bit", "k": 4})
			var bs1 := _pw(sim, "bit_splitter", Vector2i(7, 1), 5, {"lo": 3})
			var bs2 := _pw(sim, "bit_splitter", Vector2i(7, 4), 5, {"lo": 3})
			var ad := _pw(sim, "add", Vector2i(11, 1), 3, {"k": 1})
			var mu := _pw(sim, "multiply", Vector2i(11, 4), 3, {"k": 2})
			var mg := _pw(sim, "merger", Vector2i(15, 2), 3)
			_w(sim, s, "out", cr, "in")
			_w(sim, cr, "a", bs1, "in")
			_w(sim, cr, "b", bs2, "in")
			_w(sim, bs1, "lo", ad, "in")
			_w(sim, bs2, "lo", mu, "in")
			_w(sim, ad, "out", mg, "a")
			_w(sim, mu, "out", mg, "b")
			_w(sim, mg, "out", d, "in")
		14:  # L15: widen 3 → 5 bits, then multiply by 5 at 5 bits
			_lab_plug(sim, s, "bit")
			var zx := _pw(sim, "zero_extend", Vector2i(4, 1), 3, {"to": 5})
			var mu := _pw(sim, "multiply", Vector2i(8, 1), 5, {"k": 5})
			_w(sim, s, "out", zx, "in")
			_w(sim, zx, "out", mu, "in")
			_w(sim, mu, "out", d, "in")
		15:  # L16: two Adder doublers (x + x) share the load: 6 power for 5/s
			_lab_plug(sim, s, "bit")
			var sp := _pw(sim, "splitter", Vector2i(4, 2), 3)
			var d1 := _pw(sim, "splitter", Vector2i(8, 1), 3, {"mode": "Duplicate"})
			var d2 := _pw(sim, "splitter", Vector2i(8, 5), 3, {"mode": "Duplicate"})
			var a1 := _pw(sim, "adder", Vector2i(12, 1), 3)
			var a2 := _pw(sim, "adder", Vector2i(12, 5), 3)
			var mg := _pw(sim, "merger", Vector2i(16, 3), 3)
			_w(sim, s, "out", sp, "in")
			_w(sim, sp, "a", d1, "in")
			_w(sim, sp, "b", d2, "in")
			_w(sim, d1, "a", a1, "a")
			_w(sim, d1, "b", a1, "b")
			_w(sim, d2, "a", a2, "a")
			_w(sim, d2, "b", a2, "b")
			_w(sim, a1, "out", mg, "a")
			_w(sim, a2, "out", mg, "b")
			_w(sim, mg, "out", d, "in")
		16:  # L17: overclocked splitter -> two overclocked Adds -> overclocked merger, a Blower on each Add
			_lab_plug(sim, s, "bit")
			var oc := {"clock": "overclocked"}
			var sp := _pw(sim, "splitter", Vector2i(4, 2), 3, oc)
			var a1 := _pw(sim, "add", Vector2i(8, 1), 3, {"k": 1, "clock": "overclocked"})
			var a2 := _pw(sim, "add", Vector2i(8, 5), 3, {"k": 1, "clock": "overclocked"})
			_pw(sim, "blower", Vector2i(8, 0), 3)
			_pw(sim, "blower", Vector2i(8, 6), 3)
			var mg := _pw(sim, "merger", Vector2i(12, 2), 3, oc)
			_w(sim, s, "out", sp, "in")
			_w(sim, sp, "a", a1, "in")
			_w(sim, sp, "b", a2, "in")
			_w(sim, a1, "out", mg, "a")
			_w(sim, a2, "out", mg, "b")
			_w(sim, mg, "out", d, "in")
		17:  # L18: 8-bit ASCII AND the 0xDF mask from the key stick
			var s2 := _lab_socket(sim, 4)
			_lab_plug(sim, s, "text")
			_lab_plug(sim, s2, "key")
			var ce := _p(sim, "char_encoder", Vector2i(4, 1), {"width": 8})
			var ne := _p(sim, "number_encoder", Vector2i(4, 4), {"width": 8})
			var an := _pw(sim, "and_gate", Vector2i(9, 2), 8)
			var dc := _p(sim, "char_decoder", Vector2i(13, 2), {"width": 8})
			_w(sim, s, "out", ce, "in")
			_w(sim, s2, "out", ne, "in")
			_w(sim, ce, "out", an, "a")
			_w(sim, ne, "out", an, "b")
			_w(sim, an, "out", dc, "in")
			_w(sim, dc, "out", d, "in")
		18:  # L19: ASCII XOR the key byte, delivered as raw 8-bit cipher bytes
			var s2 := _lab_socket(sim, 4)
			_lab_plug(sim, s, "text")
			_lab_plug(sim, s2, "key")
			var ce := _p(sim, "char_encoder", Vector2i(4, 1), {"width": 8})
			var ne := _p(sim, "number_encoder", Vector2i(4, 4), {"width": 8})
			var xo := _pw(sim, "xor_gate", Vector2i(9, 2), 8)
			_w(sim, s, "out", ce, "in")
			_w(sim, s2, "out", ne, "in")
			_w(sim, ce, "out", xo, "a")
			_w(sim, ne, "out", xo, "b")
			_w(sim, xo, "out", d, "in")
		19:  # L20: x4 is a shift left by 2 — one machine, 1 power
			_lab_plug(sim, s, "bit")
			var sh := _pw(sim, "shift_left", Vector2i(5, 1), 5, {"n": 2})
			_w(sim, s, "out", sh, "in")
			_w(sim, sh, "out", d, "in")
		20:  # L21: four overclocked Multiplies, each over a Radiator, fed and drained by overclocked routing
			_lab_plug(sim, s, "bit")
			var oc := {"clock": "overclocked"}
			var sp1 := _pw(sim, "splitter", Vector2i(4, 7), 5, oc)
			var sp2 := _pw(sim, "splitter", Vector2i(8, 4), 5, oc)
			var sp3 := _pw(sim, "splitter", Vector2i(8, 11), 5, oc)
			var ms := []
			for y in [2, 6, 10, 14]:
				ms.append(_pw(sim, "multiply", Vector2i(13, y), 5, {"k": 3, "clock": "overclocked"}))
				_pw(sim, "radiator", Vector2i(13, y + 1), 5)
			var mg1 := _pw(sim, "merger", Vector2i(18, 3), 5, oc)
			var mg2 := _pw(sim, "merger", Vector2i(18, 11), 5, oc)
			var mg3 := _pw(sim, "merger", Vector2i(23, 7), 5, oc)
			_w(sim, s, "out", sp1, "in")
			_w(sim, sp1, "a", sp2, "in")
			_w(sim, sp1, "b", sp3, "in")
			_w(sim, sp2, "a", ms[0], "in")
			_w(sim, sp2, "b", ms[1], "in")
			_w(sim, sp3, "a", ms[2], "in")
			_w(sim, sp3, "b", ms[3], "in")
			_w(sim, ms[0], "out", mg1, "a")
			_w(sim, ms[1], "out", mg1, "b")
			_w(sim, ms[2], "out", mg2, "a")
			_w(sim, ms[3], "out", mg2, "b")
			_w(sim, mg1, "out", mg3, "a")
			_w(sim, mg2, "out", mg3, "b")
			_w(sim, mg3, "out", d, "in")
		21:  # L22: an Adder whose B input is its own previous total, kept by an echo Register
			_lab_plug(sim, s, "bit")
			var zx := _pw(sim, "zero_extend", Vector2i(4, 1), 3, {"to": 5})
			var ad := _pw(sim, "adder", Vector2i(8, 1), 5)
			var sp := _pw(sim, "splitter", Vector2i(11, 1), 5, {"mode": "Duplicate"})
			var rg := _pw(sim, "register", Vector2i(8, 4), 5, {"mode": "echo", "init": 0})
			_w(sim, s, "out", zx, "in")
			_w(sim, zx, "out", ad, "a")
			_w(sim, ad, "out", sp, "in")
			_w(sim, sp, "a", d, "in")
			_w(sim, sp, "b", rg, "in")
			_w(sim, rg, "out", ad, "b")
		22:  # L23: the substitution is a ROM table
			_lab_plug(sim, s, "bit")
			var rom := _pw(sim, "rom", Vector2i(5, 1), 3, {"table": "6 4 7 1 0 3 5 2", "out": 3})
			_w(sim, s, "out", rom, "in")
			_w(sim, rom, "out", d, "in")
		23:  # L24: number and key into the ALU, the bit stick picks ADD / SUB
			var s2 := _lab_socket(sim, 4)
			var s3 := _lab_socket(sim, 7)
			_lab_plug(sim, s, "number")
			_lab_plug(sim, s2, "key")
			_lab_plug(sim, s3, "bit")
			var ne1 := _p(sim, "number_encoder", Vector2i(4, 1), {"width": 5})
			var ne2 := _p(sim, "number_encoder", Vector2i(4, 4), {"width": 5})
			var alu := _pw(sim, "alu", Vector2i(9, 2), 5, {"op0": "ADD", "op1": "SUB"})
			_w(sim, s, "out", ne1, "in")
			_w(sim, s2, "out", ne2, "in")
			_w(sim, ne1, "out", alu, "a")
			_w(sim, ne2, "out", alu, "b")
			_w(sim, s3, "out", alu, "op")
			_w(sim, alu, "out", d, "in")
		24:  # L25: split each instruction into WE / address / value and run it on RAM
			_lab_plug(sim, s, "bit")
			var s1 := _pw(sim, "splitter", Vector2i(4, 2), 8, {"mode": "Duplicate"})
			var dec := _pw(sim, "instruction_decoder", Vector2i(8, 0), 8)
			var s2b := _pw(sim, "splitter", Vector2i(8, 5), 8, {"mode": "Duplicate"})
			var b1 := _pw(sim, "bit_splitter", Vector2i(12, 4), 8, {"lo": 3})
			var b2 := _pw(sim, "bit_splitter", Vector2i(16, 4), 5, {"lo": 4})
			var b3 := _pw(sim, "bit_splitter", Vector2i(12, 8), 8, {"lo": 3})
			var ram := _pw(sim, "ram", Vector2i(21, 3), 3)
			_w(sim, s, "out", s1, "in")
			_w(sim, s1, "a", dec, "in")
			_w(sim, s1, "b", s2b, "in")
			_w(sim, s2b, "a", b1, "in")
			_w(sim, s2b, "b", b3, "in")
			_w(sim, b1, "hi", b2, "in")
			_w(sim, dec, "a", ram, "we")
			_w(sim, b2, "lo", ram, "a")
			_w(sim, b3, "lo", ram, "d")
			_w(sim, ram, "out", d, "in")
		25:  # L26: clock pulses → program counter → ROM melody
			_lab_plug(sim, s, "bit")
			var pc := _pw(sim, "program_counter", Vector2i(4, 1), 3)
			var rom2 := _pw(sim, "rom", Vector2i(7, 1), 3, {"table": "3 5 8 5 10 8 12 1", "out": 4})
			_w(sim, s, "out", pc, "in")
			_w(sim, pc, "out", rom2, "in")
			_w(sim, rom2, "out", d, "in")
		26:  # L27: fetch (PC → ROM), decode (bit 7 → ALU op, low 6 bits → operand), execute (ALU + ACC)
			_lab_cpu(sim, s, d, "5 12 131 20 135 1 158 9", false)
		27:  # L28: the same CPU; the decoder's second line (OUT) gates the accumulator to the drive
			_lab_cpu(sim, s, d, "10 67 134 64 194 20 65 139", true)


## The tiny accumulator CPU of L27 / L28.
static func _lab_cpu(sim: Simulation, s: int, d: int, program: String, with_out: bool) -> void:
	_lab_plug(sim, s, "bit")
	var pc := _pw(sim, "program_counter", Vector2i(4, 1), 3)
	var rom := _pw(sim, "rom", Vector2i(7, 1), 3, {"table": program, "out": 8})
	var s1 := _pw(sim, "splitter", Vector2i(11, 1), 8, {"mode": "Duplicate"})
	var dec := _pw(sim, "instruction_decoder", Vector2i(15, 0), 8)
	var imm := _pw(sim, "bit_splitter", Vector2i(15, 3), 8, {"lo": 6})
	var alu := _pw(sim, "alu", Vector2i(20, 2), 6, {"op0": "ADD", "op1": "SUB"})
	var s2 := _pw(sim, "splitter", Vector2i(24, 2), 6, {"mode": "Duplicate"})
	var acc := _pw(sim, "register", Vector2i(20, 6), 6, {"mode": "echo", "init": 0})
	_w(sim, s, "out", pc, "in")
	_w(sim, pc, "out", rom, "in")
	_w(sim, rom, "out", s1, "in")
	_w(sim, s1, "a", dec, "in")
	_w(sim, s1, "b", imm, "in")
	_w(sim, dec, "a", alu, "op")
	_w(sim, imm, "lo", alu, "b")
	_w(sim, acc, "out", alu, "a")
	_w(sim, alu, "out", s2, "in")
	_w(sim, s2, "b", acc, "in")
	if with_out:
		var g := _pw(sim, "gate", Vector2i(28, 1), 6)
		_w(sim, dec, "b", g, "ctrl")
		_w(sim, s2, "a", g, "in")
		_w(sim, g, "out", d, "in")
	else:
		_w(sim, s2, "a", d, "in")


static func _lab_rush_hour(sim: Simulation, s: int, d: int) -> void:
	var sp1 := _pw(sim, "splitter", Vector2i(4, 5), 3)
	var sp2 := _pw(sim, "splitter", Vector2i(8, 3), 3)
	var sp3 := _pw(sim, "splitter", Vector2i(8, 7), 3)
	var m1 := _pw(sim, "multiply", Vector2i(13, 2), 3, {"k": 3})
	var m2 := _pw(sim, "multiply", Vector2i(13, 5), 3, {"k": 3})
	var m3 := _pw(sim, "multiply", Vector2i(13, 9), 3, {"k": 3})
	var m4 := _pw(sim, "multiply", Vector2i(13, 12), 3, {"k": 3})
	var mg1 := _pw(sim, "merger", Vector2i(18, 3), 3)
	var mg2 := _pw(sim, "merger", Vector2i(18, 10), 3)
	var mg3 := _pw(sim, "merger", Vector2i(24, 6), 3)
	_w(sim, s, "out", sp1, "in")
	_w(sim, sp1, "a", sp2, "in")
	_w(sim, sp1, "b", sp3, "in")
	_w(sim, sp2, "a", m1, "in")
	_w(sim, sp2, "b", m2, "in")
	_w(sim, sp3, "a", m3, "in")
	_w(sim, sp3, "b", m4, "in")
	_w(sim, m1, "out", mg1, "a")
	_w(sim, m2, "out", mg1, "b")
	_w(sim, m3, "out", mg2, "a")
	_w(sim, m4, "out", mg2, "b")
	_w(sim, mg1, "out", mg3, "a")
	_w(sim, mg2, "out", mg3, "b")
	_w(sim, mg3, "out", d, "in")
