extends Control
## HUD root (canonical HUD V2, design/reference/hud_v2_geometry.md). Full-rect, ignores the mouse
## except over its panels. Builds the panels and binds them to the World's ToolController.

var tools: Node
var _toast: Panel
var _toast_label: Label
var _toast_t := 0.0


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
	_panel("res://ui/hud/result_panel.gd")
	rail.tools = tools
	palette.tools = tools
	if tools:
		inspector.bind_tools(tools)
		tooltip.bind_tools(tools)
		tools.notice.connect(_notice)
	top.menu_pressed.connect(func(): _notice("Menu: coming with the mission select screen", "info"))
	_build_toast()


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
	_toast = HudKit.box(holder, Vector2(-240, -84), Vector2(480, 36), Palette.SURFACE_RAISED, Palette.SURFACE_BORDER, 1, 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = HudKit.label(_toast, "", Vector2(0, 10), 11, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 480, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.visible = false


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
