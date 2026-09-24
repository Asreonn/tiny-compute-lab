class_name Packet
extends RefCounted
## One unit of data travelling through the machine. Pure data: no nodes, no rendering.
## A packet carries EITHER a BitVector (`data`) OR a RawValue (`raw`), never both —
## raw values exist only at the peripheral boundary (docs/ARCHITECTURE.md §0 rule 7).

var id: int
var data: BitVector
## Raw payload (null for every packet inside the compute fabric).
var raw: RawValue = null
var created_tick: int
## Lineage: the id of the source packet this one was derived from (itself for fresh packets).
var origin_id: int
## Machine labels this packet (or its ancestors) passed through, oldest first.
var path: PackedStringArray = PackedStringArray()
## Presentation hints only, e.g. {"hint": "CHR"}; component logic never reads it.
var meta: Dictionary = {}
## Per-socket lineage (docs/SYSTEMS_EXPANSION.md §3): source machine id -> {"seq": int,
## "value": BitVector|RawValue}. Sources stamp it, single-input machines copy it,
## combining machines union it. Both payload types are immutable, so sharing is safe.
var origins: Dictionary = {}


func _init(p_id: int, p_data: BitVector, p_tick: int, p_origin: int = -1) -> void:
	id = p_id
	data = p_data
	created_tick = p_tick
	origin_id = p_id if p_origin < 0 else p_origin


## A fresh raw packet: no BitVector, the raw value instead (data stays null).
static func make_raw(p_id: int, p_raw: RawValue, p_tick: int) -> Packet:
	var p := Packet.new(p_id, null, p_tick)
	p.raw = p_raw
	return p


func is_raw() -> bool:
	return raw != null


## A new bit packet computed from this one: new id, new data, same lineage and history.
func derive(new_id: int, new_data: BitVector) -> Packet:
	var p := Packet.new(new_id, new_data, created_tick, origin_id)
	p.path = path.duplicate()
	p.meta = meta.duplicate()
	p.origins = _copy_origins()
	return p


## A new raw packet computed from this one: new id, new raw value, same lineage and history.
func derive_raw(new_id: int, new_raw: RawValue) -> Packet:
	var p := Packet.new(new_id, null, created_tick, origin_id)
	p.raw = new_raw
	p.path = path.duplicate()
	p.meta = meta.duplicate()
	p.origins = _copy_origins()
	return p


## Union of two lineage maps: keys already present keep THIS packet's entry.
func merge_origins(other: Packet) -> void:
	if other == null:
		return
	for k in other.origins:
		if not origins.has(k):
			origins[k] = (other.origins[k] as Dictionary).duplicate()


## Outer dict + inner dicts are copied (shallowly); the values themselves are immutable.
func _copy_origins() -> Dictionary:
	var out := {}
	for k in origins:
		out[k] = (origins[k] as Dictionary).duplicate()
	return out


## Display string in the given ViewMode; never changes the data. Raw packets show their glyph.
func label(mode: int = ViewMode.Mode.BIN) -> String:
	if raw != null:
		return raw.glyph()
	return ViewMode.format(data, mode, meta.get("hint", ""))
