class_name ThermalTests
extends RefCounted
## Checkpoint E2 acceptance tests: the ThermalGrid, stages with hysteresis, throttling / critical
## pause and the cooling family, calibrated against docs/SYSTEMS_EXPANSION.md §5. Machines run at
## 100 % duty (a new job every tick they are free) on a 40x22 board.

const SETTLE := 1500
const S := ThermalGrid.Stage


## A mission with heat on, unlimited power unless `cap` is set.
class HeatStub:
	extends RefCounted
	var cap := 0
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

	func thermal_enabled() -> bool:
		return true


static func run(t) -> void:
	_stages(t)
	_gate(t)
	_isolated(t)
	_packed_cluster(t)
	_network(t)
	_processor(t)
	_critical(t)
	_brownout_blower(t)
	_cooldown_and_determinism(t)
	_lab_gate(t)
	_heat_level(t)
	_datacenter(t)


static func _sim(cap := 0) -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(40, 22)
	sim.campaign_timing = true
	var stub := HeatStub.new()
	stub.cap = cap
	sim.mission = stub
	return sim


## Runs `ticks` steps keeping every machine in `busy` at 100 % duty; returns the highest stage
## each machine reached.
static func _run(sim: Simulation, busy: Array, ticks := SETTLE) -> Array:
	var peak := []
	peak.resize(busy.size())
	peak.fill(0)
	for i in ticks:
		for m in busy:
			if m.job.is_empty():
				m.begin_job({}, null)
		sim.step()
		for j in busy.size():
			peak[j] = maxi(peak[j], busy[j].heat_stage)
	return peak


static func _add(sim: Simulation, x: int, y: int, params := {"k": 1}) -> Machine:
	return sim.place("add", Vector2i(x, y), 0, params, 3)


static func _cluster(sim: Simulation) -> Array:
	return [_add(sim, 17, 10), _add(sim, 19, 10), _add(sim, 17, 11), _add(sim, 19, 11)]


static func _max_stage(ms: Array) -> int:
	var s := 0
	for m in ms:
		s = maxi(s, m.heat_stage)
	return s


static func _stages(t) -> void:
	t.check(ThermalGrid.stage_for(249, S.NORMAL) == S.NORMAL and ThermalGrid.stage_for(250, S.NORMAL) == S.WARM, "WARM is entered at 250 (50 °C)")
	t.check(ThermalGrid.stage_for(210, S.WARM) == S.WARM and ThermalGrid.stage_for(199, S.WARM) == S.NORMAL, "WARM is left only 50 below its entry")
	t.check(ThermalGrid.stage_for(760, S.NORMAL) == S.CRITICAL, "a jump can cross several stages at once")
	t.check(ThermalGrid.stage_for(701, S.CRITICAL) == S.CRITICAL and ThermalGrid.stage_for(699, S.CRITICAL) == S.THROTTLING, "CRITICAL holds until the machine cools below 700")
	t.check(is_equal_approx(ThermalGrid.celsius(250), 50.0), "t = 250 reads 50 °C")


static func _gate(t) -> void:
	var sim := Simulation.new()
	sim.campaign_timing = true
	var a := sim.place("add", Vector2i(4, 4), 0, {"k": 1}, 3)
	_run(sim, [a], 200)
	t.check(sim.thermal == null and a.temp == 0 and a.heat_stage == S.NORMAL, "without a heat run there is no thermal grid and nothing heats")


static func _isolated(t) -> void:
	var sim := _sim()
	var a := _add(sim, 18, 10)
	var peak: Array = _run(sim, [a])
	t.check(peak[0] == S.NORMAL and a.temp > 100, "an isolated Add at 100 %% settles warm but NORMAL (t=%d)" % a.temp)
	var sim2 := _sim()
	var oc := _add(sim2, 18, 10, {"k": 1, "clock": "overclocked"})
	_run(sim2, [oc])
	t.check(oc.heat_stage >= S.HOT, "an overclocked Add (x4 heat) runs HOT or worse (t=%d)" % oc.temp)


static func _packed_cluster(t) -> void:
	var sim := _sim()
	var cl := _cluster(sim)
	var peak: Array = _run(sim, cl)
	t.check(_max_stage(cl) == S.HOT and peak.max() == S.HOT, "four Adds packed edge to edge reach HOT without throttling (t=%d)" % cl[0].temp)


## P7b: the ThermalNetwork is plugged into the grid. Heat pipes are raised hardware now — they
## carry heat only through the network model (offers → allocation → sink dump), never by
## conduction, so the old "pipe chain to a heatsink" cases are replaced by the network ones.
static func _network(t) -> void:
	_network_radiator(t)
	_network_fin_stack(t)
	_network_third_blower(t)
	_network_recirculate(t)
	_network_pipe_material(t)
	_network_conservation(t)


## Pipes from the Processor's contact tile (10,9) to the west inlet of a sink at (9, rad_y).
static func _pipe_run(sim: Simulation, rad_y: int, pipe := "heat_pipe") -> void:
	sim.place(pipe, Vector2i(10, 9), 0, {}, 3)
	sim.place(pipe, Vector2i(9, 9), 0, {}, 3)
	for y in range(9, rad_y - 1, -1):
		sim.place(pipe, Vector2i(8, y), 0, {}, 3)


## A Processor piped into a top-edge Radiator with two Blowers stays <= WARM; without the
## network the same Processor reaches THROTTLING (the existing calibration above).
static func _network_radiator(t) -> void:
	var sim := _sim()
	var p := sim.place("processor", Vector2i(10, 10), 0, {}, 3)
	_pipe_run(sim, 0)
	sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim.place("blower", Vector2i(10, 2), 0, {}, 3)
	var peak: Array = _run(sim, [p])
	t.check(peak[0] <= S.WARM, "a Processor piped into a top-edge Radiator stays <= WARM (t=%d)" % p.temp)
	t.check(sim.thermal.net.network_of(p.id) != "" and sim.thermal.net.sinks()[0]["exhaust_out"], "the Processor is attached and the Radiator exhausts out")


## The same pipe run into a passive Fin Stack (capacity 400, no airflow) caps the removal lower
## than the Radiator's 1600, so a fast Processor runs hotter with it.
static func _network_fin_stack(t) -> void:
	var sim := _sim()
	var p := sim.place("processor", Vector2i(10, 10), 0, {"clock": "fast"}, 3)
	_pipe_run(sim, 0)
	sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim.place("blower", Vector2i(10, 2), 0, {}, 3)
	_run(sim, [p])
	var with_radiator := p.temp
	var sim2 := _sim()
	var p2 := sim2.place("processor", Vector2i(10, 10), 0, {"clock": "fast"}, 3)
	_pipe_run(sim2, 0)
	sim2.place("fin_stack", Vector2i(9, 0), 0, {}, 3)
	var peak2: Array = _run(sim2, [p2])
	t.check(p2.temp > with_radiator, "a passive Fin Stack runs the Processor hotter than the Radiator (%d vs %d)" % [p2.temp, with_radiator])
	t.check(peak2[0] > S.WARM, "…and pushes it past WARM (peak %d)" % peak2[0])


## A third Blower under the Radiator feeds no sink tile, so it changes nothing: the Processor's
## temperature after 300 ticks is identical.
static func _network_third_blower(t) -> void:
	var sim := _sim()
	var p := sim.place("processor", Vector2i(10, 10), 0, {}, 3)
	_pipe_run(sim, 0)
	sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim.place("blower", Vector2i(10, 2), 0, {}, 3)
	_run(sim, [p], 300)
	var base := p.temp
	var sim2 := _sim()
	var p2 := sim2.place("processor", Vector2i(10, 10), 0, {}, 3)
	_pipe_run(sim2, 0)
	sim2.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim2.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim2.place("blower", Vector2i(10, 2), 0, {}, 3)
	sim2.place("blower", Vector2i(12, 2), 0, {}, 3)
	_run(sim2, [p2], 300)
	t.check(p2.temp == base, "a third Blower under the Radiator changes nothing (%d vs %d)" % [base, p2.temp])


## A Radiator at the top edge exhausts out of the computer; moved down one row its exhaust tiles
## lie inside the board, so the dumped heat recirculates and the board runs hotter.
static func _network_recirculate(t) -> void:
	var sim := _sim()
	var p := sim.place("processor", Vector2i(10, 10), 0, {}, 3)
	_pipe_run(sim, 0)
	sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim.place("blower", Vector2i(10, 2), 0, {}, 3)
	_run(sim, [p])
	var edge_total := 0
	for v in sim.thermal.t:
		edge_total += v
	var sim2 := _sim()
	var p2 := sim2.place("processor", Vector2i(10, 10), 0, {}, 3)
	_pipe_run(sim2, 1)
	sim2.place("radiator", Vector2i(9, 1), 0, {}, 3)
	sim2.place("blower", Vector2i(9, 3), 0, {}, 3)
	sim2.place("blower", Vector2i(10, 3), 0, {}, 3)
	_run(sim2, [p2])
	var moved_total := 0
	for v in sim2.thermal.t:
		moved_total += v
	t.check(p2.temp > p.temp or moved_total > edge_total, "a recirculating Radiator leaves the Processor or the board hotter (%d/%d vs %d/%d)" % [p2.temp, moved_total, p.temp, edge_total])


## Three wide Adds (84×6 = 504 heat/tick each, 1512 > the copper 800) piped through copper vs
## heavy pipes: the copper caps the removal at 800, the heavy pipe passes it all.
static func _network_pipe_material(t) -> void:
	var copper := _pipe_adds("heat_pipe")
	var heavy := _pipe_adds("heat_pipe_heavy")
	t.check(heavy[0] < copper[0], "three Adds through a heavy pipe run cooler than through copper (peak %d vs %d)" % [heavy[0], copper[0]])
	t.check(heavy[1] < copper[1], "…and their hottest tile stays below the copper case (%d vs %d)" % [heavy[1], copper[1]])


## Three width-64 Adds piped into a top-edge Radiator with two Blowers. Returns [peak stage,
## hottest tile] after SETTLE ticks.
static func _pipe_adds(pipe: String) -> Array:
	var sim := _sim()
	var adds := []
	for x in [10, 12, 14]:
		adds.append(sim.place("add", Vector2i(x, 10), 0, {"k": 1}, 64))
	for x in [10, 11, 12, 13, 14, 15]:
		sim.place(pipe, Vector2i(x, 9), 0, {}, 3)
	sim.place(pipe, Vector2i(9, 9), 0, {}, 3)
	for y in range(9, -1, -1):
		sim.place(pipe, Vector2i(8, y), 0, {}, 3)
	sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim.place("blower", Vector2i(10, 2), 0, {}, 3)
	var peak: Array = _run(sim, adds)
	var hot := 0
	for a in adds:
		hot = maxi(hot, a.temp)
	return [peak.max(), hot]


## With no sink exhausting out, the removal is internal: the dump equals the removal and the
## board only cools by the ambient/edge dissipation (the existing conservation style).
static func _network_conservation(t) -> void:
	var sim := _sim()
	var p := sim.place("processor", Vector2i(10, 10), 0, {}, 3)
	_pipe_run(sim, 1)
	sim.place("radiator", Vector2i(9, 1), 0, {}, 3)
	sim.place("blower", Vector2i(9, 3), 0, {}, 3)
	sim.place("blower", Vector2i(10, 3), 0, {}, 3)
	_run(sim, [p], 500)
	var rsum := 0
	for v in sim.thermal.last_alloc.get("removal", {}).values():
		rsum += v
	var dsum := 0
	for v in sim.thermal.last_alloc.get("dump", {}).values():
		dsum += v
	t.check(rsum == dsum, "recirculated removal equals the dump (%d == %d)" % [rsum, dsum])
	p.jobs.clear()
	sim.remove(p.id)  # the idle baseline would keep a powered part warm (DATA_FACTORY §2.0b)
	var prev := 0
	for v in sim.thermal.t:
		prev += v
	var grew := false
	var never_neg := true
	for i in 6000:
		sim.step()
		var cur := 0
		for v in sim.thermal.t:
			cur += v
		grew = grew or cur > prev
		prev = cur
		if i % 50 == 0:
			for v in sim.thermal.t:
				never_neg = never_neg and v >= 0
	var cold := true
	for v in sim.thermal.t:
		cold = cold and v == 0
	t.check(not grew and cold and never_neg, "with no exhaust the board only cools by dissipation (grew=%s cold=%s never_neg=%s)" % [grew, cold, never_neg])


static func _processor(t) -> void:
	var sim := _sim()
	var p := sim.place("processor", Vector2i(18, 10), 0, {}, 3)
	var peak: Array = _run(sim, [p])
	t.check(peak[0] == S.THROTTLING, "an isolated Processor at 100 %% reaches THROTTLING (t=%d, peak %d)" % [p.temp, peak[0]])
	var sim2 := _sim()
	var p2 := sim2.place("processor", Vector2i(18, 10), 0, {}, 3)
	sim2.place("blower", Vector2i(20, 10), 0, {}, 3)
	var peak2: Array = _run(sim2, [p2])
	t.check(peak2[0] <= S.WARM, "a Processor with a Blower beside it stays <= WARM (t=%d)" % p2.temp)
	var sim3 := _sim()
	var p3 := sim3.place("processor", Vector2i(18, 10), 0, {}, 3)
	sim3.place("heatsink", Vector2i(20, 10), 0, {}, 3)
	_run(sim3, [p3])
	t.check(p3.heat_stage <= S.HOT, "an adjacent Heatsink keeps a Processor out of THROTTLING (t=%d)" % p3.temp)
	var sim4 := _sim()
	var p4 := sim4.place("processor", Vector2i(18, 10), 0, {}, 3)
	sim4.place("radiator", Vector2i(20, 10), 0, {}, 3)
	var peak4: Array = _run(sim4, [p4])
	t.check(peak4[0] == S.NORMAL, "a Radiator keeps a Processor NORMAL (t=%d)" % p4.temp)


static func _critical(t) -> void:
	var sim := _sim()
	var p := sim.place("processor", Vector2i(18, 10), 0, {"clock": "overclocked"}, 3)
	var saw_pause := false
	var kept := true
	var done_while_paused := false
	for i in SETTLE:
		if p.job.is_empty():
			p.begin_job({}, null)
		var before: int = p.processed
		var left: int = int(p.job.get("work_left", 0))
		var was_critical: bool = p.heat_stage == S.CRITICAL
		sim.step()
		if was_critical:
			saw_pause = true
			done_while_paused = done_while_paused or p.processed != before
			kept = kept and int(p.job.get("work_left", -1)) == left
	t.check(saw_pause, "an overclocked Processor reaches CRITICAL")
	t.check(kept and not done_while_paused, "a CRITICAL machine pauses and keeps its job")
	t.check(p.processed > 0 and sim.machines.has(p.id), "it recovers and keeps working — nothing is destroyed")


static func _brownout_blower(t) -> void:
	# a blower that gets half its power cools half as much
	var full := _sim()
	var p := full.place("processor", Vector2i(18, 10), 0, {}, 3)
	full.place("blower", Vector2i(20, 10), 0, {}, 3)
	_run(full, [p], 800)
	var weak := _sim(3)  # demand: processor 4 + blower 2 = 6 on a 3-unit PSU
	var pw := weak.place("processor", Vector2i(18, 10), 0, {}, 3)
	weak.place("blower", Vector2i(20, 10), 0, {}, 3)
	_run(weak, [pw], 800)
	t.check(weak.thermal.dissipation[weak.thermal.idx(Vector2i(20, 10))] < full.thermal.dissipation[full.thermal.idx(Vector2i(20, 10))], "a browned-out Blower moves less air")


static func _cooldown_and_determinism(t) -> void:
	var a := _small_trace()
	var b := _small_trace()
	t.check(a[0] == b[0], "the heat field is deterministic")
	t.check(a[1], "every tile cools back to ambient once the work stops")
	t.check(a[2], "no tile ever goes below ambient")


static func _small_trace() -> Array:
	var sim := Simulation.new()
	sim.size = Vector2i(12, 8)
	sim.campaign_timing = true
	sim.mission = HeatStub.new()
	var ms := [sim.place("multiply", Vector2i(2, 2), 0, {"k": 2}, 3), sim.place("add", Vector2i(4, 2), 0, {"k": 1, "clock": "fast"}, 3)]
	sim.place("heat_pipe", Vector2i(6, 2), 0, {}, 3)
	sim.place("heat_pipe", Vector2i(7, 2), 1, {}, 3)  # elbow
	sim.place("heat_pipe", Vector2i(7, 3), 1, {}, 3)
	sim.place("heatsink", Vector2i(7, 4), 0, {}, 3)
	_run(sim, ms, 400)
	var snap := sim.thermal.t.duplicate()
	# switch the compute off: powered parts keep an idle baseline (DATA_FACTORY §2.0b), so only a
	# board without them cools all the way back to ambient
	for m in ms:
		sim.remove(m.id)
	var never_neg := true
	for i in 3000:
		sim.step()
		if i % 50 == 0:
			for v in sim.thermal.t:
				never_neg = never_neg and v >= 0
	var cold := true
	for v in sim.thermal.t:
		cold = cold and v == 0
	return [snap, cold, never_neg]


static func _lab_gate(t) -> void:
	var run := LabRun.new()
	run.level = 10
	t.check(not run.thermal_enabled(), "the Lab has no heat before L17")
	run.level = LabRun.HEAT_LEVEL
	t.check(run.thermal_enabled(), "heat arrives with the L17 Heat level")


## L17 Heat: the reference layout without its Blowers throttles (the window keeps restarting);
## the same layout at the normal clock is too slow for 8/s.
static func _heat_level(t) -> void:
	var hot := _l17(func(m: Machine): return m.type == "blower", {})
	t.check(hot[0].level == LabRun.HEAT_LEVEL and str(hot[0].warning).contains("THROTTLING"), "L17 without cooling throttles and restarts the window (%s)" % hot[0].warning)
	var slow := _l17(func(_m): return false, {"clock": "normal"})
	t.check(slow[0].level == LabRun.HEAT_LEVEL and slow[0].rate() < 8.0, "at the normal clock L17 stays under 8/s (%.1f/s)" % slow[0].rate())


## Runs the L17 reference layout minus the machines `drop` selects, with `params` forced onto
## every machine that has them; returns [run, sim].
static func _l17(drop: Callable, params: Dictionary) -> Array:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = LabRun.HEAT_LEVEL
	run.build_board(sim)
	Solutions.lab_solution(sim, LabRun.HEAT_LEVEL)
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if drop.call(m):
			sim.remove(id)
		elif not m.locked:
			for k in params:
				if m.params.has(k):
					m.params[k] = params[k]
	sim.reset_run()
	for i in 2500:
		sim.step()
		if run.level > LabRun.HEAT_LEVEL:
			break
	return [run, sim]


## L21 Datacenter: swap each Radiator of the reference layout for a Blower — the Blowers draw
## 2 power each, the 32-unit PSU browns out and the line falls under 8/s.
static func _datacenter(t) -> void:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = 20
	run.build_board(sim)
	Solutions.lab_solution(sim, 20)
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "radiator":
			var c := m.cell
			sim.remove(id)
			sim.place("blower", c, 0, {}, 5)
	sim.reset_run()
	for i in 2500:
		sim.step()
		if run.level > 20:
			break
	t.check(run.level == 20 and sim.overloaded() and run.rate() < 8.0, "L21 cooled by Blowers overdraws the PSU (%d/%d) and makes %.1f/s" % [sim.power_demand(), sim.power_capacity(), run.rate()])

