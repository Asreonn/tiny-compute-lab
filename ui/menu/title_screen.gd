extends Control
## Title screen (main menu). It lives ON the laptop's screen: the laptop intro waits on its first
## frame with the camera on the lid (IntroLaptop.hold), the intro draws the title, and this layer
## lays a row of tiles over the lid screen, scaled with it. Continue releases the intro — the
## camera dives into the keyboard and the HUD slides in.
##
## Pages: main (Continue / Tutorial / Settings / New Lab / Quit), tutorial (the missions), settings
## (sound, motion, screen, intro) and the New Lab confirmation. Mouse or ← → / Enter / Esc.

const BASE := Vector2(1360, 424)  # design size of the lid screen; everything scales with it
const TILE := Vector2(196, 116)
const GAP := 16.0
const ROW_Y := 204.0
const FADE := 0.25

var main: Node  # main.gd: restart()
var intro: IntroLaptop
var _content: Control
var _page := "main"
var _tiles: Array = []  # [{box, action, arg, danger, primary}]
var _focus := 0
var _leaving := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # the world and HUD wait until the menu is gone
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.size = BASE
	add_child(_content)
	_show_page("main")
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.0 if HudKit.REDUCED_MOTION else 0.4)


func _sm() -> Node:
	return get_node("/root/SimulationManager")


func _process(_delta: float) -> void:
	if intro == null or not is_instance_valid(intro):
		return
	var ct := get_viewport().get_canvas_transform()
	var r: Rect2 = intro.screen_rect()
	var p0: Vector2 = ct * r.position
	var p1: Vector2 = ct * r.end
	var s := (p1.x - p0.x) / BASE.x
	_content.position = p0
	_content.scale = Vector2(s, s)


# ------------------------------------------------------------------ pages

func _show_page(page: String) -> void:
	_page = page
	for c in _content.get_children():
		c.queue_free()
	_tiles.clear()
	match page:
		"main": _page_main()
		"tutorial": _page_tutorial()
		"settings": _page_settings()
		"confirm": _page_confirm()
	_layout_tiles()
	# the keyboard starts on the page's primary (safe) choice: Continue, or "Keep my Lab"
	_focus = 0
	for i in _tiles.size():
		if _tiles[i]["primary"]:
			_focus = i
			break
	_refresh_focus()
	var hint := "← →  choose     Enter  open" + ("" if page == "main" else "     Esc  back")
	HudKit.label(_content, hint, Vector2(0, BASE.y - 40), 12, HudKit.W_MEDIUM, Palette.TEXT_MUTED, BASE.x, HORIZONTAL_ALIGNMENT_CENTER)


func _tagline(text: String, color := Palette.TEXT_SECONDARY) -> void:
	HudKit.label(_content, text, Vector2(0, 136), 16, HudKit.W_MEDIUM, color, BASE.x, HORIZONTAL_ALIGNMENT_CENTER)


func _page_main() -> void:
	_tagline("Build a computer, one bit at a time.")
	var lr = _sm().lab_run
	var fresh: bool = lr == null or (lr.level == 0 and _player_machines() == 0)
	var sub := "First Contact"
	if lr != null:
		sub = "Free build" if lr.all_done() else "Level %d · %s" % [lr.level + 1, lr.title()]
	_add("continue", "Start the Lab" if fresh else "Continue", sub, "icon_play", {"primary": true})
	_add("tutorial", "Tutorial", "%d short missions" % Missions.all().size(), "icon_mission")
	_add("settings", "Settings", "Sound · motion · screen", "icon_menu")
	_add("new", "New Lab", "Start the factory over", "icon_reset", {"danger": true})
	_add("quit", "Quit", "See you soon", "icon_cross")


func _page_tutorial() -> void:
	_tagline("Short missions that teach one idea each. The Lab is the real game.")
	for d in Missions.all():
		var md: MissionDef = d
		var open := SaveStore.unlocked(md.id)
		var stars := SaveStore.stars(md.id)
		var sub := md.teaches if open else "Finish the one before"
		if stars > 0:
			sub = "★".repeat(stars) + "☆".repeat(3 - stars) + "  " + md.teaches
		_add("mission" if open else "locked", "%02d  %s" % [md.index + 1, md.title], sub, "icon_mission" if open else "icon_lock", {"arg": md.id, "muted": not open})
	_add("back", "Back", "Main menu", "icon_chevron_left")


func _page_settings() -> void:
	_tagline("Settings are saved on this computer.")
	var vol := int(GameSettings.get_value("volume"))
	_add("volume", "Sound", "Volume %d %%" % vol if vol > 0 else "Muted", "icon_rate_out")
	_add("motion", "Motion", "Reduced" if bool(GameSettings.get_value("reduced_motion")) else "Full animation", "icon_latency")
	_add("screen", "Screen", "Fullscreen" if bool(GameSettings.get_value("fullscreen")) else "Window", "icon_inspect")
	_add("intro", "Intro", "Plays at launch" if bool(GameSettings.get_value("intro")) else "Skipped", "icon_play")
	_add("back", "Back", "Main menu", "icon_chevron_left")


func _page_confirm() -> void:
	var lr = _sm().lab_run
	var lvl: int = (lr.level + 1) if lr != null else 1
	_tagline("Start over? Level %d and your whole factory will be erased. Tutorial stars are kept." % lvl, Palette.STATE_BLOCKED)
	_add("erase", "Erase and restart", "This cannot be undone", "icon_reset", {"danger": true})
	_add("back", "Keep my Lab", "Back to the menu", "icon_chevron_left", {"primary": true})


func _player_machines() -> int:
	var sim: Simulation = _sm().sim
	var n := 0
	if sim != null:
		for id in sim.machines:
			if not sim.machines[id].locked:
				n += 1
	return n


# ------------------------------------------------------------------ tiles

func _add(action: String, title: String, sub: String, icon: String, opts := {}) -> void:
	_tiles.append({"action": action, "title": title, "sub": sub, "icon": icon, "arg": opts.get("arg", ""),
		"danger": opts.get("danger", false), "primary": opts.get("primary", false), "muted": opts.get("muted", false)})


func _layout_tiles() -> void:
	var n := _tiles.size()
	# more than 6 tiles (the tutorial list): two rows of compact tiles
	var compact := n > 6
	var tile := Vector2(160, 84) if compact else TILE
	var per_row := ceili(n / 2.0) if compact else n
	var total := per_row * tile.x + (per_row - 1) * GAP
	var x0 := (BASE.x - total) * 0.5
	for i in n:
		var t: Dictionary = _tiles[i]
		var row := i / per_row
		var col := i % per_row
		var pos := Vector2(x0 + col * (tile.x + GAP), (ROW_Y - 36.0 + row * (tile.y + 12.0)) if compact else ROW_Y)
		t["compact"] = compact
		var box := HudKit.box(_content, pos, tile, Palette.SURFACE_PANEL, Palette.SURFACE_BORDER, 1, 10)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t["box"] = box
		t["home"] = pos
		var muted: bool = t["muted"]
		var ic := Palette.STATE_ERROR if t["danger"] else (Palette.DATA_NUMBER if t["primary"] else Palette.TEXT_SECONDARY)
		var title := str(t["title"])
		if compact:
			HudKit.icon(box, str(t["icon"]), Vector2(14, 12), 18, Palette.TEXT_MUTED if muted else ic)
			var cfs := 13 if title.length() <= 16 else 11
			HudKit.label(box, title, Vector2(14, 38), cfs, HudKit.W_XBOLD, Palette.TEXT_MUTED if muted else Palette.TEXT_PRIMARY, tile.x - 22)
			HudKit.label(box, str(t["sub"]), Vector2(14, 60), 10, HudKit.W_MEDIUM, Palette.TEXT_MUTED, tile.x - 24)
		else:
			HudKit.icon(box, str(t["icon"]), Vector2(18, 18), 22, Palette.TEXT_MUTED if muted else ic)
			var fs := 16 if title.length() <= 14 else (14 if title.length() <= 16 else 12)  # fit long names
			HudKit.label(box, title, Vector2(18, 54 + (16 - fs) * 0.5), fs, HudKit.W_XBOLD, Palette.TEXT_MUTED if muted else Palette.TEXT_PRIMARY, TILE.x - 26)
			HudKit.label(box, str(t["sub"]), Vector2(18, 82), 11, HudKit.W_MEDIUM, Palette.TEXT_MUTED, TILE.x - 30)
		var idx := i
		var hb := HudKit.hit(_content, pos, tile, func(): _activate(idx), str(t["title"]))
		hb.mouse_entered.connect(func():
			_focus = idx
			_refresh_focus())
		HudKit.card_entrance(box, i)


func _refresh_focus() -> void:
	for i in _tiles.size():
		var t: Dictionary = _tiles[i]
		var box: Panel = t.get("box")
		if box == null or not is_instance_valid(box):
			continue
		var on := i == _focus
		var stroke := Palette.SURFACE_BORDER
		if t["primary"]:
			stroke = Palette.DATA_NUMBER
		if on:
			stroke = Color(Palette.STATE_ERROR, 0.7) if t["danger"] else (Palette.DATA_NUMBER if t["primary"] else Palette.SURFACE_BORDER_STRONG)
		HudKit.restyle(box, Palette.SURFACE_RAISED if on else Palette.SURFACE_PANEL, stroke, 1.5 if (on or t["primary"]) else 1.0, 10)
		var home: Vector2 = t["home"]
		box.position.y = home.y - (3.0 if on else 0.0)


func _activate(i: int) -> void:
	if _leaving or i < 0 or i >= _tiles.size():
		return
	var t: Dictionary = _tiles[i]
	match str(t["action"]):
		"continue":
			_leave(func(): intro.release())
		"tutorial":
			_show_page("tutorial")
		"settings":
			_show_page("settings")
		"new":
			_show_page("confirm")
		"quit":
			get_tree().quit()
		"back":
			_show_page("main")
		"mission":
			var id := str(t["arg"])
			_leave(func():
				intro.skip()
				_sm().load_mission(id))
		"locked":
			pass
		"volume":
			var v := int(GameSettings.get_value("volume"))
			GameSettings.set_value("volume", 100 if v <= 0 else v - 25)
			_rebuild_keep_focus(i)
		"motion":
			GameSettings.set_value("reduced_motion", not bool(GameSettings.get_value("reduced_motion")))
			_rebuild_keep_focus(i)
		"screen":
			GameSettings.set_value("fullscreen", not bool(GameSettings.get_value("fullscreen")))
			_rebuild_keep_focus(i)
		"intro":
			GameSettings.set_value("intro", not bool(GameSettings.get_value("intro")))
			_rebuild_keep_focus(i)
		"erase":
			SaveStore.reset_lab()
			_leaving = true
			main.restart(true)


func _rebuild_keep_focus(i: int) -> void:
	_show_page(_page)
	_focus = i
	_refresh_focus()


## Fade out, then run `then` (release the intro / start a mission) and go away.
func _leave(then: Callable) -> void:
	_leaving = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.0 if HudKit.REDUCED_MOTION else FADE)
	tw.tween_callback(func():
		then.call()
		var layer := get_parent()
		if layer is CanvasLayer:
			layer.queue_free()
		else:
			queue_free())


func _input(event: InputEvent) -> void:
	if _leaving or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	get_viewport().set_input_as_handled()  # the board and HUD never see keys under the menu
	if not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_LEFT:
			_focus = (_focus - 1 + _tiles.size()) % _tiles.size()
			_refresh_focus()
		KEY_RIGHT, KEY_TAB:
			_focus = (_focus + 1) % _tiles.size()
			_refresh_focus()
		KEY_UP, KEY_DOWN:
			var per_row := ceili(_tiles.size() / 2.0) if _tiles.size() > 6 else _tiles.size()
			var step := per_row if _tiles.size() > 6 else 1
			_focus = clampi(_focus + (step if k.keycode == KEY_DOWN else -step), 0, _tiles.size() - 1)
			_refresh_focus()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate(_focus)
		KEY_ESCAPE:
			if _page != "main":
				_show_page("main")
