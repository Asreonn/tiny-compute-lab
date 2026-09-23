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


func _ready() -> void:
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
	var rect := Rect2(Vector2.ZERO, Vector2(sim.size) * MachineView.T)
	camera_rig.fit_board(rect)


func _process(delta: float) -> void:
	for c in machine_layer.get_children():
		var mv := c as MachineView
		if mv != null:
			mv.refresh(delta)
	for c in wire_layer.get_children():
		var cv := c as ConnectionView
		if cv != null:
			cv.refresh(delta)