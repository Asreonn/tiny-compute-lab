extends SceneTree
## Main menu smoke test (lab HUD + main menu):  timeout 60 godot --headless --path . -s tools/menu_smoke.gd
## Opens the main menu via the hud, checks the LAB card + one tutorial card per mission exist,
## clicks the first tutorial card and prints "MENU PASS" when mission a1_plus_two is loaded.
## A frame watchdog guarantees the script always quits.

const MAX_FRAMES := 200

var _frame := 0
var _step := 0
var _fail := ""


func _initialize() -> void:
	SaveStore.set_path("user://menu_smoke_save.json")
	SaveStore.clear()
	root.add_child(load("res://main.tscn").instantiate())


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > MAX_FRAMES:
		return _done("watchdog: no result after %d frames (step %d)" % [MAX_FRAMES, _step])
	if _frame < 3:
		return false  # let main.tscn load
	match _step:
		0: _open()
		1: _check()
		2: _click_first()
	if _fail != "":
		return _done(_fail)
	return false


func _open() -> void:
	var hud := root.get_node("Main/HUD/HudRoot")
	hud.open_menu()
	_step = 1


func _check() -> void:
	var menus := get_nodes_in_group("main_menu")
	_expect(menus.size() == 1, "main menu exists (got %d)" % menus.size())
	if menus.is_empty():
		_step = 99
		return
	_expect(menus[0].visible, "menu is open")
	_expect(get_nodes_in_group("lab_card").size() == 1, "LAB card exists (got %d)" % get_nodes_in_group("lab_card").size())
	var missions: Array = Missions.all()
	var cards := get_nodes_in_group("menu_cards")
	_expect(cards.size() == missions.size(), "one tutorial card per mission (got %d, want %d)" % [cards.size(), missions.size()])
	_step = 2


func _click_first() -> void:
	var cards := get_nodes_in_group("menu_cards")
	if cards.is_empty():
		_fail = "no tutorial cards"
		return
	cards[0].get_meta("on_click").call()
	var mgr := root.get_node("/root/SimulationManager")
	if mgr.mission != null and mgr.mission.id == "a1_plus_two":
		print("MENU PASS")
		quit(0)
	else:
		_fail = "mission not loaded: %s" % (str(mgr.mission.id) if mgr.mission != null else "null")
		_step = 99


func _expect(cond: bool, what: String) -> void:
	if not cond and _fail == "":
		_fail = what


func _done(msg: String) -> bool:
	printerr("MENU FAIL: " + msg)
	quit(1)
	return true
