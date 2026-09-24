extends SceneTree
## HUD motion capture:  timeout 60 godot --path . -s tools/hud_motion_shot.gd -- <out_prefix>
## Loads main.tscn, switches playback speed 1x -> 10x and saves the viewport every other frame for
## ~0.3 s so the speed-selector pill slide (MOTION_SYSTEM §9) can be checked frame by frame.

var _frame := 0
var _prefix := ""
var _sm


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_prefix = args[0] if args.size() > 0 else "/tmp/hud_motion"
	SaveStore.use_file("user://hud_motion_save.json")
	SaveStore.clear()
	root.size = Vector2i(1600, 900)
	root.add_child(load("res://main.tscn").instantiate())


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 10:
		_sm = root.get_node("/root/SimulationManager")
		_sm.set_speed(_sm.SPEEDS[3])
	if _frame >= 10 and _frame <= 30 and _frame % 2 == 0:
		root.get_texture().get_image().save_png("%s_%02d.png" % [_prefix, _frame - 10])
	if _frame > 32:
		quit(0)
		return true
	return false
