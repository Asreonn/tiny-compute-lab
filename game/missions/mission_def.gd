class_name MissionDef
extends Resource
## Data definition of one mission. Built from game/missions/missions.gd; could equally be
## authored as .tres files because every field is exported.

@export var id: String = ""
@export var index: int = 0
@export var title: String = ""
@export var teaches: String = ""
@export_multiline var brief: String = ""
@export var formula: String = ""
@export var board_size: Vector2i = Vector2i(16, 10)
## [{cell: Vector2i, rot, values: Array, type: DataType, interval, strict}]
@export var inputs: Array = []
## [{cell: Vector2i, rot, expected: Array, type: DataType, ordered: bool, label}]
@export var outputs: Array = []
## machine types the player may build
@export var allowed: PackedStringArray = PackedStringArray()
## newly unlocked this mission (highlighted in the build bar)
@export var unlocks: PackedStringArray = PackedStringArray()
## optional goals: [{kind: "power"|"components"|"latency"|"throughput", max|min: number, label}]
@export var goals: Array = []
@export var hint: String = ""


static func from_dict(i: int, d: Dictionary) -> MissionDef:
	var m := MissionDef.new()
	m.index = i
	m.id = d["id"]
	m.title = d["title"]
	m.teaches = d.get("teaches", "")
	m.brief = d.get("brief", "")
	m.formula = d.get("formula", "")
	m.board_size = d.get("size", Vector2i(16, 10))
	m.inputs = d.get("inputs", [])
	m.outputs = d.get("outputs", [])
	m.allowed = PackedStringArray(d.get("allowed", []))
	m.unlocks = PackedStringArray(d.get("unlocks", []))
	m.goals = d.get("goals", [])
	m.hint = d.get("hint", "")
	return m


func expected_total() -> int:
	var n := 0
	for o in outputs:
		n += o["expected"].size()
	return n


func input_values(i: int = 0) -> Array:
	return inputs[i]["values"] if i < inputs.size() else []
