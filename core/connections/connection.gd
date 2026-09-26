class_name Connection
extends RefCounted
## A physical data trace between an output port and an input port.
## Modelled as a conveyor of fixed slots — one slot per routed tile — so
## bandwidth is naturally 1 packet/tick and back-pressure is physical.
## The wire carries one width; both endpoints must match it.
## A connection may also run several parallel conveyors ("lanes") for extra
## bandwidth; lane 0 is the original conveyor and `slots` always aliases it.

var id: int
var from_id: int
var from_port: String
var to_id: int
var to_port: String
var width: int = 1
var cells: Array[Vector2i] = []  # routed tiles, source side first
var lane_slots: Array = []  # one Array per lane, each of length length()
var slots: Array = []  # Packet or null per slot — always lane_slots[0]
var lanes := 1
var blocked := false  # head packet could not be delivered this tick
var moved_this_tick := false
var carried := 0
var saturated := false  # a waiting packet was refused while the wire flowed (bandwidth-bound, FACTORY_SYSTEMS §2.2)
## The last 60 ticks of `saturated` as a bit window plus its popcount (O(1) per tick; §7.4).
var sat_hist := 0
var sat_cnt := 0
const BOUND_WINDOW := 60


var slots_per_tile := 1  # campaign boards use 2: longer, readable travel (Catalog.CAMPAIGN_SLOTS_PER_TILE)


func _init(p_id: int, p_from: int, p_from_port: String, p_to: int, p_to_port: String, p_cells: Array[Vector2i], p_width: int, p_slots_per_tile := 1, p_lanes := 1) -> void:
	slots_per_tile = maxi(1, p_slots_per_tile)
	id = p_id
	from_id = p_from
	from_port = p_from_port
	to_id = p_to
	to_port = p_to_port
	cells = p_cells
	width = p_width
	lanes = valid_lanes(p_lanes)
	reset()


## The largest of [1, 2, 4, 8] that is <= n; 1 if n < 1.
static func valid_lanes(n: int) -> int:
	if n < 1:
		return 1
	for k in [8, 4, 2, 1]:
		if n >= k:
			return k
	return 1


func length() -> int:
	return max(1, cells.size() * slots_per_tile)


## The bus class a wire of this width belongs to (FACTORY_SYSTEMS §2.1).
static func class_of(width: int) -> String:
	if width <= 5:
		return "trace"
	if width <= 8:
		return "byte"
	if width <= 32:
		return "wide"
	return "backbone"


static func class_title(width: int) -> String:
	if width <= 5:
		return "Trace"
	if width <= 8:
		return "Byte Bus"
	if width <= 32:
		return "Wide Bus"
	return "Backbone"


func reset() -> void:
	lane_slots = []
	for k in lanes:
		var lane: Array = []
		lane.resize(length())
		lane_slots.append(lane)
	slots = lane_slots[0]
	blocked = false
	moved_this_tick = false
	carried = 0
	saturated = false
	sat_hist = 0
	sat_cnt = 0


## Record this tick's saturation into the 60-tick window.
func note_saturation(flag: bool) -> void:
	var leaving := (sat_hist >> (BOUND_WINDOW - 1)) & 1
	sat_hist = ((sat_hist << 1) | int(flag)) & ((1 << BOUND_WINDOW) - 1)
	sat_cnt += int(flag) - leaving


## Share of the last 60 ticks this wire was saturated (0..1).
func saturation_ratio() -> float:
	return float(sat_cnt) / float(BOUND_WINDOW)


func set_lanes(n: int) -> void:
	lanes = valid_lanes(n)
	reset()


func has_packets() -> bool:
	for k in lanes:
		for s in lane_slots[k]:
			if s != null:
				return true
	return false


func packet_count() -> int:
	var n := 0
	for k in lanes:
		for s in lane_slots[k]:
			if s != null:
				n += 1
	return n


func entry_free() -> bool:
	return free_entries() > 0


## How many lanes have a free slot 0.
func free_entries() -> int:
	var n := 0
	for k in lanes:
		if lane_slots[k][0] == null:
			n += 1
	return n


func push(p: Packet) -> void:
	for k in lanes:
		if lane_slots[k][0] == null:
			lane_slots[k][0] = p
			break
	carried += 1
	moved_this_tick = true


## Shift packets one slot toward the target where the next slot is free,
## per lane independently. Processed head-first so a contiguous train
## advances together.
func advance() -> void:
	for k in lanes:
		var lane: Array = lane_slots[k]
		for i in range(lane.size() - 2, -1, -1):
			if lane[i] != null and lane[i + 1] == null:
				lane[i + 1] = lane[i]
				lane[i] = null
				moved_this_tick = true


## [[lane_index, Packet], ...] for every lane whose LAST slot is non-null,
## sorted by ascending packet id.
func heads() -> Array:
	var hs := []
	for k in lanes:
		var lane: Array = lane_slots[k]
		var p: Packet = lane[lane.size() - 1]
		if p != null:
			hs.append([k, p])
	hs.sort_custom(func(a, b): return (a[1] as Packet).id < (b[1] as Packet).id)
	return hs


## The head Packet with the lowest id, or null.
func head() -> Packet:
	var best: Packet = null
	for k in lanes:
		var lane: Array = lane_slots[k]
		var p: Packet = lane[lane.size() - 1]
		if p != null and (best == null or p.id < best.id):
			best = p
	return best


## Remove the lowest-id head packet from its lane's last slot and return it.
func pop_head() -> Packet:
	var p := head()
	if p == null:
		return null
	for k in lanes:
		var lane: Array = lane_slots[k]
		if lane[lane.size() - 1] == p:
			lane[lane.size() - 1] = null
			break
	moved_this_tick = true
	return p


## [{"packet": p, "lane": k, "slot": i}] for every non-null slot, lane 0
## first, slots ascending.
func all_packets() -> Array:
	var out := []
	for k in lanes:
		var lane: Array = lane_slots[k]
		for i in lane.size():
			if lane[i] != null:
				out.append({"packet": lane[i], "lane": k, "slot": i})
	return out


func to_dict() -> Dictionary:
	var cs := []
	for c in cells:
		cs.append([c.x, c.y])
	return {"from": from_id, "from_port": from_port, "to": to_id, "to_port": to_port, "width": width, "cells": cs, "lanes": lanes}
