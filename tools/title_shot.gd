extends SceneTree
## Title screen visual check:  timeout 60 godot --path . -s tools/title_shot.gd -- <out_prefix>
## Boots main.tscn, opens the title screen over the held laptop intro and writes the main,
## settings, quests and tutorial pages. Needs a real renderer. Never touches the real save.

var _frame := 0
var _prefix := ""
var _ts: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_prefix = args[0] if args.size() > 0 else "/tmp/title"
	SaveStore.use_file("user://title_shot_save.json")
	SaveStore.clear()
	SaveStore.save_lab({"level": 11})
	root.size = Vector2i(1600, 900)
	root.add_child(load("res://main.tscn").instantiate())


func _process(_d: float) -> bool:
	_frame += 1
	var main = root.get_node("Main")
	if _frame == 3:
		main.play_intro(true)
	if _frame == 8:
		_ts = root.get_node("Main/TitleLayer/TitleScreen")
	if _frame == 40:
		_shot("main")
		_ts._show_page("settings")
	if _frame == 60:
		_shot("settings")
		_ts._show_page("quests")
	if _frame == 90:
		_shot("quests")
		_ts._show_page("tutorial")
	if _frame == 120:
		_shot("tutorial")
		_ts._show_page("confirm")
	if _frame == 160:
		_shot("confirm")
		SaveStore.clear()
		quit(0)
		return true
	return false


func _shot(tag: String) -> void:
	var p := "%s_%s.png" % [_prefix, tag]
	root.get_texture().get_image().save_png(p)
	print("title_shot: wrote %s" % p)
