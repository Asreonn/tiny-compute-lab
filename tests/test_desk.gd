class_name DeskTests
extends RefCounted
## Desk zones + quests (docs/SYSTEMS_EXPANSION.md §2.2): every active quest brings its own
## sticks; they lie on the desk or sit in a port; a filled quest is filed by dropping one of its
## sticks into the COMPLETED tray.


static func run(t) -> void:
	_initial(t)
	_plug_swap_unplug(t)
	_refusals(t)
	_outputs(t)
	_new_sticks_arrive(t)
	_save_roundtrip(t)
	_tray(t)
	_two_quests_at_once(t)
	_quest_save(t)
	_old_save_migrates(t)
	_job_sticks(t)


static func _board(level_idx: int, auto := true) -> Array:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = level_idx
	run.auto_file = auto
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
	t.check(run.active_quests() == [0, 1], "two quests are active at once")
	t.check(_port(sim, "in", 1).device == "bit@0" and run.desk_inputs.values() == ["bit@1"], "L1: quest 1's stick is plugged, quest 2's lies on the desk")
	t.check(_port(sim, "out", 1).device == "job@0" and run.desk_outputs.values() == ["job@1"], "quest 1's Job stick is plugged, quest 2's lies on the desk")
	t.check(run.desk_slot_count("in") == 4, "the input desk has owned + 2 slots (got %d)" % run.desk_slot_count("in"))
	var b6 := _board(5)
	var run6: LabRun = b6[1]
	t.check(run6.desk_inputs.values().has("text@5") and run6.desk_inputs.values().has("text@6"), "L6: both active quests' text sticks lie on the desk")
	t.check(_consistent(b6[0], run6), "every stick is in exactly one place (L6)")


static func _plug_swap_unplug(t) -> void:
	var b := _board(5)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var p1 := _port(sim, "in", 1)
	t.check(p1.device == "", "L6 starts with input port 1 empty")
	t.check(run.plug_from_desk(sim, "in", _slot_of(run, "in", "text@5"), p1.id) and p1.device == "text@5", "a desk stick plugs into an open input port")
	var slot6 := _slot_of(run, "in", "text@6")
	t.check(run.plug_from_desk(sim, "in", slot6, p1.id), "a second stick plugs into the occupied port")
	t.check(p1.device == "text@6" and run.desk_inputs.get(slot6, "") == "text@5", "the port's old stick swapped back into that slot")
	t.check(_consistent(sim, run), "consistency after a swap")
	t.check(run.unplug_to_desk(sim, p1.id), "a plugged stick can be unplugged onto the desk")
	t.check(p1.device == "" and run.desk_inputs.values().has("text@6"), "the unplugged stick lies on the desk")
	var from := _slot_of(run, "in", "text@6")
	var free := -1
	for i in run.desk_slot_count("in"):
		if not run.desk_inputs.has(i):
			free = i
	t.check(run.move_on_desk("in", from, free) and run.desk_inputs.get(free, "") == "text@6", "sticks can be moved between desk slots")
	t.check(_consistent(sim, run), "consistency after unplug + move")


static func _refusals(t) -> void:
	var b := _board(7)  # L8 (bit) and L9 (sensor) are active
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var out1 := _port(sim, "out", 1)
	var slot: int = _slot_of(run, "in", "bit@7")
	var before := run.desk_inputs.duplicate()
	t.check(not run.plug_from_desk(sim, "in", slot, out1.id), "an input stick is refused by an output port")
	t.check(run.desk_inputs == before, "a refusal changes nothing")
	# wire rule: a 5-bit wire from the socket to a Bit Splitter refuses the raw sensor stick
	var p1 := _port(sim, "in", 1)
	run.plug_from_desk(sim, "in", _slot_of(run, "in", "bit@7"), p1.id)
	var bs := sim.place("bit_splitter", Vector2i(4, 1), 0, {"lo": 3}, 5)
	var w := sim.connect_ports(p1.id, "out", bs.id, "in")
	var sensor_slot := _slot_of(run, "in", "sensor@8")
	t.check(w != null and not run.plug_from_desk(sim, "in", sensor_slot, p1.id), "the wire rule refuses a raw stick on a bit wire")
	t.check(p1.device == "bit@7" and run.desk_inputs.get(sensor_slot, "") == "sensor@8", "the refused stick stays on the desk")
	t.check(sim.last_error.begins_with("Unplug the wire first"), "the refusal explains itself (got '%s')" % sim.last_error)


static func _outputs(t) -> void:
	var b := _board(8)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	t.check(run.desk_outputs.values().has("monitor") and run.desk_outputs.values().has("job@9"), "L9: the Monitor and quest 10's Job stick lie on the output desk")
	var o2 := _port(sim, "out", 4)
	t.check(run.plug_from_desk(sim, "out", _slot_of(run, "out", "monitor"), o2.id) and o2.device == "monitor", "the Monitor plugs into output port 2")
	t.check(run.unplug_to_desk(sim, _port(sim, "out", 1).id), "a Job drive can be put on the desk")
	t.check(run.desk_outputs.values().has("job@8") and _consistent(sim, run), "the Job stick lies on the desk")


static func _new_sticks_arrive(t) -> void:
	var b := _board(3)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	run._advance(sim)  # quest 4 filed -> quests 5 and 6 are active
	t.check(run.new_devices.has("text@5") and run.desk_inputs.values().has("text@5"), "a newly active quest's stick lands on the desk as New")
	t.check(not run.desk_inputs.values().has("bit@3"), "the filed quest's stick is gone")


static func _save_roundtrip(t) -> void:
	var b := _board(5)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var p1 := _port(sim, "in", 1)
	run.plug_from_desk(sim, "in", _slot_of(run, "in", "text@5"), p1.id)
	var lay := sim.layout_to_dict()
	var desk := run.desk_to_dict()
	var sim2 := Simulation.new()
	var run2 := LabRun.new()
	run2.level = 5
	run2.build_board(sim2)
	sim2.load_player_layout(lay)
	run2.desk_from_dict(JSON.parse_string(JSON.stringify(desk)), sim2)
	t.check(_port(sim2, "in", 1).device == "text@5", "restore keeps the plugged stick")
	t.check(run2.desk_inputs == run.desk_inputs, "restore keeps the desk slots (got %s)" % str(run2.desk_inputs))
	t.check(_consistent(sim2, run2), "consistency after restore")


## The game files quests by hand: a filled quest waits; the tray refuses an unfinished one.
static func _tray(t) -> void:
	var b := _board(0, false)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var p1 := _port(sim, "in", 1)
	var out := _port(sim, "out", 1)
	sim.connect_ports(p1.id, "out", out.id, "in")
	t.check(not run.file_from_port(sim, p1.id) and sim.last_error.begins_with("Not finished yet"), "the tray refuses an unfinished quest (%s)" % sim.last_error)
	sim.reset_run()
	for i in 1200:
		sim.step()
		if run.quest_progress(0).filled:
			break
	t.check(run.quest_progress(0).filled and run.level == 0, "a filled quest waits to be filed")
	t.check(run.file_from_port(sim, p1.id), "dropping its stick in the tray files it")
	t.check(run.level == 1 and run.files == 1 and p1.device == "", "quest 1 is done and its stick is gone")
	t.check(run.active_quests() == [1, 2] and run.desk_inputs.values().has("bit@2"), "the next quest arrives with its stick")


## Two quests at once: each value is judged for the quest its stick stamped, on either drive.
static func _two_quests_at_once(t) -> void:
	var b := _board(1, false)  # L2 (+2) and L3 (+7, wraps) are active
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var p1 := _port(sim, "in", 1)
	var p2 := _port(sim, "in", 4)
	run.plug_from_desk(sim, "in", _slot_of(run, "in", "bit@1"), p1.id)
	run.plug_from_desk(sim, "in", _slot_of(run, "in", "bit@2"), p2.id)
	var o2 := _port(sim, "out", 4)
	run.plug_from_desk(sim, "out", _slot_of(run, "out", "job@2"), o2.id)
	var a2 := sim.place("add", Vector2i(8, 1), 0, {"k": 2}, 3)
	var a7 := sim.place("add", Vector2i(8, 4), 0, {"k": 7}, 3)
	sim.connect_ports(p1.id, "out", a2.id, "in")
	sim.connect_ports(a2.id, "out", _port(sim, "out", 1).id, "in")
	sim.connect_ports(p2.id, "out", a7.id, "in")
	sim.connect_ports(a7.id, "out", o2.id, "in")
	sim.reset_run()
	for i in 2500:
		sim.step()
		if run.quest_progress(1).filled and run.quest_progress(2).filled:
			break
	t.check(run.quest_progress(1).filled and run.quest_progress(2).filled, "both quests fill at the same time")
	t.check(run.quest_progress(1).rejected == 0 and run.quest_progress(2).rejected == 0, "no value was judged for the wrong quest")
	t.check(run.file_from_port(sim, p2.id) and run.level == 1 and run.completed.has(2), "the later quest can be filed first")
	t.check(run.file_from_port(sim, p1.id) and run.level == 3, "filing the earlier one moves on past both")


## Filed-ahead quests and per-quest progress survive a save (the active window decides the board).
static func _quest_save(t) -> void:
	var b := _board(4, false)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	run.quest_progress(5).filled = true
	run.quest_progress(5).delivered = 12
	run.file_quest(sim, 5)
	run.quest_progress(4).delivered = 3
	var d = JSON.parse_string(JSON.stringify(run.quests_to_dict()))
	var sim2 := Simulation.new()
	var run2 := LabRun.new()
	run2.level = run.level
	run2.auto_file = false
	run2.quests_from_dict(d)
	run2.build_board(sim2)
	t.check(run2.active_quests() == [4, 6], "a quest filed ahead stays filed (got %s)" % str(run2.active_quests()))
	t.check(run2.quest_progress(4).delivered == 3 and run2.files == 1, "progress and the filed count come back")
	var all_there := true
	for st in run2.quest_sticks(6):
		all_there = all_there and run2.desk_inputs.values().has(st)
	t.check(all_there and not run2.desk_inputs.values().has(Devices.stick(LabDef.quest_kinds(5)[0], 5)), "the next quest's sticks lie on the desk, the filed one's are gone")


## An old save plugged plain modules: they become the current quest's sticks; spare ones go.
static func _old_save_migrates(t) -> void:
	var b := _board(5, false)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var p1 := _port(sim, "in", 1)
	sim.insert_device(p1.id, "text")
	run.desk_inputs[3] = "number"
	var o1 := _port(sim, "out", 1)
	sim.insert_device(o1.id, "job")
	run.migrate_plain(sim)
	t.check(o1.device == "job@5", "an old plain Job drive becomes the current quest's Job stick (got '%s')" % o1.device)
	t.check(p1.device == "text@5", "a plugged plain module becomes the current quest's stick (got '%s')" % p1.device)
	t.check(not run.desk_inputs.values().has("number") and not run.desk_inputs.values().has("text@5"), "a spare plain module leaves the desk")
	t.check(_consistent(sim, run), "consistency after the migration")


## Each quest's Job stick takes that quest's results only; it is what the player files.
static func _job_sticks(t) -> void:
	var b := _board(0, false)
	var sim: Simulation = b[0]
	var run: LabRun = b[1]
	var p1 := _port(sim, "in", 1)
	var o1 := _port(sim, "out", 1)
	var o2 := _port(sim, "out", 4)
	run.plug_from_desk(sim, "out", _slot_of(run, "out", "job@1"), o2.id)
	sim.connect_ports(p1.id, "out", o2.id, "in")  # quest 1's values into quest 2's Job stick
	sim.reset_run()
	for i in 200:
		sim.step()
	t.check(run.quest_progress(1).delivered == 0 and run.quest_progress(1).rejected > 0, "a Job stick rejects another quest's values")
	t.check(run.quest_progress(0).delivered == 0, "they never count for the quest they came from")
	sim.disconnect_wire(sim.connection_at_port(o2.id, "in").id)
	sim.connect_ports(p1.id, "out", o1.id, "in")
	sim.reset_run()
	for i in 1200:
		sim.step()
		if run.quest_progress(0).filled:
			break
	t.check(run.quest_progress(0).filled, "quest 1's Job stick fills with quest 1's values")
	t.check(run.file_from_port(sim, o1.id), "the filled Job stick goes in the tray")
	t.check(run.files == 1 and o1.device == "" and not run.desk_outputs.values().has("job@0") and p1.device == "", "filing takes all of the quest's sticks")
	t.check(run.desk_outputs.values().has("job@2"), "the next quest's Job stick lands on the output desk")
