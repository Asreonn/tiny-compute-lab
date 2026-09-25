class_name ToolController
extends Node2D
## Slice A5a: board tools + input. Interprets mouse/keyboard on top of the read-only
## world layers and routes EVERY simulation mutation through SimulationManager.request_edit
## followed by a public Simulation method (place/remove/rotate/move/connect/disconnect).
##
## Public interface consumed by the (future) HUD:
##   signals: tool_changed(tool), selection_changed(machine_id, conn_id), hover_changed(info),
##           notice(text, kind)
##   methods: set_tool(name), begin_place(type), clear_selection()
##   vars:    tool, selected_machine, selected_conn

signal tool_changed(tool_name: String)
signal selection_changed(machine_id: int, conn_id: int)  # -1 = none
signal hover_changed(info: Dictionary)  # {} or {kind, id, port, screen_pos}
signal notice(text: String, kind: String)  # kind "info"|"error"
signal placed(type: String)  # a machine was placed from the palette / a duplicate (recents)

const T := Palette.TILE
const PORT_HIT_PX := 12.0
const WIRE_HIT_PX := 8.0
const PACKET_HIT_PX := 10.0
const DRAG_START_PX := 4.0  # world px an LMB must travel before it becomes a drag
const EDGE_ASSIST_PX := 16.0  # wire mode: a click this close to a machine edge picks its nearest port

var tool := "select"  # "select" | "wire" | "place" (delete / rotate are actions, not modes)
var last_place_type := ""  # E builds this again (SYSTEMS_EXPANSION §9 control map)
var selected_machine := -1
var selected_conn := -1
## Multi-select (SYSTEMS_EXPANSION §9): 2+ machines picked with a box; moved, duplicated or
## deleted together. Empty when the selection is a single machine / wire.
var selected_group: Array = []

var _world: Node2D
var _machine_layer: Node2D
var _wire_layer: Node2D
var _packet_layer: PacketLayer
var _overlay_layer: Node2D
var _preview: PreviewLayer
var _move_preview: MovePreview  # connected move: origin ghost + hologram routes

# --- placement ghost ("place" tool)
var place_type := ""  # non-empty while a placement ghost is being dragged around
var place_rot := 0
var place_params := {}  # duplicate: the source's parameters ({} = defaults)
var place_width := 0  # duplicate: the source's width (0 = mission default)
var _settings_clip := {}  # Ctrl+Shift+C: {type, name, params, width}
var _ghost_view: MachineView = null
var _ghost_pad: Sprite2D = null
var _ghost_cell := Vector2i(-1, 0)

# --- drags
var _press_world := Vector2.ZERO
var _press_hit := {}
var _lmb_down := false
var _move_drag := {}  # {machine_id: int, cell: Vector2i, from: Vector2i}
var _wire_drag := {}  # {from_id: int, from_port: String, error?: String}
var _preview_cells: Array = []  # route shown by the wire preview (committed as-is on release)
var _preview_target := {}  # {id, port} of the valid target under the cursor, or {}
var _hover := {}
var _box := {}  # box select: {start, cur, active}
var _group_drag := {}  # {ids, grab: Vector2i, delta: Vector2i, dup, carry, preview}
var _group_ghosts: Array = []  # ghost pads + MachineViews of a group drag


func _ready() -> void:
	_world = get_parent()
	_machine_layer = _world.get_node("MachineLayer")
	_wire_layer = _world.get_node("WireLayer")
	_packet_layer = _world.get_node("PacketLayer")
	_overlay_layer = _world.get_node("OverlayLayer")
	_preview = PreviewLayer.new()
	_preview.name = "ToolPreview"
	_overlay_layer.add_child(_preview)
	_move_preview = MovePreview.new()
	_move_preview.name = "MovePreview"
	_overlay_layer.add_child(_move_preview)
	SimulationManager.run_finished.connect(_on_run_finished)
	SimulationManager.ticked.connect(_on_ticked)
	SimulationManager.layout_changed.connect(_on_layout_changed)


# ============================================================ public API

func set_tool(tool_name: String) -> void:
	if tool == "place":
		_clear_place()
	tool = tool_name
	tool_changed.emit(tool)


func begin_place(type: String) -> void:
	if not Catalog.has(type):
		return
	if tool == "place":
		_clear_place()
	place_type = type
	last_place_type = type
	place_rot = 0
	place_params = {}
	place_width = 0
	tool = "place"
	tool_changed.emit(tool)


func clear_selection() -> void:
	_set_selection(-1, -1)


## Select several machines as a group (2+ unlocked; 1 falls back to a single selection).
func select_group(ids: Array) -> void:
	var sim := SimulationManager.sim
	var keep := []
	for id in ids:
		if sim != null and sim.machines.has(id) and not sim.machines[id].locked:
			keep.append(id)
	if keep.size() == 1:
		_set_selection(keep[0], -1)
		return
	selected_machine = -1
	selected_conn = -1
	selected_group = keep
	_apply_selection()
	selection_changed.emit(-1, -1)


## Ctrl+D / quick bar on a group: pick up a copy of the whole group; the next click drops it.
func duplicate_group() -> void:
	if selected_group.is_empty():
		return
	var sim := SimulationManager.sim
	var first: Machine = sim.machines[selected_group[0]]
	_group_drag = {"ids": selected_group.duplicate(), "grab": first.cell, "delta": Vector2i(-99999, 0), "dup": true, "carry": true}
	hover_changed.emit({})
	_update_group_drag(get_global_mouse_position())


# ------------------------------------------------------------------ clipboard (Ctrl+C / X / V / D / A)

## A snapshot of the last copied / cut machines (and the wires between them): pasting works even
## after the originals are gone.
var clipboard: Dictionary = {}


func _selection_ids() -> Array:
	if not selected_group.is_empty():
		return selected_group.duplicate()
	return [selected_machine] if selected_machine >= 0 else []


## Ctrl+C (cut: Ctrl+X) — the selected machine or group goes to the clipboard.
func copy_selection(cut := false) -> void:
	var sim := SimulationManager.sim
	var ids := _selection_ids()
	if sim == null or ids.is_empty():
		notice.emit("Select machines to %s" % ("cut" if cut else "copy"), "info")
		return
	var clip := sim.copy_group(ids)
	if clip.is_empty():
		notice.emit("Mission I/O can't be copied", "error")
		return
	clipboard = clip
	var n: int = (clip["machines"] as Array).size()
	if cut:
		_delete_selection()
	notice.emit("%s %d machine%s" % ["Cut" if cut else "Copied", n, "" if n == 1 else "s"], "info")


## Ctrl+V — the clipboard lands under the pointer (or the nearest free spot) and is selected.
func paste_clipboard() -> void:
	if clipboard.is_empty():
		notice.emit("Nothing to paste — copy machines with Ctrl+C", "info")
		return
	_paste_near(_cell_of(get_global_mouse_position()), "Pasted")


## Ctrl+D — a copy of the selection right beside it (the clipboard is left alone).
func duplicate_selection() -> void:
	var sim := SimulationManager.sim
	var ids := _selection_ids()
	if sim == null or ids.is_empty():
		notice.emit("Select machines to duplicate", "info")
		return
	var clip := sim.copy_group(ids)
	if clip.is_empty():
		notice.emit("Mission I/O can't be duplicated", "error")
		return
	var r := Rect2i()
	for id in ids:
		if sim.machines.has(id) and not sim.machines[id].locked:
			var m: Machine = sim.machines[id]
			var fr := Rect2i(m.cell, Catalog.size_of(m.type, m.rot))
			r = fr if r.size == Vector2i.ZERO else r.merge(fr)
	var saved := clipboard
	clipboard = clip
	_paste_near(r.position + Vector2i(r.size.x + 1, 0), "Duplicated")
	clipboard = saved


func _paste_near(at: Vector2i, verb: String) -> void:
	var sim := SimulationManager.sim
	if sim == null:
		return
	# the copy's footprint stays on the board (the pointer may be over the desk or the HUD)
	var span := Vector2i.ONE
	for e in clipboard.get("machines", []):
		span = span.max((e["cell"] as Vector2i) + Catalog.size_of(str(e["type"]), int(e["rot"])))
	at = at.clamp(Vector2i.ZERO, (sim.size - span).max(Vector2i.ZERO))
	SimulationManager.request_edit()
	var ids := []
	for ring in 12:
		for spot in _ring_cells(at, ring):
			ids = sim.paste_group(clipboard, spot)
			if not ids.is_empty():
				break
		if not ids.is_empty():
			break
	if ids.is_empty():
		notice.emit("No room here for the copy", "error")
		return
	AudioBus.event("machine_place")
	if ids.size() == 1:
		_set_selection(ids[0], -1)
	else:
		select_group(ids)
	notice.emit("%s %d machine%s" % [verb, ids.size(), "" if ids.size() == 1 else "s"], "info")


## The cells at Chebyshev distance `r` from `c`, in a fixed order (r = 0: just `c`).
static func _ring_cells(c: Vector2i, r: int) -> Array:
	if r == 0:
		return [c]
	var out := []
	for dx in range(-r, r + 1):
		out.append(c + Vector2i(dx, -r))
		out.append(c + Vector2i(dx, r))
	for dy in range(-r + 1, r):
		out.append(c + Vector2i(-r, dy))
		out.append(c + Vector2i(r, dy))
	return out


## Ctrl+A — every player machine.
func select_all() -> void:
	var sim := SimulationManager.sim
	if sim == null:
		return
	var ids := []
	for id in sim.sorted_machine_ids():
		if not sim.machines[id].locked:
			ids.append(id)
	if ids.is_empty():
		notice.emit("Nothing to select yet", "info")
		return
	select_group(ids)


## Quick bar "Move" on a group: the group follows the pointer until the next click.
func move_group_carry() -> void:
	if selected_group.is_empty():
		return
	var sim := SimulationManager.sim
	var first: Machine = sim.machines[selected_group[0]]
	_group_drag = {"ids": selected_group.duplicate(), "grab": first.cell, "delta": Vector2i(-99999, 0), "dup": false, "carry": true}
	hover_changed.emit({})
	_update_group_drag(get_global_mouse_position())


func delete_group() -> void:
	_delete_selection()


## World-space bounds of the selected group (the quick bar docks under it).
func group_rect() -> Rect2:
	var sim := SimulationManager.sim
	var r := Rect2()
	for id in selected_group:
		if sim == null or not sim.machines.has(id):
			continue
		var m: Machine = sim.machines[id]
		var fr := Rect2(Vector2(m.cell) * T, Vector2(Catalog.size_of(m.type, m.rot)) * T)
		r = fr if r.size == Vector2.ZERO else r.merge(fr)
	return r


func _finish_box() -> void:
	var rect: Rect2 = _move_preview.box
	_move_preview.box = Rect2()
	_move_preview.queue_redraw()
	var sim := SimulationManager.sim
	if sim == null:
		return
	var ids := []
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.locked:
			continue
		var fr := Rect2(Vector2(m.cell) * T, Vector2(Catalog.size_of(m.type, m.rot)) * T)
		if rect.intersects(fr):
			ids.append(id)
	if not ids.is_empty():
		select_group(ids)


func _update_group_drag(world: Vector2) -> void:
	var sim := SimulationManager.sim
	if sim == null:
		return
	var ids: Array = _group_drag["ids"]
	var delta: Vector2i = _cell_of(world) - (_group_drag["grab"] as Vector2i)
	if delta == _group_drag.get("delta", Vector2i(-99999, 0)):
		return
	_group_drag["delta"] = delta
	var preview := {"ok": true, "routes": {}, "fail": [], "error": ""}
	if bool(_group_drag["dup"]):
		for id in ids:
			var m: Machine = sim.machines[id]
			var e := sim.placement_error(m.type, m.cell + delta, m.rot)
			if e != "":
				preview = {"ok": false, "routes": {}, "fail": [], "error": e}
				break
	elif delta != Vector2i.ZERO:
		preview = sim.group_preview(ids, delta)
	_group_drag["preview"] = preview
	# ghosts
	_clear_group_ghosts()
	var ghosts := {}
	for id in ids:
		var m: Machine = sim.machines[id]
		var g := Machine.new(0, m.type, m.cell + delta, m.width, m.rot, m.params)
		ghosts[id] = g
		var key := str(Catalog.def(m.type)["size"]).to_lower()
		var pad := Art.sprite(Art.pad_file("placevalid" if bool(preview["ok"]) else "placeinvalid", key), Vector2(g.cell) * T)
		_overlay_layer.add_child(pad)
		var mv := MachineView.new()
		mv.setup(g, true)
		mv.position = Vector2(g.cell) * T
		_overlay_layer.add_child(mv)
		_group_ghosts.append(pad)
		_group_ghosts.append(mv)
	# wire holograms (a move only; a duplicate copies its internal wires as they are)
	var paths := []
	var affected := []
	if not bool(_group_drag["dup"]):
		var routes: Dictionary = preview.get("routes", {})
		for cid in routes:
			affected.append(cid)
			paths.append([_group_wire_pts(sim, int(cid), ghosts, routes[cid]), "ValidTarget"])
		for cid in preview.get("fail", []):
			affected.append(cid)
			paths.append([_group_wire_pts(sim, int(cid), ghosts, []), "InvalidTarget"])
	_set_pending_removal(affected)
	_move_preview.paths = paths
	_move_preview.origin = Rect2()
	_move_preview.queue_redraw()


func _group_wire_pts(sim: Simulation, cid: int, ghosts: Dictionary, cells: Array) -> PackedVector2Array:
	var c: Connection = sim.connections[cid]
	var fm: Machine = ghosts.get(c.from_id, sim.machines[c.from_id])
	var tm: Machine = ghosts.get(c.to_id, sim.machines[c.to_id])
	return _route_pts(MachineView.port_world(fm, c.from_port), cells, MachineView.port_world(tm, c.to_port))


func _finish_group_drag() -> void:
	var sim := SimulationManager.sim
	var ids: Array = _group_drag.get("ids", [])
	var delta: Vector2i = _group_drag.get("delta", Vector2i.ZERO)
	var dup := bool(_group_drag.get("dup", false))
	var preview: Dictionary = _group_drag.get("preview", {})
	_group_drag = {}
	_clear_group_ghosts()
	_clear_move_preview()
	if sim == null or ids.is_empty() or delta == Vector2i.ZERO or delta.x <= -99999:
		return
	if not bool(preview.get("ok", false)):
		notice.emit(str(preview.get("error", "Can't go there")), "error")
		return
	SimulationManager.request_edit()
	if dup:
		var copies := sim.duplicate_group(ids, delta)
		if copies.is_empty():
			notice.emit(sim.last_error, "error")
		else:
			AudioBus.event("machine_place")
			select_group(copies)
	elif not sim.move_group(ids, delta):
		notice.emit(sim.last_error, "error")
	else:
		select_group(ids)


func _clear_group_ghosts() -> void:
	for n in _group_ghosts:
		if is_instance_valid(n):
			n.queue_free()
	_group_ghosts.clear()


## Quick action bar / Ctrl+D: pick up a copy of the machine (same type, rotation, parameters and
## width) as a placement ghost; the next click drops it.
func duplicate_machine(mid: int) -> void:
	var sim := SimulationManager.sim
	if sim == null or not sim.machines.has(mid) or sim.machines[mid].locked:
		return
	var m: Machine = sim.machines[mid]
	begin_place(m.type)
	place_rot = m.rot
	place_params = m.params.duplicate(true)
	place_width = m.width
	_update_place_ghost(get_global_mouse_position())


## Quick action bar "Move": the machine follows the pointer until the next click drops it.
func begin_move(mid: int) -> void:
	var sim := SimulationManager.sim
	if sim == null or not sim.machines.has(mid) or not sim.machines[mid].movable():
		return
	var m: Machine = sim.machines[mid]
	_move_drag = {"machine_id": mid, "cell": m.cell, "from": m.cell, "carry": true}
	hover_changed.emit({})
	_update_move_ghost(get_global_mouse_position())


func rotate_machine(mid: int) -> void:
	_rotate_machine(mid)


func delete_machine(mid: int) -> void:
	_delete_machine(mid)


## Ctrl+Shift+C: remember the machine's parameters and width (never position or wires).
func copy_settings(mid: int) -> void:
	var sim := SimulationManager.sim
	if sim == null or not sim.machines.has(mid):
		return
	var m: Machine = sim.machines[mid]
	_settings_clip = {"type": m.type, "name": m.label, "params": m.params.duplicate(true), "width": m.width}
	notice.emit("Copied the settings of %s" % m.label, "info")


func has_settings() -> bool:
	return not _settings_clip.is_empty()


## Ctrl+Shift+V: paste the compatible parameters (same key, a valid value for this machine) and
## the width (only onto an unwired machine: a width change would cut its wires).
func paste_settings(mid: int) -> void:
	var sim := SimulationManager.sim
	if sim == null or not sim.machines.has(mid) or _settings_clip.is_empty():
		return
	var m: Machine = sim.machines[mid]
	if m.locked:
		notice.emit("Mission I/O has no settings to paste", "error")
		return
	var defs: Dictionary = m.def()["params"]
	var done := []
	SimulationManager.request_edit()
	for k in _settings_clip["params"]:
		if not defs.has(k):
			continue
		var v = _settings_clip["params"][k]
		if not _param_ok(defs[k], v) or m.params.get(k) == v:
			continue
		if sim.set_param(mid, k, v):
			done.append("%s=%s" % [k, str(v)])
	var w: int = int(_settings_clip.get("width", m.width))
	var wired := false
	for p in m.ports():
		wired = wired or sim.connection_at_port(mid, p["id"]) != null
	if w != m.width and not wired:
		sim.set_width(mid, w)
		done.append("width %d" % w)
	if done.is_empty():
		notice.emit("Nothing to paste onto %s" % m.label, "info")
	else:
		notice.emit("Pasted %s → %s" % [", ".join(done), m.label], "info")


static func _param_ok(pdef: Dictionary, v: Variant) -> bool:
	match str(pdef.get("kind", "")):
		"enum":
			return v in (pdef.get("options", []) as Array)
		"int":
			return typeof(v) in [TYPE_INT, TYPE_FLOAT] and int(v) >= int(pdef.get("min", -1000000)) and int(v) <= int(pdef.get("max", 1000000))
	return true


# ============================================================ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_mouse_motion(get_global_mouse_position())
	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton, get_global_mouse_position())
	elif event is InputEventKey:
		_on_key(event as InputEventKey)


## world: the cursor in world coordinates (a parameter so tests can drive the real path).
func _on_mouse_button(mb: InputEventMouseButton, world: Vector2) -> void:
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SPACE):
		return  # Space + drag pans (CameraRig)
	if mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_lmb_press(world)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# RMB cancels placement / any active drag; never pans while one is active.
			if _dragging() or (tool == "place" and place_type != ""):
				_cancel_drags()
				get_viewport().set_input_as_handled()
	else:
		if mb.button_index == MOUSE_BUTTON_LEFT and _lmb_down:
			_lmb_down = false
			_lmb_release(world)


func _dragging() -> bool:
	return not _wire_drag.is_empty() or not _move_drag.is_empty() or not _group_drag.is_empty() or bool(_box.get("active", false))


func _cancel_drags() -> void:
	if not _wire_drag.is_empty():
		_wire_drag = {}
		_set_pending_removal([])
		_clear_preview()
	if not _move_drag.is_empty():
		_move_drag = {}
		_clear_ghost()
		_clear_move_preview()
	if not _group_drag.is_empty():
		_group_drag = {}
		_clear_group_ghosts()
		_clear_move_preview()
	if not _box.is_empty():
		_box = {}
		_move_preview.box = Rect2()
		_move_preview.queue_redraw()
	if tool == "place" and place_type != "":
		_clear_place()
		set_tool("select")
	_update_hover_immediate()


func _on_key(k: InputEventKey) -> void:
	if not k.pressed or k.echo:
		return
	var key := k.keycode
	if k.is_command_or_control_pressed():
		# Ctrl+Z / Ctrl+Y live in the HUD; Ctrl+Shift+C / V copy a machine's settings
		if key == KEY_C and k.shift_pressed and selected_machine >= 0:
			copy_settings(selected_machine)
		elif key == KEY_V and k.shift_pressed and selected_machine >= 0:
			paste_settings(selected_machine)
		elif key == KEY_C:
			copy_selection()
		elif key == KEY_X:
			copy_selection(true)
		elif key == KEY_V:
			paste_clipboard()
		elif key == KEY_D:
			duplicate_selection()
		elif key == KEY_A:
			select_all()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	# Space is the CameraRig's (tap = play/pause, hold + drag = pan).
	if key == KEY_PERIOD:
		SimulationManager.step_once()
	elif key == KEY_BACKSPACE:
		SimulationManager.reset_run()
	elif key == KEY_Q or key == KEY_V:
		if tool == "place":
			_clear_place()
		set_tool("select")
	elif key == KEY_W:
		set_tool("wire")
	elif key == KEY_E:
		if last_place_type != "" and _allowed(last_place_type):
			begin_place(last_place_type)
			_update_place_ghost(get_global_mouse_position())
	elif key == KEY_R:
		_rotate_key()
	elif key == KEY_X or key == KEY_DELETE:
		_delete_selection()
	elif key == KEY_ESCAPE:
		if tool == "place" and place_type != "":
			_clear_place()
			set_tool("select")
		elif _dragging():
			_cancel_drags()
		else:
			clear_selection()


## R rotates the placement ghost, else the selected machine, else the hovered one.
func _rotate_key() -> void:
	if tool == "place" and place_type != "":
		place_rot = (place_rot + 1) % 4
		var cell := _ghost_cell
		if cell.x < 0:
			cell = _snap_cell(get_global_mouse_position(), place_type, place_rot)
		_rebuild_ghost(cell, place_type, place_rot)
	elif selected_machine >= 0:
		_rotate_machine(selected_machine)
	elif str(_hover.get("kind", "")) in ["machine", "port"]:
		_rotate_machine(int(_hover["id"]))


func _allowed(type: String) -> bool:
	var sm := SimulationManager
	return sm.mission != null and type in sm.mission.allowed


# ============================================================ click actions

func _lmb_press(world: Vector2) -> void:
	_press_world = world
	get_viewport().gui_release_focus()  # a click on the board hands the keys back to the board (shortcuts)
	var sim := SimulationManager.sim
	if sim == null:
		return
	# Every LMB press arms the release (not only in select mode: the wire tool needs it too).
	_lmb_down = true
	if not _wire_drag.is_empty():
		# Click-click wiring: the source was picked with a click, this click picks the target.
		_finish_wire_drag(world)
		_lmb_down = false
		return
	if bool(_move_drag.get("carry", false)):
		_update_move_ghost(world)
		_finish_move_drag()
		_lmb_down = false
		return
	if bool(_group_drag.get("carry", false)):
		_update_group_drag(world)
		_finish_group_drag()
		_lmb_down = false
		return
	if _dragging():
		return
	_press_hit = _hit_at(world)
	match tool:
		"select":
			_lmb_down = true
			if _press_hit.is_empty():
				_set_selection(-1, -1)
				_box = {"start": world, "cur": world, "active": false}  # may become a box select
			else:
				match str(_press_hit.get("kind", "")):
					"machine", "port":
						# pressing a member of the group keeps the group (it can be dragged)
						if not (str(_press_hit["kind"]) == "machine" and int(_press_hit["id"]) in selected_group):
							_set_selection(int(_press_hit["id"]), -1)
					"wire":
						_set_selection(-1, int(_press_hit["id"]))
		"wire":
			if _press_hit.get("kind") == "port":
				_begin_wire(int(_press_hit["id"]), str(_press_hit["port"]), world)
			elif _press_hit.get("kind") == "machine":
				var near := _edge_port(int(_press_hit["id"]), world)
				if near != "":
					_begin_wire(int(_press_hit["id"]), near, world)
		"place":
			_try_place(world)


func _lmb_release(world: Vector2) -> void:
	if not _wire_drag.is_empty():
		if world.distance_to(_press_world) < DRAG_START_PX and _hit_port(world).get("id", -1) == _wire_drag.get("from_id", -2):
			# A click (no drag) on the source port: keep the wire attached to the cursor and
			# finish it with the next click (click-click wiring).
			_press_hit = {}
			return
		_finish_wire_drag(world)
	elif not _move_drag.is_empty():
		_finish_move_drag()
	elif not _group_drag.is_empty():
		_finish_group_drag()
	elif bool(_box.get("active", false)):
		_finish_box()
	else:
		_update_hover(world)
	_box = {}
	_press_hit = {}
	_press_world = Vector2.ZERO
	_update_hover_immediate()


func _on_mouse_motion(world: Vector2) -> void:
	if not _group_drag.is_empty():
		_update_group_drag(world)
	elif not _move_drag.is_empty():
		_update_move_ghost(world)
	elif not _wire_drag.is_empty():
		_update_wire_preview(world)
	elif tool == "place" and place_type != "":
		_update_place_ghost(world)
	else:
		_track_press_drag(world)
		_update_hover(world)


## In select tool: a press that travels beyond DRAG_START_PX becomes a real drag
## (moving an unlocked machine, or wiring from an OUTPUT port).
func _track_press_drag(world: Vector2) -> void:
	if not _lmb_down or tool != "select":
		return
	if _press_hit.is_empty():
		# a drag on the empty board draws the selection box
		if not _box.is_empty() and (bool(_box["active"]) or world.distance_to(_press_world) >= DRAG_START_PX):
			_box["active"] = true
			_box["cur"] = world
			_move_preview.box = Rect2(_box["start"], Vector2.ZERO).expand(world)
			_move_preview.queue_redraw()
		return
	if world.distance_to(_press_world) < DRAG_START_PX:
		return
	var kind := str(_press_hit.get("kind", ""))
	var mid := int(_press_hit.get("id", -1))
	if mid < 0:
		return
	if kind == "machine" and mid in selected_group:
		# drag the whole group (Alt: a duplicate of it)
		_group_drag = {"ids": selected_group.duplicate(), "grab": _cell_of(_press_world), "delta": Vector2i(-99999, 0), "dup": Input.is_key_pressed(KEY_ALT), "carry": false}
		hover_changed.emit({})
		_update_group_drag(world)
		return
	if kind == "port":
		_begin_wire(mid, str(_press_hit["port"]), world)  # any port: an input starts a reverse wire
		return
	var sim := SimulationManager.sim
	if sim != null and sim.machines.has(mid) and sim.machines[mid].movable() and kind == "machine":
		var m: Machine = sim.machines[mid]
		# Alt + drag drags a duplicate; the original stays (never for a USB hub: there is one each)
		_move_drag = {"machine_id": mid, "cell": m.cell, "from": m.cell, "duplicate": Input.is_key_pressed(KEY_ALT) and not m.locked}
		hover_changed.emit({})
		_rebuild_ghost(m.cell, m.type, m.rot)


# ============================================================ select tool

func _set_selection(mid: int, cid: int) -> void:
	selected_machine = mid
	selected_conn = cid
	selected_group = []
	_apply_selection()
	selection_changed.emit(selected_machine, selected_conn)


func _apply_selection() -> void:
	if _machine_layer == null or not is_inside_tree():
		return
	for c in _machine_layer.get_children():
		var mv := c as MachineView
		if mv != null:
			mv.selected = mv.machine != null and (mv.machine.id == selected_machine or mv.machine.id in selected_group)
	for c in _wire_layer.get_children():
		var cv := c as ConnectionView
		if cv != null:
			cv.selected = cv.connection != null and cv.connection.id == selected_conn


func _delete_selection() -> void:
	if not selected_group.is_empty():
		var sim := SimulationManager.sim
		if sim != null:
			SimulationManager.request_edit()
			var n := sim.remove_group(selected_group)
			notice.emit("Deleted %d machines" % n, "info")
			AudioBus.event("machine_delete")
		_set_selection(-1, -1)
		return
	if selected_machine >= 0:
		_delete_machine(selected_machine)
	elif selected_conn >= 0:
		_delete_conn(selected_conn)


func _delete_machine(mid: int) -> void:
	var sim := SimulationManager.sim
	if sim == null or not sim.machines.has(mid):
		return
	if sim.machines[mid].locked:
		notice.emit("Mission I/O can't be removed", "error")
		return
	SimulationManager.request_edit()
	if sim.machines.has(mid):
		sim.remove(mid)
		AudioBus.event("machine_delete")
	_set_selection(-1, -1)


func _delete_conn(cid: int) -> void:
	var sim := SimulationManager.sim
	if sim == null or not sim.connections.has(cid):
		return
	SimulationManager.request_edit()
	sim.disconnect_wire(cid)
	AudioBus.event("wire_disconnect")
	_set_selection(-1, -1)


func _rotate_machine(mid: int) -> void:
	var sim := SimulationManager.sim
	if sim == null or not sim.machines.has(mid):
		return
	var m: Machine = sim.machines[mid]
	if m.locked:
		notice.emit("Mission I/O can't be moved", "error")
		return
	SimulationManager.request_edit()
	if not sim.rotate(mid):
		notice.emit(sim.placement_error(m.type, m.cell, (m.rot + 1) % 4, mid), "error")


# ============================================================ move drag

func _finish_move_drag() -> void:
	var sim := SimulationManager.sim
	var mid := int(_move_drag.get("machine_id", -1))
	var cell: Vector2i = _move_drag.get("cell", Vector2i(-1, 0))
	var from: Vector2i = _move_drag.get("from", Vector2i(-1, 0))
	var dup := bool(_move_drag.get("duplicate", false))
	var preview: Dictionary = _move_drag.get("preview", {})
	_move_drag = {}
	_clear_move_preview()
	if sim == null or mid < 0 or not sim.machines.has(mid) or cell == from or cell.x < 0:
		_clear_ghost()
		return
	var m: Machine = sim.machines[mid]
	if dup:
		_clear_ghost()
		SimulationManager.request_edit()
		var copy := sim.place(m.type, cell, m.rot, m.params.duplicate(true), m.width)
		if copy == null:
			notice.emit(sim.placement_error(m.type, cell, m.rot), "error")
		else:
			_set_selection(copy.id, -1)
		return
	# connected move: commit only when every wire can follow; otherwise snap back untouched
	if preview.is_empty():
		preview = sim.relayout_preview(mid, cell, m.rot)
	if not bool(preview.get("ok", false)):
		notice.emit(str(preview.get("error", "Can't move there")), "error")
		_snap_back_ghost(from)
		return
	_clear_ghost()
	SimulationManager.request_edit()
	if sim.machines.has(mid) and not sim.move(mid, cell):
		notice.emit(sim.last_error, "error")
	_apply_selection()


## A refused move: the hologram glides back to where the machine still stands (180 ms).
func _snap_back_ghost(from: Vector2i) -> void:
	if _ghost_pad != null and is_instance_valid(_ghost_pad):
		_ghost_pad.queue_free()
	_ghost_pad = null
	var gv := _ghost_view
	_ghost_view = null
	_ghost_cell = Vector2i(-1, 0)
	if gv == null or not is_instance_valid(gv):
		return
	var tw := gv.create_tween()
	tw.tween_property(gv, "position", Vector2(from) * T, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(gv.queue_free)


func _update_move_ghost(world: Vector2) -> void:
	var sim := SimulationManager.sim
	var mid := int(_move_drag.get("machine_id", -1))
	if sim == null or not sim.machines.has(mid):
		_move_drag = {}
		_clear_move_preview()
		return
	var m: Machine = sim.machines[mid]
	var cell := _snap_cell(world, m.type, m.rot)
	if _move_drag.has("preview") and cell == _move_drag.get("cell", Vector2i(-1, 0)):
		return  # same tile: the hologram is current
	_move_drag["cell"] = cell
	var from: Vector2i = _move_drag.get("from", cell)
	var preview := {"ok": true, "routes": {}, "fail": [], "error": ""}
	if bool(_move_drag.get("duplicate", false)):
		var err := sim.placement_error(m.type, cell, m.rot)
		preview = {"ok": err == "", "routes": {}, "fail": [], "error": err}
	elif cell != from:
		preview = sim.relayout_preview(mid, cell, m.rot)
	_move_drag["preview"] = preview
	_rebuild_ghost(cell, m.type, m.rot)
	_show_move_preview(m, cell, from, preview)


## Hologram routes for the wires that would follow the move (valid: solid green; failed: red
## dashes with an X) and a dashed outline where the machine stands now. The wires being
## re-routed fade meanwhile.
func _show_move_preview(m: Machine, cell: Vector2i, from: Vector2i, preview: Dictionary) -> void:
	var sim := SimulationManager.sim
	var ghost := Machine.new(0, m.type, cell, m.width, m.rot, m.params)
	var paths := []
	var affected := []
	var routes: Dictionary = preview.get("routes", {})
	for cid in routes:
		affected.append(cid)
		paths.append([_wire_pts(sim, int(cid), m.id, ghost, routes[cid]), "ValidTarget"])
	for cid in preview.get("fail", []):
		affected.append(cid)
		paths.append([_wire_pts(sim, int(cid), m.id, ghost, []), "InvalidTarget"])
	_set_pending_removal(affected)
	_move_preview.origin = Rect2(Vector2(from) * T, Vector2(Catalog.size_of(m.type, m.rot)) * T) if not bool(_move_drag.get("duplicate", false)) else Rect2()
	_move_preview.paths = paths
	_move_preview.queue_redraw()


func _wire_pts(sim: Simulation, cid: int, moving: int, ghost: Machine, cells: Array) -> PackedVector2Array:
	var c: Connection = sim.connections[cid]
	var fm: Machine = ghost if c.from_id == moving else sim.machines[c.from_id]
	var tm: Machine = ghost if c.to_id == moving else sim.machines[c.to_id]
	return _route_pts(MachineView.port_world(fm, c.from_port), cells, MachineView.port_world(tm, c.to_port))


func _clear_move_preview() -> void:
	if _move_preview != null:
		_move_preview.paths = []
		_move_preview.origin = Rect2()
		_move_preview.queue_redraw()
	_set_pending_removal([])


# ============================================================ wire tool

func _update_wire_preview(world: Vector2) -> void:
	var sim := SimulationManager.sim
	if sim == null or _wire_drag.is_empty():
		return
	var fid := int(_wire_drag.get("from_id", -1))
	var fport := str(_wire_drag.get("from_port", ""))
	var rev := bool(_wire_drag.get("reverse", false))
	if not sim.machines.has(fid):
		_clear_preview()
		return
	var from := MachineView.port_world(sim.machines[fid], fport)
	_preview_cells = []
	_preview_target = {}
	_preview.rings = PackedVector2Array()
	# The source's current wire will be replaced by any committed drop: show it faded.
	var doomed := sim.replaced_by(fid, fport, fid, fport)
	var target := _hit_port(world)
	if target.is_empty():
		target = _body_snap(world)  # smart wiring: a body with exactly one compatible port
	if not target.is_empty() and sim.machines.has(int(target["id"])):
		# Over a port: exactly the route that release would place (WYSIWYG).
		var tid := int(target["id"])
		var tport := str(target["port"])
		var to := MachineView.port_world(sim.machines[tid], tport)
		var e := _ends(fid, fport, tid, tport, rev)
		var old := sim.replaced_by(e[0], e[1], e[2], e[3])
		var err := sim.connect_error(e[0], e[1], e[2], e[3], old)
		var r := sim.route_between(e[0], e[1], e[2], e[3])
		if err == "" and bool(r.get("ok", false)):
			_preview_cells = r["cells"]
			_preview_target = {"id": tid, "port": tport}
			_set_pending_removal(old)
			_show_preview(_route_pts(to, _preview_cells, from) if rev else _route_pts(from, _preview_cells, to), "ValidTarget")
			return
		_set_pending_removal(doomed)
		_wire_drag["error"] = err if err != "" else "No route"
		var to_tile: Vector2i = sim.machines[tid].port_geom(tport)["outside"]
		var bad_route := _route_to_cell(sim, fid, fport, to_tile)
		_show_preview(_route_pts(from, bad_route, to), "InvalidTarget")
		return
	# Free drag: live route from the source to the tile under the cursor.
	_wire_drag.erase("error")
	_set_pending_removal(doomed)
	var cells := _route_to_cell(sim, fid, fport, _cell_of(world))
	if cells.is_empty():
		_show_preview(PackedVector2Array([from, world]), "ConnectionPreview")
	else:
		_show_preview(_route_pts(from, cells, Vector2.INF), "ConnectionPreview")


## [out id, out port, in id, in port] of a wire between the drag source and a target.
static func _ends(fid: int, fport: String, tid: int, tport: String, rev: bool) -> Array:
	return [tid, tport, fid, fport] if rev else [fid, fport, tid, tport]


## Smart wiring: over a machine body, the one port a drop would connect to — or {} and the
## candidates ringed when several fit (or none).
func _body_snap(world: Vector2) -> Dictionary:
	var sim := SimulationManager.sim
	var h := _hit_machine(world)
	if h.is_empty():
		return {}
	var tid := int(h["id"])
	var fid := int(_wire_drag.get("from_id", -1))
	var fport := str(_wire_drag.get("from_port", ""))
	var rev := bool(_wire_drag.get("reverse", false))
	if tid == fid or not sim.machines.has(tid):
		return {}
	var tm: Machine = sim.machines[tid]
	var fits := []
	for pd in tm.ports():
		var pid := str(pd["id"])
		if (pd["dir"] == Catalog.DIR_OUT) != rev:
			continue
		var e := _ends(fid, fport, tid, pid, rev)
		if sim.connect_error(e[0], e[1], e[2], e[3], sim.replaced_by(e[0], e[1], e[2], e[3])) != "":
			continue
		if bool(sim.route_between(e[0], e[1], e[2], e[3]).get("ok", false)):
			fits.append(pid)
	if fits.size() == 1:
		return {"id": tid, "port": fits[0]}
	for pid in fits:
		_preview.rings.append(MachineView.port_world(tm, pid))
	return {}


## Wire mode edge assist: the port nearest to a click within EDGE_ASSIST_PX of the machine edge.
func _edge_port(mid: int, world: Vector2) -> String:
	var sim := SimulationManager.sim
	if sim == null or not sim.machines.has(mid):
		return ""
	var m: Machine = sim.machines[mid]
	var r := Rect2(Vector2(m.cell) * T, Vector2(Catalog.size_of(m.type, m.rot)) * T)
	var edge := minf(minf(world.x - r.position.x, r.end.x - world.x), minf(world.y - r.position.y, r.end.y - world.y))
	if edge > EDGE_ASSIST_PX:
		return ""
	var best := ""
	var best_d := INF
	for pd in m.ports():
		var d := world.distance_to(MachineView.port_world(m, str(pd["id"])))
		if d < best_d:
			best_d = d
			best = str(pd["id"])
	return best


## Start a wire from an output port. An output that already carries a wire can be rewired:
## its wire stays until a new connection is committed, then it is replaced (QoL).
func _begin_wire(mid: int, port: String, world: Vector2) -> void:
	_wire_drag = {"from_id": mid, "from_port": port, "reverse": _port_dir(mid, port) != Catalog.DIR_OUT}
	hover_changed.emit({})  # no tooltips while dragging a wire
	_update_wire_preview(world)


## Fade exactly the wires in `ids` (the ones a committed drop would replace); restore the rest.
func _set_pending_removal(ids: Array) -> void:
	if _wire_layer == null:
		return
	for c in _wire_layer.get_children():
		var cv := c as ConnectionView
		if cv != null and cv.connection != null and not cv.is_queued_for_deletion():
			var on: bool = cv.connection.id in ids
			if cv.pending_removal != on:
				cv.pending_removal = on


func _cell_of(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / T), floori(world.y / T))


## Router path from the tile outside the source port to `goal` (a free tile); [] if none.
func _route_to_cell(sim: Simulation, fid: int, fport: String, goal: Vector2i) -> Array:
	var ga: Dictionary = sim.machines[fid].port_geom(fport)
	var occ := sim.occupancy()
	if occ.has(goal) or goal.x < 0 or goal.y < 0 or goal.x >= sim.size.x or goal.y >= sim.size.y:
		return []
	var sd: Vector2i = Catalog.side_vec(ga["side"])
	return Router.route(sim.size, occ, sim.wire_tiles(), ga["outside"], sd, goal, Vector2i.ZERO)


## Draw points for a route: source anchor, tile centres, then the target anchor (if given).
func _route_pts(from: Vector2, cells: Array, to: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	for c in cells:
		pts.append(Vector2(c) * T + Vector2.ONE * (T * 0.5))
	if to != Vector2.INF:
		pts.append(to)
	return pts


## Release/click: commit exactly the previewed route (WYSIWYG) to the previewed target.
## Anything else reports why; existing wires are never touched.
func _finish_wire_drag(world: Vector2) -> void:
	var sim := SimulationManager.sim
	var fid := int(_wire_drag.get("from_id", -1))
	var fport := str(_wire_drag.get("from_port", ""))
	var rev := bool(_wire_drag.get("reverse", false))
	_update_wire_preview(world)  # the preview for exactly this cursor position
	var target := _preview_target
	var cells := _preview_cells
	var err := str(_wire_drag.get("error", ""))
	_clear_preview()
	_wire_drag = {}
	_preview_cells = []
	_preview_target = {}
	if sim == null or not sim.machines.has(fid):
		return
	_set_pending_removal([])
	if not target.is_empty():
		SimulationManager.request_edit()
		# commit: replaces the source's / target's old wires atomically (only now)
		var e := _ends(fid, fport, int(target["id"]), str(target["port"]), rev)
		if sim.rewire(e[0], e[1], e[2], e[3], cells) != null:
			AudioBus.event("wire_connect")
			return
		err = sim.last_error
	if err == "" and _hit_port(world).is_empty():
		return  # released on empty board: just cancel, nothing to explain
	notice.emit(err if err != "" else "No route", "error")
	_update_hover_immediate()


# ============================================================ place tool

func _try_place(world: Vector2) -> void:
	var sim := SimulationManager.sim
	if sim == null or place_type == "":
		return
	var cell := _snap_cell(world, place_type, place_rot)
	SimulationManager.request_edit()
	var m := sim.place(place_type, cell, place_rot, place_params, place_width)
	if m == null:
		notice.emit(sim.placement_error(place_type, cell, place_rot), "error")
		return
	placed.emit(place_type)
	AudioBus.event("machine_place")
	if Input.is_key_pressed(KEY_SHIFT):
		_rebuild_ghost(_snap_cell(world, place_type, place_rot), place_type, place_rot)
	else:
		_clear_place()
		set_tool("select")
	_set_selection(m.id, -1)


func _update_place_ghost(world: Vector2) -> void:
	if place_type == "":
		return
	_rebuild_ghost(_snap_cell(world, place_type, place_rot), place_type, place_rot)


func _clear_place() -> void:
	place_type = ""
	place_rot = 0
	place_params = {}
	place_width = 0
	_clear_ghost()


# ============================================================ ghost

## A ghost MachineView at 60 % alpha with the InstallPad replaced by the
## placevalid/placeinvalid <size> pad, snapped to tiles. Move ghosts copy the live machine
## params; placement ghosts use defaults.
func _rebuild_ghost(cell: Vector2i, type: String, rot: int) -> void:
	_clear_ghost()
	var sim := SimulationManager.sim
	if sim == null:
		return
	var ghost_m := Machine.new(0, type, cell, place_width if place_width > 0 else sim.default_width, rot % 4, place_params if not place_params.is_empty() else Catalog.default_params(type))
	if _move_drag.has("machine_id") and sim.machines.has(int(_move_drag["machine_id"])):
		var src: Machine = sim.machines[int(_move_drag["machine_id"])]
		ghost_m.params = src.params.duplicate()
		ghost_m.width = src.width
	var key := str(Catalog.def(type)["size"]).to_lower()
	var moving := int(_move_drag.get("machine_id", -1)) if not bool(_move_drag.get("duplicate", false)) else -1
	var err := sim.placement_error(type, cell, rot, moving)
	if err == "" and not bool((_move_drag.get("preview", {}) as Dictionary).get("ok", true)):
		err = "route"
	var pad := Art.sprite(Art.pad_file("placevalid" if err == "" else "placeinvalid", key), Vector2(cell) * T)
	_ghost_pad = pad
	_overlay_layer.add_child(pad)
	var mv := MachineView.new()
	_ghost_view = mv
	mv.setup(ghost_m, true)
	mv.position = Vector2(cell) * T
	_overlay_layer.add_child(mv)
	_ghost_cell = cell


func _clear_ghost() -> void:
	_ghost_cell = Vector2i(-1, 0)
	if _ghost_view != null and is_instance_valid(_ghost_view):
		_ghost_view.queue_free()
	_ghost_view = null
	if _ghost_pad != null and is_instance_valid(_ghost_pad):
		_ghost_pad.queue_free()
	_ghost_pad = null


func _snap_cell(world: Vector2, type: String, rot: int) -> Vector2i:
	var s := Catalog.size_of(type, rot)
	var c := Vector2i(floori(world.x / T), floori(world.y / T))
	@warning_ignore("integer_division")
	c -= Vector2i((s.x - 1) / 2, (s.y - 1) / 2)
	return c


# ============================================================ preview

func _show_preview(pts: PackedVector2Array, state: String) -> void:
	_preview.pts = pts
	_preview.state = state
	_preview.queue_redraw()


func _clear_preview() -> void:
	_preview.pts = PackedVector2Array()
	_preview.rings = PackedVector2Array()
	_preview.state = ""
	_preview.queue_redraw()


# ============================================================ hover

func _update_hover_immediate() -> void:
	if not _dragging() and not (tool == "place" and place_type != ""):
		_update_hover(get_global_mouse_position())


func _update_hover(world: Vector2) -> void:
	var h := _hit_at(world)
	if h.is_empty() and _hover.is_empty():
		return
	if not h.is_empty() and h.get("id", -1) == _hover.get("id", -1) and h.get("kind", "") == _hover.get("kind", "") and h.get("port", "") == _hover.get("port", ""):
		return
	_hover = h
	_apply_hover(h)
	hover_changed.emit(h)


func _apply_hover(h: Dictionary) -> void:
	if _machine_layer == null:
		return
	for c in _machine_layer.get_children():
		var mv := c as MachineView
		if mv != null:
			mv.hovered = false
	for c in _wire_layer.get_children():
		var cv := c as ConnectionView
		if cv != null:
			cv.hovered = false
	if h.is_empty():
		return
	if h.get("kind", "") in ["machine", "port"]:
		for c in _machine_layer.get_children():
			var mv := c as MachineView
			if mv != null and mv.machine != null and mv.machine.id == int(h.get("id", -1)):
				mv.hovered = true
				break
	elif h.get("kind", "") == "wire":
		for c in _wire_layer.get_children():
			var cv := c as ConnectionView
			if cv != null and cv.connection != null and cv.connection.id == int(h.get("id", -1)):
				cv.hovered = true
				break


# ============================================================ hit testing

## Priority: port (12 px) > packet (10 px) > machine (footprint rect) > wire (8 px polyline).
func _hit_at(world: Vector2) -> Dictionary:
	var h := _hit_port(world)
	if not h.is_empty():
		return h
	h = _hit_packet(world)
	if not h.is_empty():
		return h
	h = _hit_machine(world)
	if not h.is_empty():
		return h
	return _hit_wire(world)


func _hit_port(world: Vector2) -> Dictionary:
	var sim := SimulationManager.sim
	if sim == null:
		return {}
	for mid in sim.sorted_machine_ids():
		var m: Machine = sim.machines[mid]
		for pd in m.ports():
			if world.distance_to(MachineView.port_world(m, str(pd["id"]))) <= PORT_HIT_PX:
				return {"kind": "port", "id": mid, "port": str(pd["id"]), "screen_pos": _screen_pos(MachineView.port_world(m, str(pd["id"])))}
	return {}


func _hit_packet(world: Vector2) -> Dictionary:
	if _packet_layer == null:
		return {}
	var pos := _packet_layer.drawn_packet_positions()
	for pid in pos:
		if world.distance_to(pos[pid]) <= PACKET_HIT_PX:
			return {"kind": "packet", "id": int(pid), "screen_pos": _screen_pos(pos[pid])}
	return {}


func _hit_machine(world: Vector2) -> Dictionary:
	for c in _machine_layer.get_children():
		var mv := c as MachineView
		if mv != null and mv.machine != null and mv.world_rect().has_point(world):
			return {"kind": "machine", "id": mv.machine.id, "screen_pos": _screen_pos(world)}
	return {}


func _hit_wire(world: Vector2) -> Dictionary:
	var sim := SimulationManager.sim
	if sim == null:
		return {}
	var best_id := -1
	var best_d := WIRE_HIT_PX
	# the simulation's connections are the source of truth (views may be mid-rebuild)
	for cid in sim.sorted_connection_ids():
		var c: Connection = sim.connections[cid]
		if not sim.machines.has(c.from_id) or not sim.machines.has(c.to_id):
			continue
		var path := _wire_path(c)
		if path.size() < 2:
			continue
		var d := world.distance_to(SignalGeom.sample(path, SignalGeom.project(path, world))[0])
		if d <= best_d:
			best_d = d
			best_id = cid
	return {"kind": "wire", "id": best_id, "screen_pos": _screen_pos(world)} if best_id >= 0 else {}


## Same draw path as ConnectionView._build_path: [from anchor] + tile centres + [to anchor],
## simplified and chamfered for the trace look.
func _wire_path(c: Connection) -> PackedVector2Array:
	var sim := SimulationManager.sim
	var fm: Machine = sim.machines[c.from_id]
	var tm: Machine = sim.machines[c.to_id]
	var pts := PackedVector2Array()
	pts.append(MachineView.port_world(fm, c.from_port))
	for cell in c.cells:
		pts.append(Vector2(cell) * T + Vector2.ONE * (T * 0.5))
	pts.append(MachineView.port_world(tm, c.to_port))
	var bus := bool(fm.port_geom(c.from_port).get("bus", false)) and bool(tm.port_geom(c.to_port).get("bus", false))
	return SignalGeom.chamfer(pts, Palette.SIG_BUS_CHAMFER if bus else Palette.SIG_CHAMFER)


func _port_dir(mid: int, port: String) -> String:
	var sim := SimulationManager.sim
	if sim == null or not sim.machines.has(mid) or port == "":
		return ""
	return str(Catalog.port_def(sim.machines[mid].type, port).get("dir", ""))


func _screen_pos(world: Vector2) -> Vector2:
	if not is_inside_tree():
		return world
	return get_viewport().get_canvas_transform() * world


# ============================================================ run FAIL highlight

func _on_ticked(tick: int) -> void:
	if tick == 0:
		_apply_highlights([])


func _on_run_finished(_status: int) -> void:
	var ids: Array = []
	if SimulationManager.run != null and SimulationManager.run.status == MissionRun.Status.FAIL:
		ids = SimulationManager.run.failure.get("machines", [])
	_apply_highlights(ids)


## World built new views after a layout change: put the tool-driven flags back on them
## (selection, hover, the failure highlight).
func sync_view_flags() -> void:
	_apply_selection()
	_apply_hover(_hover)
	var ids: Array = []
	if SimulationManager.run != null and SimulationManager.run.status == MissionRun.Status.FAIL:
		ids = SimulationManager.run.failure.get("machines", [])
	_apply_highlights(ids)


func _apply_highlights(ids: Array) -> void:
	if _machine_layer == null:
		return
	for c in _machine_layer.get_children():
		var mv := c as MachineView
		if mv != null and mv.machine != null:
			mv.highlighted = mv.machine.id in ids


func _on_layout_changed() -> void:
	var sim := SimulationManager.sim
	if sim != null and not selected_group.is_empty():
		selected_group = selected_group.filter(func(id): return sim.machines.has(id))
		if selected_group.size() < 2:
			selected_group = []
	_apply_selection()
	_clear_hovered_after_rebuild()
	_clear_ghost_after_rebuild()


func _clear_hovered_after_rebuild() -> void:
	_hover = {}
	hover_changed.emit({})


func _clear_ghost_after_rebuild() -> void:
	_clear_ghost()


# ============================================================ preview node

## Draws ConnectionView.draw_preview onto the OverlayLayer while wiring.
class PreviewLayer extends Node2D:
	const FLOW_PX_PER_S := 24.0  # preview dash flow speed (source → cursor)
	var pts := PackedVector2Array()
	var rings := PackedVector2Array()  # smart wiring: candidate ports (12 px state.valid rings)
	var state := ""
	var _flow := 0.0

	func _process(delta: float) -> void:
		if pts.size() >= 2:
			_flow += delta * FLOW_PX_PER_S
			queue_redraw()

	func _draw() -> void:
		if pts.size() >= 2:
			ConnectionView.draw_preview(self, pts, state, _flow)
		for r in rings:
			draw_arc(r, 6.0, 0.0, TAU, 24, Palette.STATE_VALID, 1.5, true)


## Connected-move holograms: the origin outline (dashed state.hover α .6) and one previewed
## route per wire that follows the machine (ConnectionView.draw_preview styles).
class MovePreview extends Node2D:
	var origin := Rect2()
	var paths: Array = []  # [[PackedVector2Array, state], ...]
	var box := Rect2()  # box select marquee

	func _draw() -> void:
		if box.size != Vector2.ZERO:
			draw_rect(box, Color(Palette.STATE_SELECT, 0.06))
			SystemsDraw.rrect_dashed(self, box, 2.0, Color(Palette.STATE_SELECT, 0.8), 1.5, 6.0, 4.0)
		if origin.size != Vector2.ZERO:
			SystemsDraw.rrect_dashed(self, origin.grow(-2.0), 8.0, Color(Palette.STATE_HOVER, 0.6), 1.5, 5.0, 4.0)
		for p in paths:
			var pts: PackedVector2Array = p[0]
			if pts.size() >= 2:
				ConnectionView.draw_preview(self, pts, str(p[1]))

