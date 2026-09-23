extends Node
## Main scene root (Slice A4a part 2). Instances the World and an empty HUD CanvasLayer;
## boots straight into the first campaign mission.

func _ready() -> void:
	SimulationManager.load_mission("a1_plus_two")