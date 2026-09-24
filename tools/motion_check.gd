extends SceneTree
## Motion acceptance check:  timeout 60 godot --headless --path . -s tools/motion_check.gd
## Runs a1_plus_two with its reference solution and samples every drawn packet 10× per tick
## (SimulationManager.alpha 0.0 … 0.9) to prove the rendering is continuous:
##   * no packet moves more than MAX_STEP px between consecutive samples (no teleporting)
##   * a value stays inside the Add core for ≥ MIN_DWELL ticks (real processing dwell)
##   * the Add's processing progress reaches 100 %
## Prints "MOTION PASS" (exit 0) or the first violation. A frame watchdog always quits.

const MAX_STEP := 5.0  # px per 1/10 tick (wire travel is ~3.3; a tile is 64 px)
const MIN_DWELL := 3
const SAMPLES := 10
const TICKS := 60

var _frame := 0
var _done := false


func _initialize() -> void:
	SaveStore.use_file("user://motion_check_save.json")
	SaveStore.clear()
	root.add_child(load("res://main.tscn").instantiate())


func _process(_d: float) -> bool:
	_frame += 1
	if _frame > 600:
		printerr("MOTION FAIL: watchdog")
		quit(1)
		return true
	if _frame == 3 and not _done:
		_done = true
		_run()
	return false


func _run() -> void:
	var sm := root.get_node("/root/SimulationManager")
	sm.set_process(false)  # this script drives ticks and the tick fraction itself
	sm.load_mission("a1_plus_two")
	Solutions.build(sm.sim, "a1_plus_two")
	sm.sim.reset_run()
	var layer = root.get_node("Main/World/PacketLayer")
	var add_id := -1
	for id in sm.sim.machines:
		if sm.sim.machines[id].type == "add":
			add_id = id
	var add_view = root.get_node("Main/World/MachineLayer/Machine_%d" % add_id)
	sm.running = true
	var last := {}
	var worst := 0.0
	var worst_id := -1
	var worst_kind := ""
	var core_ticks := {}
	var max_progress := 0.0
	var inside_drawn := 0
	for tick in TICKS:
		sm._do_step()
		if sm.run.status != MissionRun.Status.RUNNING:
			break
		for s in SAMPLES:
			sm.alpha = float(s) / SAMPLES
			var pos: Dictionary = layer.drawn_packet_positions()
			for pid in pos:
				if last.has(pid):
					var d: float = (pos[pid] as Vector2).distance_to(last[pid])
					if d > worst:
						worst = d
						worst_id = pid
						var mv: Dictionary = layer._moves.get(pid, {})
						worst_kind = "%s -> %s (%s)" % [mv.get("from_k", "?"), str(mv.get("to", {}).get("k", "?")), mv.get("state", "?")]
				last[pid] = pos[pid]
			var job: Dictionary = sm.sim.machines[add_id].job
			if not job.is_empty() and pos.has(job["input"].id) and s > 0:
				inside_drawn += 1  # a value being processed must not be drawn inside the machine
			add_view._update_progress()
			if add_view._progress._p > max_progress:
				max_progress = add_view._progress._p
		var job: Dictionary = sm.sim.machines[add_id].job
		if not job.is_empty():
			var jid: int = job["input"].id
			core_ticks[jid] = int(core_ticks.get(jid, 0)) + 1
	var dwell := 0
	for pid in core_ticks:
		dwell = maxi(dwell, core_ticks[pid])
	print("motion: worst transition " + worst_kind)
	print("motion: worst step %.1f px (packet #%d), max Add dwell %d ticks, max progress %.2f, status %s" % [worst, worst_id, dwell, max_progress, MissionRun.Status.keys()[sm.run.status]])
	print("motion: samples drawing a value inside the Add while processing: %d" % inside_drawn)
	var ok: bool = inside_drawn == 0 and worst <= MAX_STEP and dwell >= MIN_DWELL and max_progress >= 0.999 and sm.run.status == MissionRun.Status.PASS
	if ok:
		print("MOTION PASS")
		quit(0)
	else:
		printerr("MOTION FAIL")
		quit(1)
