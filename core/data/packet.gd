class_name Packet
extends RefCounted
## One unit of data travelling through the machine. Pure data: no nodes, no rendering.

var id: int
var type: int
var value: Variant
var created_tick: int
## Lineage: the id of the source packet this one was derived from (itself for fresh packets).
var origin_id: int
## Machine labels this packet (or its ancestors) passed through, oldest first.
var path: PackedStringArray = PackedStringArray()


func _init(p_id: int, p_type: int, p_value: Variant, p_tick: int, p_origin: int = -1) -> void:
	id = p_id
	type = p_type
	value = p_value
	created_tick = p_tick
	origin_id = p_id if p_origin < 0 else p_origin


## A new packet computed from this one: new id, new value, same lineage and history.
func derive(new_id: int, new_type: int, new_value: Variant) -> Packet:
	var p := Packet.new(new_id, new_type, new_value, created_tick, origin_id)
	p.path = path.duplicate()
	return p


func label() -> String:
	return DataType.format_value(type, value)
