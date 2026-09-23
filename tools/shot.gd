extends SceneTree
## Screenshot tool (Slice A4a part 2):
##   godot --path . -s tools/shot.gd -- <mission_id> <out.png> [ticks] [zoom] [select_type|-] [k]
## select_type selects that machine (Inspector); k overrides the Add/Compare constant (e.g. a wrong
## value to capture the failure panel). Ticks run through SimulationManager so HUD signals fire.
## Loads main.tscn, loads the mission, builds its reference solution, runs [ticks] sim
## steps (default 0), waits 3 frames with a real renderer, and saves the viewport to
## <out.png>. Rendered offscreen at exactly 1600x900 (the OS window size may be clamped
## by the window manager, so the shot never depends on it).

const WINDOW_SIZE := Vector2i(1600, 900)
const IDLE_FRAMES := 3  # frames to wait after building before capturing

var _mission := ""
var _out_png := ""
var _ticks := 0
var _zoom := 1.0
var _select := ""
var _k := -1
var _state := 0  # 0 = wait one frame, 1 = build + step, 2 = wait for draw, 3 = quit
var _wait := 0
var _viewport: SubViewport


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: godot --path . -s tools/shot.gd -- <mission_id> <out.png> [ticks] [zoom]")
		quit(2)
		return
	_mission = args[0]
	_out_png = args[1]
	_ticks = int(args[2]) if args.size() > 2 else 0
	_zoom = float(args[3]) if args.size() > 3 else 1.0
	_select = args[4] if args.size() > 4 and args[4] != "-" else ""
	_k = int(args[5]) if args.size() > 5 else -1
	# Offscreen render target: fixed size, independent of the OS window.
	_viewport = SubViewport.new()
	_viewport.name = "ShotViewport"
	_viewport.size = WINDOW_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world_scene: PackedScene = load("res://main.tscn")
	if world_scene == null:
		push_error("shot: cannot load res://main.tscn")
		quit(2)
		return
	_viewport.add_child(world_scene.instantiate())


func _process(_delta: float) -> bool:
	match _state:
		0:
			_state = 1
			return false
		1:
			_load_and_build()
			return false
		2:
			_wait += 1
			if _wait >= IDLE_FRAMES:
				_save()
			return false
	return false


func _load_and_build() -> void:
	# Isolate the shot: never load or pollute the real player save (the autoload
	# autosaves the reference solution while we build it).
	SaveStore.set_path("user://shot_save.json")
	SaveStore.clear()
	var manager := root.get_node("/root/SimulationManager")
	manager.load_mission(_mission)
	Solutions.build(manager.sim, _mission)
	for id in manager.sim.sorted_machine_ids():
		var m = manager.sim.machines[id]
		if _k >= 0 and m.params.has("k"):
			manager.sim.set_param(id, "k", _k)
		if _select != "" and m.type == _select:
			_viewport.get_node("Main/World/Tools")._set_selection(id, -1)
	manager.sim.reset_run()
	for i in _ticks:
		if manager.run.status != MissionRun.Status.RUNNING:
			break
		manager._do_step()
	# Camera: board centre with the requested zoom (fit_to_board already centred it).
	var rig := _viewport.get_node("Main/World/CameraRig")
	if rig != null:
		rig.set_zoom_level(_zoom)
	_state = 2
	_wait = 0


func _save() -> void:
	var img := _viewport.get_texture().get_image()
	var err := img.save_png(_out_png)
	if err != OK:
		push_error("shot: failed to write %s (err %d)" % [_out_png, err])
		quit(1)
		return
	print("shot: wrote %s  (%dx%d)" % [_out_png, img.get_width(), img.get_height()])
	quit(0)