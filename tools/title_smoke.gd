extends SceneTree
## Title screen smoke:  timeout 90 godot --headless --fixed-fps 60 --path . -s tools/title_smoke.gd
## The title holds the intro; the confirm page starts on "Keep my Lab"; Continue releases the
## intro, which finishes, hands the camera back and restores the HUD. Prints "TITLE PASS".

var _frame := 0
var _step := 0
var _fail := ""
var _main: Node
var _ts: Control
var _intro: Node
var _released_at := -1


func _initialize() -> void:
	SaveStore.use_file("user://title_smoke_save.json")
	SaveStore.clear()
	SaveStore.save_lab({"level": 3})
	root.add_child(load("res://main.tscn").instantiate())


func _process(_d: float) -> bool:
	_frame += 1
	if _frame > 900:
		return _done("watchdog at step %d" % _step)
	match _step:
		0:
			if _frame == 3:
				_main = root.get_node("Main")
				_main.play_intro(true)
				_step = 1
		1:
			if root.has_node("Main/TitleLayer/TitleScreen"):
				_ts = root.get_node("Main/TitleLayer/TitleScreen")
				_intro = root.get_node("Main/World/IntroLaptop")
				_step = 2
		2:
			if _frame > 40:
				_expect(_intro.hold and _intro._t == 0.0, "the intro waits under the title")
				_ts._show_page("confirm")
				_expect(str(_ts._tiles[_ts._focus]["action"]) == "back", "the New Lab confirmation starts on Keep my Lab")
				_ts._show_page("main")
				_expect(str(_ts._tiles[_ts._focus]["action"]) == "continue", "the main page starts on Continue")
				_ts._activate(_ts._focus)
				_released_at = _frame
				_step = 3
		3:
			if not is_instance_valid(_intro):
				var hud: Control = root.get_node("Main/HUD/HudRoot")
				var shown := 0
				for c in hud.get_children():
					if c is Control and c.visible and c.modulate.a > 0.99:
						shown += 1
				_expect(shown >= 3, "the HUD is back after the dive (%d panels)" % shown)
				_expect(not root.has_node("Main/TitleLayer"), "the title layer is gone")
				_expect(_frame - _released_at > 60, "the dive played (%d frames)" % (_frame - _released_at))
				if _fail != "":
					return _done(_fail)
				print("TITLE PASS")
				SaveStore.clear()
				quit(0)
				return true
	if _fail != "":
		return _done(_fail)
	return false


func _expect(c: bool, what: String) -> void:
	if not c and _fail == "":
		_fail = what


func _done(msg: String) -> bool:
	printerr("TITLE FAIL: " + msg)
	SaveStore.clear()
	quit(1)
	return true
