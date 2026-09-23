class_name Connection
extends RefCounted
## A physical data trace between an output port and an input port.
## Modelled as a conveyor of fixed slots — one slot per routed tile — so
## bandwidth is naturally 1 packet/tick and back-pressure is physical.

var id: int
var from_id: int
var from_port: String
var to_id: int
var to_port: String
var type: int = DataType.NUMBER
var cells: Array[Vector2i] = []  # routed tiles, source side first
var slots: Array = []  # Packet or null per slot
var blocked := false  # head packet could not be delivered this tick
var moved_this_tick := false
var carried := 0


func _init(p_id: int, p_from: int, p_from_port: String, p_to: int, p_to_port: String, p_cells: Array[Vector2i], p_type: int) -> void:
	id = p_id
	from_id = p_from
	from_port = p_from_port
	to_id = p_to
	to_port = p_to_port
	cells = p_cells
	type = p_type
	reset()


func length() -> int:
	return max(1, cells.size())


func reset() -> void:
	slots = []
	slots.resize(length())
	blocked = false
	moved_this_tick = false
	carried = 0


func has_packets() -> bool:
	for s in slots:
		if s != null:
			return true
	return false


func packet_count() -> int:
	var n := 0
	for s in slots:
		if s != null:
			n += 1
	return n


func entry_free() -> bool:
	return slots[0] == null


func push(p: Packet) -> void:
	slots[0] = p
	carried += 1
	moved_this_tick = true


## Shift packets one slot toward the target where the next slot is free.
## Processed head-first so a contiguous train advances together.
func advance() -> void:
	for i in range(slots.size() - 2, -1, -1):
		if slots[i] != null and slots[i + 1] == null:
			slots[i + 1] = slots[i]
			slots[i] = null
			moved_this_tick = true


func head() -> Packet:
	return slots[slots.size() - 1]


func pop_head() -> Packet:
	var p: Packet = slots[slots.size() - 1]
	slots[slots.size() - 1] = null
	moved_this_tick = true
	return p


func to_dict() -> Dictionary:
	var cs := []
	for c in cells:
		cs.append([c.x, c.y])
	return {"from": from_id, "from_port": from_port, "to": to_id, "to_port": to_port, "cells": cs}
