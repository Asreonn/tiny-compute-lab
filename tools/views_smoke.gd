extends SceneTree
## Views smoke test:  timeout 60 godot --headless --path . -s tools/views_smoke.gd
## Builds a Simulation with default_width 5, places a bit_splitter (lo 3) and a demux,
## creates MachineViews for them, calls refresh once, and prints "VIEWS PASS" when the
## bit_splitter view shows width tags 5 / 2 / 3 (in / hi / lo live widths). A frame
## watchdog guarantees the script always quits.

const MAX_FRAMES := 600

var _frame := 0
var _step := 0
var _mgr: Node
var _mv: GDScript  # MachineView, loaded at runtime (needs the SimulationManager autoload)
var _fail := ""


func _initialize() -> void:
	# Autoloads (SimulationManager, TclTheme) are always instantiated; no main scene is
	# needed and it would drag in the HUD, which expects a real mission.
	pass


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > MAX_FRAMES:
		printerr("VIEWS FAIL: watchdog, no result after %d frames (step %d)" % [MAX_FRAMES, _step])
		quit(1)
		return true
	if _frame < 3:
		return false  # let autoloads finish _ready
	match _step:
		0: _build()
		1: _check()
	if _fail != "":
		printerr("VIEWS FAIL: " + _fail)
		quit(1)
		return true
	return false


func _build() -> void:
	_mgr = root.get_node("/root/SimulationManager")
	_mv = load("res://world/machines/machine_view.gd")
	var sim := Simulation.new()
	sim.size = Vector2i(10, 8)
	sim.default_width = 5
	var bs := sim.place("bit_splitter", Vector2i(1, 1), 0, {"lo": 3})
	var dm := sim.place("demux", Vector2i(5, 1), 0)
	_expect(bs != null and bs.type == "bit_splitter", "bit_splitter placed")
	_expect(dm != null and dm.type == "demux", "demux placed")
	# Point the autoload at this throwaway sim so MachineView.refresh can read it.
	_mgr.sim = sim
	_mgr.run = null
	_mgr.mission = null
	_mgr.in_lab = false
	_mgr.running = false
	_mgr.view_mode = -1
	_mgr.alpha = 0.0
	# Build a MachineView per machine and refresh once.
	for id in sim.sorted_machine_ids():
		var mv: Node2D = _mv.new()
		mv.setup(sim.machines[id])
		root.add_child(mv)
		mv.refresh(0.016)
	_step = 1


func _check() -> void:
	var sim: Simulation = _mgr.sim
	var bs_id := -1
	for id in sim.sorted_machine_ids():
		if sim.machines[id].type == "bit_splitter":
			bs_id = id
	_expect(bs_id >= 0, "bit_splitter machine present")
	if bs_id >= 0:
		for c in root.get_children():
			var mv := c as Node2D
			if mv != null and mv.has_method("setup") and mv.machine != null and mv.machine.id == bs_id:
				var tags: Array = mv._tag_values
				_expect(tags == [5, 2, 3], "bit_splitter width tags == [5,2,3] (got %s)" % str(tags))
				print("VIEWS PASS")
				quit(0)
				return
		_fail = "bit_splitter MachineView not found"
		_step = 99
	else:
		_step = 99


func _expect(cond: bool, what: String) -> void:
	if not cond and _fail == "":
		_fail = what
