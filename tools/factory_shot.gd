extends SceneTree
## Factory-growth visual check (docs/STYLE_GUIDE.md §15):
##   timeout 90 godot --path . -s tools/factory_shot.gd -- <out_prefix> [data|power|thermal]
## Boots the Lab with a stand-in run that allows every part and every lane count, lays out one
## scene — data: bus classes × lanes (Penpot 21/01); power: controller → rail → board → plane
## and heavy runs with tapped Adds (22/03, 25 C); thermal: spreader → pipes → radiator + blowers
## and a manifold → trunk → fin stack (22/04, 25 D/F) — runs it and writes <prefix>_board.png
## plus close-ups.
## Needs a real renderer (no --headless). Never touches the real save.

## Every part and upgrade allowed, only for this screenshot.
class OpenLab extends LabRun:
	func allows(_type: String) -> bool:
		return true

	func max_lanes() -> int:
		return 8

	func max_bus_lanes() -> int:
		return 8

	func efficiency_unlocked() -> bool:
		return true

	func uses_power_network() -> bool:
		return true

	func has_psu() -> bool:
		return true

	func power_capacity() -> int:
		return 64

	func onboard_capacity() -> int:
		return 8

	func thermal_enabled() -> bool:
		return true


var _frame := 0
var _prefix := ""
var _scene := "data"
var _busy: Array = []  # machines kept at full duty (a job always running)
var _picks: Array = []  # [add id, its input wire id] per data line (the ui scene selects them)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_prefix = args[0] if args.size() > 0 else "/tmp/factory"
	_scene = args[1] if args.size() > 1 else "data"
	SaveStore.use_file("user://factory_shot_save.json")
	SaveStore.clear()
	SaveStore.save_lab({"level": 10})
	root.size = Vector2i(1600, 900)
	root.add_child(load("res://main.tscn").instantiate())


func _place(sim: Simulation, ty: String, c: Vector2i, width := 3, params := {}) -> Machine:
	var m := sim.place(ty, c, 0, params, width)
	if m == null:
		push_warning("factory_shot: could not place %s at %s (%s)" % [ty, c, sim.last_error])
	return m


## A source → Add → Add line: a looping stream at `interval`, `lanes` wire lanes, the Adds at
## `lanes` compute lanes. The second wire bends down one row; the last Add backs up (no sink).
func _line(sim: Simulation, y: int, width: int, lanes: int, interval: int) -> void:
	var s := _place(sim, "usb_input", Vector2i(5, y), width)
	if s == null:
		return
	s.stream = [BitVector.of(1, width), BitVector.of(2, width), BitVector.of(3, width)]
	s.loop = true
	s.interval = interval
	var a := _place(sim, "add", Vector2i(11, y), width, {"k": 1, "lanes": str(lanes)})
	var o := _place(sim, "add", Vector2i(19, y + 1), width, {"k": 1, "lanes": str(lanes)})
	if a == null or o == null:
		return
	var w1 := sim.connect_ports(s.id, "out", a.id, "in")
	var w2 := sim.connect_ports(a.id, "out", o.id, "in")
	for w in [w1, w2]:
		if w != null and lanes > 1:
			sim.set_wire_lanes(w.id, lanes)
	_picks.append([a.id, w1.id if w1 != null else -1])


func _process(_d: float) -> bool:
	_frame += 1
	var sm := root.get_node("/root/SimulationManager")
	var sim: Simulation = sm.sim
	if _frame == 3:
		var run := OpenLab.new()
		run.level = 10
		run.build_board(Simulation.new())
		sim.mission = run
		sim.campaign_timing = true
		match _scene:
			"power": _power_scene(sim)
			"thermal": _thermal_scene(sim)
			_: _data_scene(sim)  # "data" and "ui"
		sm.layout_changed.emit()
		for i in (400 if _scene == "thermal" else 40):
			for m in _busy:
				if m.jobs.is_empty():
					m.begin_job({}, null)
			sim.step()
		sm.running = true
	if _scene == "ui":
		return _ui_frames(sm)
	if _frame == 20:
		_shot("board")
		_focus(FOCUS[_scene][0], 3.2)
	if _frame == 40:
		_shot("close1")
		_focus(FOCUS[_scene][1], 3.2)
	if _frame == 60:
		_shot("close2")
		sm.running = false
		SaveStore.clear()
		quit(0)
		return true
	return false


## The ui scene: the Upgrade card on the 4-lane Add, then the wire card on its input wire.
func _ui_frames(sm: Node) -> bool:
	var tools: Node = root.get_tree().get_first_node_in_group("tools")
	if _frame == 20 and tools != null and _picks.size() > 2:
		_focus(Vector2(13, 6), 2.2)
		tools._set_selection(int(_picks[2][0]), -1)
		for n in root.find_children("*", "Control", true, false):
			var sc: Script = n.get_script()
			if sc != null and sc.resource_path.ends_with("upgrade_card.gd"):
				n.open(int(_picks[2][0]))
	if _frame == 40:
		_shot("card")
		if tools != null and _picks.size() > 1:
			tools._set_selection(-1, int(_picks[1][1]))
	if _frame == 60:
		_shot("wire")
		if tools != null and _picks.size() > 2:
			tools._set_selection(-1, -1)
			root.get_viewport().warp_mouse(Vector2(700, 300))
			tools.hover_changed.emit({"kind": "machine", "id": int(_picks[2][0])})
	if _frame == 90:
		_shot("hover")
		sm.running = false
		SaveStore.clear()
		quit(0)
		return true
	return false


## Close-up centres (tiles) per scene.
const FOCUS := {
	"data": [Vector2(15, 6), Vector2(15, 12)],
	"power": [Vector2(4.5, 13), Vector2(15, 13)],
	"thermal": [Vector2(10, 3), Vector2(14, 8)],
}


## Bus classes × lanes (Penpot 21/01): trace 1/2/4/8, byte 1, wide ×4, backbone ×2.
func _data_scene(sim: Simulation) -> void:
	_line(sim, 1, 3, 1, 4)
	_line(sim, 3, 3, 2, 2)
	_line(sim, 5, 3, 4, 1)
	_line(sim, 7, 3, 8, 1)
	_line(sim, 9, 8, 1, 2)
	_line(sim, 11, 16, 4, 1)
	_line(sim, 13, 40, 2, 1)


## The power path (Penpot 22/03, 25 C): the locked jack + controller at row 12 (x 0–3); the E
## terminal feeds a Power Rail to a Distribution Board, whose E output feeds a Main Plane of
## 4-lane Adds (near its cap) and whose S output a Heavy Rail; the controller's S terminal feeds a
## Heavy Plane. A lone rail with no feed is dead.
func _power_scene(sim: Simulation) -> void:
	# the Lab builds the locked jack + controller from its power level (OpenLab.has_psu)
	(sim.mission as LabRun)._ensure_power_fixtures(sim)
	for c in sim.reserved.keys():
		if c.y >= 12 and c.y <= 13:
			sim.reserved.erase(c)  # the power bay is open now (the real Lab clears it with the PSU)
	var ctrl := sim.machine_at(Vector2i(2, 12))
	if ctrl != null:
		ctrl.params["tier"] = "basic"
	for x in range(4, 13):
		_place(sim, "power_rail", Vector2i(x, 12))
	for x in [5, 7, 9]:
		_busy.append(_place(sim, "add", Vector2i(x, 11), 3, {"k": 1}))
	_place(sim, "power_board", Vector2i(13, 12))
	for x in range(15, 23):
		_place(sim, "power_plane", Vector2i(x, 12))
	for x in [16, 18, 20]:
		_busy.append(_place(sim, "add", Vector2i(x, 11), 3, {"k": 1, "lanes": "4"}))
	for y in range(13, 17):
		_place(sim, "power_rail_heavy", Vector2i(13, y))
	for x in range(14, 21):
		_place(sim, "power_rail_heavy", Vector2i(x, 16))
	for x in [15, 18]:
		_busy.append(_place(sim, "add", Vector2i(x, 15), 8, {"k": 1, "lanes": "2"}))
	for y in range(14, 18):
		_place(sim, "power_plane_heavy", Vector2i(3, y))
	for x in range(4, 10):
		_place(sim, "power_plane_heavy", Vector2i(x, 17))
	for x in [5, 7]:
		_busy.append(_place(sim, "add", Vector2i(x, 16), 3, {"k": 1}))
	for x in range(24, 28):
		_place(sim, "power_rail", Vector2i(x, 15))
	_busy = _busy.filter(func(m): return m != null)


## The thermal path (Penpot 22/04, 25 D/F): three Adds under a spreader, a pipe up to a Radiator
## at the top edge fed by two Blowers (a cooling assembly); two Adds into a Manifold, a Trunk and
## a Heavy Pipe to a Fin Stack below the top edge (it recirculates) with an HP blower.
func _thermal_scene(sim: Simulation) -> void:
	for x in [4, 6, 8]:
		_busy.append(_place(sim, "add", Vector2i(x, 6), 16, {"k": 1, "lanes": "4"}))
	for x in range(4, 10):
		_place(sim, "thermal_spreader", Vector2i(x, 5))
	for y in [5, 4, 3, 2, 1]:
		_place(sim, "heat_pipe", Vector2i(10, y))
	for x in [11, 12, 13]:
		_place(sim, "heat_pipe", Vector2i(x, 1))
	_place(sim, "radiator", Vector2i(14, 0))
	_place(sim, "blower", Vector2i(14, 2))
	_place(sim, "blower", Vector2i(15, 2))
	for x in [4, 6]:
		_busy.append(_place(sim, "add", Vector2i(x, 10), 16, {"k": 1, "lanes": "4"}))
	for x in [4, 5, 6, 7]:
		_place(sim, "heat_pipe", Vector2i(x, 9))
	_place(sim, "thermal_manifold", Vector2i(8, 9))
	for x in [10, 11, 12]:
		_place(sim, "thermal_trunk", Vector2i(x, 9))
	for x in [13, 14, 15, 16]:
		_place(sim, "heat_pipe_heavy", Vector2i(x, 9))
	_place(sim, "heat_pipe_heavy", Vector2i(16, 8))
	_place(sim, "fin_stack", Vector2i(17, 8))
	_place(sim, "blower_hp", Vector2i(17, 9))
	_busy = _busy.filter(func(m): return m != null)


func _focus(tile: Vector2, zoom: float) -> void:
	for n in root.find_children("*", "CameraRig", true, false):
		n.set_zoom_level(zoom)
		n.position = tile * 64.0


func _shot(tag: String) -> void:
	var p := "%s_%s.png" % [_prefix, tag]
	root.get_texture().get_image().save_png(p)
	print("factory_shot: wrote %s" % p)
