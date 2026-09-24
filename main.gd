extends Node
## Main scene root (Slice A4a part 2). Instances the World and an empty HUD CanvasLayer and loads
## the persistent Lab (the tutorial stays reachable via load_mission).
## On a real launch it opens the title screen on the laptop's lid (ui/menu/title_screen.gd); its
## Continue plays the laptop intro (docs/MOTION_SYSTEM.md §10). Neither runs when the scene is
## instanced by a tool/test script, under a headless display, or with `--no-intro`.

const TITLE_SCREEN := preload("res://ui/menu/title_screen.gd")

## restart(true): the next load skips the title screen (New Lab → straight into the intro).
static var _skip_title_once := false


func _ready() -> void:
	GameSettings.apply()
	SimulationManager.load_lab()
	if not _intro_allowed():
		return
	var skip_title := _skip_title_once
	_skip_title_once = false
	if skip_title and not bool(GameSettings.get_value("intro")):
		return
	play_intro(not skip_title)


func _intro_allowed() -> bool:
	if get_tree().current_scene != self:
		return false  # instanced by tools/*.gd or tests: keep their frames deterministic
	if DisplayServer.get_name() == "headless":
		return false
	return not ("--no-intro" in OS.get_cmdline_user_args() or "--no-intro" in OS.get_cmdline_args())


## Plays the laptop intro once the board, camera fit and HUD layout have settled. `with_title`
## holds it on the lid with the title screen until the player continues (the intro setting only
## decides whether the dive plays afterwards).
func play_intro(with_title := false) -> IntroLaptop:
	await get_tree().process_frame
	await get_tree().process_frame
	var world := $World as World
	var sim := SimulationManager.sim
	if world == null or sim == null:
		return null
	var intro := IntroLaptop.new()
	intro.name = "IntroLaptop"
	intro.hold = with_title
	intro.skip_dive = not bool(GameSettings.get_value("intro"))  # Settings → Intro: Skipped
	world.add_child(intro)
	intro.setup(sim, world.camera_rig, $HUD/HudRoot)
	if with_title:
		show_title(intro)
	return intro


## The title screen over the held intro (tools/title_shot.gd calls it directly).
func show_title(intro: IntroLaptop) -> Control:
	var layer := CanvasLayer.new()
	layer.name = "TitleLayer"
	layer.layer = 20
	add_child(layer)
	var ts: Control = TITLE_SCREEN.new()
	ts.name = "TitleScreen"
	ts.main = self
	ts.intro = intro
	layer.add_child(ts)
	return ts


## Reload the whole game (New Lab, or back to the title from the in-game menu).
func restart(skip_title: bool) -> void:
	_skip_title_once = skip_title
	get_tree().reload_current_scene()
