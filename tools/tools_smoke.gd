extends SceneTree
## Tools smoke test (slice A5a):  timeout 60 godot --headless --path . -s tools/tools_smoke.gd
## Loads a1_plus_two and drives the real ToolController handlers with world coordinates:
## place an Add, wire USB -> Add -> Output, set k = 2 (010), run to PASS. Prints "SMOKE PASS".
## Screen->world conversion is the camera's job and is not exercised here.
## A frame watchdog guarantees the script always quits.

const MAX_FRAMES := 600

var _frame := 0
var _step := 0
var _mgr: Node
var _world: Node2D
var _tools: Node2D
var _fail := ""
var _mv: GDScript  # MachineView, loaded at runtime: it needs the SimulationManager autoload to compile


func _initialize() -> void:
	SaveStore.set_path("user://tools_smoke_save.json")
	SaveStore.clear()
	root.add_child(load("res://main.tscn").instantiate())


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > MAX_FRAMES:
		return _done("watchdog: no result after %d frames (step %d)" % [MAX_FRAMES, _step])
	if _frame < 3:
		return false  # let main.tscn load the mission
	match _step:
		0: _setup()
		1: _place()
		2: _wire_all()
		3: _run()
	if _fail != "":
		return _done(_fail)
	return false


func _setup() -> void:
	_mgr = root.get_node("/root/SimulationManager")
	_world = root.get_node("Main/World")
	_tools = _world.get_node("Tools")
	_mv = load("res://world/machines/machine_view.gd")
	_mgr.load_mission("a1_plus_two")  # fresh board (the smoke save was cleared)
	_expect(_tools.tool == "select", "tools start in select mode")
	_step = 1


func _place() -> void:
	_tools.begin_place("add")
	_expect(_tools.tool == "place", "begin_place switches to place")
	var p := Vector2(6 * 64 + 32, 3 * 64 + 32)
	_tools._on_mouse_motion(p)
	_click(p)
	_expect(_find("add") >= 0, "an Add was placed")
	_step = 2


func _wire_all() -> void:
	var sim = _mgr.sim
	var usb := _find("usb_input")
	var add := _find("add")
	var out := _find("output")
	# Wire tool, through the real mouse-button path: one drag, one click-click.
	_tools.set_tool("wire")
	var src: Vector2 = _mv.port_world(sim.machines[usb], "out")
	var dst: Vector2 = _mv.port_world(sim.machines[add], "in")
	# live routing: mid-drag over an empty tile the preview is a routed path, not a straight line
	_tools._on_mouse_motion(src)
	_button(true, src)
	_tools._on_mouse_motion(Vector2(4 * 64 + 32, 6 * 64 + 32))
	_expect(_tools._preview.pts.size() > 2, "free-drag preview is routed (got %d points)" % _tools._preview.pts.size())
	_tools._on_mouse_motion(dst)
	var previewed: Array = _tools._preview_cells.duplicate()
	_expect(_tools._preview.state == "ValidTarget", "hovering a free input previews ValidTarget")
	_button(false, dst)
	_expect(sim.connections.size() == 1, "wire tool drag makes a wire (got %d)" % sim.connections.size())
	var c1: Connection = sim.connections.values()[0]
	_expect(Array(c1.cells) == previewed, "placed wire == previewed route (WYSIWYG)")
	_click(_mv.port_world(sim.machines[add], "out"))
	_tools._on_mouse_motion(_mv.port_world(sim.machines[out], "in"))
	_click(_mv.port_world(sim.machines[out], "in"))
	_expect(sim.connections.size() == 2, "two wires exist (got %d)" % sim.connections.size())
	# occupancy: an occupied output does not start a wire; an occupied input rejects the drop.
	var before := {}
	for cid in sim.connections:
		before[cid] = Array(sim.connections[cid].cells)
	_drag(_mv.port_world(sim.machines[usb], "out"), _mv.port_world(sim.machines[out], "in"))
	_tools.set_tool("place")
	_tools.begin_place("add")
	var p2 := Vector2(6 * 64 + 32, 6 * 64 + 32)
	_tools._on_mouse_motion(p2)
	_click(p2)
	var add2 := -1
	for id in sim.sorted_machine_ids():
		if sim.machines[id].type == "add" and id != add:
			add2 = id
	_tools.set_tool("wire")
	if add2 >= 0:
		_drag(_mv.port_world(sim.machines[add2], "out"), _mv.port_world(sim.machines[out], "in"))
	var same: bool = sim.connections.size() == 2
	for cid in before:
		same = same and sim.connections.has(cid) and Array(sim.connections[cid].cells) == before[cid]
	_expect(same, "occupied ports reject new wires and the existing wires stay untouched")
	if add2 >= 0:
		sim.remove(add2)
	_step = 3


func _run() -> void:
	var sim = _mgr.sim
	_mgr.request_edit()
	sim.set_param(_find("add"), "k", 2)
	sim.reset_run()
	for i in 500:
		if _mgr.run.status != MissionRun.Status.RUNNING:
			break
		sim.step()
	if _mgr.run.status == MissionRun.Status.PASS:
		print("SMOKE PASS")
		quit(0)
		_step = 99
	else:
		_fail = "run did not pass: %s" % str(_mgr.run.failure)


func _button(pressed: bool, at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	_tools._on_mouse_button(ev, at)


func _drag(a: Vector2, b: Vector2) -> void:
	_tools._on_mouse_motion(a)
	_button(true, a)
	_tools._on_mouse_motion((a + b) / 2.0)
	_tools._on_mouse_motion(b)
	_button(false, b)


func _click(at: Vector2) -> void:
	_button(true, at)
	_button(false, at)


func _find(type: String) -> int:
	for id in _mgr.sim.sorted_machine_ids():
		if _mgr.sim.machines[id].type == type:
			return id
	return -1


func _expect(cond: bool, what: String) -> void:
	if not cond and _fail == "":
		_fail = what


func _done(msg: String) -> bool:
	printerr("SMOKE FAIL: " + msg)
	quit(1)
	return true
