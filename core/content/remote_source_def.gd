class_name RemoteSourceDef
extends Resource
## A compromised remote source (docs/DATA_FACTORY.md §5): a fixed record layout and the knobs of
## its deterministic generator. content/network/sources/<id>.tres. A source never changes layout.
@export var id := ""
@export var display_name := ""
## Silk on the source card / stick ("FC").
@export var glyph := ""
## Record width in bits (the sum of the field widths).
@export var width := 16
## MSB first: {name, width, desc, kind: "id"|"enum"|"range"|"flags", labels (flags: bit names MSB first)}.
@export var fields: Array[Dictionary] = []
## Records per second when LIVE; realtime sources drop when full, others pause.
@export var rate := 3.0
@export var realtime := false
@export var remote_buffer := 32
@export var seed := 1
## Probability that record `seq` is about the shared session identity U(seq).
@export var p_same := 1.0
## field name (or flag bit name) -> probability of the noise event.
@export var noise: Dictionary = {}
## [{seq, note}]: the default test set (filled in by C7).
@export var test_vectors: Array[Dictionary] = []
## Base sale value per accepted record.
@export var value := 1


## Index of `name` in `fields`, -1 if absent.
func field_index(name: String) -> int:
	for k in range(fields.size()):
		var f: Dictionary = fields[k]
		if str(f.get("name", "")) == name:
			return k
	return -1