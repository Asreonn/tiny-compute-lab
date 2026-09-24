extends Node
## Main scene root (Slice A4a part 2). Instances the World and an empty HUD CanvasLayer;
## boots straight into the persistent Lab (the tutorial stays reachable via load_mission).

func _ready() -> void:
	SimulationManager.load_lab()