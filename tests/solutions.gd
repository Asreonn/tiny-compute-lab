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
