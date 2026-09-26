class_name BottleneckTests
extends RefCounted
## P3: bottleneck metrics (docs/FACTORY_SYSTEMS.md §7.4). A wire is bandwidth-bound when it was
## saturated in ≥ 50 % of the last 60 ticks, a machine compute-bound when all its lanes were busy
## with the inputs full in ≥ 50 % of them; first_bound() walks upstream from a sink.

static func run(t) -> void:
	_window(t)
	_bandwidth_bound(t)
	_compute_bound(t)
	_clean_line(t)


## The 60-tick window: 60 saturated ticks → 1.0, then 30 clear → 0.5, 60 clear → 0.
static func _window(t) -> void:
	var c := Connection.new(1, 0, "out", 1, "in", [Vector2i(0, 0)] as Array[Vector2i], 3)
	for i in 60:
		c.note_saturation(true)
	t.check(is_equal_approx(c.saturation_ratio(), 1.0), "60 saturated ticks fill the window (%.2f)" % c.saturation_ratio())
	for i in 30:
		c.note_saturation(false)
	t.check(is_equal_approx(c.saturation_ratio(), 0.5), "30 clear ticks halve it (%.2f)" % c.saturation_ratio())
	for i in 60:
		c.note_saturation(false)
	t.check(c.saturation_ratio() == 0.0, "60 clear ticks empty it")
	var m := Machine.new(1, "add", Vector2i.ZERO, 3)
	for i in 45:
		m.note_compute_bound(true)
	t.check(is_equal_approx(m.compute_bound_ratio(), 0.75), "the machine window counts the same way (%.2f)" % m.compute_bound_ratio())


static func _socket_line(lanes: int) -> Dictionary:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	var src := sim.place("usb_input", Vector2i(1, 5), 0, {}, 3)
	src.socket = true
	var out := sim.place("usb_output", Vector2i(9, 5), 0, {}, 3)
	sim.insert_device(src.id, "bit", {"values": ["010"], "width": 3, "interval": 1, "burst": 2})
	var c := sim.connect_ports(src.id, "out", out.id, "in")
	if lanes > 1:
		sim.set_wire_lanes(c.id, lanes)
	sim.reset_run()
	for i in 80:
		sim.step()
	return {"sim": sim, "out": out, "wire": c}


## A burst-2 stick on a 1-lane wire saturates it; on a 2-lane wire it does not.
static func _bandwidth_bound(t) -> void:
	var d := _socket_line(1)
	var sim: Simulation = d["sim"]
	var c: Connection = d["wire"]
	t.check(sim.wire_bound(c.id), "a 1-lane wire under a 2/tick stick is bandwidth-bound (%.2f)" % c.saturation_ratio())
	var b := sim.first_bound(d["out"].id)
	t.check(str(b.get("kind", "")) == "bandwidth" and int(b.get("connection", -1)) == c.id, "first_bound from the sink names the wire (%s)" % str(b))
	var d2 := _socket_line(2)
	t.check(not d2["sim"].wire_bound(d2["wire"].id), "the same stick on a 2-lane wire is not bound (%.2f)" % d2["wire"].saturation_ratio())


## A 1-lane Add fed every tick (4-tick jobs) is compute-bound, and first_bound names it.
static func _compute_bound(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	sim.campaign_timing = true
	sim.default_width = 3
	var s := sim.place("usb_input", Vector2i(0, 2), 0, {}, 3)
	s.stream = [BitVector.of(1, 3)]
	s.loop = true
	s.interval = 1
	var a := sim.place("add", Vector2i(4, 2), 0, {"k": 1}, 3)
	var o := sim.place("output", Vector2i(8, 2), 0, {}, 3)
	sim.connect_ports(s.id, "out", a.id, "in")
	sim.connect_ports(a.id, "out", o.id, "in")
	for i in 80:
		sim.step()
	t.check(sim.compute_bound(a.id), "a 1-lane Add fed every tick is compute-bound (%.2f)" % a.compute_bound_ratio())
	var b := sim.first_bound(o.id)
	t.check(str(b.get("kind", "")) == "compute" and int(b.get("machine", -1)) == a.id, "first_bound from the output names the Add (%s)" % str(b))


## A slow source into a 4-lane Add on plain wires: nothing is bound.
static func _clean_line(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	sim.campaign_timing = true
	sim.default_width = 3
	var s := sim.place("usb_input", Vector2i(0, 2), 0, {}, 3)
	s.stream = [BitVector.of(1, 3)]
	s.loop = true
	s.interval = 4
	var a := sim.place("add", Vector2i(4, 2), 0, {"k": 1, "lanes": "4"}, 3)
	var o := sim.place("output", Vector2i(8, 2), 0, {}, 3)
	sim.connect_ports(s.id, "out", a.id, "in")
	sim.connect_ports(a.id, "out", o.id, "in")
	for i in 80:
		sim.step()
	t.check(sim.first_bound(o.id).is_empty(), "a comfortable line reports no bound (%s)" % str(sim.first_bound(o.id)))
