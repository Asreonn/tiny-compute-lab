extends Control
## ToolRail (Penpot 06, 56×236 at 16,68): select / wire / delete / rotate. Active = number-dim fill
## + number stroke.

const TOOLS := [["select", "tool_select", "Select / move (V)"], ["wire", "tool_wire", "Wire (W)"],
	["delete", "tool_delete", "Delete (X)"], ["rotate", "tool_rotate", "Rotate (R)"]]

var tools: Node
var _boxes := {}
var _icons := {}


func _ready() -> void:
	position = Vector2(16, 68)
	size = Vector2(56, 236)
	HudKit.box(self, Vector2.ZERO, size, Palette.SURFACE_PANEL, Color(0, 0, 0, 0), 0, 10)
	for i in TOOLS.size():
		var t: Array = TOOLS[i]
		var p := Vector2(4, 6 + i * 56)
		_boxes[t[0]] = HudKit.box(self, p, Vector2(48, 48), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6)
		_icons[t[0]] = HudKit.icon(self, t[1], p + Vector2(12, 12), 24, Palette.TEXT_SECONDARY)
		var tool_name: String = t[0]
		HudKit.hit(self, p, Vector2(48, 48), func(): if tools: tools.set_tool(tool_name), t[2])


func _process(_delta: float) -> void:
	if tools == null:
		return
	for tool_name in _boxes:
		var on: bool = tools.tool == tool_name
		HudKit.restyle(_boxes[tool_name], Palette.DATA_NUMBER_DIM if on else Color(0, 0, 0, 0), Palette.DATA_NUMBER if on else Color(0, 0, 0, 0), 1 if on else 0, 6)
		_icons[tool_name].modulate = Palette.DATA_NUMBER if on else Palette.TEXT_SECONDARY
