extends SceneTree
## Power / heat visual check (E3):  timeout 90 godot --path . -s tools/systems_shot.gd -- <out_prefix>
## Boots the Lab at L11 with a stand-in run that has heat and a 16-unit PSU, builds hot clusters,
## a Processor with a Blower, a heat-pipe chain to a Heatsink and a Radiator, runs them at 100 %
## duty and writes <prefix>_board.png, <prefix>_thermal.png, <prefix>_power.png and a close-up
## <prefix>_close.png. Needs a real renderer (no --headless). Never touches the real save.

## The L11 Lab with heat on and a Desktop-ish PSU, only for this screenshot.
class HeatLab extends LabRun:
	func thermal_enabled() -> bool:
		return true

	func power_capacity() -> int:
		return 16

	func allows(_type: String) -> bool:
		return true


var _frame := 0
var _prefix := ""
var _busy: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_prefix = args[0] if args.size() > 0 else "/tmp/systems"
	SaveStore.use_file("user://systems_shot_save.json")
	SaveStore.clear()
	SaveStore.save_lab({"level": 10})
	root.size = Vector2i(1600, 900)
	root.add_child(load("res://main.tscn").instantiate())


func _place(sim: Simulation, ty: String, c: Vector2i, rot := 0, params := {}) -> Machine:
	var m := sim.place(ty, c, rot, params, 3)
	if m == null:
		push_warning("systems_shot: could not place %s at %s (%s)" % [ty, c, sim.last_error])
	return m


func _process(_d: float) -> bool:
	_frame += 1
	var sm := root.get_node("/root/SimulationManager")
	var sim: Simulation = sm.sim
	if _frame == 3:
		var hl := HeatLab.new()
		hl.level = 10
		hl.build_board(Simulation.new())
		sim.mission = hl
		# a packed 4-Add cluster (HOT), and the same cluster drained by a heat pipe to a heatsink
		for c in [Vector2i(8, 13), Vector2i(10, 13), Vector2i(8, 14), Vector2i(10, 14)]:
			_busy.append(_place(sim, "add", c, 0, {"k": 1}))
		for c in [Vector2i(20, 13), Vector2i(22, 13), Vector2i(20, 14), Vector2i(22, 14)]:
			_busy.append(_place(sim, "add", c, 0, {"k": 1}))
		for x in [24, 25, 26]:
			_place(sim, "heat_pipe", Vector2i(x, 13))
		_place(sim, "heat_pipe", Vector2i(27, 13), 1)
		_place(sim, "heat_pipe", Vector2i(27, 14), 1)
		_place(sim, "heatsink", Vector2i(27, 15))
		# a lone Processor (THROTTLING), one with a Blower, one with a Radiator
		_busy.append(_place(sim, "processor", Vector2i(8, 17)))
		_busy.append(_place(sim, "processor", Vector2i(14, 17)))
		_place(sim, "blower", Vector2i(16, 17))
		_busy.append(_place(sim, "processor", Vector2i(22, 17)))
		_place(sim, "radiator", Vector2i(24, 17))
		# an overclocked Multiply pair
		_busy.append(_place(sim, "multiply", Vector2i(30, 8), 0, {"k": 2, "clock": "overclocked"}))
		_busy.append(_place(sim, "multiply", Vector2i(30, 9), 0, {"k": 2, "clock": "fast"}))
		_busy = _busy.filter(func(m): return m != null)
		sm.layout_changed.emit()
		for i in 900:
			for m in _busy:
				if m.job.is_empty():
					m.begin_job({}, null)
			sim.step()
		sm.running = true  # blower spins, LEDs read live
	if _frame == 12:
		_shot("board")
		sm.toggle_overlay("thermal")
	if _frame == 40:
		_shot("thermal")
		sm.toggle_overlay("power")
	if _frame == 80:
		_shot("power")
		sm.toggle_overlay("power")
		var cam: CameraRig = root.get_node("Main/World/CameraRig") if root.has_node("Main/World/CameraRig") else null
		if cam == null:
			for n in root.find_children("*", "CameraRig", true, false):
				cam = n
		if cam != null:
			cam.set_zoom_level(1.4)
			cam.position = Vector2(17, 15) * 64.0
	if _frame == 110:
		_shot("close")
		sm.running = false
		SaveStore.clear()
		quit(0)
		return true
	return false


func _shot(tag: String) -> void:
	var p := "%s_%s.png" % [_prefix, tag]
	root.get_texture().get_image().save_png(p)
	print("systems_shot: wrote %s" % p)
