class_name UpgradeTests
extends RefCounted
## Upgrade gates + upgrade API (JOB P2): the LabRun lane / bus-lane / efficiency gates, the
## Simulation upgrade API (set_machine_lanes / set_machine_efficiency / set_wire_lanes /
## upgrade_preview) and the quest-window rule (LabConfig.quest_window_level, FACTORY_SYSTEMS §4).


static func run(t) -> void:
	_gates(t)
	_machine_lanes(t)
	_wire_lanes(t)
	_preview(t)
	_quest_window(t)


static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	sim.campaign_timing = true
	sim.default_width = 3
	return sim


static func _gates(t) -> void:
	var run := LabRun.new()
	run.level = 0
	t.check(run.max_lanes() == 1, "level 0: max_lanes is 1 (got %d)" % run.max_lanes())
	t.check(run.max_bus_lanes() == 1, "level 0: max_bus_lanes is 1 (got %d)" % run.max_bus_lanes())
	t.check(not run.efficiency_unlocked(), "level 0: efficiency is locked")
	run.level = 5
	t.check(run.max_lanes() == 4, "level 5 (L6): max_lanes is 4 (got %d)" % run.max_lanes())
	t.check(run.max_bus_lanes() == 2, "level 5 (L6): max_bus_lanes is 2 (got %d)" % run.max_bus_lanes())
	run.level = 21
	t.check(run.max_lanes() == 8, "level 21 (L22): max_lanes is 8 (got %d)" % run.max_lanes())
	t.check(run.max_bus_lanes() == 8, "level 21 (L22): max_bus_lanes is 8 (got %d)" % run.max_bus_lanes())
	t.check(run.efficiency_unlocked(), "level 21 (L22): efficiency is unlocked")


static func _machine_lanes(t) -> void:
	var sim := _sim()
	var add := sim.place("add", Vector2i(2, 2), 0, {}, 3)
	var adder := sim.place("adder", Vector2i(8, 2), 0, {}, 3)
	t.check(add != null and adder != null, "Add and Adder place")
	var run := LabRun.new()
	run.level = 0
	sim.mission = run
	# beyond the run's gate (level 0, max 1)
	t.check(not sim.set_machine_lanes(add.id, 4), "beyond the run's gate is refused")
	t.check(sim.last_error == "Unlocks later", "the refusal says 'Unlocks later' (got '%s')" % sim.last_error)
	t.check(add.params.get("lanes", "1") == "1", "a refused upgrade changes nothing")
	# efficiency is gated too
	t.check(not sim.set_machine_efficiency(add.id, true), "efficiency before L22 is refused")
	t.check(sim.last_error == "Unlocks later", "the efficiency refusal says 'Unlocks later' (got '%s')" % sim.last_error)
	# a def with one lane refuses
	t.check(not sim.set_machine_lanes(adder.id, 2), "an Adder (max 1) refuses lanes")
	t.check(sim.last_error == "This machine has one lane", "the refusal says 'This machine has one lane' (got '%s')" % sim.last_error)
	# level 5 (L6): 4 machine lanes
	run.level = 5
	t.check(sim.set_machine_lanes(add.id, 4), "an Add upgrades to 4 lanes at level 5")
	t.check(add.params["lanes"] == "4" and add.lanes() == 4, "params lanes '4' and lanes()==4 (got %s / %d)" % [add.params["lanes"], add.lanes()])
	# level 21 (L22): efficiency unlocks
	run.level = 21
	t.check(sim.set_machine_efficiency(add.id, true), "efficiency applies at L22")
	t.check(add.params["efficiency"] == "efficient" and add.efficient(), "params efficiency is 'efficient'")


static func _wire_lanes(t) -> void:
	var sim := _sim()
	var src := sim.place("usb_input", Vector2i(1, 4), 0, {}, 3)
	var dst := sim.place("add", Vector2i(6, 4), 0, {}, 3)
	var c := sim.connect_ports(src.id, "out", dst.id, "in")
	t.check(c != null, "the wire connects")
	var run := LabRun.new()
	run.level = 0
	sim.mission = run
	t.check(not sim.set_wire_lanes(c.id, 2), "beyond max_bus_lanes (level 0, max 1) is refused")
	t.check(sim.last_error == "Unlocks later", "the refusal says 'Unlocks later' (got '%s')" % sim.last_error)
	t.check(c.lanes == 1, "the refused wire stays at 1 lane")
	run.level = 5
	t.check(sim.set_wire_lanes(c.id, 2), "a wire upgrades to 2 lanes at level 5")
	t.check(c.lanes == 2, "the wire has 2 lanes")


static func _preview(t) -> void:
	var sim := _sim()
	var add := sim.place("add", Vector2i(2, 2), 0, {}, 3)
	t.check(add != null, "Add places")
	var pv := sim.upgrade_preview(add.id, {"lanes": 4})
	t.check(is_equal_approx(float(pv["rate_before"]), 2.5), "rate before is 2.5/s (got %s)" % str(pv["rate_before"]))
	t.check(is_equal_approx(float(pv["rate_after"]), 10.0), "rate after is 10/s (got %s)" % str(pv["rate_after"]))
	t.check(int(pv["power_before"]) == 1 and int(pv["power_after"]) == 4, "power 1 → 4 (got %s → %s)" % [pv["power_before"], pv["power_after"]])
	t.check(int(pv["heat_before"]) == 84 and int(pv["heat_after"]) == 336, "heat 84 → 336 (got %s → %s)" % [pv["heat_before"], pv["heat_after"]])
	t.check(add.params.get("lanes", "1") == "1" and add.lanes() == 1, "the preview changes nothing")


static func _quest_window(t) -> void:
	LabDef.CONFIG.quest_window_level = 15
	var run := LabRun.new()
	run.level = 0
	t.check(run.active_quests() == [0], "level 0: one quest active (got %s)" % str(run.active_quests()))
	run.level = 15
	t.check(run.active_quests() == [15, 16], "level 15 (L16): two quests active (got %s)" % str(run.active_quests()))