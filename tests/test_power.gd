class_name PowerTests
extends RefCounted
## Checkpoint E1 acceptance tests: work units, clock modes, PSU capacity and brownout
## (docs/SYSTEMS_EXPANSION.md §4 and §6). Each case calls t.check(cond, what); run() is invoked
## from tests/run_tests.gd.


## A minimal mission with a PSU: everything allowed, nothing judged.
class PsuStub:
	extends RefCounted
	var cap := 8
	var status := MissionRun.Status.RUNNING

	func allows(_type: String) -> bool:
		return true

	func reset(_sim) -> void:
		pass

	func after_tick(_sim) -> void:
		pass

	func on_output(_sim, _m, _p) -> void:
		pass

	func on_overflow(_sim, _m, _p) -> void:
		pass

	func power_capacity() -> int:
		return cap


static func run(t) -> void:
	_normal_timing(t)
	_clock_modes(t)
	_demand(t)
	_brownout(t)
	_paused(t)
	_psu_tiers(t)
	_determinism(t)


static func _sim(cap: int) -> Simulation:
	var sim := Simulation.new()
	sim.campaign_timing = true
	if cap > 0:
		var stub := PsuStub.new()
		stub.cap = cap
		sim.mission = stub
	return sim


## Steps until m's job completes; returns the step count (or -1 after `limit` steps).
static func _job_steps(sim: Simulation, m: Machine, limit := 64) -> int:
	m.begin_job({}, null)
	for i in limit:
		sim.step()
		if m.job.is_empty():
			return i + 1
	return -1


static func _normal_timing(t) -> void:
	var sim := _sim(0)
	var a := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	var mul := sim.place("multiply", Vector2i(2, 6), 0, {"k": 2}, 3)
	t.check(_job_steps(sim, a) == Catalog.ticks("add", true), "a normal-clock Add keeps its campaign dwell (4 ticks)")
	t.check(_job_steps(sim, mul) == Catalog.ticks("multiply", true), "a normal-clock Multiply keeps its campaign dwell (6 ticks)")
	t.check(a.job.is_empty() and a.last_rate == Machine.WORK_PER_TICK, "normal clock applies 12 work units per tick")


static func _clock_modes(t) -> void:
	var sim := _sim(0)
	var fast := sim.place("add", Vector2i(2, 2), 0, {"k": 1, "clock": "fast"}, 3)
	var oc := sim.place("add", Vector2i(2, 6), 0, {"k": 1, "clock": "overclocked"}, 3)
	t.check(_job_steps(sim, fast) == 3, "a fast Add finishes 48 work units in 3 ticks")
	t.check(_job_steps(sim, oc) == 2, "an overclocked Add finishes in 2 ticks")
	var junk := sim.place("add", Vector2i(2, 10), 0, {"k": 1, "clock": "turbo"}, 3)
	t.check(junk.clock_mode() == "normal", "an unknown clock value falls back to normal")


static func _demand(t) -> void:
	var sim := _sim(0)
	var a := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	t.check(a.power_demand() == 1, "a normal Add draws 1")
	a.params["clock"] = "fast"
	t.check(a.power_demand() == 2, "a fast Add draws ceil(1.5) = 2")
	a.params["clock"] = "overclocked"
	t.check(a.power_demand() == 2 and a.heat_mult() == 4, "an overclocked Add draws 2 and makes 4x heat")
	var mul := sim.place("multiply", Vector2i(2, 6), 0, {"k": 2, "clock": "fast"}, 3)
	t.check(mul.power_demand() == 3, "a fast Multiply draws 3")
	t.check(sim.power_demand() == 5, "the board demand is the sum (got %d)" % sim.power_demand())
	t.check(sim.power_capacity() == 0 and not sim.overloaded(), "without a PSU the capacity is unlimited")


static func _brownout(t) -> void:
	var sim := _sim(8)
	var machines: Array[Machine] = []
	for i in 8:  # 8 multiplies x 2 = demand 16 on a cap-8 PSU
		machines.append(sim.place("multiply", Vector2i(2 + (i % 4) * 4, 2 + (i / 4) * 4), 0, {"k": 2}, 3))
	var a := machines[0]
	sim.remove(machines[7].id)
	var add := sim.place("add", Vector2i(18, 10), 0, {"k": 1}, 3)
	sim.place("add", Vector2i(18, 6), 0, {"k": 1}, 3)
	# 7 multiplies (14) + 2 adds (2) = 16
	t.check(sim.power_demand() == 16, "brownout board demand is 16 (got %d)" % sim.power_demand())
	t.check(_job_steps(sim, add) == 8, "cap 8 / demand 16 -> 6 work units per tick -> an Add job takes 8 ticks")
	t.check(sim.overloaded() and add.last_rate == 6, "the overload is reported and the rate was 6 (got %d)" % add.last_rate)
	# one machine can never be starved below 1 unit
	var tiny := _sim(1)
	for i in 6:
		tiny.place("multiply", Vector2i(2 + (i % 3) * 4, 2 + (i / 3) * 4), 0, {"k": 2, "clock": "overclocked"}, 3)
	var slow := tiny.place("add", Vector2i(2, 10), 0, {"k": 1}, 3)
	t.check(_job_steps(tiny, slow) == 48 and slow.last_rate == 1, "a deep brownout floors at 1 work unit per tick")
	t.check(a.job.is_empty(), "idle machines are untouched by the brownout")


static func _paused(t) -> void:
	var sim := _sim(0)
	var a := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	a.thermal_num = 0
	t.check(_job_steps(sim, a, 40) == -1, "a paused machine (thermal factor 0) never completes")
	t.check(int(a.job["work_left"]) == int(a.job["work_total"]), "a paused job keeps its progress")
	a.thermal_num = 1
	var left := 0
	for i in 8:
		sim.step()
		if a.job.is_empty():
			left = i + 1
			break
	t.check(left == 4, "it resumes where it stopped (got %d ticks)" % left)


static func _psu_tiers(t) -> void:
	var run := LabRun.new()
	run.level = LabRun.POWER_LEVEL
	t.check(run.power_capacity() == 8, "the Starter adapter supplies 8")
	run.psu_tier = 2
	t.check(run.power_capacity() == 32 and run.psu_name() == "Desktop PSU", "tier 2 is the 32-unit Desktop PSU")
	run.psu_tier = 9
	t.check(run.power_capacity() == 64, "the tier is clamped to High-Capacity 64")
	t.check(run.clock_unlocked(), "clock modes unlock with the power level")
	var sim := Simulation.new()
	run.level = 10
	run.psu_tier = 0
	run.build_board(sim)
	t.check(sim.power_capacity() == 0 and not run.has_psu(), "before L16 the Lab has unlimited power (no brownout)")
	t.check(not run.clock_unlocked(), "clock modes are locked before the power level")


static func _trace(cap: int) -> Array:
	var sim := _sim(cap)
	var ms: Array[Machine] = []
	for i in 6:
		ms.append(sim.place("multiply" if i % 2 == 0 else "add", Vector2i(2 + (i % 3) * 4, 2 + (i / 3) * 4), 0, {"k": 1, "clock": ["normal", "fast", "overclocked"][i % 3]}, 3))
	var out: Array = []
	for m in ms:
		m.begin_job({}, null)
	for tick in 40:
		sim.step()
		for m in ms:
			out.append(int(m.job.get("work_left", 0)))
	return out


static func _determinism(t) -> void:
	t.check(_trace(5) == _trace(5), "a brownout run is deterministic")
	t.check(_trace(5) != _trace(0), "the brownout changes the timing")
