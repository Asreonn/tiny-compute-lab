extends SceneTree
## Headless test runner:  godot --headless --path . -s tests/run_tests.gd
## Exit code 0 = all passed.

var failures := 0
var passes := 0


func _init() -> void:
	BitVectorTests.run(self)
	SignalGeomTests.run(self)
	test_all_missions_pass()
	test_determinism()
	test_wrong_constant_fails_with_reason()
	test_traffic_without_buffer_overflows()
	test_single_processor_cannot_keep_up()
	test_gate_without_control_stalls_with_reason()
	test_width_mismatch_rejected()
	test_set_width_disconnects()
	test_router_straight_and_blocked()
	test_rotation_moves_ports()
	test_layout_roundtrip()
	test_wrap_carries()
	test_a1_wrong_constant_fails()
	test_save_layout_reloads_and_passes()
	test_save_record_result_keeps_best()
	test_save_unlock_chain()
	SaveStore.clear()
	print("\n%d passed, %d failed" % [passes, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		printerr("FAIL: " + what)


func run_mission(id: String, build := true, max_ticks := 2000) -> Dictionary:
	var sim := Simulation.new()
	var run := MissionRun.new(Missions.by_id(id))
	run.build_board(sim)
	if build:
		Solutions.build(sim, id)
	sim.reset_run()
	var log := PackedStringArray()
	while run.status == MissionRun.Status.RUNNING and sim.tick < max_ticks:
		sim.step()
		for e in sim.events:
			log.append("%d:%s" % [sim.tick, str(e)])
	return {"sim": sim, "run": run, "log": log}


func test_all_missions_pass() -> void:
	for m in Missions.all() + Missions.legacy():
		var r := run_mission(m.id)
		var run: MissionRun = r["run"]
		var sim: Simulation = r["sim"]
		var ok := run.status == MissionRun.Status.PASS
		check(ok, "mission %s should PASS with reference solution; got %s %s" % [m.id, MissionRun.Status.keys()[run.status], run.failure])
		if ok:
			print("  %-10s PASS  ticks=%-4d thr=%.1f/s lat=%.1f pow=%d comps=%d stars=%d" % [m.id, sim.tick, sim.throughput(), sim.avg_latency(), sim.total_power(), sim.component_count(), run.stars(sim)])


func test_determinism() -> void:
	for id in ["a1_plus_two", "a2_wrap", "pipeline", "filter", "parallel", "optimize"]:
		var a := run_mission(id)
		var b := run_mission(id)
		check(a["log"] == b["log"] and a["sim"].tick == b["sim"].tick, "mission %s must be deterministic" % id)


func test_wrong_constant_fails_with_reason() -> void:
	var sim := Simulation.new()
	var run := MissionRun.new(Missions.by_id("pipeline"))
	run.build_board(sim)
	Solutions.build(sim, "pipeline")
	for id in sim.machines:
		if sim.machines[id].type == "add":
			sim.set_param(id, "k", 4)
	sim.reset_run()
	while run.status == MissionRun.Status.RUNNING and sim.tick < 500:
		sim.step()
	check(run.status == MissionRun.Status.FAIL, "wrong constant should FAIL")
	check(run.failure.get("title") == "Wrong value", "failure should be 'Wrong value', got %s" % run.failure.get("title"))
	check(run.failure.get("expected") == "7" and run.failure.get("received") == "6", "expected 7 / received 6, got %s / %s" % [run.failure.get("expected"), run.failure.get("received")])
	check(run.failure.get("path", PackedStringArray()).size() >= 3, "failure should carry the packet path")


func test_traffic_without_buffer_overflows() -> void:
	var sim := Simulation.new()
	var run := MissionRun.new(Missions.by_id("traffic"))
	run.build_board(sim)
	var io := Solutions._io(sim)
	var m := sim.place("multiply", Vector2i(5, 3), 0, {"k": 3})
	sim.connect_ports(io["in"][0], "out", m.id, "in")
	sim.connect_ports(m.id, "out", io["out"][0], "in")
	sim.reset_run()
	while run.status == MissionRun.Status.RUNNING and sim.tick < 500:
		sim.step()
	check(run.status == MissionRun.Status.FAIL and run.failure.get("title") == "Input overflow", "traffic without buffer should overflow, got %s" % run.failure)


func test_single_processor_cannot_keep_up() -> void:
	var sim := Simulation.new()
	var run := MissionRun.new(Missions.by_id("parallel"))
	run.build_board(sim)
	var io := Solutions._io(sim)
	var p := sim.place("processor", Vector2i(8, 5))
	sim.connect_ports(io["in"][0], "out", p.id, "in")
	sim.connect_ports(p.id, "out", io["out"][0], "in")
	sim.reset_run()
	while run.status == MissionRun.Status.RUNNING and sim.tick < 800:
		sim.step()
	check(run.status == MissionRun.Status.FAIL and run.failure.get("title") == "Input overflow", "single processor should overflow, got %s" % run.failure)
	check(sim.bottleneck() != null and sim.bottleneck().type == "processor", "bottleneck should be the processor")


func test_gate_without_control_stalls_with_reason() -> void:
	var sim := Simulation.new()
	var run := MissionRun.new(Missions.by_id("filter"))
	run.build_board(sim)
	var io := Solutions._io(sim)
	var g := sim.place("gate", Vector2i(7, 4))
	sim.connect_ports(io["in"][0], "out", g.id, "in")
	sim.connect_ports(g.id, "out", io["out"][0], "in")
	sim.reset_run()
	while run.status == MissionRun.Status.RUNNING and sim.tick < 800:
		sim.step()
	check(run.status == MissionRun.Status.FAIL, "gate without control should fail")
	check(str(run.failure.get("reason", "")).contains("control signal"), "reason should mention the control signal, got %s" % run.failure.get("reason"))


func test_width_mismatch_rejected() -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	var u := sim.place("usb_input", Vector2i(1, 2), 0, {}, 3)
	var a := sim.place("add", Vector2i(6, 2), 0, {}, 5)
	var err := sim.connect_error(u.id, "out", a.id, "in")
	check(err == "3-bit output cannot connect to a 5-bit input. Use a width converter.", "3→5 must be rejected with the exact message, got '%s'" % err)
	check(sim.connect_ports(u.id, "out", a.id, "in") == null, "mismatched wire must not be created")
	var c := sim.place("compare", Vector2i(1, 6), 0, {}, 3)
	var b := sim.place("add", Vector2i(6, 6), 0, {}, 3)
	var err2 := sim.connect_error(c.id, "out", b.id, "in")
	check(err2 == "1-bit output cannot connect to a 3-bit input. Use a width converter.", "1→3 must be rejected, got '%s'" % err2)


func test_set_width_disconnects() -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	var u := sim.place("usb_input", Vector2i(1, 4), 0, {}, 3)
	var a := sim.place("add", Vector2i(9, 4), 0, {}, 3)
	var c := sim.connect_ports(u.id, "out", a.id, "in")
	check(c != null, "matching-width wire should connect")
	var removed := sim.set_width(a.id, 5)
	check(removed.size() == 1 and removed[0] == c.id, "set_width should report the removed wire, got %s" % [removed])
	check(sim.connections.is_empty(), "mismatched wire should be disconnected")
	check(a.port_width("in") == 5 and a.port_width("out") == 5, "instance width resolves on 'W' ports")
	check(sim.set_width(a.id, 0).is_empty() and a.width == 5, "out-of-range width is refused")
	var locked := sim.place("output", Vector2i(13, 4), 0, {}, 3)
	locked.locked = true
	check(sim.set_width(locked.id, 4).is_empty() and locked.width == 3, "locked machine width is refused")


func test_router_straight_and_blocked() -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	var a := sim.place("add", Vector2i(1, 4), 0, {}, 3)
	var b := sim.place("add", Vector2i(10, 4), 0, {}, 3)
	var r := sim.route_between(a.id, "out", b.id, "in")
	check(r["ok"] and r["cells"].size() == 7, "straight route should be 7 tiles, got %s" % [r["cells"]])
	sim.place("buffer", Vector2i(5, 4), 0, {}, 3)
	var r2 := sim.route_between(a.id, "out", b.id, "in")
	check(r2["ok"] and r2["cells"].size() > 7, "route should detour around an obstacle")
	var turns := 0
	var cells: Array = r2["cells"]
	for k in range(1, cells.size() - 1):
		if (cells[k] - cells[k - 1]) != (cells[k + 1] - cells[k]):
			turns += 1
	check(turns <= 4, "detour should use few turns, used %d" % turns)


func test_rotation_moves_ports() -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	var m := sim.place("multiply", Vector2i(4, 4), 0, {}, 3)
	check(m.port_geom("out")["side"] == Catalog.Side.E, "unrotated output faces east")
	sim.rotate(m.id)
	var g := m.port_geom("out")
	check(g["side"] == Catalog.Side.S and g["cell"] == Vector2i(4, 5), "rotated output faces south at (4,5), got %s" % g)
	check(Catalog.size_of("multiply", 1) == Vector2i(1, 2), "rotated M footprint is 1×2")


func test_layout_roundtrip() -> void:
	var r := run_mission("a1_plus_two")
	var sim: Simulation = r["sim"]
	var d := sim.layout_to_dict()
	var sim2 := Simulation.new()
	var run2 := MissionRun.new(Missions.by_id("a1_plus_two"))
	run2.build_board(sim2)
	sim2.load_player_layout(d)
	check(sim2.machines.size() == sim.machines.size() and sim2.connections.size() == sim.connections.size(), "layout round-trip keeps machines and wires")
	var widths_match := true
	for id in sim2.machines:
		if not sim2.machines[id].locked:
			widths_match = widths_match and sim2.machines[id].width == 3
	check(widths_match, "layout round-trip preserves width")
	sim2.reset_run()
	while run2.status == MissionRun.Status.RUNNING and sim2.tick < 2000:
		sim2.step()
	check(run2.status == MissionRun.Status.PASS, "reloaded layout still passes")


func test_wrap_carries() -> void:
	var r := run_mission("a2_wrap")
	var sim: Simulation = r["sim"]
	var add: Machine = null
	for id in sim.machines:
		if sim.machines[id].type == "add":
			add = sim.machines[id]
	check(add != null, "a2 should have an Add")
	check(add != null and add.carries == 2, "a2 Add carries should be 2, got %s" % [add.carries if add != null else -1])


func test_a1_wrong_constant_fails() -> void:
	var sim := Simulation.new()
	var run := MissionRun.new(Missions.by_id("a1_plus_two"))
	run.build_board(sim)
	Solutions.build(sim, "a1_plus_two")
	for id in sim.machines:
		if sim.machines[id].type == "add":
			sim.set_param(id, "k", 1)
	sim.reset_run()
	while run.status == MissionRun.Status.RUNNING and sim.tick < 500:
		sim.step()
	check(run.status == MissionRun.Status.FAIL, "a1 wrong constant should FAIL")
	check(run.failure.get("title") == "Wrong value", "a1 failure should be 'Wrong value', got %s" % run.failure.get("title"))
	check(run.failure.get("expected") == "100" and run.failure.get("received") == "011", "a1 expected 100 / received 011, got %s / %s" % [run.failure.get("expected"), run.failure.get("received")])
	check(run.failure.get("expected_bits") == "100" and run.failure.get("received_bits") == "011", "a1 BIN failure keys, got %s / %s" % [run.failure.get("expected_bits"), run.failure.get("received_bits")])


# ------------------------------------------------------------------ SaveStore
# The autoload Node is NOT tested headless; only the pure static SaveStore is.

func test_save_layout_reloads_and_passes() -> void:
	SaveStore.set_path("user://test_save.json")
	SaveStore.clear()
	var r := run_mission("a1_plus_two")
	var sim: Simulation = r["sim"]
	SaveStore.save_layout("a1_plus_two", sim.layout_to_dict())
	var loaded := SaveStore.load_layout("a1_plus_two")
	check(not loaded.is_empty(), "saved layout should reload from disk")
	var sim2 := Simulation.new()
	var run2 := MissionRun.new(Missions.by_id("a1_plus_two"))
	run2.build_board(sim2)
	sim2.load_player_layout(loaded)
	check(sim2.machines.size() == sim.machines.size() and sim2.connections.size() == sim.connections.size(), "save round-trip keeps machines and wires")
	sim2.reset_run()
	while run2.status == MissionRun.Status.RUNNING and sim2.tick < 2000:
		sim2.step()
	check(run2.status == MissionRun.Status.PASS, "layout reloaded from SaveStore still passes a1_plus_two")


func test_save_record_result_keeps_best() -> void:
	SaveStore.set_path("user://test_save.json")
	SaveStore.clear()
	check(SaveStore.stars("a1_plus_two") == 0, "missing result should read 0 stars")
	SaveStore.record_result("a1_plus_two", 1, 6.0)
	SaveStore.record_result("a1_plus_two", 3, 4.0)
	SaveStore.record_result("a1_plus_two", 2, 9.5)
	check(SaveStore.stars("a1_plus_two") == 3, "record_result keeps the best stars, got %d" % SaveStore.stars("a1_plus_two"))
	SaveStore.record_result("a1_plus_two", 0, 1.0)
	check(SaveStore.stars("a1_plus_two") == 3, "a worse run must not lower the recorded stars")


func test_save_unlock_chain() -> void:
	SaveStore.set_path("user://test_save.json")
	SaveStore.clear()
	check(SaveStore.unlocked("a1_plus_two"), "first campaign mission is always unlocked")
	check(not SaveStore.unlocked("a2_wrap"), "next campaign mission should start locked")
	SaveStore.record_result("a1_plus_two", 1, 5.0)
	check(SaveStore.unlocked("a2_wrap"), "previous mission with >=1 star unlocks the next")
	check(SaveStore.unlocked("boot"), "legacy missions stay available")
