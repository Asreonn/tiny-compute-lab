extends Control
## BuildPalette (Penpot 06, 232×330 at 88,68): category tabs + PaletteItems for the mission's
## machines. Default / Selected (family stroke) / New (green) / Locked (muted + lock).

const CAT_ICON := {"io": "io_input", "math": "op_add", "logic": "op_compare", "routing": "op_split", "storage": "op_buffer"}
const IO_TYPES := ["input", "usb_input", "output"]

var tools: Node
var _cat := ""
var _tabs := {}  # cat -> [box, icon]
var _items: Control
var _item_boxes := {}  # type -> Panel


func _ready() -> void:
	position = Vector2(88, 68)
	size = Vector2(232, 330)
	HudKit.box(self, Vector2.ZERO, size, Palette.SURFACE_PANEL, Color(0, 0, 0, 0), 0, 10)
	for i in Catalog.CATEGORIES.size():
		var cat: String = Catalog.CATEGORIES[i]["id"]
		var p := Vector2(8 + i * 44, 8)
		var b := HudKit.box(self, p, Vector2(40, 36), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6)
		var ic := HudKit.icon(b, CAT_ICON.get(cat, "icon_components"), Vector2(10, 8), 20, Palette.TEXT_MUTED)
		_tabs[cat] = [b, ic]
		HudKit.hit(self, p, Vector2(40, 36), func(): _select_cat(cat), Catalog.CATEGORIES[i]["label"])
	HudKit.box(self, Vector2(8, 50), Vector2(216, 1), Palette.SURFACE_BORDER)
	_items = Control.new()
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_items)
	_mgr().mission_loaded.connect(func(_d): _on_mission())
	_on_mission()


func _mgr() -> Node:
	return get_node("/root/SimulationManager")


func _on_mission() -> void:
	var d: MissionDef = _mgr().mission
	if d == null:
		return
	_cat = ""
	for t in Catalog.ORDER:
		if t in d.allowed:
			_cat = Catalog.category_of(t)
			break
	if _cat == "":
		_cat = "math"
	_select_cat(_cat)


func _select_cat(cat: String) -> void:
	_cat = cat
	for c in _tabs:
		var on: bool = c == cat
		HudKit.restyle(_tabs[c][0], Palette.SURFACE_RAISED if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6)
	_build_items()


func _build_items() -> void:
	for ch in _items.get_children():
		ch.queue_free()
	_item_boxes.clear()
	var d: MissionDef = _mgr().mission
	var types := []
	for t in Catalog.ORDER:
		if t in IO_TYPES or Catalog.category_of(t) != _cat:
			continue
		types.append(t)
	# allowed first, then locked
	types.sort_custom(func(a, b): return (a in d.allowed) and not (b in d.allowed))
	for i in mini(types.size(), 4):
		_item(types[i], Vector2(8, 60 + i * 56), d)


func _item(type: String, pos: Vector2, d: MissionDef) -> void:
	var def := Catalog.def(type)
	var allowed: bool = type in d.allowed
	var is_new: bool = type in d.unlocks
	var fill := Palette.SURFACE_SUNKEN if allowed else Palette.SURFACE_PANEL
	var stroke := Palette.STATE_VALID if is_new else Palette.SURFACE_BORDER
	var b := HudKit.box(_items, pos, Vector2(176, 48), fill, stroke, 1, 8)
	_item_boxes[type] = b
	b.set_meta("base", [fill, stroke])
	var tile := HudKit.box(b, Vector2(8, 10), Vector2(28, 28), Palette.MATERIAL_PLATE, Palette.MATERIAL_FRAME, 1, 4)
	HudKit.icon(tile, str(def["icon"]), Vector2(4, 4), 20, Palette.TEXT_PRIMARY if allowed else Palette.TEXT_MUTED)
	HudKit.label(b, str(def["name"]), Vector2(44, 8), 11, HudKit.W_XBOLD, Palette.TEXT_PRIMARY if allowed else Palette.TEXT_MUTED, 110)
	var sub := "%d tick · %d power" % [int(def["ticks"]), int(def["power"])] if allowed else "Locked"
	HudKit.label(b, sub, Vector2(44, 26), 9, HudKit.W_MEDIUM, Palette.TEXT_MUTED, 120)
	if is_new:
		HudKit.dot(b, Vector2(164, 12), 6, Palette.STATE_VALID)
	if not allowed:
		HudKit.icon(b, "icon_lock", Vector2(150, 16), 16, Palette.TEXT_MUTED)
		return
	HudKit.hit(_items, pos, Vector2(176, 48), func(): if tools: tools.begin_place(type), str(def["desc"]))


func _process(_delta: float) -> void:
	if tools == null:
		return
	for type in _item_boxes:
		var b: Panel = _item_boxes[type]
		var base: Array = b.get_meta("base")
		if tools.tool == "place" and tools.place_type == type:
			HudKit.restyle(b, Palette.SURFACE_RAISED, Palette.family(Catalog.def(type)["family"]), 1.5, 8)
		else:
			HudKit.restyle(b, base[0], base[1], 1, 8)
