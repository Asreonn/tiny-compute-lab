class_name UndoTests
extends RefCounted
## F5 acceptance tests: Simulation.apply_layout, the in-place layout restore behind undo / redo
## (docs/SYSTEMS_EXPANSION.md §9). Matching machines and wires are kept with their packets; the
## rest is removed, re-placed or re-wired; socket devices follow the snapshot.


static func run(t) -> void:
	_add_then_undo(t)
	_remove_then_undo(t)
	_param_change(t)
	_packets_survive(t)
	_devices(t)
	_single_change_signal(t)


static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	return sim


static func _snap(sim: Simulation) -> Dictionary:
	return JSON.parse_string(JSON.stringify(sim.layout_to_dict()))


## Order-free form of a layout: sorted machine keys + wires named by their machines' keys.
static func _canon(d: Dictionary) -> String:
	var keys := []
	for md in d["machines"]:
		keys.append(Simulation._layout_key(md))
	var wires := []
	for cd in d["connections"]:
		wires.append("%s:%s>%s:%s" % [keys[int(cd["from"])], cd["from_port"], keys[int(cd["to"])], cd["to_port"]])
	var ks := keys.duplicate()
	ks.sort()
	wires.sort()
	return JSON.stringify([ks, wires])


static func _add_then_undo(t) -> void:
	var sim := _sim()
	var a := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	var b := sim.place("add", Vector2i(6, 2), 0, {"k": 2}, 3)
	var ab := sim.connect_ports(a.id, "out", b.id, "in")
	var before := _snap(sim)
	var c := sim.place("add", Vector2i(10, 2), 0, {"k": 3}, 3)
	sim.connect_ports(b.id, "out", c.id, "in")
	sim.apply_layout(before)
	t.check(not sim.machines.has(c.id) and sim.machines.size() == 2, "undo removes the machine placed after the snapshot")
	t.check(sim.machines.has(a.id) and sim.machines.has(b.id), "untouched machines keep their ids")
	t.check(sim.connections.size() == 1 and sim.connections.has(ab.id), "the untouched wire is kept as the same connection")
	t.check(_canon(_snap(sim)) == _canon(before), "the layout equals the snapshot")


static func _remove_then_undo(t) -> void:
	var sim := _sim()
	var a := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	var b := sim.place("multiply", Vector2i(6, 2), 0, {"k": 2}, 3)
	var c := sim.place("add", Vector2i(10, 2), 0, {"k": 3}, 3)
	sim.connect_ports(a.id, "out", b.id, "in")
	sim.connect_ports(b.id, "out", c.id, "in")
	var before := _snap(sim)
	sim.remove(b.id)
	t.check(sim.connections.is_empty(), "removing the middle machine drops both wires")
	sim.apply_layout(before)
	var mul: Machine = null
	for id in sim.machines:
		if sim.machines[id].type == "multiply":
			mul = sim.machines[id]
	t.check(mul != null and mul.cell == Vector2i(6, 2) and int(mul.params.get("k", 0)) == 2, "undo re-places the removed machine with its parameters")
	t.check(sim.connections.size() == 2, "and re-connects both of its wires")
	t.check(_canon(_snap(sim)) == _canon(before), "the restored layout equals the snapshot (up to machine order)")


static func _param_change(t) -> void:
	var sim := _sim()
	var a := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	var before := _snap(sim)
	a.params["k"] = 5
	sim.apply_layout(before)
	var k := -1
	for id in sim.machines:
		k = int(sim.machines[id].params.get("k", -1))
	t.check(sim.machines.size() == 1 and k == 1, "undo restores a changed parameter")


static func _packets_survive(t) -> void:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = 1  # L2: the Add is unlocked
	run.build_board(sim)
	var src: Machine = null
	for id in sim.sorted_machine_ids():
		if sim.machines[id].type == "usb_input" and sim.machines[id].cell.y == 1:
			src = sim.machines[id]
	if src.device == "":
		sim.insert_device(src.id, "bit")
	var a := sim.place("add", Vector2i(12, 1), 0, {"k": 1}, 3)
	var w := sim.connect_ports(src.id, "out", a.id, "in")
	sim.reset_run()
	for i in 6:
		sim.step()
	var carried := w.packet_count()
	var before := _snap(sim)
	sim.place("add", Vector2i(12, 8), 0, {"k": 2}, 3)
	sim.apply_layout(before)
	t.check(sim.connections.has(w.id) and w.packet_count() == carried and carried > 0, "packets on an untouched wire survive an undo (%d)" % carried)


static func _devices(t) -> void:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = 5
	run.build_board(sim)
	var p1: Machine = null
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "usb_input" and m.cell.y == 1:
			p1 = m
	run.plug_from_desk(sim, "in", _slot(run, "text@5"), p1.id)
	var before := _snap(sim)
	run.unplug_to_desk(sim, p1.id)
	t.check(p1.device == "", "the module is unplugged")
	sim.apply_layout(before)
	t.check(p1.device == "text@5", "undo plugs the quest stick back in (got '%s')" % p1.device)


static func _slot(run: LabRun, kind: String) -> int:
	for s in run.desk_inputs:
		if run.desk_inputs[s] == kind:
			return s
	return -1


static func _single_change_signal(t) -> void:
	var sim := _sim()
	var a := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	var before := _snap(sim)
	for i in 3:
		sim.place("add", Vector2i(2 + i * 4, 6), 0, {"k": 1}, 3)
	sim.remove(a.id)
	var n := [0]
	sim.changed.connect(func(): n[0] += 1)
	sim.apply_layout(before)
	t.check(n[0] == 1, "apply_layout emits `changed` exactly once (got %d)" % n[0])
