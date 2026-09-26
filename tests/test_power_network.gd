class_name PowerNetworkTests
extends RefCounted
## P5a acceptance tests: the pure PowerNetwork module — copper chains, the controller, boards,
## pads and the single tightest bottleneck. No Simulation integration yet: every case builds a
## plain Simulation and calls PowerNetwork.build() directly.

const SPLIT_MSG := "Copper splits only at a Distribution Board"


static func run(t) -> void:
	_onboard(t)
	_rail_chain(t)
	_heavy_rail_and_ctrl_tier(t)
	_board(t)
	_copper_t(t)
	_pads(t)
	_determinism(t)


static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(40, 22)
	sim.campaign_timing = true
	return sim


## No controller: every machine is fed by onboard; its cap 8 over 12 Adds caps the rate.
static func _onboard(t) -> void:
	var sim := _sim()
	var adds: Array[Machine] = []
	for i in 12:
		adds.append(sim.place("add", Vector2i(2 + (i % 6) * 4, 2 + (i / 6) * 4), 0, {"k": 1}, 3))
	var pn := PowerNetwork.build(sim, 32, 8)
	for a in adds:
		t.check(pn.feeder_of(a.id) == "onboard", "no controller -> onboard")
		t.check(pn.work_rate(a.id, 12) == 8, "onboard 8 over 12 demand caps the rate at 8 (got %d)" % pn.work_rate(a.id, 12))
	t.check(pn.state("onboard") == "over" and pn.state("source") == "normal", "onboard is over, source is not")
	t.check(pn.nodes["ctrl"]["cap"] == 0 and pn.nodes["ctrl"]["live"], "without a controller ctrl is unlimited and live")
	t.check(pn.bottleneck(adds[0].id) == {"node": "onboard", "cap": 8, "load": 12}, "the onboard stage is the bottleneck")
	t.check(pn.path(adds[0].id) == [
		{"node": "source", "cap": 32, "load": 12},
		{"node": "ctrl", "cap": 0, "load": 12},
		{"node": "onboard", "cap": 8, "load": 12},
	], "the path is source -> ctrl -> onboard")


## A basic controller (32) feeds one rail chain; the chain's 16 cap over 20 demand is the
## bottleneck for every Add on it.
static func _rail_chain(t) -> void:
	var sim := _sim()
	sim.place("power_controller", Vector2i(1, 10), 0, {"tier": "basic"}, 3)
	for x in range(3, 13):
		sim.place("power_rail", Vector2i(x, 10), 0, {}, 3)
	var adds: Array[Machine] = []
	for x in [4, 6, 8, 10, 12]:
		adds.append(sim.place("add", Vector2i(x, 9), 0, {"k": 1, "lanes": "4"}, 3))
	var pn := PowerNetwork.build(sim, 32, 8)
	t.check(pn.feeder_of(adds[0].id) == "c403", "the E-terminal chain feeds the Adds (got %s)" % pn.feeder_of(adds[0].id))
	t.check(pn.nodes["c403"]["load"] == 20 and pn.nodes["c403"]["cap"] == 16, "chain load 20 on a 16 rail (got %d/%d)" % [pn.nodes["c403"]["load"], pn.nodes["c403"]["cap"]])
	for a in adds:
		t.check(pn.work_rate(a.id, 12) == 9, "rail 16 over 20 caps the rate at 9 (got %d)" % pn.work_rate(a.id, 12))
		t.check(pn.bottleneck(a.id) == {"node": "c403", "cap": 16, "load": 20}, "the rail chain is the bottleneck")
	t.check(pn.state("c403") == "over", "the overloaded chain reads over")
	t.check(pn.path(adds[0].id)[0] == {"node": "source", "cap": 32, "load": 20}, "source carries the chain load")
	t.check(pn.path(adds[0].id)[-1] == {"node": "p%d" % adds[0].id, "cap": 16, "load": 4}, "pads node: 2 contacts x 8 = 16 cap")


## Heavy rail (48) clears the same 20 demand; the controller tier is then the only limit.
static func _heavy_rail_and_ctrl_tier(t) -> void:
	var sim := _sim()
	sim.place("power_controller", Vector2i(1, 10), 0, {"tier": "basic"}, 3)
	for x in range(3, 13):
		sim.place("power_rail_heavy", Vector2i(x, 10), 0, {}, 3)
	var adds: Array[Machine] = []
	for x in [4, 6, 8, 10, 12]:
		adds.append(sim.place("add", Vector2i(x, 9), 0, {"k": 1, "lanes": "4"}, 3))
	var pn := PowerNetwork.build(sim, 32, 8)
	for a in adds:
		t.check(pn.work_rate(a.id, 12) == 12, "heavy rail 48 >= 20: no slowdown (got %d)" % pn.work_rate(a.id, 12))
	# the same copper with the starter "ctrl" tier (12) makes the controller the bottleneck
	var sim2 := _sim()
	sim2.place("power_controller", Vector2i(1, 10), 0, {"tier": "ctrl"}, 3)
	for x in range(3, 13):
		sim2.place("power_rail_heavy", Vector2i(x, 10), 0, {}, 3)
	for x in [4, 6, 8, 10, 12]:
		sim2.place("add", Vector2i(x, 9), 0, {"k": 1, "lanes": "4"}, 3)
	var pn2 := PowerNetwork.build(sim2, 32, 8)
	t.check(pn2.bottleneck(adds[0].id) == {"node": "ctrl", "cap": 12, "load": 20}, "ctrl tier 12 is the bottleneck")
	t.check(pn2.work_rate(adds[0].id, 12) == 7, "ctrl 12 over 20 caps the rate at 7 (got %d)" % pn2.work_rate(adds[0].id, 12))


## Controller -> plane -> board -> two output chains; the board's 48 cap over 64 demand wins.
static func _board(t) -> void:
	var sim := _sim()
	sim.place("power_controller", Vector2i(1, 10), 0, {"tier": "hc"}, 3)
	sim.place("power_plane", Vector2i(3, 10), 0, {}, 3)
	var board: Machine = sim.place("power_board", Vector2i(4, 10), 0, {}, 3)
	# N output chain (row 9, east of the board) feeds 3 Adds at lanes 8 -> 24
	for x in range(4, 9):
		sim.place("power_rail_heavy", Vector2i(x, 9), 0, {}, 3)
	var n_adds: Array[Machine] = []
	for x in [4, 6, 8]:
		n_adds.append(sim.place("add", Vector2i(x, 8), 0, {"k": 1, "lanes": "8"}, 3))
	# S output chain (row 11, east of the board) feeds 5 Adds at lanes 8 -> 40
	for x in range(4, 16):
		sim.place("power_rail_heavy", Vector2i(x, 11), 0, {}, 3)
	var e_adds: Array[Machine] = []
	for x in [6, 8, 10, 12, 14]:
		e_adds.append(sim.place("add", Vector2i(x, 10), 0, {"k": 1, "lanes": "8"}, 3))
	var pn := PowerNetwork.build(sim, 128, 8)
	var bn := "b%d" % board.id
	t.check(pn.nodes["c364"]["load"] == 24 and pn.nodes["c444"]["load"] == 40, "output chains carry 24 and 40 (got %d/%d)" % [pn.nodes["c364"]["load"], pn.nodes["c444"]["load"]])
	t.check(pn.nodes[bn]["load"] == 64 and pn.nodes[bn]["cap"] == 48, "the board sums its outputs: 64 on a 48 board (got %d/%d)" % [pn.nodes[bn]["load"], pn.nodes[bn]["cap"]])
	for a in n_adds + e_adds:
		t.check(pn.feeder_of(a.id) != "onboard", "board-fed Adds are on a chain")
		t.check(pn.bottleneck(a.id) == {"node": bn, "cap": 48, "load": 64}, "the overloaded board is the bottleneck")
		t.check(pn.work_rate(a.id, 12) == 9, "board 48 over 64 caps the rate at 9 (got %d)" % pn.work_rate(a.id, 12))
	t.check(pn.state(bn) == "over", "the board reads over")


## Copper never branches: a T kills the whole chain and its machines fall back to onboard.
static func _copper_t(t) -> void:
	var sim := _sim()
	sim.place("power_rail", Vector2i(5, 5), 0, {}, 3)
	sim.place("power_rail", Vector2i(5, 6), 0, {}, 3)
	sim.place("power_rail", Vector2i(5, 7), 0, {}, 3)
	t.check(PowerNetwork.placement_error(sim, "power_rail", Vector2i(4, 6)) == SPLIT_MSG, "a T junction is refused")
	t.check(PowerNetwork.placement_error(sim, "power_rail", Vector2i(3, 6)) == "", "an extension that keeps a line is fine")
	t.check(PowerNetwork.placement_error(sim, "add", Vector2i(4, 6)) == "", "non-copper types are not checked")
	sim.place("power_rail", Vector2i(4, 6), 0, {}, 3)
	var a: Machine = sim.place("add", Vector2i(5, 4), 0, {"k": 1}, 3)
	var pn := PowerNetwork.build(sim, 32, 8)
	t.check(not pn.nodes.has("c205"), "the T chain has no node (dead)")
	t.check(pn.feeder_of(a.id) == "onboard", "a machine on the dead chain falls back to onboard (got %s)" % pn.feeder_of(a.id))
	t.check(pn.work_rate(a.id, 12) == 12, "a single machine does not overload onboard 8 (got %d)" % pn.work_rate(a.id, 12))


## One tapped contact with 16 demand is bound by the pad (cap 8), not the rail or controller.
static func _pads(t) -> void:
	var sim := _sim()
	sim.place("power_controller", Vector2i(1, 10), 0, {"tier": "basic"}, 3)
	sim.place("power_rail", Vector2i(3, 10), 0, {}, 3)
	var mul: Machine = sim.place("multiply", Vector2i(3, 9), 0, {"k": 2, "lanes": "8"}, 3)
	t.check(mul.power_demand() == 16, "a lanes-8 Multiply draws 16 (got %d)" % mul.power_demand())
	var pn := PowerNetwork.build(sim, 32, 8)
	t.check(pn.feeder_of(mul.id) == "c403", "the single rail feeds it")
	t.check(pn.bottleneck(mul.id) == {"node": "p%d" % mul.id, "cap": 8, "load": 16}, "one pad (8) is the bottleneck")
	t.check(pn.work_rate(mul.id, 12) == 6, "pad 8 over 16 caps the rate at 6 (got %d)" % pn.work_rate(mul.id, 12))


static func _determinism(t) -> void:
	var sim := _sim()
	sim.place("power_controller", Vector2i(1, 10), 0, {"tier": "basic"}, 3)
	for x in range(3, 13):
		sim.place("power_rail_heavy", Vector2i(x, 10), 0, {}, 3)
	for x in [4, 6, 8, 10, 12]:
		sim.place("add", Vector2i(x, 9), 0, {"k": 1, "lanes": "4"}, 3)
	var a := PowerNetwork.build(sim, 32, 8)
	var b := PowerNetwork.build(sim, 32, 8)
	t.check(a.nodes == b.nodes, "building twice gives identical nodes")
	for mid in sim.sorted_machine_ids():
		t.check(a.work_rate(mid, 12) == b.work_rate(mid, 12) and a.feeder_of(mid) == b.feeder_of(mid), "queries are deterministic")