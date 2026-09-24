extends SceneTree
## Interaction QoL visual check (F):  timeout 60 godot --path . -s tools/qol_shot.gd -- <out.png>
## Boots the Lab at L7, places two Adds, selects one (quick action bar) and hovers the other
## (hover card), then saves the viewport. Needs a real renderer. Never touches the real save.

var _frame := 0
var _out := ""
var _hover_world := Vector2.ZERO


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/qol_shot.png"
	SaveStore.use_file("user://qol_shot_save.json")
	SaveStore.clear()
	SaveStore.save_lab({"level": 6})
	root.size = Vector2i(1600, 900)
	root.add_child(load("res://main.tscn").instantiate())


func _process(_d: float) -> bool:
	_frame += 1
	var sm := root.get_node("/root/SimulationManager")
	var tools = root.get_node("Main/World/Tools")
	if _frame == 3:
		var a: Machine = sm.sim.place("add", Vector2i(8, 6), 0, {"k": 3}, 0)
		var b: Machine = sm.sim.place("modulo", Vector2i(14, 9), 0, {"k": 26}, 0)
		var cam = root.get_node("Main/World/CameraRig")
		cam.set_zoom_level(1.2)
		cam.position = Vector2(12, 8) * 64.0
		tools._set_selection(a.id, -1)
		_hover_world = Vector2(15 * 64, 9 * 64 + 32)
	if _frame >= 6 and _frame < 40:
		var screen: Vector2 = root.get_viewport().get_canvas_transform() * _hover_world
		root.warp_mouse(screen)
		tools._update_hover(_hover_world)
	if _frame == 40:
		root.get_texture().get_image().save_png(_out)
		print("qol_shot: wrote %s" % _out)
		SaveStore.clear()
		quit(0)
		return true
	return false
