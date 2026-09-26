class_name SignalGeomTests
extends RefCounted
## Slice A4b acceptance tests for SignalGeom (world/connections/signal_geom.gd).
## Each case calls t.check(cond, what); run() is invoked from tests/run_tests.gd.

static func run(t) -> void:
	_chamfer(t)
	_simplify(t)
	_arc(t)
	_sub_project(t)
	_offset(t)
	_teardrop(t)
	_chevrons_dash(t)
	_bus_geometry(t)


# --- chamfer ------------------------------------------------------------------

static func _chamfer(t) -> void:
	var straight := SignalGeom.chamfer(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)]), 4.0)
	t.check(straight.size() == 3 and straight == PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)]), "chamfer leaves a straight run untouched")
	var corner := SignalGeom.chamfer(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), 4.0)
	t.check(corner.size() == 4 and corner[1] == Vector2(6, 0) and corner[2] == Vector2(10, 4), "chamfer cuts a 45° corner at both legs")
	var jog := SignalGeom.chamfer(PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2)]), 10.0)
	t.check(jog[1] == Vector2(1, 0) and jog[2] == Vector2(2, 1), "chamfer clamps to half of a short jog (never overshoots)")
	var far := SignalGeom.chamfer(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), 1.0)
	t.check(far[1].distance_to(Vector2(9, 0)) < 0.001 and far[2].distance_to(Vector2(10, 1)) < 0.001, "chamfer honours a small c")


# --- simplify -----------------------------------------------------------------

static func _simplify(t) -> void:
	var flat := SignalGeom.simplify(PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(10, 0), Vector2(10, 5)]))
	t.check(flat.size() == 3 and flat[0] == Vector2(0, 0) and flat[1] == Vector2(10, 0) and flat[2] == Vector2(10, 5), "simplify drops collinear middle points and keeps the endpoints")
	var corner := SignalGeom.simplify(PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(5, 5), Vector2(10, 5)]))
	t.check(corner.size() == 4, "simplify keeps real corners")
	var short := SignalGeom.simplify(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]))
	t.check(short.size() == 2, "simplify leaves short polylines alone")


# --- arc length / sample ------------------------------------------------------

static func _arc(t) -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	t.check(absf(SignalGeom.poly_len(pts) - 20.0) < 0.001, "poly_len sums segment lengths")
	var s0 := SignalGeom.sample(pts, 0.0)
	t.check((s0[0] as Vector2) == Vector2.ZERO and (s0[1] as Vector2) == Vector2.RIGHT, "sample(0) starts at the first point facing forward")
	var sm := SignalGeom.sample(pts, 0.25)
	t.check((sm[0] as Vector2).distance_to(Vector2(5, 0)) < 0.001 and (sm[1] as Vector2) == Vector2.RIGHT, "sample(0.25) is at arc 5 px along the first segment")
	var s1 := SignalGeom.sample(pts, 1.0)
	t.check((s1[0] as Vector2) == Vector2(10, 10) and (s1[1] as Vector2) == Vector2.DOWN, "sample(1) is the last point facing the last segment")
	var clamped := SignalGeom.sample(pts, 2.0)
	t.check((clamped[0] as Vector2) == Vector2(10, 10), "sample clamps t > 1")


# --- sub_poly / project -------------------------------------------------------

static func _sub_project(t) -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	var half := SignalGeom.sub_poly(pts, 0.0, 0.5)
	t.check(half.size() >= 2 and absf(SignalGeom.poly_len(half) - 10.0) < 0.001, "sub_poly(0, 0.5) has half the arc length")
	var tail := SignalGeom.sub_poly(pts, 0.5, 1.0)
	t.check(absf(SignalGeom.poly_len(tail) - 10.0) < 0.001, "sub_poly(0.5, 1) has the other half")
	t.check(absf(SignalGeom.project(pts, Vector2(5, 1)) - 0.25) < 0.001, "project of a point beside the first segment")
	t.check(absf(SignalGeom.project(pts, Vector2(12, 5)) - 0.75) < 0.001, "project of a point beside the second segment")
	t.check(SignalGeom.project(pts, Vector2(0, 0)) < 0.001 and absf(SignalGeom.project(pts, Vector2(10, 10)) - 1.0) < 0.001, "project maps the endpoints to 0 and 1")


# --- offset -------------------------------------------------------------------

static func _offset(t) -> void:
	var straight := SignalGeom.offset_poly(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]), 2.6)
	t.check((straight[0] as Vector2) == Vector2(0, 2.6) and (straight[1] as Vector2) == Vector2(10, 2.6), "offset_poly shifts a straight run perpendicular by off")
	var corner := SignalGeom.offset_poly(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), 1.0)
	t.check(absf(corner[1].distance_to(Vector2(10, 0)) - 1.0) < 0.001, "offset_poly miter-ish corner shifts the vertex ~1 px along its bisector")


# --- teardrop ----------------------------------------------------------------

static func _teardrop(t) -> void:
	var td := SignalGeom.teardrop(Vector2.ZERO, Vector2.RIGHT)
	t.check(td.size() == 18, "teardrop flattens both quadratics into an 18-vertex polygon, got %d" % td.size())
	t.check(td[0] == Vector2(6, 8), "teardrop starts at s=6, +half-width 8")
	t.check(td[9] == Vector2(20, -5), "teardrop far corner is s=20, -half-width 5")
	t.check(td[17] == Vector2(6, -8), "teardrop closes back at s=6, -half-width 8")
	t.check(td[4].distance_to(Vector2(14, 6.75)) < 0.001, "teardrop quad midpoint follows the bezier curve")
	var up := SignalGeom.teardrop(Vector2(100, 100), Vector2.UP)
	t.check(up[0].distance_to(Vector2(108, 94)) < 0.001, "teardrop rotates with the entry direction")


# --- chevrons / dash ----------------------------------------------------------

static func _chevrons_dash(t) -> void:
	var chev := SignalGeom.chevrons(PackedVector2Array([Vector2(0, 0), Vector2(480, 0)]), 48.0)
	t.check(chev.size() == 10, "chevrons places one chevron per spacing of arc, got %d" % chev.size())
	var first: PackedVector2Array = chev[0]
	t.check(first.size() == 3, "each chevron is a 3-point polyline")
	t.check(first[0].distance_to(Vector2(21.5, 3)) < 0.001 and first[1].distance_to(Vector2(25.5, 0)) < 0.001 and first[2].distance_to(Vector2(21.5, -3)) < 0.001, "chevron points back along the travel direction")
	var dash := SignalGeom.dash_poly(PackedVector2Array([Vector2(0, 0), Vector2(20, 0)]), 6.0, 4.0)
	t.check(dash.size() == 2, "dash_poly emits 6 px dashes with 4 px gaps, got %d" % dash.size())
	var d0: PackedVector2Array = dash[0]
	var d1: PackedVector2Array = dash[1]
	t.check(d0[0] == Vector2(0, 0) and d0[1] == Vector2(6, 0), "first dash starts at the polyline origin")
	t.check(d1[0] == Vector2(10, 0) and d1[1] == Vector2(16, 0), "second dash is offset by 6+4 px of arc")


# --- bus geometry (P10a) -----------------------------------------------------

static func _bus_geometry(t) -> void:
	t.check(SignalGeom.trench_for(3, 1) == 8.0, "trench_for(3,1) is the trace trench 8, got %s" % SignalGeom.trench_for(3, 1))
	t.check(SignalGeom.trench_for(8, 1) == 12.0, "trench_for(8,1) is the byte trench 12, got %s" % SignalGeom.trench_for(8, 1))
	t.check(SignalGeom.trench_for(16, 1) == 16.0, "trench_for(16,1) is the wide trench 16, got %s" % SignalGeom.trench_for(16, 1))
	t.check(SignalGeom.trench_for(40, 1) == 22.0, "trench_for(40,1) is the backbone trench 22, got %s" % SignalGeom.trench_for(40, 1))
	t.check(SignalGeom.trench_for(3, 4) == 16.0, "trench_for(3,4) widens to the 4-lane trench 16, got %s" % SignalGeom.trench_for(3, 4))
	t.check(SignalGeom.trench_for(8, 8) == 22.0, "trench_for(8,8) widens to the 8-lane trench 22, got %s" % SignalGeom.trench_for(8, 8))
	t.check(SignalGeom.chamfer_for(3, 1) == 14.0, "chamfer_for(3,1) is the trace chamfer 14, got %s" % SignalGeom.chamfer_for(3, 1))
	t.check(SignalGeom.chamfer_for(3, 2) == 18.0, "chamfer_for(3,2) is the bus chamfer 18, got %s" % SignalGeom.chamfer_for(3, 2))
	t.check(SignalGeom.chamfer_for(8, 1) == 18.0, "chamfer_for(8,1) is the bus chamfer 18, got %s" % SignalGeom.chamfer_for(8, 1))
	var one := SignalGeom.lane_offsets(3, 1)
	t.check(one.size() == 1 and one[0] == 0.0, "lane_offsets(3,1) is [0], got %s" % [one])
	var two := SignalGeom.lane_offsets(3, 2)
	t.check(two.size() == 2 and is_equal_approx(two[0], -1.925) and is_equal_approx(two[1], 1.925), "lane_offsets(3,2) ≈ [−1.925, 1.925], got %s" % [two])
	var four := SignalGeom.lane_offsets(3, 4)
	t.check(four.size() == 4 and is_equal_approx(four[0], -5.5) and is_equal_approx(four[1], -11.0 / 6.0) and is_equal_approx(four[2], 11.0 / 6.0) and is_equal_approx(four[3], 5.5), "lane_offsets(3,4) ≈ [−5.5, −1.8333, 1.8333, 5.5], got %s" % [four])
	t.check(SignalGeom.lane_core_width(1) == 2.5 and SignalGeom.lane_core_width(2) == 2.0 and SignalGeom.lane_core_width(4) == 1.4 and SignalGeom.lane_core_width(8) == 1.0, "lane_core_width maps 1/2/4/8 to 2.5/2/1.4/1")