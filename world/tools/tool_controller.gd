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

const T := Palette.TILE
const PORT_HIT_PX := 12.0
const WIRE_HIT_PX := 8.0
const PACKET_HIT_PX := 10.0
const DRAG_START_PX := 4.0  # world px an LMB must travel before it becomes a drag

var tool := "select"  # "select" | "wire" | "delete" | "rotate" | "place"
var selected_machine := -1
var selected_conn := -1

var _world: Node2D
var _machine_layer: Node2D
var _wire_layer: Node2D
var _packet_layer: PacketLayer
var _overlay_layer: Node2D
var _preview: PreviewLayer

# --- placement ghost ("place" tool)
var place_type := ""  # non-empty while a placement ghost is being dragged around
var place_rot := 0
var _ghost_view: MachineView = null
var _ghost_pad: Sprite2D = null
var _ghost_cell := Vector2i(-1, 0)

# --- drags
var _press_world := Vector2.ZERO
var _press_hit := {}
var _lmb_down := false
var _move_drag := {}  # {machine_id: int, cell: Vector2i, from: Vector2i}
var _wire_drag := {}  # {from_id: int, from_port: String}
var _hover := {}


func _ready() -> void:
	_world = get_parent()
	_machine_layer = _world.get_node("MachineLayer")
	_wire_layer = _world.get_node("WireLayer")
	_packet_layer = _world.get_node("PacketLayer")
	_overlay_layer = _world.get_node("OverlayLayer")
	_preview = PreviewLayer.new()
	_preview.name = "ToolPreview"
	_overlay_layer.add_child(_preview)
	SimulationManager.run_finished.connect(_on_run_finished)
	SimulationManager.ticked.connect(_on_ticked)
	SimulationManager.layout_changed.connect(_on_layout_changed)


# ============================================================ public API

func set_tool(name: String) -> void:
	if tool == "place":
		_clear_place()
	tool = name
	tool_changed.emit(tool)


func begin_place(type: String) -> void:
	if not Catalog.has(type):
		return
	if tool == "place":
		_clear_place()
	place_type = type
	place_rot = 0
	tool = "place"
	tool_changed.emit(tool)


func clear_selection() -> void:
	_set_selection(-1, -1)


# ============================================================ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_mouse_motion(get_global_mouse_position())
	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventKey:
		_on_key(event as InputEventKey)


func _on_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_lmb_press(get_global_mouse_position())
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# RMB cancels placement / any active drag; never pans while one is active.
			if _dragging() or (tool == "place" and place_type != ""):
				_cancel_drags()
				get_viewport().set_input_as_handled()
	else:
		if mb.button_index == MOUSE_BUTTON_LEFT and _lmb_down:
			_lmb_down = false
			_lmb_release(get_global_mouse_position())


func _dragging() -> bool:
	return not _wire_drag.is_empty() or not _move_drag.is_empty()


func _cancel_drags() -> void:
	if not _wire_drag.is_empty():
		_wire_drag = {}
		_clear_preview()
	if not _move_drag.is_empty():
		_move_drag = {}
		_clear_ghost()
	if tool == "place" and place_type != "":
		_clear_place()
		set_tool("select")
	_update_hover_immediate()


func _on_key(k: InputEventKey) -> void:
	if not k.pressed or k.echo:
		return
	var key := k.keycode
	if key == KEY_SPACE:
		SimulationManager.toggle()
	elif key == KEY_PERIOD:
		SimulationManager.step_once()
	elif key == KEY_BACKSPACE:
		SimulationManager.reset_run()
	elif key == KEY_V:
		set_tool("select")
	elif key == KEY_W:
		set_tool("wire")
	elif key == KEY_X:
		set_tool("delete")
	elif key == KEY_R:
		if tool == "place" and place_type != "":
			place_rot = (place_rot + 1) % 4
			var cell := _ghost_cell
			if cell.x < 0:
				cell = _snap_cell(get_global_mouse_position(), place_type, place_rot)
			_rebuild_ghost(cell, place_type, place_rot)
		elif selected_machine >= 0:
			_rotate_machine(selected_machine)
	elif key == KEY_DELETE:
		_delete_selection()
	elif key == KEY_ESCAPE:
		if tool == "place" and place_type != "":
			_clear_place()
			set_tool("select")
		elif _dragging():
			_cancel_drags()
		else:
			clear_selection()


# ============================================================ click actions

func _lmb_press(world: Vector2) -> void:
	_press_world = world
	var sim := SimulationManager.sim
	if _dragging() or sim == null:
		return
	_press_hit = _hit_at(world)
	match tool:
		"select":
			_lmb_down = true
			if _press_hit.is_empty():
				_set_selection(-1, -1)
			else:
				match str(_press_hit.get("kind", "")):
					"machine", "port":
						_set_selection(int(_press_hit["id"]), -1)
					"wire":
						_set_selection(-1, int(_press_hit["id"]))
		"wire":
			if _press_hit.get("kind") == "port" and _port_dir(int(_press_hit["id"]), str(_press_hit.get("port", ""))) == Catalog.DIR_OUT:
				_wire_drag = {"from_id": int(_press_hit["id"]), "from_port": str(_press_hit["port"])}
				_update_wire_preview(world)
		"delete":
			if _press_hit.get("kind") == "machine":
				_delete_machine(int(_press_hit["id"]))
			elif _press_hit.get("kind") == "wire":
				_delete_conn(int(_press_hit["id"]))
		"rotate":
			if _press_hit.get("kind") == "machine":
				_rotate_machine(int(_press_hit["id"]))
		"place":
			_try_place(world)


func _lmb_release(world: Vector2) -> void:
	if not _wire_drag.is_empty():
		_finish_wire_drag(world)
	elif not _move_drag.is_empty():
		_finish_move_drag()
	else:
		_update_hover(world)
	_press_hit = {}
	_press_world = Vector2.ZERO
	_update_hover_immediate()


func _on_mouse_motion(world: Vector2) -> void:
	if not _move_drag.is_empty():
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
	if not _lmb_down or tool != "select" or _press_hit.is_empty():
		return
	if world.distance_to(_press_world) < DRAG_START_PX:
		return
	var kind := str(_press_hit.get("kind", ""))
	var mid := int(_press_hit.get("id", -1))
	if mid < 0:
		return
	if kind == "port" and _port_dir(mid, str(_press_hit.get("port", ""))) == Catalog.DIR_OUT:
		_wire_drag = {"from_id": mid, "from_port": str(_press_hit["port"])}
		_update_wire_preview(world)
		return
	var sim := SimulationManager.sim
	if sim != null and sim.machines.has(mid) and not sim.machines[mid].locked and kind == "machine":
		var m: Machine = sim.machines[mid]
		_move_drag = {"machine_id": mid, "cell": m.cell, "from": m.cell}
		_rebuild_ghost(m.cell, m.type, m.rot)


# ============================================================ select tool

func _set_selection(mid: int, cid: int) -> void:
	selected_machine = mid
	selected_conn = cid
	_apply_selection()
	selection_changed.emit(selected_machine, selected_conn)


func _apply_selection() -> void:
	if _machine_layer == null or not is_inside_tree():
		return
	for c in _machine_layer.get_children():
		var mv := c as MachineView
		if mv != null:
			mv.selected = mv.machine != null and mv.machine.id == selected_machine
	for c in _wire_layer.get_children():
		var cv := c as ConnectionView
		if cv != null:
			cv.selected = cv.connection != null and cv.connection.id == selected_conn


func _delete_selection() -> void:
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
	_set_selection(-1, -1)


func _delete_conn(cid: int) -> void:
	var sim := SimulationManager.sim
	if sim == null or not sim.connections.has(cid):
		return
	SimulationManager.request_edit()
	sim.disconnect_wire(cid)
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
	_clear_ghost()
	_move_drag = {}
	if sim != null and mid >= 0 and sim.machines.has(mid) and cell != from and cell.x >= 0:
		SimulationManager.request_edit()
		if sim.machines.has(mid):
			sim.move(mid, cell)
			_apply_selection()


func _update_move_ghost(world: Vector2) -> void:
	var sim := SimulationManager.sim
	var mid := int(_move_drag.get("machine_id", -1))
	if sim == null or not sim.machines.has(mid):
		_move_drag = {}
		return
	var m: Machine = sim.machines[mid]
	var cell := _snap_cell(world, m.type, m.rot)
	_move_drag["cell"] = cell
	_rebuild_ghost(cell, m.type, m.rot)


# ============================================================ wire tool

func _update_wire_preview(world: Vector2) -> void:
	var sim := SimulationManager.sim
	if sim == null or _wire_drag.is_empty():
		return
	var fid := int(_wire_drag.get("from_id", -1))
	var fport := str(_wire_drag.get("from_port", ""))
	if not sim.machines.has(fid):
		_clear_preview()
		return
	var from := MachineView.port_world(sim.machines[fid], fport)
	var target := _hit_port(world)
	if target.is_empty():
		_show_preview(PackedVector2Array([from, world]), "ConnectionPreview")
		return
	var tid := int(target["id"])
	var tport := str(target["port"])
	if not sim.machines.has(tid):
		_show_preview(PackedVector2Array([from, world]), "ConnectionPreview")
		return
	var to := MachineView.port_world(sim.machines[tid], tport)
	var err := sim.connect_error(fid, fport, tid, tport)
	var r := sim.route_between(fid, fport, tid, tport)
	if err == "" and bool(r.get("ok", false)):
		var pts := PackedVector2Array([from])
		for cell in r.get("cells", []):
			pts.append(Vector2(cell) * T + Vector2.ONE * (T * 0.5))
		pts.append(to)
		_show_preview(pts, "ValidTarget")
	else:
		_show_preview(PackedVector2Array([from, to]), "InvalidTarget")


## Release over a valid input-port target: create the wire. Otherwise notice with the
## exact connect_error text (mismatched widths included) or "No route".
func _finish_wire_drag(world: Vector2) -> void:
	var sim := SimulationManager.sim
	var fid := int(_wire_drag.get("from_id", -1))
	var fport := str(_wire_drag.get("from_port", ""))
	_clear_preview()
	_wire_drag = {}
	if sim == null or not sim.machines.has(fid):
		return
	var target := _hit_port(world)
	var err := ""
	if not target.is_empty():
		var tid := int(target["id"])
		var tport := str(target["port"])
		if sim.machines.has(tid):
			err = sim.connect_error(fid, fport, tid, tport)
			var r := sim.route_between(fid, fport, tid, tport)
			if err == "" and bool(r.get("ok", false)):
				SimulationManager.request_edit()
				if sim.connect_ports(fid, fport, tid, tport) != null:
					return
				err = "No route"
	if err == "":
		err = "No route"
	notice.emit(err, "error")
	_update_hover_immediate()


# ============================================================ place tool

func _try_place(world: Vector2) -> void:
	var sim := SimulationManager.sim
	if sim == null or place_type == "":
		return
	var cell := _snap_cell(world, place_type, place_rot)
	SimulationManager.request_edit()
	var m := sim.place(place_type, cell, place_rot)
	if m == null:
		notice.emit(sim.placement_error(place_type, cell, place_rot), "error")
		return
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
	var ghost_m := Machine.new(0, type, cell, sim.default_width, rot % 4, Catalog.default_params(type))
	if _move_drag.has("machine_id") and sim.machines.has(int(_move_drag["machine_id"])):
		ghost_m.params = sim.machines[int(_move_drag["machine_id"])].params.duplicate()
	var key := str(Catalog.def(type)["size"]).to_lower()
	var err := sim.placement_error(type, cell, rot)
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
	c -= Vector2i((s.x - 1) / 2, (s.y - 1) / 2)
	return c


# ============================================================ preview

func _show_preview(pts: PackedVector2Array, state: String) -> void:
	_preview.pts = pts
	_preview.state = state
	_preview.queue_redraw()


func _clear_preview() -> void:
	_preview.pts = PackedVector2Array()
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
	for c in _wire_layer.get_children():
		var cv := c as ConnectionView
		if cv == null or cv.connection == null:
			continue
		var path := _wire_path(cv.connection)
		var d := world.distance_to(SignalGeom.sample(path, SignalGeom.project(path, world))[0])
		if d <= best_d:
			best_d = d
			best_id = cv.connection.id
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


func _apply_highlights(ids: Array) -> void:
	if _machine_layer == null:
		return
	for c in _machine_layer.get_children():
		var mv := c as MachineView
		if mv != null and mv.machine != null:
			mv.highlighted = mv.machine.id in ids


func _on_layout_changed() -> void:
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
	var pts := PackedVector2Array()
	var state := ""

	func _draw() -> void:
		if pts.size() >= 2:
			ConnectionView.draw_preview(self, pts, state)