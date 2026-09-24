extends SceneTree
## Intro storyboard capture:  timeout 60 godot --path . -s tools/intro_shot.gd -- <out_prefix> [t1 t2 ...]
## Loads main.tscn, builds the laptop intro and saves one 1600x900 frame per requested time
## (seconds on the intro timeline; default 0 1.0 1.8 2.6 3.6). Needs a real renderer.

var _frame := 0
var _intro: IntroLaptop
var _times: Array = []
var _prefix := ""
var _vp: SubViewport


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_prefix = args[0] if args.size() > 0 else "/tmp/intro"
	for i in range(1, args.size()):
		_times.append(float(args[i]))
	if _times.is_empty():
		_times = [0.0, 1.0, 1.8, 2.6, 3.6]
	SaveStore.set_path("user://intro_shot_save.json")
	SaveStore.clear()
	root.size = Vector2i(1600, 900)
	root.add_child(load("res://main.tscn").instantiate())


func _process(_d: float) -> bool:
	_frame += 1
	if _frame > 400:
		printerr("intro_shot: watchdog")
		quit(1)
		return true
	if _frame == 4:
		var main := root.get_node("Main")
		var world = main.get_node("World")
		_intro = IntroLaptop.new()
		world.add_child(_intro)
		_intro.setup(root.get_node("/root/SimulationManager").sim, world.camera_rig, main.get_node("HUD/HudRoot"))
		_intro.set_process(false)
		_intro.set_process_unhandled_input(false)
	if _frame >= 6 and not _times.is_empty() and (_frame % 3) == 0:
		var t: float = _times[0]
		_intro._t = t
		_intro._apply_camera(t)
		if t >= IntroLaptop.T_HUD and not _intro._hud_started:
			_intro._start_hud(true)
		_intro.queue_redraw()
	if _frame >= 6 and not _times.is_empty() and (_frame % 3) == 2:
		var t: float = _times.pop_front()
		var img := root.get_texture().get_image()
		var out := "%s_%04d.png" % [_prefix, int(t * 1000.0)]
		img.save_png(out)
		print("intro_shot: wrote %s" % out)
	if _frame >= 6 and _times.is_empty():
		quit(0)
		return true
	return false
