class_name MissionDef
extends Resource
## Data definition of one mission. Built from game/missions/missions.gd; could equally be
## authored as .tres files because every field is exported.
## Widths are explicit mission configuration — there is no global default (docs/ARCHITECTURE.md §6).

@export var id: String = ""
@export var index: int = 0
@export var title: String = ""
@export var teaches: String = ""
@export_multiline var brief: String = ""
@export var formula: String = ""
@export var board_size: Vector2i = Vector2i(16, 10)
## the width a newly placed player component takes (mission configuration)
@export var default_width: int = 0
## ViewMode.Mode ints the HUD offers, e.g. [ViewMode.Mode.BIN, ViewMode.Mode.UDEC, ViewMode.Mode.HEX]
@export var view_modes: Array = []
## true for the pre-BitVector "factory" mechanics regression missions
@export var legacy: bool = false
## [{cell: Vector2i, rot, width, values, interval, strict, start, source: "usb_input"|"input"}]
@export var inputs: Array = []
## [{cell: Vector2i, rot, width, expected, ordered, view: ViewMode.Mode}]
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
	m.default_width = int(d.get("default_width", 0))
	m.view_modes = d.get("view_modes", [])
	m.legacy = bool(d.get("legacy", false))
	m.inputs = d.get("inputs", [])
	m.outputs = d.get("outputs", [])
	m.allowed = PackedStringArray(d.get("allowed", []))
	m.unlocks = PackedStringArray(d.get("unlocks", []))
	m.goals = d.get("goals", [])
	m.hint = d.get("hint", "")
	return m


## Convert a mission value (BitVector, "010" string, int or bool) to a BitVector of `width`.
static func to_bits(v: Variant, width: int) -> BitVector:
	if v is BitVector:
		if v.width != width:
			push_error("MissionDef.to_bits: BitVector width %d != %d" % [v.width, width])
		return v
	if typeof(v) == TYPE_STRING:
		var b := BitVector.from_bin(v)
		if b.width != width:
			push_error("MissionDef.to_bits: \"%s\" has %d digits, expected %d" % [v, b.width, width])
		return b
	if typeof(v) == TYPE_BOOL:
		return BitVector.of(1 if v else 0, width)
	if typeof(v) == TYPE_INT:
		return BitVector.of(v, width)
	push_error("MissionDef.to_bits: unsupported value type %s" % str(typeof(v)))
	return BitVector.zero(width)


func expected_total() -> int:
	var n := 0
	for o in outputs:
		n += o["expected"].size()
	return n


func input_values(i: int = 0) -> Array:
	return inputs[i]["values"] if i < inputs.size() else []
