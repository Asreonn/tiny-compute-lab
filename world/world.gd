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
var _fit_sim: Simulation = null
var _fit_size := Vector2i.ZERO
## Lab-expansion reveal: ids of the locked USB Inputs added on the last level-up, plus the
## shared reveal start. Views own the fade clock; World just tags the freshly added machines.
const REVEAL_DURATION := 2.5
var _known_ids: Array = []
var _prev_size := Vector2i.ZERO
var _reveal_ids: Array = []
var _reveal_start := -1.0
var _initialized := false


func _ready() -> void:
	tools = ToolController.new()
	tools.name = "Tools"
	add_child(tools)
	tools.add_to_group("tools")
	SimulationManager.mission_loaded.connect(_rebuild)
	SimulationManager.layout_changed.connect(_rebuild)
	_rebuild()


## Rebuilds the machine views from the current Simulation; called on mission load and on
## every layout change. Views are read-only mirrors, so a full rebuild is safe.
func _rebuild(_def: Variant = null) -> void:
	for c in machine_layer.get_children():
		c.queue_free()
	for c in wire_layer.get_children():
		c.queue_free()
	var sim := SimulationManager.sim
	if sim == null:
		return
	var ids: Array = []
	for id in sim.sorted_machine_ids():
		ids.append(id)
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
	for id in sim.sorted_machine_ids():
		var mv := MachineView.new()
		mv.setup(sim.machines[id])
		machine_layer.add_child(mv)
	for id in sim.sorted_connection_ids():
		var cv := ConnectionView.new()
		cv.setup(sim.connections[id])
		cv.packet_positions = packet_layer.comet_arcs.bind(id)
		wire_layer.add_child(cv)
	board_view.redraw()
	# Refit the camera only for a new board or a board-size change (lab expansion) — never on
	# ordinary edits, so the player's pan/zoom survives placing machines and wires.
	if sim != _fit_sim or sim.size != _fit_size:
		_fit_sim = sim
		_fit_size = sim.size
		camera_rig.fit_board(Rect2(Vector2.ZERO, Vector2(sim.size) * MachineView.T))


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
	for c in wire_layer.get_children():
		var cv := c as ConnectionView
		if cv != null:
			cv.refresh(delta)