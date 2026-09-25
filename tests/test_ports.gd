class_name PortTests
extends RefCounted
## Laptop port racks (docs/SYSTEMS_EXPANSION.md §2.1): 4 input + 4 output ports at rows 1/4/7/10,
## sealed bays as reserved tiles, output devices (Job drive / Monitor), the bigger grid.


static func run(t) -> void:
	_l1_layout(t)
	_reserved_blocks_building(t)
	_ports_open_with_levels(t)
	_job_drive_moves(t)
	_monitor(t)
	_empty_output_stalls(t)
	_old_port_order(t)


static func _board(level_idx: int) -> Array:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = level_idx
	run.build_board(sim)
	return [sim, run]


static func _port(sim: Simulation, side: String, row: int) -> Machine:
	var ty := "usb_input" if side == "in" else "usb_output"
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == ty and m.cell.y == row:
			return m
	return null


static func _l1_layout(t) -> void:
	var b := _board(0)
	var sim: Simulation = b[0]
	t.check(sim.size == Vector2i(28, 16), "the Lab starts on a 28x16 grid (got %s)" % sim.size)
	var inp := _port(sim, "in", 1)
	var outp := _port(sim, "out", 1)
	t.check(inp != null and inp.cell == Vector2i(0, 1) and inp.device == "bit", "input port 1 at (0,1) holds the Bit module")
	t.check(outp != null and outp.cell == Vector2i(26, 1) and outp.device == "job", "output port 1 at (26,1) holds the Job drive")
	t.check(_port(sim, "in", 4) != null and _port(sim, "out", 4) != null, "two input and two output ports are open from the start")
	for row in [7, 10]:
		t.check(sim.is_reserved(Vector2i(0, row)) and sim.is_reserved(Vector2i(1, row)), "input row %d is a sealed bay" % row)
		t.check(sim.is_reserved(Vector2i(26, row)) and sim.is_reserved(Vector2i(27, row)), "output row %d is a sealed bay" % row)
	t.check(sim.reserved_label(Vector2i(0, 7)).begins_with("USB 3"), "a sealed bay carries its label (got '%s')" % sim.reserved_label(Vector2i(0, 7)))
	# creation order: [input row 1, output row 1] first (save migration relies on it)
	var ids := sim.sorted_machine_ids()
	t.check(ids.size() >= 2 and sim.machines[ids[0]] == inp and sim.machines[ids[1]] == outp, "ports are created input-1 then output-1")


static func _reserved_blocks_building(t) -> void:
	var sim: Simulation = _board(1)[0]  # L2: the Add is unlocked
	t.check(sim.placement_error("add", Vector2i(0, 7), 0) == "Sealed USB bay", "building on a sealed bay is refused")
	t.check(sim.placement_error("add", Vector2i(4, 4), 0) == "", "an ordinary tile is still buildable")
	# a wire from row 3 to row 5 along column 0/1 must go around the bay, never through it
	var a := sim.place("add", Vector2i(2, 3), 0, {"k": 1}, 3)
	var z := sim.place("add", Vector2i(2, 5), 0, {"k": 1}, 3)
	var r := sim.route_between(a.id, "out", z.id, "in")
	var through := false
	for c in r.get("cells", []):
		if sim.is_reserved(c):
			through = true
	t.check(not through, "wires never route through a sealed bay")


static func _ports_open_with_levels(t) -> void:
	var sim8: Simulation = _board(8)[0]
	t.check(_port(sim8, "out", 4) != null and not sim8.is_reserved(Vector2i(sim8.size.x - 2, 4)), "output port 2 (row 4) opens at L9")
	t.check(_port(sim8, "in", 7) == null and sim8.is_reserved(Vector2i(0, 7)), "input port 3 is still sealed at L9")
	var sim11: Simulation = _board(10)[0]
	t.check(sim11.size == Vector2i(40, 22), "L11 grows the grid to 40x22 (got %s)" % sim11.size)
	t.check(_port(sim11, "out", 1).cell == Vector2i(38, 1), "output ports follow the east edge")


static func _job_drive_moves(t) -> void:
	var b := _board(8)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var o1 := _port(sim, "out", 1)
	var o2 := _port(sim, "out", 4)
	t.check(sim.insert_device(o2.id, "job"), "the Job drive can be plugged into output port 2")
	t.check(o2.device == "job" and o1.device == "", "there is exactly one Job drive: port 1 is now empty")
	t.check(run.output_devices_owned() == PackedStringArray(["job", "monitor"]), "L9 owns the Job drive and the Monitor")


static func _monitor(t) -> void:
	var b := _board(8)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var o1 := _port(sim, "out", 1)
	var o2 := _port(sim, "out", 4)
	sim.insert_device(o2.id, "monitor")
	var src := _port(sim, "in", 1)
	sim.remove_device(src.id)
	sim.insert_device(src.id, "bit", {"values": ["010"], "width": 3, "interval": 1})
	sim.connect_ports(src.id, "out", o2.id, "in")
	sim.reset_run()
	for i in 80:
		sim.step()
	t.check(o2.received.size() > 0 and o2.received.size() <= 10, "the Monitor keeps at most 10 samples (got %d)" % o2.received.size())
	t.check(run.delivered == 0 and run.rejected == 0, "the Monitor judges nothing")
	t.check(o1.device == "job", "the Job drive stayed on port 1")


static func _empty_output_stalls(t) -> void:
	var b := _board(8)
	var sim: Simulation = b[0]
	var o2 := _port(sim, "out", 4)  # opened at L9 but nothing plugged in
	var src := _port(sim, "in", 1)
	sim.remove_device(src.id)
	sim.insert_device(src.id, "bit", {"values": ["010"], "width": 3, "interval": 1})
	var c := sim.connect_ports(src.id, "out", o2.id, "in")
	sim.reset_run()
	for i in 40:
		sim.step()
	t.check(c != null and c.packet_count() > 0 and o2.received.is_empty(), "a wire into an empty output port stalls")


## A layout saved when the racks opened in another order (in 1, out 1, out 4, out 7, in 4) still
## gives every port its own module: locked entries match by type and cell.
static func _old_port_order(t) -> void:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = 11
	run.build_board(sim)
	var ox := sim.size.x - 2
	var lay := {"machines": [
		{"type": "usb_input", "cell": [0, 1], "locked": true, "device": "text", "last_device": "text", "socket": true},
		{"type": "usb_output", "cell": [ox, 1], "locked": true, "device": "job", "last_device": "job", "socket": true},
		{"type": "usb_output", "cell": [ox, 4], "locked": true, "device": "monitor", "last_device": "monitor", "socket": true},
		{"type": "usb_output", "cell": [ox, 7], "locked": true, "device": "", "last_device": "", "socket": true},
		{"type": "usb_input", "cell": [0, 4], "locked": true, "device": "key", "last_device": "key", "socket": true},
	], "connections": []}
	sim.load_player_layout(lay)
	t.check(_port(sim, "in", 4).device == "key" and _port(sim, "out", 4).device == "monitor" and _port(sim, "in", 1).device == "text", "an old save's modules land on their own ports")

