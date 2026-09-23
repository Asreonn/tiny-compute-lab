class_name Packet
extends RefCounted
## One unit of data travelling through the machine. Pure data: no nodes, no rendering.
## The payload is always a BitVector (docs/ARCHITECTURE.md §0/§3.4).

var id: int
var data: BitVector
var created_tick: int
## Lineage: the id of the source packet this one was derived from (itself for fresh packets).
var origin_id: int
## Machine labels this packet (or its ancestors) passed through, oldest first.
var path: PackedStringArray = PackedStringArray()
## Presentation hints only, e.g. {"hint": "CHR"}; component logic never reads it.
var meta: Dictionary = {}


func _init(p_id: int, p_data: BitVector, p_tick: int, p_origin: int = -1) -> void:
	id = p_id
	data = p_data
	created_tick = p_tick
	origin_id = p_id if p_origin < 0 else p_origin


## A new packet computed from this one: new id, new data, same lineage and history.
func derive(new_id: int, new_data: BitVector) -> Packet:
	var p := Packet.new(new_id, new_data, created_tick, origin_id)
	p.path = path.duplicate()
	p.meta = meta.duplicate()
	return p


## Display string in the given ViewMode; never changes the data.
func label(mode: int = ViewMode.Mode.BIN) -> String:
	return ViewMode.format(data, mode, meta.get("hint", ""))
