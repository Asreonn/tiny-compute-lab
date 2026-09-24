extends Control
## ToolRail (Penpot 06, 56 wide at 16,68): select / wire. Delete and rotate are actions now
## (quick action bar, X / Del, R — SYSTEMS_EXPANSION §9), not modes. A single selection
## highlight slides to the active tool (160 ms) instead of per-button toggling.

const TOOLS := [["select", "tool_select", "Select / move (Q)"], ["wire", "tool_wire", "Wire (W)"]]

var tools: Node
var _boxes := {}
var _icons := {}
var _highlight: Panel
var _last_tool := ""
var _hl_tw: Tween


func _ready() -> void:
	position = Vector2(16, 68)
	size = Vector2(56, 12 + TOOLS.size() * 56)
	HudKit.box(self, Vector2.ZERO, size, Palette.SURFACE_PANEL, Color(0, 0, 0, 0), 0, 10)
	_highlight = HudKit.box(self, Vector2(4, 6), Vector2(48, 48), Palette.DATA_NUMBER_DIM, Palette.DATA_NUMBER, 1, 6)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in TOOLS.size():
		var t: Array = TOOLS[i]
		var p := Vector2(4, 6 + i * 56)
		var tool_name: String = t[0]
		_boxes[tool_name] = HudKit.icon_button(self, p, Vector2(48, 48), t[1], Vector2(12, 12), 24,
			func(): if tools: tools.set_tool(tool_name), t[2], 6)
		_icons[tool_name] = _boxes[tool_name].get_meta("ib_icon")


func _process(_delta: float) -> void:
	if tools == null:
		return
	var active: String = tools.tool
	for tool_name in _boxes:
		var on: bool = tool_name == active
		HudKit.set_icon_color(_boxes[tool_name], Palette.DATA_NUMBER if on else Palette.TEXT_SECONDARY)
	if active != _last_tool:
		_last_tool = active
		_slide(active)


func _slide(tool_name: String) -> void:
	var idx := 0
	for i in TOOLS.size():
		if TOOLS[i][0] == tool_name:
			idx = i
			break
	var target := Vector2(4, 6 + idx * 56)
	HudKit.kill(_hl_tw)
	if HudKit.REDUCED_MOTION:
		_highlight.position = target
		return
	_hl_tw = HudKit.anim(self)
	_hl_tw.tween_property(_highlight, "position", target, 0.16)
