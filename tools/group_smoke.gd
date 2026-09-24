extends SceneTree
## Multi-select smoke:  timeout 90 godot --headless --path . -s tools/group_smoke.gd
## Drives the real ToolController: box-select two wired Adds, drag the group, Ctrl+D a copy and
## drop it, delete the copy, undo. Prints "GROUP PASS".

var _frame := 0
var _fail := ""
var _mgr: Node
var _tools: Node2D


func _initialize() -> void:
	SaveStore.use_file("user://group_smoke_save.json")
	SaveStore.clear()
	SaveStore.save_lab({"level": 5})
	root.add_child(load("res://main.tscn").instantiate())


func _process(_d: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_mgr = root.get_node("/root/SimulationManager")
			_tools = root.get_node("Main/World/Tools")
			var sim = _mgr.sim
			var a = sim.place("add", Vector2i(8, 8), 0, {"k": 1}, 5)
			var b = sim.place("add", Vector2i(12, 8), 0, {"k": 2}, 5)
			sim.connect_ports(a.id, "out", b.id, "in")
		5:
			# box select: press on empty board, drag across both Adds, release
			_drag(Vector2(7 * 64 + 10, 7 * 64 + 10), Vector2(14 * 64 + 50, 9 * 64 + 30))
			_expect(_tools.selected_group.size() == 2, "a box selects both Adds (got %d)" % _tools.selected_group.size())
		7:
			# drag the group by grabbing one member: 3 tiles down
			var sim = _mgr.sim
			var ids: Array = _tools.selected_group.duplicate()
			_drag(Vector2(8 * 64 + 40, 8 * 64 + 32), Vector2(8 * 64 + 40, 11 * 64 + 32))
			_expect(sim.machines[ids[0]].cell == Vector2i(8, 11) and sim.machines[ids[1]].cell == Vector2i(12, 11), "the group moved 3 tiles down")
			_expect(sim.connections.size() == 1, "its wire followed")
			_expect(_tools.selected_group.size() == 2, "the group stays selected after the move")
		9:
			# Ctrl+D: pick up a copy of the group, drop it 3 tiles further down
			_tools.duplicate_group()
			var p := Vector2(8 * 64 + 40, 14 * 64 + 32)
			_tools._on_mouse_motion(p)
			_click(p)
			_expect(_count("add") == 4 and _mgr.sim.connections.size() == 2, "the copy has both Adds and their wire")
		11:
			# delete the (new, selected) copy as a group
			_tools._delete_selection()
			_expect(_count("add") == 2 and _mgr.sim.connections.size() == 1, "delete removes the copied group")
		13:
			_mgr.undo()
			_expect(_count("add") == 4, "undo brings the deleted group back")
		15:
			if _fail != "":
				printerr("GROUP FAIL: " + _fail)
				quit(1)
			else:
				print("GROUP PASS")
				quit(0)
			SaveStore.clear()
			return true
	return false


func _button(pressed: bool, at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	_tools._on_mouse_button(ev, at)


func _drag(a: Vector2, b: Vector2) -> void:
	_tools._on_mouse_motion(a)
	_button(true, a)
	_tools._on_mouse_motion(a.lerp(b, 0.5))
	_tools._on_mouse_motion(b)
	_button(false, b)


func _click(at: Vector2) -> void:
	_button(true, at)
	_button(false, at)


func _count(type: String) -> int:
	var n := 0
	for id in _mgr.sim.machines:
		if _mgr.sim.machines[id].type == type:
			n += 1
	return n


func _expect(c: bool, what: String) -> void:
	if not c and _fail == "":
		_fail = what
