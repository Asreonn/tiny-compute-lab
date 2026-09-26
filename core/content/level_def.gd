class_name LevelDef
extends Resource
## One Lab quest as an asset (docs/CONTENT.md): content/lab/levels/<nn>_<id>.tres, listed in the
## campaign's LabConfig. LabDef reads the dictionary form (LabDef.level).
##
## contract  the Contract dictionary (kind, ops, count, constraints) — game/lab/contract.gd
## streams   {stick kind: {values, width?, interval?, pattern?}} — what the quest's sticks carry;
##           a quest without streams reuses the last quest's
## devices   stick kinds first owned from this quest on
## unlocks   machine types (or machine variants) unlocked when the quest starts
## grow      the board size from this quest on (0 × 0 = unchanged)
## view      ViewMode.Mode the quest is shown in
## reward    e.g. {"psu_tier": 1} once the quest is done
## tests     the quest's test set (JOB C7b): [{seq?: int, value?: "BIN string", note: String}]
## require_test  the quest files only after one all-pass test run on its current circuit

@export var id := ""
@export var title := ""
@export_multiline var brief := ""
@export var contract: Dictionary = {}
@export var streams: Dictionary = {}
@export var devices: PackedStringArray = PackedStringArray()
@export var unlocks: PackedStringArray = PackedStringArray()
@export var grow := Vector2i.ZERO
@export_enum("BIN", "UDEC", "HEX", "CHAR", "SDEC", "TYPE") var view := 0
@export var reward: Dictionary = {}
## The quest's test set (JOB C7b): [{seq?: int, value?: "BIN string", note: String}].
@export var tests: Array[Dictionary] = []
## True: the quest files only after one all-pass test run on its current circuit.
@export var require_test := false


func to_dict() -> Dictionary:
	var d := {
		"id": id, "title": title, "brief": brief, "contract": contract.duplicate(true), "view": view,
		"unlocks": Array(unlocks),
	}
	if not streams.is_empty():
		d["streams"] = streams.duplicate(true)
	if not devices.is_empty():
		d["devices"] = Array(devices)
	if grow != Vector2i.ZERO:
		d["grow"] = grow
	if not reward.is_empty():
		d["reward"] = reward.duplicate(true)
	if not tests.is_empty():
		d["tests"] = tests.duplicate(true)
	if require_test:
		d["require_test"] = true
	return d
