class_name RunBase
extends RefCounted
## Shared surface of the tutorial MissionRun and the lab LabRun, so SimulationManager.run and
## the views can hold either without knowing which mode is active. Pure data — no Node.
## Subclasses override the members they need; the defaults are the inert "nothing to report"
## behaviour (the lab and the tutorial each override the ones that matter).

var status: int = 0  # MissionRun.Status.RUNNING
var failure: Dictionary = {}
var def = null  # MissionDef for the tutorial; null for the lab (use LabRun's accessors)
var progress: Array = []
var last_ok: Array = []
var expected_bits: Array = []
var warning := ""
var live_edit := false


func build_board(_sim: Simulation) -> void:
	pass


func reset(_sim: Simulation) -> void:
	pass


func allows(_type: String) -> bool:
	return false


func on_output(_sim: Simulation, _m: Machine, _p: Packet) -> void:
	pass


func on_overflow(_sim: Simulation, _m: Machine, _p: Packet) -> void:
	pass


func after_tick(_sim: Simulation) -> void:
	pass


func correct_total() -> int:
	return 0


func accuracy() -> float:
	return 100.0


func goal_results(_sim) -> Array:
	return []


func stars(_sim) -> int:
	return 0
