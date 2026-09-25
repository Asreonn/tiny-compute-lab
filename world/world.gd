class_name World
extends Node2D
## Slice A4a part 2: the game world scene root. Hosts the rendering layers (BoardView,
## WireLayer, MachineLayer, PacketLayer, OverlayLayer) and the CameraRig; rebuilds the
## MachineViews whenever the SimulationManager board changes and refreshes them every frame.

@onready var board_view: BoardView = $BoardView
@onready var wire_layer: Node2D = $WireLayer
@onready var machine_layer: Node2D = $MachineLayer
@onready var packet_layer: PacketLayer = $PacketLayer
@onready var overlay_layer: Node2D = $OverlayLayer
@onready var camera_rig: CameraRig = $CameraRig

## The tool layer (Slice A5a): added as the last child so it receives unhandled input
## before the CameraRig (RMB never pans while a tool drag is active).
var tools: ToolController
## Desk zones + port racks (added after the tools so it sees clicks first; it only claims its
## own areas: the desk mats and the modules sticking out of the ports).
var desk: DeskView
## Thermal / power overlay (T / P), drawn over the machines, under the tool previews.
var systems_overlay: SystemsOverlay
var _fit_sim: Simulation = null
var _fit_size := Vector2i.ZERO
## Lab-expansion reveal: ids of the locked USB Inputs added on the last level-up, plus the
## shared reveal start. Views own the fade clock; World just tags the freshly added machines.
const REVEAL_DURATION := 2.5
## Horizontal room outside the grid: the plugged USB modules (112 px) + the desk mats beside
## the laptop (gap 32 + mat 168 + margin 16) — SYSTEMS_EXPANSION §2.2.
const IO_OVERHANG := 328.0
## The Lab frames its free desk areas too (DeskView: overhang 112 + gap 32 + area 300 + margin).
const LAB_OVERHANG := 460.0
var _known_ids: Array = []
var _prev_size := Vector2i.ZERO
var _reveal_ids: Array = []
var _reveal_start := -1.0
var _initialized := false
var _views := {}  # machine id -> MachineView
var _view_keys := {}  # machine id -> the MachineView.view_key it was built for
var _wire_views := {}  # connection id -> ConnectionView


func _ready() -> void:
	tools = ToolController.new()
	tools.name = "Tools"
	add_child(tools)
	tools.add_to_group("tools")
	desk = DeskView.new()
	desk.name = "DeskView"
	add_child(desk)
	systems_overlay = SystemsOverlay.new()
	systems_overlay.name = "SystemsOverlay"
	overlay_layer.add_child(systems_overlay)
	overlay_layer.move_child(systems_overlay, 0)  # under the tool previews
	SimulationManager.mission_loaded.connect(_rebuild)
	SimulationManager.layout_changed.connect(_on_layout_changed)
	_rebuild()


## Rebuilds every machine / wire view from the current Simulation: a new board (mission load).
func _rebuild(_def: Variant = null) -> void:
	for c in machine_layer.get_children():
		c.queue_free()
	for c in wire_layer.get_children():
		c.queue_free()
	_views.clear()
	_wire_views.clear()
	_sync_layout()


## A layout change: views are read-only mirrors, so only the views whose model changed are
## rebuilt (MachineView.view_key / the wire route); the rest stay, keeping their motion state.
func _sync_layout() -> void:
	var sim := SimulationManager.sim
	if sim == null:
		for c in machine_layer.get_children():
			c.queue_free()
		for c in wire_layer.get_children():
			c.queue_free()
		_views.clear()
		_wire_views.clear()
		return
	var ids: Array = sim.sorted_machine_ids()
	var grew := _initialized and (sim.size.x > _prev_size.x or sim.size.y > _prev_size.y)
	if grew:
		var new_usb: Array = []
		for id in ids:
			if _known_ids.has(id):
				continue
			var m: Machine = sim.machines[id]
			if m.locked and m.type == "usb_input":
				new_usb.append(id)
		if not new_usb.is_empty():
			_reveal_ids = new_usb
			_reveal_start = Time.get_ticks_msec() / 1000.0
	_known_ids = ids
	_prev_size = sim.size
	_initialized = true
	# machines
	var created := false
	for id in _views.keys():
		if not sim.machines.has(id) or (_views[id] as MachineView).machine != sim.machines[id]:
			(_views[id] as MachineView).queue_free()
			_views.erase(id)
	var i := 0
	for id in ids:
		var m: Machine = sim.machines[id]
		var key := MachineView.view_key(m)
		var mv: MachineView = _views.get(id)
		if mv != null and _view_keys.get(id, "") != key:
			mv.queue_free()
			mv = null
		if mv == null:
			mv = MachineView.new()
			mv.setup(m)
			machine_layer.add_child(mv)
			_views[id] = mv
			_view_keys[id] = key
			created = true
		else:
			mv.on_layout()
		if mv.get_index() != i:
			machine_layer.move_child(mv, i)
		i += 1
	# wires: kept while the connection object and its route are the same
	for cid in _wire_views.keys():
		var cv: ConnectionView = _wire_views[cid]
		if not sim.connections.has(cid) or cv.connection != sim.connections[cid] or cv.route_key != ConnectionView.key_of(sim.connections[cid]):
			cv.queue_free()
			_wire_views.erase(cid)
	var j := 0
	for cid in sim.sorted_connection_ids():
		var cv2: ConnectionView = _wire_views.get(cid)
		if cv2 == null:
			cv2 = ConnectionView.new()
			cv2.setup(sim.connections[cid])
			cv2.packet_positions = packet_layer.comet_arcs.bind(cid)
			wire_layer.add_child(cv2)
			_wire_views[cid] = cv2
			created = true
		else:
			cv2.on_layout()
		if cv2.get_index() != j:
			wire_layer.move_child(cv2, j)
		j += 1
	for id in _view_keys.keys():
		if not _views.has(id):
			_view_keys.erase(id)
	if created and tools != null:
		tools.sync_view_flags()  # selection / hover / failure highlight onto the new views
	board_view.redraw()
	if desk != null:
		desk.redraw()
	# Refit the camera only for a new board or a board-size change (lab expansion) — never on
	# ordinary edits, so the player's pan/zoom survives placing machines and wires.
	if sim != _fit_sim or sim.size != _fit_size:
		_fit_sim = sim
		_fit_size = sim.size
		# The USB modules and the contract drive's job module stick out past the west/east grid
		# edges (laptop side ports, STYLE_GUIDE §14.4): frame them too.
		var board := Rect2(Vector2.ZERO, Vector2(sim.size) * MachineView.T)
		var side := LAB_OVERHANG if SimulationManager.in_lab else IO_OVERHANG
		camera_rig.fit_board(board.grow_individual(side, 0.0, side, 0.0))


func _on_layout_changed() -> void:
	_sync_layout()


func _process(delta: float) -> void:
	# Tag freshly added locked USB Inputs for the expansion hover pulse while the reveal is live.
	if _reveal_start >= 0.0 and not _reveal_ids.is_empty():
		if (Time.get_ticks_msec() / 1000.0) - _reveal_start >= REVEAL_DURATION:
			_reveal_ids = []
			_reveal_start = -1.0
		else:
			for c in machine_layer.get_children():
				var mv := c as MachineView
				if mv != null and mv.machine != null and _reveal_ids.has(mv.machine.id):
					mv.reveal_active = true
					mv.reveal_start = _reveal_start
	for c in machine_layer.get_children():
		var mv := c as MachineView
		if mv != null:
			mv.refresh(delta)
	# an overlay pushes the machines back to α .55 (cross-faded with the overlay)
	if systems_overlay != null:
		machine_layer.modulate.a = lerpf(1.0, 0.55, systems_overlay.fade)
	for c in wire_layer.get_children():
		var cv := c as ConnectionView
		if cv != null:
			cv.refresh(delta)