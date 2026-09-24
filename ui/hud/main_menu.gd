extends Control
## MainMenu (modal overlay like ResultPanel): BG_VOID 60% dim + centred SURFACE_PANEL panel.
## A large LAB card (Continue the lab) and a grid of Penpot MissionCards for Missions.all().
## Opening pauses the simulation; Esc / the cross closes; clicking a card loads that mission.

const W := 620.0
const H := 440.0
const CARD_W := 180.0
const CARD_H := 96.0
const GAP := 16.0
const COLS := 3

var _dim: ColorRect
var _panel: Panel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_to_group("main_menu")


func _mgr() -> Node:
	return get_node("/root/SimulationManager")


## Open the modal: dim the world, pause the simulation, build the content.
func open() -> void:
	_mgr().pause()
	visible = true
	_build()


func close() -> void:
	visible = false
	if _dim:
		_dim.queue_free()
		_dim = null


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	if _dim:
		_dim.queue_free()
	_dim = ColorRect.new()
	_dim.color = Color(Palette.BG_VOID, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.add_child(holder)
	_panel = HudKit.box(holder, Vector2(-W / 2, -H / 2), Vector2(W, H), Palette.SURFACE_PANEL, Palette.SURFACE_BORDER_STRONG, 1, 10)

	HudKit.label(_panel, "TINY COMPUTE LAB", Vector2(0, 24), 20, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, W, HORIZONTAL_ALIGNMENT_CENTER)
	HudKit.icon(_panel, "icon_cross", Vector2(W - 34, 18), 20, Palette.TEXT_SECONDARY)
	HudKit.hit(_panel, Vector2(W - 40, 14), Vector2(28, 28), close, "Close")

	_lab_card()
	HudKit.label(_panel, "TUTORIAL", Vector2(24, 172), 9, HudKit.W_XBOLD, Palette.TEXT_SECONDARY)
	_grid()


func _lab_card() -> void:
	var sm := _mgr()
	var title := "Level 1 · First Contact"
	if sm.lab_run != null:
		var lvl: int = sm.lab_run.level
		title = "Level %d · %s" % [lvl + 1, sm.lab_run.title()]
	var card := HudKit.box(_panel, Vector2(120, 60), Vector2(380, 96), Palette.SURFACE_RAISED, Palette.DATA_NUMBER, 1, 8)
	card.add_to_group("lab_card")
	HudKit.label(card, "Continue the lab", Vector2(24, 20), 14, HudKit.W_XBOLD, Palette.TEXT_PRIMARY)
	HudKit.label(card, title, Vector2(24, 46), 11, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
	var cb := Callable(func():
		close()
		_mgr().load_lab())
	card.set_meta("on_click", cb)
	HudKit.hit(card, Vector2.ZERO, Vector2(380, 96), cb, "Continue the lab")


func _grid() -> void:
	var missions: Array = Missions.all()
	var y := 200.0
	for i in missions.size():
		var col: int = i % COLS
		@warning_ignore("integer_division")
		var row: int = i / COLS
		var pos := Vector2(24 + col * (CARD_W + GAP), y + row * (CARD_H + GAP))
		_card(pos, missions[i])


func _card(pos: Vector2, d: MissionDef) -> void:
	var unlocked := SaveStore.unlocked(d.id)
	var stars := SaveStore.stars(d.id)
	var completed := stars > 0
	var card := HudKit.box(_panel, pos, Vector2(CARD_W, CARD_H),
		Palette.SURFACE_RAISED if unlocked else Palette.SURFACE_PANEL,
		Palette.DATA_NUMBER if unlocked and not completed else Palette.SURFACE_BORDER, 1, 8)
	card.add_to_group("menu_cards")
	card.set_meta("mission_id", d.id)

	HudKit.label(card, "%02d" % (d.index + 1), Vector2(14, 12), 10, HudKit.W_MEDIUM, Palette.TEXT_MUTED)
	var title_color := Palette.DATA_NUMBER if completed else (Palette.TEXT_PRIMARY if unlocked else Palette.TEXT_MUTED)
	HudKit.label(card, d.title, Vector2(14, 34), 14, HudKit.W_XBOLD, title_color, 150)
	HudKit.label(card, d.teaches, Vector2(14, 56), 10, HudKit.W_MEDIUM,
		Palette.TEXT_SECONDARY if unlocked else Palette.TEXT_MUTED, 150)

	if not unlocked:
		HudKit.icon(card, "icon_lock", Vector2(152, 12), 16, Palette.TEXT_MUTED)
		return
	if completed:
		for i in 3:
			HudKit.icon(card, "icon_star" if i < stars else "icon_star_empty", Vector2(14 + i * 20, 72), 16,
				Palette.FAMILY_ROUTING if i < stars else Palette.TEXT_MUTED)
	else:
		HudKit.dot(card, Vector2(160, 16), 6, Palette.STATE_VALID)
	var cb := Callable(func():
		close()
		_mgr().load_mission(d.id))
	card.set_meta("on_click", cb)
	HudKit.hit(card, Vector2.ZERO, Vector2(CARD_W, CARD_H), cb, d.title)
