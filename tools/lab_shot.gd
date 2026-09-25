extends SceneTree
## Lab screenshot at a given level:  timeout 60 godot --path . -s tools/lab_shot.gd -- <level> <out.png> [ticks] [solve] [x,y,zoom|-] [view]
## Writes a throwaway save (user://lab_shot_save.json) at that level, boots main.tscn (no intro),
## steps [ticks] simulation ticks and saves the viewport. Needs a real renderer.

var _frame := 0
var _out := ""
var _ticks := 0
var _focus := Vector3.ZERO  # close-up camera: tile x, tile y, zoom (0 = the fitted view)
var _solve := false  # lay the reference solution (tests/solutions.gd) before stepping
var _view := ""  # a board view to show: data / flow / thermal / power


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var level := clampi(int(args[0]) if args.size() > 0 else 1, 1, LabDef.count()) - 1
	_out = args[1] if args.size() > 1 else "/tmp/lab_shot.png"
	_ticks = int(args[2]) if args.size() > 2 else 0
	_solve = args.size() > 3 and args[3] == "solve"
	if args.size() > 4 and args[4] != "-":
		var f := args[4].split(",")  # "tile_x,tile_y,zoom": a close-up
		_focus = Vector3(float(f[0]), float(f[1]), float(f[2]))
	if args.size() > 5:
		_view = args[5]
	SaveStore.use_file("user://lab_shot_save.json")
	SaveStore.clear()
	SaveStore.save_lab({"level": level})
	root.size = Vector2i(1600, 900)
	root.add_child(load("res://main.tscn").instantiate())


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 3:
		var sm := root.get_node("/root/SimulationManager")
		if _solve:
			Solutions.lab_solution(sm.sim, sm.lab_run.level)
			sm.sim.reset_run()
		if _focus.z > 0.0:
			var cam = root.get_node("Main/World/CameraRig")  # untyped: -s scripts can't name autoload-bound classes
			cam.set_zoom_level(_focus.z)
			cam.position = Vector2(_focus.x, _focus.y) * 64.0
		for i in _ticks:
			sm.sim.step()
		sm.ticked.emit(sm.sim.tick)  # the HUD refreshes on ticks
		if _view != "":
			sm.set_overlay(_view)
		sm.sim.changed.emit()
	if _frame == (30 if _view != "" else 8):
		root.get_texture().get_image().save_png(_out)
		print("lab_shot: wrote %s" % _out)
		SaveStore.clear()
		quit(0)
		return true
	return false
