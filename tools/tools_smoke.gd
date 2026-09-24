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
	SaveStore.use_file("user://tools_smoke_save.json")
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
		3: _undo_place()
		4: _undo_check()
		5: _redo_check()
		6: _duplicate_and_settings()
		7: _smart_wire()
		8: _run()
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
	# Rewiring (player QoL): dragging from / onto occupied ports is allowed. The old wires stay
	# (faded) until the drop commits; cancelling leaves them untouched.
	var before := {}
	for cid in sim.connections:
		before[cid] = Array(sim.connections[cid].cells)
	var usb_out: Vector2 = _mv.port_world(sim.machines[usb], "out")
	var out_in: Vector2 = _mv.port_world(sim.machines[out], "in")
	_tools._on_mouse_motion(usb_out)
	_button(true, usb_out)
	_tools._on_mouse_motion(out_in)
	_expect(_tools._preview.state == "ValidTarget", "rewire onto an occupied input previews as valid")
	var faded := 0
	for cv in _world.get_node("WireLayer").get_children():
		if cv.pending_removal and not cv.is_queued_for_deletion():
			faded += 1
	_expect(faded == 2, "both wires that would be replaced are faded (got %d)" % faded)
	_expect(sim.connections.size() == 2, "old wires still exist while previewing")
	_tools._cancel_drags()
	_button(false, out_in)
	var same: bool = sim.connections.size() == 2
	for cid in before:
		same = same and sim.connections.has(cid) and Array(sim.connections[cid].cells) == before[cid]
	_expect(same, "cancelled rewire leaves every wire untouched")
	for cv in _world.get_node("WireLayer").get_children():
		_expect(not cv.pending_removal, "cancel restores faded wires")
	# committed rewire: a second Add takes over the Output's input; the old wire is replaced
	_tools.set_tool("place")
	_tools.begin_place("add")
	var p2 := Vector2(6 * 64 + 32, 6 * 64 + 32)
	_tools._on_mouse_motion(p2)
	_click(p2)
	var add2 := -1
	for id in sim.sorted_machine_ids():
		if sim.machines[id].type == "add" and id != add:
			add2 = id
	_expect(add2 >= 0, "second Add placed")
	_tools.set_tool("wire")
	_drag(_mv.port_world(sim.machines[add2], "out"), out_in)
	var to_out: Connection = sim.connection_at_port(out, "in")
	_expect(to_out != null and to_out.from_id == add2, "committed rewire replaces the Output's old wire")
	_expect(sim.connection_at_port(add, "out") == null, "the replaced wire is gone")
	# restore the solution: remove the second Add, rewire Add -> Output
	sim.remove(add2)
	_drag(_mv.port_world(sim.machines[add], "out"), out_in)
	_expect(sim.connections.size() == 2, "solution restored (got %d wires)" % sim.connections.size())
	_step = 3


## Undo / redo (F5): history commits once per frame of edits, so each step runs a frame apart.
func _undo_place() -> void:
	_tools.begin_place("add")
	var p := Vector2(6 * 64 + 32, 6 * 64 + 32)
	_tools._on_mouse_motion(p)
	_click(p)
	_tools.set_tool("select")
	_expect(_count("add") == 2, "a spare Add was placed for the undo check")
	_step = 4


func _undo_check() -> void:
	_expect(_mgr.can_undo(), "the placement is in the history")
	_expect(_mgr.undo(), "undo succeeds")
	_expect(_count("add") == 1 and _mgr.sim.connections.size() == 2, "undo removes the spare Add and keeps the wires")
	_expect(_mgr.can_redo(), "the undone placement can be redone")
	_step = 5


func _redo_check() -> void:
	_expect(_mgr.redo(), "redo succeeds")
	_expect(_count("add") == 2, "redo places the spare Add again")
	_mgr.undo()
	_expect(_count("add") == 1, "undo again")
	_step = 6


## F2: Ctrl+D-style duplicate picks up a copy (same params), copy / paste settings, delete.
func _duplicate_and_settings() -> void:
	var sim = _mgr.sim
	var add := _find("add")
	sim.set_param(add, "k", 3)
	_tools.duplicate_machine(add)
	_expect(_tools.tool == "place" and _tools.place_params.get("k", -1) == 3, "duplicate picks up a ghost with the source's parameters")
	var p := Vector2(6 * 64 + 32, 6 * 64 + 32)
	_tools._on_mouse_motion(p)
	_click(p)
	_expect(_count("add") == 2, "the duplicate was dropped")
	var dup := -1
	for id in sim.sorted_machine_ids():
		if sim.machines[id].type == "add" and id != add:
			dup = id
	_expect(dup >= 0 and int(sim.machines[dup].params.get("k", -1)) == 3, "the duplicate keeps k = 3")
	sim.set_param(dup, "k", 5)
	_tools.copy_settings(dup)
	_tools.paste_settings(add)
	_expect(int(sim.machines[add].params.get("k", -1)) == 5, "paste settings copies k onto the original")
	_tools.delete_machine(dup)
	_expect(_count("add") == 1 and sim.connections.size() == 2, "delete removes the duplicate, the wires stay")
	_step = 7


## F3: in Select mode, drag from the Output's INPUT port (a reverse wire) and drop on the Add's
## body: it has exactly one compatible port, so the drop snaps to it.
func _smart_wire() -> void:
	var sim = _mgr.sim
	var add := _find("add")
	var out := _find("output")
	var old: Connection = sim.connection_at_port(out, "in")
	sim.disconnect_wire(old.id)
	_expect(sim.connection_at_port(out, "in") == null, "the Add -> Output wire was removed")
	_tools.set_tool("select")
	var body: Vector2 = Vector2(sim.machines[add].cell) * 64.0 + Vector2(64, 32)  # the Add's centre
	_drag(_mv.port_world(sim.machines[out], "in"), body)
	var c: Connection = sim.connection_at_port(out, "in")
	_expect(c != null and c.from_id == add and c.from_port == "out", "a reverse drag onto the body snaps to the Add's output")
	_step = 8


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


func _count(type: String) -> int:
	var n := 0
	for id in _mgr.sim.machines:
		if _mgr.sim.machines[id].type == type:
			n += 1
	return n


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
