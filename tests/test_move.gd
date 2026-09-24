class_name MoveTests
extends RefCounted
## F4 acceptance tests: Simulation.relayout_preview, the connected-move hologram behind a drag
## (docs/SYSTEMS_EXPANSION.md §9). It never changes the board; a move commits only when every
## wire can follow.


static func run(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(12, 6)
	var a := sim.place("add", Vector2i(2, 2), 0, {"k": 1}, 3)
	var b := sim.place("add", Vector2i(6, 4), 0, {"k": 1}, 3)
	var w := sim.connect_ports(a.id, "out", b.id, "in")
	var before := Array(w.cells)
	var ok := sim.relayout_preview(a.id, Vector2i(2, 0), 0)
	t.check(bool(ok["ok"]) and ok["routes"].has(w.id) and ok["fail"].is_empty(), "a free move previews a route for the machine's wire")
	t.check(a.cell == Vector2i(2, 2) and Array(w.cells) == before, "the preview changes nothing")
	var bad := sim.relayout_preview(a.id, Vector2i(10, 0), 0)  # the output port would face the board edge
	t.check(not bool(bad["ok"]) and bad["fail"].has(w.id), "a move that strands a wire is reported (%s)" % str(bad["error"]))
	t.check(str(bad["error"]).begins_with("Would cut the wire"), "and explained")
	t.check(sim.move(a.id, Vector2i(2, 0)) and Array(w.cells) == Array(ok["routes"][w.id]), "the committed move takes exactly the previewed route")
	var busy := sim.relayout_preview(a.id, Vector2i(6, 4), 0)
	t.check(not bool(busy["ok"]) and busy["routes"].is_empty(), "an occupied target is refused before routing")
