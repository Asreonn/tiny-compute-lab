class_name ThermalNetworkTests
extends RefCounted
## P7a acceptance tests: the pure ThermalNetwork module — topology, airflow, allocation,
## recirculation, blocked intake and determinism. No Simulation / ThermalGrid integration yet:
## every case builds a plain Simulation and calls ThermalNetwork.build() directly.


static func run(t) -> void:
	_topology(t)
	_airflow(t)
	_allocation(t)
	_recirculation(t)
	_blocked_intake(t)
	_determinism(t)
	_shared_pipe_order(t)
	_no_air_no_dump(t)
	_view_queries(t)


static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	sim.campaign_timing = true
	return sim


## Add at (4,5); a heat_pipe chain from (4,4) to (8,4) then up (8,3),(8,2),(8,1) into the west
## inlet of a radiator at (9,0). The Add connects; the radiator attaches; it exhausts out.
static func _topology(t) -> void:
	var sim := _sim()
	var add := sim.place("add", Vector2i(4, 5), 0, {"k": 1}, 3)
	for x in range(4, 9):
		sim.place("heat_pipe", Vector2i(x, 4), 0, {}, 3)
	for y in [3, 2, 1]:
		sim.place("heat_pipe", Vector2i(8, y), 0, {}, 3)
	var rad := sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	var tn := ThermalNetwork.build(sim)
	t.check(tn.network_of(add.id) == "n28", "the Add connects to n28, got %s" % tn.network_of(add.id))
	t.check(tn.contact_cap(add.id) == 1200, "an M Add has contact cap 1200, got %d" % tn.contact_cap(add.id))
	var sinks := tn.sinks()
	t.check(sinks.size() == 1 and sinks[0]["id"] == rad.id, "the radiator is the only sink")
	t.check(sinks[0]["network"] == "n28", "the radiator attaches to n28, got %s" % sinks[0]["network"])
	t.check(sinks[0]["exhaust_out"], "a radiator at the top edge exhausts out of the computer")


## Radiator at (9,0) with blowers below it: airflow is capped at the need and the effective
## capacity follows. A third (non-feeding) blower adds nothing.
static func _airflow(t) -> void:
	var sim := _sim()
	sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim.place("blower", Vector2i(10, 2), 0, {}, 3)
	var tn := ThermalNetwork.build(sim)
	var s: Dictionary = tn.sinks()[0]
	t.check(s["airflow"] == 40, "two blowers cap airflow at the need 40, got %d" % s["airflow"])
	t.check(s["effective"] == 1600, "full airflow gives effective 1600, got %d" % s["effective"])

	var sim2 := _sim()
	sim2.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim2.place("blower", Vector2i(9, 2), 0, {}, 3)
	var tn2 := ThermalNetwork.build(sim2)
	var s2: Dictionary = tn2.sinks()[0]
	t.check(s2["airflow"] == 25 and s2["effective"] == 1000, "one blower: airflow 25, effective 1000, got %d/%d" % [s2["airflow"], s2["effective"]])

	var sim3 := _sim()
	sim3.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim3.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim3.place("blower", Vector2i(10, 2), 0, {}, 3)
	sim3.place("blower", Vector2i(12, 2), 0, {}, 3)  # not feeding, not blocking
	var tn3 := ThermalNetwork.build(sim3)
	var s3: Dictionary = tn3.sinks()[0]
	t.check(s3["effective"] == 1600, "a third blower adds nothing, effective stays 1600, got %d" % s3["effective"])


## offers {add: 1200}: a copper pipe (800) caps removal at 800; a heavy pipe (2000) passes all
## 1200; the same heavy pipe with a single blower (effective 1000) caps removal at 1000.
static func _allocation(t) -> void:
	var sim := _sim()
	var add := sim.place("add", Vector2i(4, 5), 0, {"k": 1}, 3)
	for x in range(4, 9):
		sim.place("heat_pipe", Vector2i(x, 4), 0, {}, 3)
	for y in [3, 2, 1]:
		sim.place("heat_pipe", Vector2i(8, y), 0, {}, 3)
	sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim.place("blower", Vector2i(10, 2), 0, {}, 3)
	var tn := ThermalNetwork.build(sim)
	var r := tn.allocate({add.id: 1200})
	t.check(r["removal"][add.id] == 800, "copper pipe 800 caps removal at 800, got %d" % r["removal"][add.id])

	var sim2 := _sim()
	var add2 := sim2.place("add", Vector2i(4, 5), 0, {"k": 1}, 3)
	for x in range(4, 9):
		sim2.place("heat_pipe_heavy", Vector2i(x, 4), 0, {}, 3)
	for y in [3, 2, 1]:
		sim2.place("heat_pipe_heavy", Vector2i(8, y), 0, {}, 3)
	sim2.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim2.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim2.place("blower", Vector2i(10, 2), 0, {}, 3)
	var tn2 := ThermalNetwork.build(sim2)
	var r2 := tn2.allocate({add2.id: 1200})
	t.check(r2["removal"][add2.id] == 1200, "heavy pipe 2000 passes all 1200, got %d" % r2["removal"][add2.id])

	var sim3 := _sim()
	var add3 := sim3.place("add", Vector2i(4, 5), 0, {"k": 1}, 3)
	for x in range(4, 9):
		sim3.place("heat_pipe_heavy", Vector2i(x, 4), 0, {}, 3)
	for y in [3, 2, 1]:
		sim3.place("heat_pipe_heavy", Vector2i(8, y), 0, {}, 3)
	sim3.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim3.place("blower", Vector2i(9, 2), 0, {}, 3)
	var tn3 := ThermalNetwork.build(sim3)
	var r3 := tn3.allocate({add3.id: 1200})
	t.check(r3["removal"][add3.id] == 1000, "single blower effective 1000 caps removal at 1000, got %d" % r3["removal"][add3.id])


## The same radiator moved down one row (not at the edge) recirculates instead of exhausting.
static func _recirculation(t) -> void:
	var sim := _sim()
	sim.place("add", Vector2i(4, 5), 0, {"k": 1}, 3)
	for x in range(4, 9):
		sim.place("heat_pipe", Vector2i(x, 4), 0, {}, 3)
	for y in [3, 2, 1]:
		sim.place("heat_pipe", Vector2i(8, y), 0, {}, 3)
	sim.place("radiator", Vector2i(9, 1), 0, {}, 3)
	var tn := ThermalNetwork.build(sim)
	var s: Dictionary = tn.sinks()[0]
	t.check(s["network"] == "n28", "the moved radiator still attaches to n28, got %s" % s["network"])
	t.check(not s["exhaust_out"], "a radiator not at the top edge recirculates (exhaust_out false)")


## A machine directly south of a blower blocks its intake and halves its airflow.
static func _blocked_intake(t) -> void:
	var sim := _sim()
	sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim.place("add", Vector2i(9, 3), 0, {"k": 1}, 3)  # directly south of the blower
	var tn := ThermalNetwork.build(sim)
	var s: Dictionary = tn.sinks()[0]
	t.check(s["airflow"] == 12, "a blocked blower halves its airflow to 12, got %d" % s["airflow"])


## Building twice gives identical sinks() and allocate() results.
static func _determinism(t) -> void:
	var sim := _sim()
	var add := sim.place("add", Vector2i(4, 5), 0, {"k": 1}, 3)
	for x in range(4, 9):
		sim.place("heat_pipe_heavy", Vector2i(x, 4), 0, {}, 3)
	for y in [3, 2, 1]:
		sim.place("heat_pipe_heavy", Vector2i(8, y), 0, {}, 3)
	sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim.place("blower", Vector2i(9, 2), 0, {}, 3)
	var a := ThermalNetwork.build(sim)
	var b := ThermalNetwork.build(sim)
	t.check(a.sinks() == b.sinks(), "building twice gives identical sinks()")
	t.check(a.allocate({add.id: 1200}) == b.allocate({add.id: 1200}), "building twice gives identical allocate()")

## Two machines share one copper pipe (800) and offer 600 each: both get 400, whatever the
## order they are processed in (the flows are summed before any factor is taken).
static func _shared_pipe_order(t) -> void:
	var sim := _sim()
	var a := sim.place("add", Vector2i(2, 5), 0, {"k": 1}, 3)
	var b := sim.place("add", Vector2i(5, 5), 0, {"k": 1}, 3)
	for x in range(2, 9):
		sim.place("heat_pipe", Vector2i(x, 4), 0, {}, 3)
	for y in [3, 2, 1]:
		sim.place("heat_pipe", Vector2i(8, y), 0, {}, 3)
	sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	sim.place("blower", Vector2i(9, 2), 0, {}, 3)
	sim.place("blower", Vector2i(10, 2), 0, {}, 3)
	var tn := ThermalNetwork.build(sim)
	var r := tn.allocate({a.id: 600, b.id: 600})
	t.check(r["removal"][a.id] == 400 and r["removal"][b.id] == 400, "a shared 800 pipe splits evenly (%d / %d)" % [r["removal"][a.id], r["removal"][b.id]])
	var r2 := tn.allocate({b.id: 600, a.id: 600})
	t.check(r2["removal"][a.id] == 400 and r2["removal"][b.id] == 400, "…independent of offer order")


## A radiator with no airflow dumps nothing.
static func _no_air_no_dump(t) -> void:
	var sim := _sim()
	var add := sim.place("add", Vector2i(4, 5), 0, {"k": 1}, 3)
	for x in range(4, 9):
		sim.place("heat_pipe_heavy", Vector2i(x, 4), 0, {}, 3)
	for y in [3, 2, 1]:
		sim.place("heat_pipe_heavy", Vector2i(8, y), 0, {}, 3)
	sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	var tn := ThermalNetwork.build(sim)
	t.check(tn.allocate({add.id: 1200})["removal"][add.id] == 0, "a radiator without airflow removes nothing")


## View queries: blowers_of() per sink, tile_cap(), the allocation's tile flow, and a rotated
## machine's contact row (its rotated footprint, not the unrotated one).
static func _view_queries(t) -> void:
	var sim := _sim()
	var rad := sim.place("radiator", Vector2i(9, 0), 0, {}, 3)
	var b1 := sim.place("blower", Vector2i(9, 2), 0, {}, 3)
	var b2 := sim.place("blower", Vector2i(10, 2), 0, {}, 3)
	sim.place("blower", Vector2i(12, 2), 0, {}, 3)
	for x in range(5, 9):
		sim.place("heat_pipe", Vector2i(x, 3), 0, {}, 3)
	for y in [2, 1]:
		sim.place("heat_pipe", Vector2i(8, y), 0, {}, 3)
	var turned := sim.place("add", Vector2i(4, 4), 1, {"k": 1}, 3)  # 1×2 footprint at x 4
	var tn := ThermalNetwork.build(sim)
	t.check(tn.blowers_of(rad.id) == [b1.id, b2.id], "the two blowers under the radiator feed it (got %s)" % str(tn.blowers_of(rad.id)))
	t.check(tn.tile_cap(Vector2i(6, 3)) == 800 and tn.tile_cap(Vector2i(0, 0)) == 0, "tile_cap reads the pipe's capacity")
	t.check(tn.network_of(turned.id) == "", "a rotated Add only touches the tile above its 1-wide footprint (no pipe there)")
	sim.place("heat_pipe", Vector2i(4, 3), 0, {}, 3)
	var tn2 := ThermalNetwork.build(sim)
	t.check(tn2.network_of(turned.id) != "", "a pipe above the rotated Add connects it")
	var r := tn2.allocate({turned.id: 300})
	t.check(int(r["flow"].get(Vector2i(6, 3), 0)) == 300, "the offer flows through the pipe tiles on its path (got %s)" % str(r["flow"].get(Vector2i(6, 3))))
