class_name PowerIntegrationTests
extends RefCounted
## P5b acceptance tests: the PowerNetwork wired into Simulation (via a tiny stub mission) and
## into the Lab (locked fixtures, reservations, save round trip).

const SPLIT_MSG := "Copper splits only at a Distribution Board"


## A tiny mission that drives Simulation.step() without a LabRun.
class StubMission:
	extends RefCounted
	var cap := 0
	var onboard := 0
	var use_net := false
	var status = MissionRun.Status.RUNNING
	func power_capacity() -> int:
		return cap
	func uses_power_network() -> bool:
		return use_net
	func onboard_capacity() -> int:
		return onboard
	func allows(_type: String) -> bool:
		return true
	func reset(_sim: Simulation) -> void:
		pass
	func on_output(_sim: Simulation, _m: Machine, _p: Packet) -> void:
		pass
	func on_overflow(_sim: Simulation, _m: Machine, _p: Packet) -> void:
		pass
	func after_tick(_sim: Simulation) -> void:
		pass


static func run(t) -> void:
	_old_brownout(t)
	_onboard(t)
	_rail_and_onboard(t)
	_placement_t(t)
	_lab_fixtures(t)
	_save_round_trip(t)


static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(40, 22)
	sim.campaign_timing = true
	sim.default_width = 3
	return sim


## Without uses_power_network the old global brownout keeps working: cap 16 over 20 demand.
static func _old_brownout(t) -> void:
	var sim := _sim()
	var adds: Array[Machine] = []
	for i in 5:
		adds.append(sim.place("add", Vector2i(2 + i * 4, 2), 0, {"k": 1, "lanes": "4"}, 3))
	var mission := StubMission.new()
	mission.cap = 16
	mission.use_net = false
	sim.mission = mission
	sim.step()
	t.check(sim.power_net == null, "no network without uses_power_network")
	for a in adds:
		t.check(sim.work_rate(a) == 9, "global brownout 16/20 caps the rate at 9 (got %d)" % sim.work_rate(a))


## With the network and no copper, onboard 8 over 12 Adds caps the rate at 8.
static func _onboard(t) -> void:
	var sim := _sim()
	var adds: Array[Machine] = []
	for i in 12:
		adds.append(sim.place("add", Vector2i(2 + (i % 6) * 4, 2 + (i / 6) * 4), 0, {"k": 1}, 3))
	var mission := StubMission.new()
	mission.cap = 32
	mission.onboard = 8
	mission.use_net = true
	sim.mission = mission
	sim.step()
	t.check(sim.power_net != null, "the network is built from the mission")
	for a in adds:
		t.check(sim.work_rate(a) == 8, "onboard 8 over 12 caps the rate at 8 (got %d)" % sim.work_rate(a))
	t.check(sim.overloaded(), "an over stage makes the run overloaded")


## A basic controller + rail feeds 6 Adds at the rail's limit; the rest stay on onboard.
static func _rail_and_onboard(t) -> void:
	var sim := _sim()
	sim.place("power_controller", Vector2i(1, 10), 0, {"tier": "basic"}, 3)
	for x in range(3, 15):
		sim.place("power_rail", Vector2i(x, 10), 0, {}, 3)
	var rail: Array[Machine] = []
	for x in [4, 6, 8, 10, 12, 14]:
		rail.append(sim.place("add", Vector2i(x, 9), 0, {"k": 1, "lanes": "4"}, 3))
	var onboard: Array[Machine] = []
	for i in 3:
		onboard.append(sim.place("add", Vector2i(2 + i * 4, 2), 0, {"k": 1}, 3))
	var mission := StubMission.new()
	mission.cap = 32
	mission.onboard = 8
	mission.use_net = true
	sim.mission = mission
	sim.step()
	for a in rail:
		t.check(sim.power_net.feeder_of(a.id) != "onboard", "rail-fed Add is on the chain")
		t.check(sim.work_rate(a) == 8, "rail 16 over 24 caps the rate at 8 (got %d)" % sim.work_rate(a))
	for a in onboard:
		t.check(sim.power_net.feeder_of(a.id) == "onboard", "unwired Add stays on onboard")
		t.check(sim.work_rate(a) == 12, "onboard 8 covers 3 Adds: no slowdown (got %d)" % sim.work_rate(a))


## Copper never T-joins: the simulation refuses the tile through PowerNetwork.placement_error.
static func _placement_t(t) -> void:
	var sim := _sim()
	sim.place("power_rail", Vector2i(5, 5), 0, {}, 3)
	sim.place("power_rail", Vector2i(5, 6), 0, {}, 3)
	sim.place("power_rail", Vector2i(5, 7), 0, {}, 3)
	t.check(sim.placement_error("power_rail", Vector2i(4, 6), 0) == SPLIT_MSG, "a T junction is refused")
	t.check(sim.placement_error("power_rail", Vector2i(3, 6), 0) == "", "an extension that keeps a line is fine")
	t.check(sim.placement_error("add", Vector2i(10, 10), 0) == "", "non-copper types are not checked")


## At/above the power level the board carries the locked fixtures; below it the tiles are sealed.
static func _lab_fixtures(t) -> void:
	var row := LabDef.CONFIG.power_input_row
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = LabDef.CONFIG.power_level
	run.build_board(sim)
	var input: Machine = null
	var ctrl: Machine = null
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "power_input":
			input = m
		elif m.type == "power_controller":
			ctrl = m
	t.check(input != null and input.locked and input.cell == Vector2i(0, row), "power input fixture at (0, %d)" % row)
	t.check(ctrl != null and ctrl.locked and ctrl.cell == Vector2i(2, row), "power controller fixture at (2, %d)" % row)
	t.check(str(ctrl.params.get("tier", "")) == run.controller_tier(), "controller tier matches the level")
	# below the power level the tiles are reserved
	var sim2 := Simulation.new()
	var run2 := LabRun.new()
	run2.level = LabDef.CONFIG.power_level - 1
	run2.build_board(sim2)
	for c in [Vector2i(0, row), Vector2i(1, row), Vector2i(2, row), Vector2i(3, row), Vector2i(2, row + 1), Vector2i(3, row + 1)]:
		t.check(sim2.reserved.has(c), "power tiles reserved before the PSU (%s)" % c)
	t.check(sim2.placement_error("add", Vector2i(0, row), 0) != "", "reserved power tiles refuse placement")
	# tier progression
	var run3 := LabRun.new()
	run3.level = LabDef.CONFIG.power_level + 1
	t.check(run3.controller_tier() == "basic", "L%d controller tier is basic" % (LabDef.CONFIG.power_level + 2))


## layout_to_dict / load_player_layout keep the fixtures matched, never duplicated.
static func _save_round_trip(t) -> void:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = LabDef.CONFIG.power_level
	run.build_board(sim)
	var d := sim.layout_to_dict()
	var sim2 := Simulation.new()
	var run2 := LabRun.new()
	run2.level = LabDef.CONFIG.power_level
	run2.build_board(sim2)
	sim2.load_player_layout(d)
	var count := func(s: Simulation) -> int:
		var n := 0
		for id in s.sorted_machine_ids():
			if s.machines[id].type in ["power_input", "power_controller"]:
				n += 1
		return n
	t.check(count.call(sim) == 2 and count.call(sim2) == 2, "fixtures survive the round trip without duplication (got %d -> %d)" % [count.call(sim), count.call(sim2)])