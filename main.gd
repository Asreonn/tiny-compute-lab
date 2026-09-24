extends Node
## Main scene root (Slice A4a part 2). Instances the World and an empty HUD CanvasLayer;
## boots straight into the persistent Lab (the tutorial stays reachable via load_mission).
## On a real launch it plays the laptop intro (docs/MOTION_SYSTEM.md §10); never when the scene
## is instanced by a tool/test script, under a headless display, or with `--no-intro`.

func _ready() -> void:
	SimulationManager.load_lab()
	if _intro_allowed():
		play_intro()


func _intro_allowed() -> bool:
	if get_tree().current_scene != self:
		return false  # instanced by tools/*.gd or tests: keep their frames deterministic
	if DisplayServer.get_name() == "headless":
		return false
	return not ("--no-intro" in OS.get_cmdline_user_args() or "--no-intro" in OS.get_cmdline_args())


## Plays the laptop intro once the board, camera fit and HUD layout have settled.
func play_intro() -> IntroLaptop:
	await get_tree().process_frame
	await get_tree().process_frame
	var world := $World as World
	var sim := SimulationManager.sim
	if world == null or sim == null:
		return null
	var intro := IntroLaptop.new()
	intro.name = "IntroLaptop"
	world.add_child(intro)
	intro.setup(sim, world.camera_rig, $HUD/HudRoot)
	return intro
