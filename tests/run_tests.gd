extends SceneTree
## Headless test runner:  godot --headless --path . -s tests/run_tests.gd
## Exit code 0 = all passed.

var failures := 0
var passes := 0


func _init() -> void:
	# Never touch the player's real save (user://tcl_save.json), whatever a test forgets.
	SaveStore.use_file("user://test_save.json")
	BitVectorTests.run(self)
	SignalGeomTests.run(self)
	RawTests.run(self)
	UsbTests.run(self)
	ContractTests.run(self)
	SaveStoreTests.run(self)
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
	test_move_reroutes_wires()
	test_move_refuses_invalid()
	test_layout_roundtrip()
	test_wrap_carries()
	test_a1_wrong_constant_is_non_fatal()
	test_streak_prevents_accidental_pass()
	test_slice_b()
	test_splitter_and_demux()
	test_save_layout_reloads_and_passes()
	test_save_record_result_keeps_best()
	test_save_unlock_chain()
	test_lab_mode()
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


func test_move_reroutes_wires() -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	var u := sim.place("usb_input", Vector2i(1, 4), 0, {}, 3)
	var a := sim.place("add", Vector2i(6, 4), 0, {}, 3)
	var c := sim.connect_ports(u.id, "out", a.id, "in")
	check(c != null, "wire should connect before the move")
	var old_cells: Array = c.cells.duplicate()
	check(sim.move(a.id, Vector2i(8, 4)), "move to a free cell should succeed")
	check(a.cell == Vector2i(8, 4), "machine cell should update after move, got %s" % a.cell)
	check(sim.connections.has(c.id), "wire should survive the move")
	check(c.cells != old_cells, "wire should be rerouted after the move")
	check(Vector2i(c.cells[c.cells.size() - 1]) == a.port_geom("in")["outside"], "rerouted wire should end at the in port's outside tile, got %s" % c.cells[c.cells.size() - 1])
	var locked := sim.place("output", Vector2i(13, 4), 0, {}, 3)
	locked.locked = true
	check(not sim.move(locked.id, Vector2i(12, 4)), "locked machines refuse move")
	check(locked.cell == Vector2i(13, 4), "locked machine cell is unchanged")


func test_move_refuses_invalid() -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	var a := sim.place("add", Vector2i(2, 2), 0, {}, 3)
	var b := sim.place("multiply", Vector2i(8, 2), 0, {}, 3)
	check(not sim.move(a.id, Vector2i(8, 2)), "moving onto an occupied footprint must be refused")
	check(a.cell == Vector2i(2, 2), "refused move must not change the cell")
	check(not sim.move(b.id, Vector2i(0, -1)), "move outside the board must be refused")
	check(b.cell == Vector2i(8, 2), "out-of-board move must not change the cell")
	check(not sim.move(99, Vector2i(1, 1)), "unknown id must be refused")
	# A move to a valid cell whose wire can no longer be routed drops the wire.
	var u := sim.place("usb_input", Vector2i(1, 6), 0, {}, 3)
	var a2 := sim.place("add", Vector2i(6, 6), 0, {}, 3)
	var c := sim.connect_ports(u.id, "out", a2.id, "in")
	check(c != null, "wire should connect before the drop test")
	sim.place("compare", Vector2i(4, 8), 0, {}, 3)
	sim.place("compare", Vector2i(5, 8), 0, {}, 3)
	# A wire is never silently deleted: a move that would leave a wire unroutable is refused.
	var before: Vector2i = a2.cell
	check(not sim.move(a2.id, Vector2i(6, 8)), "move that would cut a wire is refused")
	check(a2.cell == before, "refused move keeps the machine where it was")
	check(sim.connections.has(c.id), "the wire is kept (never silently dropped)")
	check(sim.last_error.begins_with("Would cut the wire"), "refusal explains itself, got '%s'" % sim.last_error)


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
	# 101+010 no carry, 110+010 and 111+010 carry. The source loops, so the Add may process a
	# 4th value (110 again) before the PASS lands: carries = processed values that overflow.
	var expect := 0
	var cycle := [false, true, true]
	var started: int = (add.processed + (0 if add.job.is_empty() else 1)) if add != null else 0  # carry is computed when a job starts
	for i in started:
		expect += 1 if cycle[i % 3] else 0
	check(add != null and add.carries == expect and add.carries >= 2, "a2 Add carries match the overflowing inputs (%s vs %d)" % [add.carries if add != null else -1, expect])


func _run_with(id: String, setup: Callable, max_ticks := 500) -> Dictionary:
	var sim := Simulation.new()
	var run := MissionRun.new(Missions.by_id(id))
	run.build_board(sim)
	setup.call(sim)
	sim.reset_run()
	while run.status == MissionRun.Status.RUNNING and sim.tick < max_ticks:
		sim.step()
	return {"sim": sim, "run": run}


## Campaign validation is non-fatal: a wrong constant never FAILs, the values are rejected,
## the source keeps looping and the mission simply does not pass.
func test_a1_wrong_constant_is_non_fatal() -> void:
	var r := _run_with("a1_plus_two", func(sim):
		Solutions.build(sim, "a1_plus_two")
		for id in sim.machines:
			if sim.machines[id].type == "add":
				sim.set_param(id, "k", 1))
	var run: MissionRun = r["run"]
	check(run.status == MissionRun.Status.RUNNING, "a1 wrong constant stays RUNNING (non-fatal), got %s" % MissionRun.Status.keys()[run.status])
	check(run.failure.is_empty(), "a1 wrong constant records no failure")
	check(run.rejected_total() > 3, "a1 wrong values are rejected and the source loops (rejected %d)" % run.rejected_total())
	check(run.progress[0] < 3, "a1 wrong constant never completes the 3-value streak (progress %d)" % run.progress[0])
	check(not run.last_ok[0].is_empty(), "a1 records the last arrival for the HUD")
	check(run.accuracy() < 100.0, "a1 accuracy drops with rejected values")


## A wrong machine must not pass by collecting matches across loops: identity on a1 outputs
## 010 011 100 forever; 100 matches expected[0] each loop but the streak always breaks.
func test_streak_prevents_accidental_pass() -> void:
	var r := _run_with("a1_plus_two", func(sim):
		var io := Solutions._io(sim)
		sim.connect_ports(io["in"][0], "out", io["out"][0], "in"))
	check(r["run"].status != MissionRun.Status.PASS, "identity wiring must never pass a1")


func test_slice_b() -> void:
	check(ViewMode.format(Missions.chars("HELLO", 5)[0], ViewMode.Mode.BIN) == "0 0111", "chars(HELLO)[0] is H = 0 0111")
	check(BitVector.of(28, 5).umod(26).equals(BitVector.of(2, 5)), "5-bit 28 % 26 == 2")
	# b3 with only an Add: Z+3 = 28 = ',' is rejected, never passes
	var r := _run_with("b3_caesar", func(sim):
		var io := Solutions._io(sim)
		var a: Machine = sim.place("add", Vector2i(6, 4), 0, {"k": 3})
		sim.connect_ports(io["in"][0], "out", a.id, "in")
		sim.connect_ports(a.id, "out", io["out"][0], "in"))
	var run: MissionRun = r["run"]
	check(run.status != MissionRun.Status.PASS, "b3 without Modulo must not pass")
	check(run.rejected_total() > 0, "b3 without Modulo rejects values")
	var term: Machine = null
	for id in r["sim"].machines:
		if r["sim"].machines[id].type == "terminal_output":
			term = r["sim"].machines[id]
	check(term != null and not term.received.is_empty() and Charset.decode(term.received[0].data) == ",", "b3 Add-only: Z+3 arrives as ','")
	# a 3-bit source cannot feed a 5-bit terminal
	var sim := Simulation.new()
	sim.size = Vector2i(16, 8)
	var src := sim.place("usb_input", Vector2i(1, 3), 0, {}, 3)
	var dst := sim.place("terminal_output", Vector2i(8, 3), 0, {}, 5)
	check(sim.connect_error(src.id, "out", dst.id, "in") == "3-bit output cannot connect to a 5-bit input. Use a width converter.", "terminal width mismatch rejected")
	# determinism
	var d1 := run_mission("b3_caesar")
	var d2 := run_mission("b3_caesar")
	check(d1["log"] == d2["log"] and d1["sim"].tick == d2["sim"].tick, "b3 is deterministic")


# ------------------------------------------------------------------ SaveStore
# The autoload Node is NOT tested headless; only the pure static SaveStore is.

func test_splitter_and_demux() -> void:
	check(Catalog.ticks("demux", true) == 3, "demux campaign dwell should be 3 ticks, got %d" % Catalog.ticks("demux", true))
	check(Catalog.category_of("bit_splitter") == "routing", "conversion machines belong to the routing palette category")
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	sim.default_width = 5
	# bit splitter port widths: hi = W - lo = 2, lo = lo = 3 for W=5, lo=3
	var bs := sim.place("bit_splitter", Vector2i(2, 2), 0, {"lo": 3}, 5)
	check(bs.port_width("in") == 5 and bs.port_width("hi") == 2 and bs.port_width("lo") == 3, "splitter port widths resolve to 5/2/3, got %d/%d/%d" % [bs.port_width("in"), bs.port_width("hi"), bs.port_width("lo")])
	# 10101 through the splitter -> hi 10 (2-bit), lo 101 (3-bit); call the logic directly.
	# Only wired outputs produce a part, so wire both to any-width sinks first.
	var sink_hi := sim.place("usb_output", Vector2i(8, 1), 0, {}, 5)
	var sink_lo := sim.place("usb_output", Vector2i(8, 5), 0, {}, 5)
	sim.connect_ports(bs.id, "hi", sink_hi.id, "in")
	sim.connect_ports(bs.id, "lo", sink_lo.id, "in")
	var p := Packet.new(sim.new_packet_id(), BitVector.from_bin("10101"), sim.tick)
	bs.inq["in"].append(p)
	ComponentLogic.for_type("bit_splitter").start(bs, sim)
	check(not bs.job.is_empty(), "splitter should start a job with both outputs")
	bs.advance(sim)
	var hi: BitVector = bs.outq["hi"].data
	var lo: BitVector = bs.outq["lo"].data
	check(hi.equals(BitVector.of(2, 2)) and lo.equals(BitVector.of(5, 3)), "10101 -> hi 10 (2-bit) and lo 101 (3-bit), got %s / %s" % [hi, lo])
	# only the payload wired: the splitter keeps processing (the unused tag is dropped)
	var sim3 := Simulation.new()
	sim3.size = Vector2i(16, 10)
	sim3.default_width = 5
	sim3.campaign_timing = true
	var src3 := sim3.place("usb_input", Vector2i(0, 2), 0, {}, 5)
	src3.stream = [BitVector.from_bin("10101")]
	src3.loop = true
	src3.interval = 2
	var bs3 := sim3.place("bit_splitter", Vector2i(4, 2), 0, {"lo": 3}, 5)
	var out3 := sim3.place("usb_output", Vector2i(10, 3), 0, {}, 3)
	sim3.connect_ports(src3.id, "out", bs3.id, "in")
	sim3.connect_ports(bs3.id, "lo", out3.id, "in")
	for i in 120:
		sim3.step()
	check(out3.received.size() >= 5 and out3.received[0].data.equals(BitVector.from_bin("101")), "splitter with only LO wired keeps delivering 101 (got %d)" % out3.received.size())
	# set_param(lo) refused while a width-dependent port is wired; applied when unwired
	var sim2 := Simulation.new()
	sim2.size = Vector2i(16, 10)
	sim2.default_width = 5
	var bs2 := sim2.place("bit_splitter", Vector2i(2, 6), 0, {"lo": 3}, 5)
	var dst := sim2.place("output", Vector2i(12, 7), 0, {}, 3)
	var c := sim2.connect_ports(bs2.id, "lo", dst.id, "in")
	check(c != null, "lo port (3-bit) should wire to a 3-bit output")
	check(sim2.set_param(bs2.id, "lo", 4) == false, "set_param(lo) must be refused while lo is wired")
	check(sim2.last_error == "Unwire the ports first — the widths would change", "refusal sets last_error, got '%s'" % sim2.last_error)
	check(bs2.params["lo"] == 3 and sim2.connections.size() == 1, "refused change keeps param and wires")
	sim2.disconnect_wire(c.id)
	check(sim2.set_param(bs2.id, "lo", 4), "set_param(lo) applies once unwired")
	check(bs2.params["lo"] == 4, "param value applied after unwiring")
	check(sim2.set_param(99, "lo", 1) == false, "unknown machine id sets nothing")
	# demux routes by select bit and waits for both inputs
	var da := sim.place("demux", Vector2i(6, 2), 0, {}, 5)
	da.inq["sel"].append(Packet.new(sim.new_packet_id(), BitVector.from_bool(false), sim.tick))
	ComponentLogic.for_type("demux").start(da, sim)
	check(da.job.is_empty(), "demux waits until both inputs are present")
	da.inq["in"].append(Packet.new(sim.new_packet_id(), BitVector.of(7, 5), sim.tick))
	ComponentLogic.for_type("demux").start(da, sim)
	check(da.job.has("results") and da.job["results"].has("a") and not da.job["results"].has("b"), "demux sel=0 routes to a only")
	da.advance(sim)
	check(da.outq["a"] != null and da.outq["a"].data.equals(BitVector.of(7, 5)) and da.outq["b"] == null, "demux sel=0 sends the value to a")
	var db := sim.place("demux", Vector2i(10, 2), 0, {}, 5)
	db.inq["sel"].append(Packet.new(sim.new_packet_id(), BitVector.from_bool(true), sim.tick))
	db.inq["in"].append(Packet.new(sim.new_packet_id(), BitVector.of(9, 5), sim.tick))
	ComponentLogic.for_type("demux").start(db, sim)
	check(db.job.has("results") and db.job["results"].has("b") and not db.job["results"].has("a"), "demux sel=1 routes to b only")
	db.advance(sim)
	check(db.outq["b"] != null and db.outq["b"].data.equals(BitVector.of(9, 5)), "demux sel=1 sends the value to b")

func test_save_layout_reloads_and_passes() -> void:
	SaveStore.use_file("user://test_save.json")
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
	SaveStore.use_file("user://test_save.json")
	SaveStore.clear()
	check(SaveStore.stars("a1_plus_two") == 0, "missing result should read 0 stars")
	SaveStore.record_result("a1_plus_two", 1, 6.0)
	SaveStore.record_result("a1_plus_two", 3, 4.0)
	SaveStore.record_result("a1_plus_two", 2, 9.5)
	check(SaveStore.stars("a1_plus_two") == 3, "record_result keeps the best stars, got %d" % SaveStore.stars("a1_plus_two"))
	SaveStore.record_result("a1_plus_two", 0, 1.0)
	check(SaveStore.stars("a1_plus_two") == 3, "a worse run must not lower the recorded stars")


func test_save_unlock_chain() -> void:
	SaveStore.use_file("user://test_save.json")
	SaveStore.clear()
	check(SaveStore.unlocked("a1_plus_two"), "first campaign mission is always unlocked")
	check(not SaveStore.unlocked("a2_wrap"), "next campaign mission should start locked")
	SaveStore.record_result("a1_plus_two", 1, 5.0)
	check(SaveStore.unlocked("a2_wrap"), "previous mission with >=1 star unlocks the next")
	check(SaveStore.unlocked("boot"), "legacy missions stay available")


# ------------------------------------------------------------------ Lab mode

func _lab_output(sim: Simulation) -> Machine:
	for id in sim.sorted_machine_ids():
		if sim.machines[id].type == "usb_output":
			return sim.machines[id]
	return null


func _lab_source_at(sim: Simulation, cell: Vector2i) -> Machine:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "usb_input" and m.cell == cell:
			return m
	return null


func _lab_log(ticks: int) -> String:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.build_board(sim)
	var src := _lab_source_at(sim, Vector2i(0, 5))
	var out := _lab_output(sim)
	sim.connect_ports(src.id, "out", out.id, "in")
	var log := PackedStringArray()
	for i in ticks:
		sim.step()
		for e in sim.events:
			log.append("%d:%s" % [sim.tick, str(e)])
	return "\n".join(log)


func test_lab_mode() -> void:
	SaveStore.use_file("user://test_save.json")
	SaveStore.clear()
	# --- L1: the socket wired straight to the Contract Drive ---
	var sim := Simulation.new()
	var run := LabRun.new()
	run.build_board(sim)
	check(run.level == 0 and sim.size == Vector2i(20, 12), "lab starts at L1 on a 20x12 board")
	check(Catalog.has("usb_output"), "usb_output is in the catalog")
	var out := _lab_output(sim)
	var src := _lab_source_at(sim, Vector2i(0, 5))
	check(out != null and src != null, "lab starts with a Contract Drive and a USB socket")
	check(src.socket and src.device == "bit", "L1 plugs the Bit module in automatically")
	check(run.request_label() == "deliver 010 × 10", "L1's contract is deliver 010 x10 (got '%s')" % run.request_label())
	var c := sim.connect_ports(src.id, "out", out.id, "in")
	check(c != null and out.port_width("in") == 3, "the drive accepts a 3-bit wire and resolves its width")
	var guard := 0
	while run.level < 1 and guard < 4000:
		sim.step()
		guard += 1
	check(run.level == 1, "L1 completes and advances to L2 (got level %d)" % run.level)
	check(run.unlocked.has("add"), "L2 unlocks Add")

	# --- L2: place an Add k=2 LIVE (no reset) and reach L3 ---
	sim.disconnect_wire(c.id)
	var add := sim.place("add", Vector2i(8, 5), 0, {"k": 2}, 3)
	check(add != null, "Add can be placed in L2")
	sim.connect_ports(src.id, "out", add.id, "in")
	sim.connect_ports(add.id, "out", out.id, "in")
	guard = 0
	while run.level < 2 and guard < 6000:
		sim.step()
		guard += 1
	check(run.level == 2, "L2 completes live and reaches L3 (got level %d)" % run.level)
	check(run.delivered < 20, "delivered resets on level advance")

	# --- L3: wrong values (100) are rejected, never fatal ---
	guard = 0
	while run.rejected < 3 and guard < 2000:
		sim.step()
		guard += 1
	check(run.rejected >= 3, "wrong values are counted as rejected (got %d)" % run.rejected)
	check(run.status == MissionRun.Status.RUNNING, "wrong values never fail the lab")
	check(run.failure.is_empty(), "the lab records no failure")

	# --- L5: the board grows and the drive follows the east edge ---
	var sim4 := Simulation.new()
	var run4 := LabRun.new()
	run4.level = 4
	run4.build_board(sim4)
	check(sim4.size == Vector2i(24, 14), "L5 board grows to 24x14 (got %s)" % sim4.size)
	check(_lab_source_at(sim4, Vector2i(0, 5)) != null, "the socket stays at column 0")
	check(_lab_output(sim4).cell == Vector2i(22, 5), "the drive sits at the L5 east edge")
	check(run4.request_bits().width == 3 and run4.view_mode() == ViewMode.Mode.UDEC, "L5 request is a 3-bit number")

	# --- width "*": the same drive also accepts a 5-bit wire ---
	var sim5 := Simulation.new()
	var run5 := LabRun.new()
	run5.level = 7
	run5.build_board(sim5)
	var out5 := _lab_output(sim5)
	var src5 := _lab_source_at(sim5, Vector2i(0, 5))
	sim5.insert_device(src5.id, "bit")
	var c5 := sim5.connect_ports(src5.id, "out", out5.id, "in")
	check(c5 != null and out5.port_width("in") == 5, "the drive accepts a 5-bit wire and resolves its width")

	# --- save / load round-trip ---
	SaveStore.save_lab({"level": run.level, "delivered": run.delivered, "rejected": run.rejected, "size": [sim.size.x, sim.size.y], "layout": sim.layout_to_dict(), "devices_owned": Array(run.devices_owned())})
	var loaded := SaveStore.load_lab()
	check(int(loaded.get("level", -1)) == run.level, "lab save keeps the level")
	check(loaded.has("devices_owned"), "lab save stores the owned devices")
	var sim2 := Simulation.new()
	var run2 := LabRun.new()
	run2.level = int(loaded["level"])
	run2.build_board(sim2)
	sim2.load_player_layout(loaded["layout"])
	check(sim2.machines.size() == sim.machines.size(), "lab reload keeps every machine")
	check(sim2.connections.size() == sim.connections.size(), "lab reload keeps every wire")
	check(_lab_source_at(sim2, Vector2i(0, 5)) != null, "lab reload rebuilds the socket")
	var has_add := false
	for id in sim2.machines:
		if sim2.machines[id].type == "add":
			has_add = true
	check(has_add, "lab reload restores the player's Add")

	# --- determinism of the first 200 ticks ---
	check(_lab_log(200) == _lab_log(200), "the lab's first 200 ticks are deterministic")

	SaveStore.clear()
