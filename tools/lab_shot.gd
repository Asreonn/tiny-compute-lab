extends SceneTree
## Lab screenshot at a given level:  timeout 60 godot --path . -s tools/lab_shot.gd -- <level 1..11> <out.png> [ticks]
## Writes a throwaway save (user://lab_shot_save.json) at that level, boots main.tscn (no intro),
## steps [ticks] simulation ticks and saves the viewport. Needs a real renderer.

var _frame := 0
var _out := ""
var _ticks := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var level := clampi(int(args[0]) if args.size() > 0 else 1, 1, 11) - 1
	_out = args[1] if args.size() > 1 else "/tmp/lab_shot.png"
	_ticks = int(args[2]) if args.size() > 2 else 0
	SaveStore.use_file("user://lab_shot_save.json")
	SaveStore.clear()
	SaveStore.save_lab({"level": level})
	root.size = Vector2i(1600, 900)
	root.add_child(load("res://main.tscn").instantiate())


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 3:
		var sm := root.get_node("/root/SimulationManager")
		for i in _ticks:
			sm.sim.step()
	if _frame == 8:
		root.get_texture().get_image().save_png(_out)
		print("lab_shot: wrote %s" % _out)
		SaveStore.clear()
		quit(0)
		return true
	return false
