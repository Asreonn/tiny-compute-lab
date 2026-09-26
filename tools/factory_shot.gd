extends SceneTree
## Factory-growth visual check (docs/STYLE_GUIDE.md §15):
##   timeout 90 godot --path . -s tools/factory_shot.gd -- <out_prefix> [data|all]
## Boots the Lab with a stand-in run that allows every part and every lane count, lays out the
## bus-class × lane scene (Penpot 21/01), runs it and writes <prefix>_board.png plus close-ups.
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


var _frame := 0
var _prefix := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_prefix = args[0] if args.size() > 0 else "/tmp/factory"
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
		# bus classes × lanes (Penpot 21/01): trace 1/2/4/8, byte 1, wide ×4, backbone ×2
		_line(sim, 1, 3, 1, 4)
		_line(sim, 3, 3, 2, 2)
		_line(sim, 5, 3, 4, 1)
		_line(sim, 7, 3, 8, 1)
		_line(sim, 9, 8, 1, 2)
		_line(sim, 11, 16, 4, 1)
		_line(sim, 13, 40, 2, 1)
		sm.layout_changed.emit()
		for i in 40:
			sim.step()
		sm.running = true
	if _frame == 20:
		_shot("board")
		_focus(Vector2(15, 6), 3.2)
	if _frame == 40:
		_shot("lanes")
		_focus(Vector2(15, 12), 3.2)
	if _frame == 60:
		_shot("classes")
		sm.running = false
		SaveStore.clear()
		quit(0)
		return true
	return false


func _focus(tile: Vector2, zoom: float) -> void:
	for n in root.find_children("*", "CameraRig", true, false):
		n.set_zoom_level(zoom)
		n.position = tile * 64.0


func _shot(tag: String) -> void:
	var p := "%s_%s.png" % [_prefix, tag]
	root.get_texture().get_image().save_png(p)
	print("factory_shot: wrote %s" % p)
