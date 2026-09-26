extends Control
## BuildPalette (Penpot 06 + SYSTEMS_EXPANSION §9 palette QoL, 232×330 at 88,68): a search field
## (`/` focuses it, Enter builds the first match), category tabs with ★ (favourites + recently
## built) first, and a scrolling list of PaletteItems: Default / Selected (family stroke) /
## New (green) / Locked (muted + lock + the honest requirement, e.g. "Unlocks at L9 · Sorting").
## Machines that no level unlocks yet are not listed at all.

const TABS := [["quick", "icon_star", "Favourites and recent"], ["math", "op_add", "Math"], ["logic", "op_compare", "Logic"],
	["routing", "op_split", "Routing"], ["storage", "op_buffer", "Storage"], ["thermal", "", "Cooling"], ["power", "icon_power", "Power"]]
const TAB_PITCH := 32.0  # 7 tabs across the 232 px panel
const IO_TYPES := ["input", "usb_input", "output", "terminal_output", "usb_output"]
const ITEM_H := 56.0
const LIST_TOP := 90.0
const LIST_H := 234.0
const MAX_RECENTS := 5

var tools: Node
var _bound := false
var _cat := ""
var _tabs := {}  # cat -> [box, icon]
var _search: LineEdit
var _items: Control
var _item_boxes := {}  # type -> Panel
var _pulsed := {}  # type -> true (a New dot already pulsed this mission)
var _scroll := 0.0
var _favs: Array = []
var _recents: Array = []


func _ready() -> void:
	position = Vector2(88, 68)
	size = Vector2(232, 330)
	HudKit.box(self, Vector2.ZERO, size, Palette.SURFACE_PANEL, Color(0, 0, 0, 0), 0, 10)
	_build_search()
	for i in TABS.size():
		var cat: String = TABS[i][0]
		var p := Vector2(8 + i * TAB_PITCH, 44)
		var b := HudKit.box(self, p, Vector2(TAB_PITCH - 4.0, 36), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6)
		var ic: Control
		if str(TABS[i][1]) != "":
			ic = HudKit.icon(b, TABS[i][1], Vector2(6, 8), 20, Palette.TEXT_MUTED)
		else:
			ic = FinIcon.new()  # the cooling tab: the heatsink fin motif (no icon asset exists)
			ic.position = Vector2(6, 8)
			ic.size = Vector2(20, 20)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(ic)
		_tabs[cat] = [b, ic]
		HudKit.hit(self, p, Vector2(TAB_PITCH - 4.0, 36), func(): _select_cat(cat), TABS[i][2])
	HudKit.box(self, Vector2(8, 86), Vector2(216, 1), Palette.SURFACE_BORDER)
	_items = Control.new()
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_items.clip_contents = true
	_items.position = Vector2(0, LIST_TOP)
	_items.size = Vector2(232, LIST_H)
	add_child(_items)
	var prefs := SaveStore.load_prefs()
	_favs = (prefs.get("favourites", []) as Array).filter(func(t): return Catalog.has(str(t)))
	_recents = (prefs.get("recents", []) as Array).filter(func(t): return Catalog.has(str(t)))
	_mgr().mission_loaded.connect(func(_d): _on_mission())
	_on_mission()


func _build_search() -> void:
	_search = LineEdit.new()
	_search.position = Vector2(8, 8)
	_search.size = Vector2(216, 28)
	_search.placeholder_text = "Search machines   /"
	_search.add_theme_font_override("font", TclTheme.font(HudKit.W_MEDIUM))
	_search.add_theme_font_size_override("font_size", 11)
	_search.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	_search.add_theme_color_override("font_placeholder_color", Palette.TEXT_MUTED)
	_search.add_theme_color_override("caret_color", Palette.DATA_NUMBER)
	_search.add_theme_stylebox_override("normal", HudKit.style(Palette.SURFACE_SUNKEN, Palette.SURFACE_BORDER, 1, 6))
	_search.add_theme_stylebox_override("focus", HudKit.style(Palette.SURFACE_SUNKEN, Palette.DATA_NUMBER, 1, 6))
	_search.text_changed.connect(func(_t): _scroll = 0.0; _build_items())
	_search.text_submitted.connect(_on_search_submit)
	_search.gui_input.connect(_on_search_input)
	add_child(_search)


func _mgr() -> Node:
	return get_node("/root/SimulationManager")


func _on_mission() -> void:
	var d: MissionDef = _mgr().mission
	if d == null:
		return
	_cat = ""
	for t in Catalog.ORDER:
		if t in d.allowed and not t in IO_TYPES:
			_cat = Catalog.category_of(t)
			break
	if _cat == "" or not _tabs.has(_cat):
		_cat = "math"
	_select_cat(_cat)


func _select_cat(cat: String) -> void:
	_cat = cat
	_scroll = 0.0
	for c in _tabs:
		var on: bool = c == cat and _search.text.strip_edges() == ""
		HudKit.restyle(_tabs[c][0], Palette.SURFACE_RAISED if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6)
	_build_items()


## Every machine the palette may list: in the Lab, what is unlocked now or by a later level (an
## honest lock); in a tutorial mission, what the mission allows.
func _listable(d: MissionDef) -> Array:
	var out := []
	var lab: bool = _mgr().in_lab
	for t in Catalog.ORDER:
		if t in IO_TYPES or not Catalog.has(t):
			continue
		if t in d.allowed or (lab and LabDef.unlock_level(t) >= 0):
			out.append(t)
	return out


func _build_items() -> void:
	for ch in _items.get_children():
		ch.queue_free()
	_item_boxes.clear()
	var d: MissionDef = _mgr().mission
	if d == null:
		return
	var all := _listable(d)
	var q := _search.text.strip_edges().to_lower()
	var types := []
	if q != "":
		for t in all:
			if str(Catalog.def(t)["name"]).to_lower().contains(q) or t.contains(q):
				types.append(t)
	elif _cat == "quick":
		for t in _favs + _recents:
			if t in all and not t in types:
				types.append(t)
	else:
		for t in all:
			if Catalog.category_of(t) == _cat:
				types.append(t)
	# allowed first, then locked (stable)
	var open := types.filter(func(t): return t in d.allowed)
	var locked := types.filter(func(t): return not t in d.allowed)
	types = open + locked
	var max_scroll := maxf(0.0, types.size() * ITEM_H - LIST_H + 4.0)
	_scroll = clampf(_scroll, 0.0, max_scroll)
	if types.is_empty():
		var msg := "No machine matches “%s”" % q if q != "" else ("Star ☆ a machine or build one to keep it here" if _cat == "quick" else "Nothing here yet")
		HudKit.label(_items, msg, Vector2(12, 12), 10, HudKit.W_MEDIUM, Palette.TEXT_MUTED, 208)
		return
	for i in types.size():
		var y := 4.0 + i * ITEM_H - _scroll
		if y > LIST_H or y + 48.0 < 0.0:
			continue
		_item(types[i], Vector2(8, y), d)


func _requirement(type: String) -> String:
	if _mgr().in_lab:
		var lvl := LabDef.unlock_level(type)
		if lvl >= 0:
			return "Unlocks at L%d · %s" % [lvl + 1, str(LabDef.level(lvl).get("title", ""))]
	return "Locked"


func _item(type: String, pos: Vector2, d: MissionDef) -> void:
	var def := Catalog.def(type)
	var allowed: bool = type in d.allowed
	var is_new: bool = type in d.unlocks
	var fill := Palette.SURFACE_SUNKEN if allowed else Palette.SURFACE_PANEL
	var stroke := Palette.STATE_VALID if is_new else Palette.SURFACE_BORDER
	var b := HudKit.box(_items, pos, Vector2(216, 48), fill, stroke, 1, 8)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_boxes[type] = b
	b.set_meta("base", [fill, stroke])
	var tile := HudKit.box(b, Vector2(8, 10), Vector2(28, 28), Palette.MATERIAL_PLATE, Palette.MATERIAL_FRAME, 1, 4)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudKit.machine_icon(tile, type, Vector2(4, 4), 20, Palette.TEXT_PRIMARY if allowed else Palette.TEXT_MUTED)
	HudKit.label(b, str(def["name"]), Vector2(44, 8), 11, HudKit.W_XBOLD, Palette.TEXT_PRIMARY if allowed else Palette.TEXT_MUTED, 130)
	var sub := "%d tick · %d power" % [int(def["ticks"]), int(def["power"])] if allowed else _requirement(type)
	if allowed and ThermalGrid.COOLERS.has(type):
		sub = "cools r%d · %d power" % [int(ThermalGrid.COOLERS[type][1]), int(def["power"])]
	elif allowed and type == "heat_pipe":
		sub = "carries heat · 0 power"
	HudKit.label(b, sub, Vector2(44, 26), 9, HudKit.W_MEDIUM, Palette.TEXT_MUTED, 144 if allowed else 164)
	if not allowed:
		HudKit.icon(b, "icon_lock", Vector2(190, 16), 16, Palette.TEXT_MUTED)
		return
	var hb := HudKit.hit(_items, pos, Vector2(216, 48), func(): if tools: tools.begin_place(type), str(def["desc"]))
	HudKit.card_hover(b, hb, stroke)
	# favourite star (on top of the item's hit area)
	var fav: bool = type in _favs
	HudKit.icon(b, "icon_star" if fav else "icon_star_empty", Vector2(188, 16), 16, Palette.MATERIAL_GOLD if fav else Palette.TEXT_MUTED)
	HudKit.hit(_items, pos + Vector2(182, 10), Vector2(28, 28), func(): _toggle_fav(type), "Unfavourite" if fav else "Favourite")
	if is_new and not _pulsed.has(type):
		_pulsed[type] = true
		HudKit.pulse_new(HudKit.dot(b, Vector2(172, 12), 6, Palette.STATE_VALID))


func _toggle_fav(type: String) -> void:
	if type in _favs:
		_favs.erase(type)
	else:
		_favs.append(type)
	_save_prefs()
	_build_items.call_deferred()  # never free the button that is handling this click


func _on_placed(type: String) -> void:
	_recents.erase(type)
	_recents.push_front(type)
	while _recents.size() > MAX_RECENTS:
		_recents.pop_back()
	_save_prefs()
	if _cat == "quick":
		_build_items.call_deferred()


func _save_prefs() -> void:
	SaveStore.save_prefs({"favourites": _favs, "recents": _recents})


func _on_search_submit(_text: String) -> void:
	var d: MissionDef = _mgr().mission
	var q := _search.text.strip_edges().to_lower()
	_search.release_focus()
	if d == null or q == "":
		return
	for t in _listable(d):
		if t in d.allowed and (str(Catalog.def(t)["name"]).to_lower().contains(q) or t.contains(q)):
			if tools:
				tools.begin_place(t)
			return


func _on_search_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
		_search.text = ""
		_search.release_focus()
		_build_items()
		_search.accept_event()


func _input(e: InputEvent) -> void:
	# the wheel scrolls the list (not the camera) while the pointer is over the palette
	if e is InputEventMouseButton and e.pressed and visible:
		var mb := e as InputEventMouseButton
		var over := get_global_rect().has_point(mb.position)
		if over and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_scroll += ITEM_H * 0.5 * (-1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0)
			_build_items()
			get_viewport().set_input_as_handled()
		elif not _search.get_global_rect().has_point(mb.position) and _search.has_focus():
			_search.release_focus()  # a click elsewhere hands the keys back to the board


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_SLASH:
		_search.grab_focus()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if tools == null:
		return
	if not _bound:
		_bound = true
		tools.placed.connect(_on_placed)
	for type in _item_boxes:
		var b: Panel = _item_boxes[type]
		if not is_instance_valid(b):
			continue
		var base: Array = b.get_meta("base")
		if tools.tool == "place" and tools.place_type == type:
			HudKit.restyle(b, Palette.SURFACE_RAISED, Palette.family(Catalog.def(type)["family"]), 1.5, 8)
		else:
			HudKit.restyle(b, base[0], base[1], 1, 8)


## 20 px cooling glyph: a spreader base with four fins, in the tab icon colour.
class FinIcon extends Control:
	func _draw() -> void:
		var c := Palette.TEXT_MUTED
		draw_rect(Rect2(3, 15, 14, 2), c)
		for i in 4:
			draw_rect(Rect2(4 + i * 3.5, 4, 1.6, 11), c)

