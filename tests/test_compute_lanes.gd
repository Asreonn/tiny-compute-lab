class_name ComputeLaneTests
extends RefCounted
## JOB P1b acceptance tests: parallel job lanes on machines (FACTORY_SYSTEMS §3). A Machine runs
## up to lanes() jobs at once; power/heat scale with lanes, width and the Efficiency setting,
## and at lanes 1 / standard / widths ≤ 5 everything behaves exactly as before.


static func run(t) -> void:
	_throughput(t)
	_four_finish_together(t)
	_stall_on_blocked_output(t)
	_power_demand_table(t)
	_heat(t)
	_processing_ticks(t)
	_lanes_clamp(t)
	_catalog_params(t)
	_save_round_trip(t)


## A campaign-timing 20x12 board with no mission and a 3-bit default width.
static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	sim.campaign_timing = true
	sim.default_width = 3
	return sim


## A buffer-free source that offers one 3-bit value every tick.
static func _source(sim: Simulation) -> Machine:
	var s := sim.place("usb_input", Vector2i(0, 2), 0, {}, 3)
	s.stream = [BitVector.of(1, 3)]
	s.loop = true
	s.interval = 1
	return s


## Outputs the wire-fed pipeline (source -> Add -> plain Output) produces in the 40 ticks that
## follow a 10-tick warm-up, at the given lane count on the Add and both wires.
static func _throughput_40(t, lanes: int) -> int:
	var sim := _sim()
	var s := _source(sim)
	var a := sim.place("add", Vector2i(3, 2), 0, {"k": 1, "lanes": str(lanes)}, 3)
	var o := sim.place("output", Vector2i(6, 2), 0, {}, 3)
	var w1 := sim.connect_ports(s.id, "out", a.id, "in")
	var w2 := sim.connect_ports(a.id, "out", o.id, "in")
	if w1 == null or w2 == null:
		t.check(false, "throughput rig fails to wire (source %d, add %d, output %d)" % [s.id, a.id, o.id])
		return -1
	sim.set_wire_lanes(w1.id, lanes)
	sim.set_wire_lanes(w2.id, lanes)
	for i in 10:
		sim.step()  # warm-up: fill the pipeline
	var before := sim.outputs_total
	for i in 40:
		sim.step()
	return sim.outputs_total - before


static func _throughput(t) -> void:
	var four := _throughput_40(t, 4)
	t.check(four >= 36, "a warmed-up 4-lane Add delivers ~1 value/tick (got %d in 40 ticks)" % four)
	var one := _throughput_40(t, 1)
	t.check(one >= 8, "a warmed-up 1-lane Add delivers ~1/4 value/tick (got %d in 40 ticks)" % one)


## Four jobs that start together finish in the same tick: a 4-value burst fills all lanes, and
## after the 4-tick campaign dwell every lane completes at once.
static func _four_finish_together(t) -> void:
	var sim := _sim()
	var a := sim.place("add", Vector2i(4, 2), 0, {"k": 1, "lanes": "4"}, 3)
	for i in 4:
		a.inq["in"].append(Packet.new(sim.new_packet_id(), BitVector.of(i + 1, 3), 0))
	for i in 5:
		sim.step()
	t.check(a.processed == 4 and a.jobs.is_empty(), "4 lanes finish together after their dwell (processed %d, %d running)" % [a.processed, a.jobs.size()])
	t.check(a.waiting_results() == 4 and a.outq["out"] != null and a.out_backlog["out"].size() == 3, "the 4 results wait behind one head (waiting %d, backlog %d)" % [a.waiting_results(), a.out_backlog["out"].size()])


## Back-pressure stays physical: a 2-lane Add whose output has no wire holds at most lanes()
## results, runs nothing, and accepts no new job.
static func _stall_on_blocked_output(t) -> void:
	var sim := _sim()
	var a := sim.place("add", Vector2i(4, 2), 0, {"k": 1, "lanes": "2"}, 3)
	for i in 3:
		a.inq["in"].append(Packet.new(sim.new_packet_id(), BitVector.of(i + 1, 3), 0))
	for i in 24:
		sim.step()
	t.check(a.jobs.is_empty(), "a blocked 2-lane Add runs no jobs (got %d running)" % a.jobs.size())
	t.check(a.waiting_results() == 2, "a blocked 2-lane Add holds exactly 2 results (got %d)" % a.waiting_results())
	t.check(not a.has_free_lane(), "no free lane while the output is blocked")
	t.check(a.inq["in"].size() == 1, "the extra input stays queued, never started (got %d)" % a.inq["in"].size())


static func _power_demand_table(t) -> void:
	var sim := _sim()
	var a3 := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	t.check(a3.power_demand() == 1, "Add 1 lane / normal / 3-bit draws 1 (got %d)" % a3.power_demand())
	a3.params["lanes"] = "4"
	t.check(a3.power_demand() == 4, "4-lane Add draws 4 (got %d)" % a3.power_demand())
	a3.params["efficiency"] = "efficient"
	t.check(a3.power_demand() == 3, "4-lane efficient Add draws 3 (got %d)" % a3.power_demand())
	var a8 := sim.place("add", Vector2i(8, 2), 0, {"k": 1}, 8)
	t.check(a8.power_demand() == 2, "8-bit Add draws 2 (width factor 2, got %d)" % a8.power_demand())
	var af := sim.place("add", Vector2i(14, 2), 0, {"k": 1, "clock": "fast"}, 3)
	t.check(af.power_demand() == 2, "fast Add draws 2 (got %d)" % af.power_demand())
	var mo := sim.place("multiply", Vector2i(2, 8), 0, {"k": 2, "clock": "overclocked"}, 3)
	t.check(mo.power_demand() == 4, "overclocked Multiply draws 4 (got %d)" % mo.power_demand())


static func _heat(t) -> void:
	var base := Catalog.heat("add")
	var sim := _sim()
	var a8 := sim.place("add", Vector2i(6, 6), 0, {"k": 1}, 8)
	t.check(a8.heat() == base * 2, "8-bit Add makes 2x the base heat (%d != %d)" % [a8.heat(), base * 2])
	a8.params["efficiency"] = "efficient"
	t.check(a8.heat() == base, "efficient halves the width-scaled heat (%d != %d)" % [a8.heat(), base])
	t.check(Catalog.width_factor(5) == 1 and Catalog.width_factor(6) == 2 and Catalog.width_factor(16) == 3 and Catalog.width_factor(32) == 4 and Catalog.width_factor(64) == 6, "width factors: 1/2/3/4/6 at 5/6/16/32/64")


static func _processing_ticks(t) -> void:
	var sim := _sim()
	var a := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	t.check(a.processing_ticks() == Catalog.ticks("add", true), "a standard Add keeps its campaign dwell")
	a.params["efficiency"] = "efficient"
	t.check(a.processing_ticks() == Catalog.ticks("add", true) + 1, "an efficient Add takes one tick longer (got %d)" % a.processing_ticks())


static func _lanes_clamp(t) -> void:
	var sim := _sim()
	var sp := sim.place("splitter", Vector2i(2, 4), 0, {"lanes": "8"}, 3)
	t.check(sp.lanes() == 4, "lanes '8' clamps to a splitter's max_lanes 4 (got %d)" % sp.lanes())
	var ad := sim.place("adder", Vector2i(8, 4), 0, {"lanes": "8"}, 3)
	t.check(ad.lanes() == 1, "lanes '8' clamps to an adder's max_lanes 1 (got %d)" % ad.lanes())
	var junk := sim.place("add", Vector2i(14, 4), 0, {"lanes": "3"}, 3)
	t.check(junk.lanes() == 2, "lanes '3' snaps down to the allowed set 2 (got %d)" % junk.lanes())
	var four := sim.place("add", Vector2i(2, 8), 0, {"lanes": "4"}, 3)
	t.check(four.mk() == 3 and sp.mk() == 3 and ad.mk() == 1, "mk() labels: 4 lanes -> Mk3, 1 lane -> Mk1")


static func _catalog_params(t) -> void:
	var add: Dictionary = Catalog.def("add")
	t.check(add["params"].has("lanes") and add["params"]["lanes"]["options"] == ["1", "2", "4", "8"], "add has a Lanes param with all four options (%s)" % str(add["params"].get("lanes", {})))
	t.check(add["params"].has("efficiency") and add["params"]["efficiency"]["default"] == "standard", "powered machines get an Efficiency param")
	var sp: Dictionary = Catalog.def("splitter")
	t.check(sp["params"]["lanes"]["options"] == ["1", "2", "4"], "splitter's Lanes options stop at 4 (%s)" % str(sp["params"]["lanes"]["options"]))
	t.check(not Catalog.def("adder")["params"].has("lanes"), "the Adder (max_lanes 1) has no Lanes param")
	t.check(not Catalog.def("heatsink")["params"].has("efficiency"), "a powerless machine has no Efficiency param")
	t.check(int(add["max_lanes"]) == 8 and int(sp["max_lanes"]) == 4, "the defs carry max_lanes (add %s, splitter %s)" % [add["max_lanes"], sp["max_lanes"]])


static func _save_round_trip(t) -> void:
	var sim := _sim()
	var a := sim.place("add", Vector2i(4, 2), 0, {"k": 1, "lanes": "4", "efficiency": "efficient"}, 3)
	var d := sim.layout_to_dict()
	var sim2 := Simulation.new()
	sim2.size = sim.size
	sim2.load_player_layout(d)
	var a2: Machine = sim2.machines.values()[0] if not sim2.machines.is_empty() else null
	t.check(a2 != null, "the layout reloads the machine")
	t.check(a2 != null and a2.params.get("lanes", "") == "4" and a2.params.get("efficiency", "") == "efficient", "save round-trip keeps lanes/efficiency (%s)" % (a2.params if a2 != null else "-"))
	t.check(a2 != null and a2.lanes() == 4 and a2.efficient(), "the reloaded machine behaves as 4-lane efficient")