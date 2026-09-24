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
			socket = id
		elif m.type == "usb_output":
			drive = id
	return {"socket": socket, "drive": drive}


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
