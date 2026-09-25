extends SceneTree
## Frame-cost probe (docs/PERFORMANCE.md):
##   timeout 90 godot [--headless] --fixed-fps 60 --path . -s tools/perf_probe.gd -- [level] [frames] [speed] [off] [--micro]
## Boots main.tscn in the Lab at <level> (1-based, default 27) with the reference solution laid,
## runs the board at <speed> (default 10) and prints the average / p95 frame time over <frames>
## frames (default 300) after a warm-up, plus render CPU/GPU time and draw calls.
##   --headless    script + draw-callback cost only (no GPU); the low-processor sleep is off
##   --fixed-fps   the same simulated time per frame, so runs compare
##   off           comma list of nodes under Main to switch off ("World/DeskView", "HUD"), or
##                 "noproc:<path>" to stop only that node's _process — cost attribution
##   --micro       per-part costs: each view's refresh, a sim tick, the tick / layout handlers
## Writes a throwaway save.

const WARMUP := 60

var _frame := 0
var _frames := 300
var _speed := 10
var _level := 26
var _last := 0
var _times: PackedInt64Array = []
var _rcpu := 0.0
var _rgpu := 0.0
var _draws := 0.0
var _off: PackedStringArray = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_level = clampi(int(args[0]) if args.size() > 0 else 27, 1, LabDef.count()) - 1
	_frames = int(args[1]) if args.size() > 1 else 300
	_speed = int(args[2]) if args.size() > 2 else 10
	if args.size() > 3 and args[3] != "" and not args[3].begins_with("--"):
		_off = args[3].split(",")
	SaveStore.use_file("user://perf_probe_save.json")
	SaveStore.clear()
	SaveStore.save_lab({"level": _level})
	root.size = Vector2i(1600, 900)
	OS.low_processor_usage_mode = false  # headless: no 6.9 ms idle sleep per frame
	OS.low_processor_usage_mode_sleep_usec = 0
	root.add_child(load("res://main.tscn").instantiate())
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)


func _process(_d: float) -> bool:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _frame == 3:
		var sm := root.get_node("/root/SimulationManager")
		Solutions.lab_solution(sm.sim, sm.lab_run.level)
		sm.sim.reset_run()
		sm.sim.changed.emit()
		sm.set_speed(_speed)
		sm.play()
		_switch_off()
	elif _frame > 3 + WARMUP:
		_times.append(now - _last)
		var vp := root.get_viewport_rid()
		_rcpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		_rgpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_last = now
	if _times.size() < _frames:
		return false
	var sorted := _times.duplicate()
	sorted.sort()
	var total := 0
	for t in _times:
		total += t
	var sm := root.get_node("/root/SimulationManager")
	var n := float(_times.size())
	print("perf_probe: [%s] L%d  machines %d  wires %d  nodes %d  avg %.2f ms  p95 %.2f ms  render cpu %.2f gpu %.2f ms  draws %d  tick %d" % [
		",".join(_off), _level + 1, sm.sim.machines.size(), sm.sim.connections.size(), get_node_count(),
		total / 1000.0 / n, sorted[int(sorted.size() * 0.95)] / 1000.0, _rcpu / n, _rgpu / n, int(_draws / n), sm.sim.tick])
	if "--micro" in OS.get_cmdline_user_args():
		_micro()
	SaveStore.clear()
	quit(0)
	return true


func _switch_off() -> void:
	for path in _off:
		if path.begins_with("noproc:"):
			var np := root.get_node_or_null("Main/" + path.trim_prefix("noproc:"))
			if np != null:
				np.set_process(false)
			continue
		var n := root.get_node_or_null("Main/" + path)
		if n == null:
			push_error("perf_probe: no node Main/%s" % path)
			continue
		n.process_mode = Node.PROCESS_MODE_DISABLED
		if n is CanvasItem:
			(n as CanvasItem).visible = false
		elif n is CanvasLayer:
			(n as CanvasLayer).visible = false


## Per-part costs, each averaged over repeated calls (µs).
func _micro() -> void:
	var by := {}
	for c in root.get_node("Main/World/MachineLayer").get_children():
		var t0 := Time.get_ticks_usec()
		for i in 50:
			c.refresh(0.016)
		var key := "refresh machine " + str(c.machine.type)
		by[key] = by.get(key, 0.0) + (Time.get_ticks_usec() - t0) / 50.0
	var wt := 0.0
	for c in root.get_node("Main/World/WireLayer").get_children():
		var t1 := Time.get_ticks_usec()
		for i in 50:
			c.refresh(0.016)
		wt += (Time.get_ticks_usec() - t1) / 50.0
	by["refresh wires (all)"] = wt
	var sm := root.get_node("/root/SimulationManager")
	by["sim.step (one tick)"] = _time(func(): sm.sim.step(), 50)
	by["ticked handlers"] = _time(func(): sm.ticked.emit(sm.sim.tick), 50)
	by["autosave"] = _time(func(): sm._save_lab(), 20)
	by["undo snapshot"] = _time(func(): sm._snapshot(), 20)
	by["world layout sync"] = _time(func(): root.get_node("Main/World")._sync_layout(), 20)
	by["layout change (all handlers)"] = _time(func(): sm.sim.changed.emit(), 20)
	for k in by:
		print("  micro %-30s %8.1f us" % [k, by[k]])


func _time(f: Callable, n: int) -> float:
	var t := Time.get_ticks_usec()
	for i in n:
		f.call()
	return (Time.get_ticks_usec() - t) / float(n)
