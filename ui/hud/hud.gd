extends Control
## HUD root (canonical HUD V2, design/reference/hud_v2_geometry.md). Full-rect, ignores the mouse
## except over its panels. Builds the panels and binds them to the World's ToolController.

var tools: Node
var _menu: Control
var _toast: Panel
var _toast_label: Label
var _toast_t := 0.0
var _banner: Panel
var _banner_label: Label
var _banner_sub: Label
var _banner_t := 0.0
var _banner_tw: Tween
var _banner_base := Vector2.ZERO
var _lab_last_files := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = TclTheme.get_theme()
	tools = get_tree().get_first_node_in_group("tools")
	var top := _panel("res://ui/hud/top_bar.gd")
	var rail := _panel("res://ui/hud/tool_rail.gd")
	var palette := _panel("res://ui/hud/build_palette.gd")
	var inspector := _panel("res://ui/hud/inspector.gd")
	_panel("res://ui/hud/mission_summary.gd")
	var tooltip := _panel("res://ui/hud/tooltip.gd")
	var card := _panel("res://ui/hud/hover_card.gd")
	var bar := _panel("res://ui/hud/quick_bar.gd")
	_panel("res://ui/hud/result_panel.gd")
	_panel("res://ui/hud/overlay_legend.gd")
	_panel("res://ui/hud/view_dock.gd")
	_menu = _panel("res://ui/hud/main_menu.gd")
	rail.tools = tools
	palette.tools = tools
	if tools:
		inspector.bind_tools(tools)
		tooltip.bind_tools(tools)
		card.bind_tools(tools)
		bar.tools = tools
		tools.notice.connect(_notice)
	top.menu_pressed.connect(open_menu)
	_build_toast()
	_build_banner()


func _panel(path: String) -> Control:
	var c := Control.new()
	c.set_script(load(path))
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


## Toast: bottom centre, auto-hide after 2.5 s; errors get a red stroke.
func _build_toast() -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_toast = HudKit.box(holder, Vector2(-240, -112), Vector2(480, 36), Palette.SURFACE_RAISED, Palette.SURFACE_BORDER, 1, 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = HudKit.label(_toast, "", Vector2(0, 10), 11, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 480, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.visible = false


## Level-complete banner: centred, non-modal, auto-hides after 3 s (STATE_VALID stroke).
func _build_banner() -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	move_child(holder, _menu.get_index())  # notifications stay BELOW modals (menu, result)
	_banner = HudKit.box(holder, Vector2(-210, -112), Vector2(420, 64), Palette.SURFACE_RAISED, Palette.STATE_VALID, 1.5, 8)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label = HudKit.label(_banner, "", Vector2(0, 12), 14, HudKit.W_XBOLD, Palette.STATE_VALID, 420, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub = HudKit.label(_banner, "", Vector2(0, 38), 11, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY, 420, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.visible = false


func _show_level_banner() -> void:
	var sm := get_node("/root/SimulationManager")
	if sm.lab_run == null:
		return
	var lr: LabRun = sm.lab_run
	var lv: Dictionary = LabDef.level(lr.frontier())  # the quest that just arrived brings these
	HudKit.set_text(_banner_label, "TASK COMPLETE", Palette.STATE_VALID)
	if sm.lab_run.all_done():
		HudKit.set_text(_banner_label, "ALL CONTRACTS COMPLETE", Palette.STATE_VALID)
		lv = {}  # the last level's unlocks were already shown when it started
	var unlocked := ""
	var names := PackedStringArray()
	for t in lv.get("unlocks", []):
		names.append(str(Catalog.def(t)["name"]))
	if not names.is_empty():
		unlocked = " · unlocked: " + ", ".join(names)
	var done := lr.quest_title(lr.last_filed) if lr.last_filed >= 0 else ""
	HudKit.set_text(_banner_sub, "Q%d %s filed%s" % [lr.last_filed + 1, done, unlocked], Palette.TEXT_SECONDARY)
	if sm.lab_run.all_done():
		HudKit.set_text(_banner_sub, "Free build — the Lab is yours. More levels are coming.", Palette.TEXT_SECONDARY)
	_banner_base = _banner.position
	_banner.visible = true
	_banner_t = 3.0
	HudKit.kill(_banner_tw)
	if HudKit.REDUCED_MOTION:
		_banner.modulate.a = 1.0
		_banner.position = _banner_base
		return
	_banner.modulate.a = 0.0
	_banner.position = _banner_base + Vector2(0, -24)
	_banner_tw = HudKit.anim(_banner)
	_banner_tw.tween_property(_banner, "modulate:a", 1.0, 0.26)
	_banner_tw.parallel().tween_property(_banner, "position", _banner_base, 0.26)


func open_menu() -> void:
	if _banner != null:
		_banner.visible = false  # a notification never covers the menu
		_banner_t = 0.0
	if _menu:
		_menu.open()


func _exit_banner() -> void:
	HudKit.kill(_banner_tw)
	if HudKit.REDUCED_MOTION:
		_banner.visible = false
		_banner.modulate.a = 1.0
		_banner.position = _banner_base
		return
	_banner_tw = HudKit.anim(_banner)
	_banner_tw.tween_property(_banner, "modulate:a", 0.0, 0.2)
	_banner_tw.parallel().tween_property(_banner, "position", _banner_base + Vector2(0, -24), 0.2)
	_banner_tw.tween_callback(func():
		_banner.visible = false
		_banner.modulate.a = 1.0
		_banner.position = _banner_base
	)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return  # a text field is being edited
	var sm := get_node("/root/SimulationManager")
	var k := event as InputEventKey
	if k.is_command_or_control_pressed():
		var redo: bool = k.keycode == KEY_Y or (k.keycode == KEY_Z and k.shift_pressed)
		if k.keycode == KEY_Z or k.keycode == KEY_Y:
			if tools != null and tools.has_method("clear_selection"):
				tools.clear_selection()
			var ok: bool = sm.redo() if redo else sm.undo()
			_notice(("Redo" if redo else "Undo") if ok else ("Nothing to redo" if redo else "Nothing to undo"), "info")
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_1: sm.set_speed(sm.SPEEDS[0])
		KEY_2: sm.set_speed(sm.SPEEDS[1])
		KEY_3: sm.set_speed(sm.SPEEDS[2])
		KEY_4: sm.set_speed(sm.SPEEDS[3])
		KEY_N: sm.set_overlay("")
		KEY_B: sm.toggle_overlay("data")
		KEY_F: sm.toggle_overlay("flow")
		KEY_T: sm.toggle_overlay("thermal")
		KEY_P: sm.toggle_overlay("power")


func _notice(text: String, kind: String) -> void:
	var err := kind == "error"
	HudKit.restyle(_toast, Palette.SURFACE_RAISED, Palette.STATE_ERROR if err else Palette.SURFACE_BORDER, 1, 6)
	HudKit.set_text(_toast_label, text, Palette.STATE_ERROR if err else Palette.TEXT_PRIMARY)
	_toast.visible = true
	_toast_t = 2.5


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			_exit_banner()
	var sm := get_node("/root/SimulationManager")
	if sm.in_lab and sm.lab_run != null:
		var files: int = sm.lab_run.files
		if _lab_last_files >= 0 and files > _lab_last_files:
			_show_level_banner()
			var fr: int = sm.lab_run.frontier()
			if fr > 0 and LabDef.size_for(fr) > LabDef.size_for(fr - 1):
				_notice("The lab expanded", "info")
		_lab_last_files = files
	else:
		_lab_last_files = -1
