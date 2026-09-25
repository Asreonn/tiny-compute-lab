class_name GroupTests
extends RefCounted
## Multi-select acceptance tests (docs/SYSTEMS_EXPANSION.md §9): group move / duplicate / delete
## are atomic, keep the wires and never change anything on failure.


static func run(t) -> void:
	_move(t)
	_move_refused(t)
	_duplicate(t)
	_delete(t)
	_clipboard(t)


static func _chain(sim: Simulation) -> Array:
	var a := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	var b := sim.place("add", Vector2i(6, 2), 0, {"k": 2}, 3)
	sim.connect_ports(a.id, "out", b.id, "in")
	return [a, b]


static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	return sim


static func _move(t) -> void:
	var sim := _sim()
	var ab := _chain(sim)
	var c := sim.place("add", Vector2i(12, 2), 0, {"k": 3}, 3)
	var w2 := sim.connect_ports(ab[1].id, "out", c.id, "in")
	t.check(sim.move_group([ab[0].id, ab[1].id], Vector2i(0, 4)), "a wired pair moves together")
	t.check(ab[0].cell == Vector2i(2, 6) and ab[1].cell == Vector2i(6, 6), "both machines moved by the same delta")
	t.check(sim.connections.size() == 2 and sim.connections.has(w2.id), "the internal wire and the wire to the outsider both follow")
	# a rigid shift may overlap the group's own old tiles
	t.check(sim.move_group([ab[0].id, ab[1].id], Vector2i(1, 0)), "a one-tile shift over its own old tiles is fine")


static func _move_refused(t) -> void:
	var sim := _sim()
	var ab := _chain(sim)
	var blocker := sim.place("add", Vector2i(2, 6), 0, {"k": 1}, 3)
	var before := JSON.stringify(sim.layout_to_dict())
	t.check(not sim.move_group([ab[0].id, ab[1].id], Vector2i(0, 4)), "a move onto another machine is refused")
	t.check(sim.last_error.begins_with("Tile occupied") and JSON.stringify(sim.layout_to_dict()) == before, "…and nothing changed (%s)" % sim.last_error)
	t.check(not sim.move_group([ab[0].id, ab[1].id], Vector2i(-5, 0)), "off the board is refused")
	t.check(blocker.cell == Vector2i(2, 6), "the blocker stayed")


static func _duplicate(t) -> void:
	var sim := _sim()
	var ab := _chain(sim)
	var copies := sim.duplicate_group([ab[0].id, ab[1].id], Vector2i(0, 5))
	t.check(copies.size() == 2 and sim.machines.size() == 4, "duplicate makes two copies")
	var ca: Machine = sim.machines[copies[0]]
	var cb: Machine = sim.machines[copies[1]]
	t.check(ca.cell == Vector2i(2, 7) and int(cb.params["k"]) == 2, "copies keep cells + delta and parameters")
	t.check(sim.connection_at_port(ca.id, "out") != null and sim.connection_at_port(ca.id, "out").to_id == cb.id, "the internal wire is copied too")
	var n := sim.machines.size()
	t.check(sim.duplicate_group([ab[0].id, ab[1].id], Vector2i(0, 0)).is_empty() and sim.machines.size() == n, "a duplicate onto the originals is refused, all or nothing")


static func _delete(t) -> void:
	var sim := _sim()
	var ab := _chain(sim)
	var fired := [0]
	sim.changed.connect(func(): fired[0] += 1)
	t.check(sim.remove_group([ab[0].id, ab[1].id]) == 2 and sim.machines.is_empty() and sim.connections.is_empty(), "delete removes the group and its wires")
	t.check(fired[0] == 1, "one change for the whole group")


## Ctrl+C / Ctrl+V: a snapshot of machines + their internal wires, pasted anywhere, all or nothing,
## and still there after the originals are deleted (Ctrl+X).
static func _clipboard(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	sim.default_width = 3
	var ab := _chain(sim)
	var clip := sim.copy_group([ab[0].id, ab[1].id])
	t.check((clip["machines"] as Array).size() == 2 and (clip["wires"] as Array).size() == 1, "a copy holds both machines and their wire")
	sim.remove_group([ab[0].id, ab[1].id])
	t.check(sim.machines.is_empty(), "the originals are gone (cut)")
	var ids := sim.paste_group(clip, Vector2i(3, 6))
	t.check(ids.size() == 2 and sim.machines[ids[0]].cell == Vector2i(3, 6) and sim.machines[ids[1]].cell == Vector2i(7, 6), "a paste keeps the layout at the new spot")
	t.check(sim.connections.size() == 1 and int(sim.machines[ids[1]].params["k"]) == 2, "the wire and the settings come along")
	var n := sim.machines.size()
	t.check(sim.paste_group(clip, Vector2i(3, 6)).is_empty() and sim.machines.size() == n, "a paste over machines places nothing")
	t.check(sim.copy_group([]).is_empty(), "copying nothing gives an empty clipboard")
