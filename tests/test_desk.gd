class_name DeskTests
extends RefCounted
## Desk zones (docs/SYSTEMS_EXPANSION.md §2.2): the physical USB inventory beside the laptop.


static func run(t) -> void:
	_initial(t)
	_plug_swap_unplug(t)
	_refusals(t)
	_outputs(t)
	_new_devices_land_on_desk(t)
	_save_roundtrip(t)


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


## Each owned device exactly once: on the desk or in a port.
static func _consistent(sim: Simulation, run: LabRun) -> bool:
	for side in ["in", "out"]:
		var owned := run.devices_owned() if side == "in" else run.output_devices_owned()
		var seen := {}
		var d: Dictionary = run.desk_inputs if side == "in" else run.desk_outputs
		for k in d.values():
			seen[k] = int(seen.get(k, 0)) + 1
		var ty := "usb_input" if side == "in" else "usb_output"
		for id in sim.sorted_machine_ids():
			var m: Machine = sim.machines[id]
			if m.type == ty and m.socket and m.device != "":
				seen[m.device] = int(seen.get(m.device, 0)) + 1
		for kind in owned:
			if int(seen.get(kind, 0)) != 1:
				return false
	return true


static func _slot_of(run: LabRun, side: String, kind: String) -> int:
	var d: Dictionary = run.desk_inputs if side == "in" else run.desk_outputs
	for s in d:
		if d[s] == kind:
			return s
	return -1


static func _initial(t) -> void:
	var b := _board(0)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	t.check(run.desk_inputs.is_empty() and run.desk_outputs.is_empty(), "L1: the Bit module and Job drive are plugged, the desks are empty")
	t.check(run.desk_slot_count("in") == 3, "L1 input desk has owned + 2 slots (got %d)" % run.desk_slot_count("in"))
	var b6 := _board(5)
	var run6: LabRun = b6[1]
	t.check(run6.desk_inputs.values().has("number") and run6.desk_inputs.values().has("text"), "L6: unplugged owned modules lie on the desk")
	t.check(_consistent(b6[0], run6), "every owned module is in exactly one place (L6)")


static func _plug_swap_unplug(t) -> void:
	var b := _board(5)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var p1 := _port(sim, "in", 1)
	t.check(p1.device == "", "L6 starts with input port 1 empty (the Bit module lies on the desk)")
	t.check(run.plug_from_desk(sim, "in", _slot_of(run, "in", "bit"), p1.id) and p1.device == "bit", "a desk module plugs into an open input port")
	var text_slot := _slot_of(run, "in", "text")
	t.check(run.plug_from_desk(sim, "in", text_slot, p1.id), "a second module plugs into the occupied port")
	t.check(p1.device == "text" and run.desk_inputs.get(text_slot, "") == "bit", "the port's old module swapped back into that slot")
	t.check(_consistent(sim, run), "consistency after a swap")
	t.check(run.unplug_to_desk(sim, p1.id), "a plugged module can be unplugged onto the desk")
	t.check(p1.device == "" and run.desk_inputs.values().has("text"), "the unplugged module lies on the desk")
	var from := -1
	for s in run.desk_inputs:
		if run.desk_inputs[s] == "text":
			from = s
	var free := -1
	for i in run.desk_slot_count("in"):
		if not run.desk_inputs.has(i):
			free = i
	t.check(run.move_on_desk("in", from, free) and run.desk_inputs.get(free, "") == "text", "modules can be moved between desk slots")
	t.check(_consistent(sim, run), "consistency after unplug + move")


static func _refusals(t) -> void:
	var b := _board(5)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var out1 := _port(sim, "out", 1)
	var slot: int = run.desk_inputs.keys()[0]
	var before := run.desk_inputs.duplicate()
	t.check(not run.plug_from_desk(sim, "in", slot, out1.id), "an input module is refused by an output port")
	t.check(run.desk_inputs == before, "a refusal changes nothing")
	# wire rule: a bit wire from the socket to an Add refuses a raw module
	var p1 := _port(sim, "in", 1)
	run.plug_from_desk(sim, "in", _slot_of(run, "in", "bit"), p1.id)
	var a := sim.place("add", Vector2i(4, 1), 0, {"k": 1}, 3)
	sim.connect_ports(p1.id, "out", a.id, "in")
	var text_slot := -1
	for s in run.desk_inputs:
		if run.desk_inputs[s] == "text":
			text_slot = s
	t.check(not run.plug_from_desk(sim, "in", text_slot, p1.id), "the wire rule refuses a raw module on a bit wire")
	t.check(p1.device == "bit" and run.desk_inputs.get(text_slot, "") == "text", "the refused module stays on the desk")
	t.check(sim.last_error.begins_with("Unplug the wire first"), "the refusal explains itself (got '%s')" % sim.last_error)


static func _outputs(t) -> void:
	var b := _board(8)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	t.check(run.desk_outputs.values().has("monitor"), "L9: the Monitor lies on the output desk")
	var o2 := _port(sim, "out", 4)
	var mslot := -1
	for s in run.desk_outputs:
		if run.desk_outputs[s] == "monitor":
			mslot = s
	t.check(run.plug_from_desk(sim, "out", mslot, o2.id) and o2.device == "monitor", "the Monitor plugs into output port 2")
	t.check(run.unplug_to_desk(sim, _port(sim, "out", 1).id), "the Job drive can be put on the desk")
	t.check(run.desk_outputs.values().has("job") and _consistent(sim, run), "the Job drive lies on the desk")


static func _new_devices_land_on_desk(t) -> void:
	var b := _board(3)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	run._advance(sim)  # L4 -> L5: the Number module becomes owned
	t.check(run.new_devices.has("number") and run.desk_inputs.values().has("number"), "a newly owned module lands on the desk as New")


static func _save_roundtrip(t) -> void:
	var b := _board(5)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var p1 := _port(sim, "in", 1)
	run.unplug_to_desk(sim, p1.id)  # bit -> desk
	var lay := sim.layout_to_dict()
	var desk := run.desk_to_dict()
	var sim2 := Simulation.new()
	var run2 := LabRun.new()
	run2.level = 5
	run2.build_board(sim2)
	sim2.load_player_layout(lay)
	run2.desk_from_dict(JSON.parse_string(JSON.stringify(desk)), sim2)
	t.check(_port(sim2, "in", 1).device == "", "restore keeps the emptied port empty")
	t.check(run2.desk_inputs == run.desk_inputs, "restore keeps the desk slots (got %s)" % str(run2.desk_inputs))
	t.check(_consistent(sim2, run2), "consistency after restore")
