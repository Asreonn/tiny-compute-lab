extends SceneTree
## Desk zones input smoke test:  timeout 90 godot --headless --path . -s tools/desk_smoke.gd
## Boots the Lab at L6, then drives REAL mouse events through the viewport:
##   1. drag the Text module from the desk onto input port 1 → plugged
##   2. drag the plugged module back onto the desk → port empty, module on the desk
##   3. click the Bit module, then click port 1 → plugged (click-click)
## Prints "DESK PASS" (exit 0) or the first failure.

var _frame := 0
var _sm
var _desk
var _fails := 0


func _initialize() -> void:
	SaveStore.use_file("user://desk_smoke_save.json")
	SaveStore.clear()
	SaveStore.save_lab({"level": 5})
	root.add_child(load("res://main.tscn").instantiate())


func _check(c: bool, what: String) -> void:
	if not c:
		_fails += 1
		printerr("DESK FAIL: " + what)


## World → window coordinates (push_input expects window coords: canvas transform, then the
## root viewport's stretch/final transform — headless windows are tiny and scaled).
func _screen(world: Vector2) -> Vector2:
	var vp := root.get_viewport()
	return vp.get_final_transform() * (vp.get_canvas_transform() * world)


func _press(world: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = _screen(world)
	e.global_position = e.position
	root.get_viewport().push_input(e)


func _move(world: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _screen(world)
	e.global_position = e.position
	root.get_viewport().warp_mouse(e.position)
	root.get_viewport().push_input(e)


func _port1() -> Machine:
	for id in _sm.sim.sorted_machine_ids():
		var m: Machine = _sm.sim.machines[id]
		if m.type == "usb_input" and m.cell.y == 1:
			return m
	return null


func _slot_of(kind: String) -> int:
	for s in _sm.run.desk_inputs:
		if _sm.run.desk_inputs[s] == kind:
			return s
	return -1


func _process(_d: float) -> bool:
	_frame += 1
	if _frame > 300:
		printerr("DESK FAIL: watchdog")
		quit(1)
		return true
	match _frame:
		4:
			_sm = root.get_node("/root/SimulationManager")
			_desk = root.get_node("Main/World/DeskView")
			_check(_port1() != null and _port1().device == "", "L6 starts with port 1 empty")
			var s := _slot_of("text@5")
			_check(s >= 0, "the Q6 Text stick lies on the desk")
			var from: Vector2 = _desk.slot_rect("in", s).get_center()
			_press(from, true)
			_move(from + Vector2(10, 0))
		6:
			var to := Vector2(_port1().cell) * Palette.TILE + Vector2(-40, 32)
			_move(to)
			_press(to, false)
		9:
			_check(_port1().device == "text@5", "drag desk → port plugs the stick (got '%s')" % _port1().device)
			var grab := Vector2(_port1().cell) * Palette.TILE + Vector2(-50, 32)
			_press(grab, true)
			_move(grab + Vector2(-10, 0))
		11:
			var free := -1
			for i in _sm.run.desk_slot_count("in"):
				if not _sm.run.desk_inputs.has(i):
					free = i
					break
			var to: Vector2 = _desk.slot_rect("in", free).get_center()
			_move(to)
			_press(to, false)
		14:
			_check(_port1().device == "" and _slot_of("text@5") >= 0, "drag port → desk unplugs the stick")
			var bit: Vector2 = _desk.slot_rect("in", _slot_of("text@6")).get_center()
			_press(bit, true)
			_press(bit, false)
		16:
			var port := Vector2(_port1().cell) * Palette.TILE + Vector2(-40, 32)
			_press(port, true)
			_press(port, false)
		19:
			_check(_port1().device == "text@6", "click stick, click port plugs it (got '%s')" % _port1().device)
			# an unfinished quest's stick is refused by the COMPLETED tray
			var from: Vector2 = _desk.slot_rect("in", _slot_of("text@5")).get_center()
			_press(from, true)
			_move(from + Vector2(10, 0))
		21:
			var tray: Vector2 = _desk.tray_rect().get_center()
			_move(tray)
			_press(tray, false)
		24:
			_check(_slot_of("text@5") >= 0 and _sm.run.files == 5 and _sm.sim.last_error.begins_with("Not finished yet"), "the tray refuses an unfinished quest (%s)" % _sm.sim.last_error)
			SaveStore.clear()
			if _fails == 0:
				print("DESK PASS")
			quit(0 if _fails == 0 else 1)
			return true
	return false
