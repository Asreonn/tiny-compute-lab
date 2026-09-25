class_name BusLanesTests
extends RefCounted
## Parallel conveyors on a Connection: multiple lanes, entry/free bookkeeping,
## independent advance, lowest-id head, per-lane packet enumeration and lane
## classes. With lanes == 1 every method must behave exactly as before.


static func run(t) -> void:
	_pushes_fill_lanes(t)
	_advance_and_heads(t)
	_valid_and_set_lanes(t)
	_class_of(t)
	_count_and_all_packets(t)
	_simulation_round_trip(t)
	_set_wire_lanes_missing(t)
	_delivery(t)


static func _cells3() -> Array[Vector2i]:
	return [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]


static func _pkt(id: int, value: int) -> Packet:
	return Packet.new(id, BitVector.of(value, 3), 0)


static func _pushes_fill_lanes(t) -> void:
	var c := Connection.new(1, 1, "out", 2, "in", _cells3(), 3, 1, 2)
	t.check(c.lanes == 2 and c.free_entries() == 2, "2-lane connection starts with two free entries")
	var p0 := _pkt(10, 1)
	var p1 := _pkt(11, 3)
	c.push(p0)
	c.push(p1)
	t.check(c.lane_slots[0][0] == p0 and c.lane_slots[1][0] == p1, "two pushes in one tick land in lane 0 then lane 1")
	t.check(not c.entry_free() and c.free_entries() == 0, "two pushes fill both lanes of a 2-lane connection")
	var one := Connection.new(2, 1, "out", 2, "in", _cells3(), 3)
	one.push(_pkt(12, 5))
	t.check(not one.entry_free() and one.free_entries() == 0, "a 1-lane connection closes its entry after one push")


static func _advance_and_heads(t) -> void:
	var c := Connection.new(3, 1, "out", 2, "in", _cells3(), 3, 1, 2)
	var a := _pkt(5, 1)  # lane 0
	var b := _pkt(2, 3)  # lane 1
	c.push(a)
	c.push(b)
	for i in 3:
		c.advance()
	var hs := c.heads()
	t.check(hs.size() == 2, "both lanes deliver a head after enough advances, got %d" % hs.size())
	t.check(hs[0][1].id == 2 and hs[1][1].id == 5, "heads() sorted by ascending packet id, got %s/%s" % [hs[0][1].id, hs[1][1].id])
	t.check(hs[0][0] == 1 and hs[1][0] == 0, "head entries carry their lane index, got %d/%d" % [hs[0][0], hs[1][0]])
	t.check(c.head() == b, "head() returns the lowest id packet")
	t.check(c.pop_head() == b, "pop_head() returns the lowest id first")
	var hs2 := c.heads()
	t.check(hs2.size() == 1 and hs2[0][0] == 0 and hs2[0][1] == a, "after pop only lane 0 still holds a head")
	t.check(c.pop_head() == a and c.head() == null, "second pop returns the remaining head")
	t.check(c.pop_head() == null, "pop_head() on an empty connection returns null")


static func _valid_and_set_lanes(t) -> void:
	t.check(Connection.valid_lanes(0) == 1, "valid_lanes(0) == 1")
	t.check(Connection.valid_lanes(1) == 1, "valid_lanes(1) == 1")
	t.check(Connection.valid_lanes(3) == 2, "valid_lanes(3) == 2")
	t.check(Connection.valid_lanes(5) == 4, "valid_lanes(5) == 4")
	t.check(Connection.valid_lanes(9) == 8, "valid_lanes(9) == 8")
	var c := Connection.new(4, 1, "out", 2, "in", _cells3(), 3)
	c.set_lanes(4)
	t.check(c.lanes == 4 and c.lane_slots.size() == 4, "set_lanes(4) gives 4 lane_slots, got %d" % c.lane_slots.size())
	t.check(c.slots == c.lane_slots[0] and c.slots.size() == c.length() and c.lane_slots[1].size() == c.length(), "every lane is sized to length()")
	var probe := _pkt(9, 7)
	c.lane_slots[0][0] = probe
	t.check(c.slots[0] == probe, "slots is the same array object as lane_slots[0]")
	t.check(c.to_dict().get("lanes") == 4, "to_dict() carries the lane count")


static func _class_of(t) -> void:
	t.check(Connection.class_of(5) == "trace", "width 5 is a trace")
	t.check(Connection.class_of(6) == "byte", "width 6 is a byte")
	t.check(Connection.class_of(8) == "byte", "width 8 is a byte")
	t.check(Connection.class_of(9) == "wide", "width 9 is wide")
	t.check(Connection.class_of(32) == "wide", "width 32 is wide")
	t.check(Connection.class_of(33) == "backbone", "width 33 is backbone")
	t.check(Connection.class_title(5) == "Trace" and Connection.class_title(8) == "Byte Bus", "titles: Trace / Byte Bus")
	t.check(Connection.class_title(32) == "Wide Bus" and Connection.class_title(33) == "Backbone", "titles: Wide Bus / Backbone")


static func _count_and_all_packets(t) -> void:
	var c := Connection.new(5, 1, "out", 2, "in", _cells3(), 3, 1, 2)
	t.check(not c.has_packets() and c.packet_count() == 0, "empty connection has no packets")
	var p0 := _pkt(1, 1)
	var p1 := _pkt(2, 3)
	var p2 := _pkt(3, 5)
	c.push(p0)  # lane 0 slot 0
	c.push(p1)  # lane 1 slot 0
	c.advance()  # both move to slot 1
	c.push(p2)  # lane 0 slot 0 again (lowest free lane)
	t.check(c.has_packets() and c.packet_count() == 3, "packet_count() spans every lane, got %d" % c.packet_count())
	var ap := c.all_packets()
	t.check(ap.size() == 3, "all_packets() lists every packet, got %d" % ap.size())
	t.check(ap[0]["lane"] == 0 and ap[0]["slot"] == 0 and ap[0]["packet"] == p2, "lane 0 slot 0 listed first")
	t.check(ap[1]["lane"] == 0 and ap[1]["slot"] == 1 and ap[1]["packet"] == p0, "lane 0 slot 1 listed second")
	t.check(ap[2]["lane"] == 1 and ap[2]["slot"] == 1 and ap[2]["packet"] == p1, "lane 1 slots listed after lane 0")


## set_wire_lanes -> layout_to_dict -> load_player_layout keeps 2 lanes on the wire.
static func _simulation_round_trip(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	var u := sim.place("usb_input", Vector2i(1, 4), 0, {}, 3)
	var a := sim.place("add", Vector2i(9, 4), 0, {}, 3)
	var c := sim.connect_ports(u.id, "out", a.id, "in")
	t.check(c != null and c.lanes == 1, "a fresh wire has one lane")
	t.check(sim.set_wire_lanes(c.id, 2), "set_wire_lanes(2) is accepted")
	t.check(c.lanes == 2 and c.lane_slots.size() == 2, "the wire now runs 2 lanes, got %d" % c.lanes)
	var d := sim.layout_to_dict()
	var cd: Dictionary = d["connections"][0]
	t.check(int(cd.get("lanes", 0)) == 2, "layout_to_dict carries the lane count, got %s" % cd.get("lanes"))
	var sim2 := Simulation.new()
	sim2.size = Vector2i(16, 10)
	sim2.load_player_layout(d)
	var ids2: Array = sim2.sorted_connection_ids()
	var c2: Connection = sim2.connections[ids2[0]]
	t.check(c2 != null and c2.lanes == 2, "fresh Simulation reloads the wire at lanes 2, got %d" % c2.lanes)


static func _set_wire_lanes_missing(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	sim.place("usb_input", Vector2i(1, 4), 0, {}, 3)
	t.check(not sim.set_wire_lanes(7, 2), "set_wire_lanes on a missing connection returns false")


## A 2-lane wire whose two head slots hold packets delivers BOTH in one step when the
## target can accept 2 (a Buffer with capacity 4); a 1-lane wire delivers one per step.
static func _delivery(t) -> void:
	var two := _delivery_sim(2)     # one packet on each head lane
	var one := _delivery_sim(1, 2)  # two packets in a row on one lane
	if two == null or one == null:
		t.check(false, "delivery test: usb_input -> buffer wire failed to connect")
		return
	var ev2 := _count_delivers(two)
	t.check(ev2 == 2, "2-lane wire delivers both head packets in one step, got %d" % ev2)
	var ev1a := _count_delivers(one)
	one.step()
	var ev1b := _count_delivers(one)
	t.check(ev1a == 1 and ev1b == 1, "1-lane wire delivers one packet per step (got %d then %d)" % [ev1a, ev1b])


## A simulation whose wire has `packets` packets ready (default: one per lane at the head)
## and has already run one step. Returns null when the wire does not connect.
static func _delivery_sim(lanes: int, packets := 0) -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	var src := sim.place("usb_input", Vector2i(1, 4), 0, {}, 3)
	var buf := sim.place("buffer", Vector2i(7, 4), 0, {"capacity": 4}, 3)
	var c := sim.connect_ports(src.id, "out", buf.id, "in")
	if c == null:
		return null
	c.set_lanes(lanes)
	var n: int = c.length()
	var q := packets if packets > 0 else lanes
	if lanes == 1 and q > 1:
		for j in q:  # single file: the head and the slot behind it
			c.lane_slots[0][n - 1 - j] = Packet.new(sim.new_packet_id(), BitVector.of(j + 1, 3), 0)
	else:
		for k in mini(lanes, q):  # one packet on each head slot
			c.lane_slots[k][n - 1] = Packet.new(sim.new_packet_id(), BitVector.of(k + 1, 3), 0)
	sim.step()
	return sim


static func _count_delivers(sim: Simulation) -> int:
	var n := 0
	for e in sim.events:
		if e["kind"] == "deliver":
			n += 1
	return n