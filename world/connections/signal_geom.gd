class_name SignalGeom
extends RefCounted
## Signal System V1 wire geometry: direct port of design/reference/signal_system_v1.js
## (L.chamferPts, L.sample, L.subPoly, L.project, L.offsetPoly, L.teardrop, chevrons).
## Pure math on PackedVector2Array polylines — no nodes, no SceneTree, unit-testable.
## All coordinates are world px; t parameters are fractions of total arc length.

const EPS := 0.0001


## Chamfer every corner of an orthogonal polyline by c px. The cut is clamped to half of
## each adjacent segment so a short jog never overshoots into the next corner (L.chamferPts).
static func chamfer(pts: PackedVector2Array, c: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(1, pts.size() - 1):
		var p := pts[i - 1]
		var x := pts[i]
		var n := pts[i + 1]
		var d1: Vector2 = (x - p).sign()
		var d2: Vector2 = (n - x).sign()
		if d1 == d2:
			out.append(x)
			continue
		var cc := minf(c, minf(x.distance_to(p) * 0.5, n.distance_to(x) * 0.5))
		out.append(x - d1 * cc)
		out.append(x + d2 * cc)
	out.append(pts[pts.size() - 1])
	return out


## Drop middle points that lie exactly on the line between their neighbours. The polyline
## endpoints are always kept (they are the port anchors that teardrops attach to).
static func simplify(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(1, pts.size() - 1):
		var a := pts[i] - pts[i - 1]
		var b := pts[i + 1] - pts[i]
		if absf(a.cross(b)) > EPS:
			out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out


## Total arc length of the polyline.
static func poly_len(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i].distance_to(pts[i - 1])
	return l


## Sample the polyline at fraction t of its arc length -> [pos: Vector2, dir: Vector2]
## where dir is the unit direction of the segment containing the sample (L.sample).
static func sample(pts: PackedVector2Array, t: float) -> Array:
	var total := maxf(poly_len(pts), 1e-9)
	var d := clampf(t, 0.0, 1.0) * total
	for i in range(1, pts.size()):
		var seg := pts[i] - pts[i - 1]
		var l := seg.length()
		if d <= l:
			var k := d / l if l > 0.0 else 0.0
			return [pts[i - 1] + seg * k, seg.normalized()]
		d -= l
	var n := pts.size() - 1
	var last := pts[n] - pts[n - 1]
	return [pts[n], last.normalized() if last.length() > 0.0 else Vector2.RIGHT]


## Slice the polyline between arc fractions t0 and t1 (L.subPoly). Shares vertices at
## segment boundaries exactly like the reference, so lengths stay faithful to arc distance.
static func sub_poly(pts: PackedVector2Array, t0: float, t1: float) -> PackedVector2Array:
	var total := maxf(poly_len(pts), 1e-9)
	var a := clampf(t0, 0.0, 1.0) * total
	var b := clampf(t1, 0.0, 1.0) * total
	var out := PackedVector2Array()
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i] - pts[i - 1]
		var l := seg.length()
		var s0 := acc
		var s1 := acc + l
		if s1 >= a and s0 <= b and l > 0.0:
			if out.is_empty():
				out.append(pts[i - 1] + seg * clampf((maxf(a, s0) - s0) / l, 0.0, 1.0))
			out.append(pts[i - 1] + seg * clampf((minf(b, s1) - s0) / l, 0.0, 1.0))
		acc = s1
	if out.size() > 1:
		return out
	return PackedVector2Array([sample(pts, t0)[0], sample(pts, t1)[0]])


## Project a world point onto the polyline -> arc-length fraction t in [0, 1] (L.project).
static func project(pts: PackedVector2Array, p: Vector2) -> float:
	var best := 0.0
	var best_d := INF
	var acc := 0.0
	var total := maxf(poly_len(pts), 1e-9)
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := b - a
		var l := seg.length()
		if l <= 0.0:
			continue
		var k := clampf((p - a).dot(seg) / (l * l), 0.0, 1.0)
		var d := (a + seg * k - p).length()
		if d < best_d:
			best_d = d
			best = (acc + k * l) / total
		acc += l
	return best


## Offset the whole polyline by off px along each vertex's local (prev..next) normal
## (L.offsetPoly, miter-ish for the 45° chamfer joints).
static func offset_poly(pts: PackedVector2Array, off: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		var a := pts[maxi(0, i - 1)]
		var c := pts[mini(pts.size() - 1, i + 1)]
		var u := (c - a).normalized()
		out[i] = pts[i] + Vector2(-u.y, u.x) * off
	return out


## PCB teardrop polygon: widens a trace from P along unit direction u (L.teardrop).
## The two quadratic edges (A->Q1->D and C->Q2->B) are flattened with 8 samples each.
static func teardrop(P: Vector2, u: Vector2) -> PackedVector2Array:
	var a := float(Palette.SIG_TEARDROP_START)
	var b := float(Palette.SIG_TEARDROP_END)
	var w0 := float(Palette.SIG_TEARDROP_HALF_WIDTH_START)
	var w1 := float(Palette.SIG_TEARDROP_HALF_WIDTH_END)
	var n := Vector2(-u.y, u.x)
	var q := func(s: float, w: float) -> Vector2:
		return P + u * s + n * w
	var A: Vector2 = q.call(a, w0)
	var B: Vector2 = q.call(a, -w0)
	var C: Vector2 = q.call(b, -w1)
	var D: Vector2 = q.call(b, w1)
	var Q1: Vector2 = q.call(a + 9.0, w0 - 1.0)
	var Q2: Vector2 = q.call(a + 9.0, -(w0 - 1.0))
	var out := PackedVector2Array()
	out.append(A)
	for k in range(1, 9):
		out.append(_quad(A, Q1, D, k / 8.0))
	out.append(C)
	for k in range(1, 9):
		out.append(_quad(C, Q2, B, k / 8.0))
	return out


## Quadratic bezier point (1-t)^2 p0 + 2(1-t)t p1 + t^2 p2.
static func _quad(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t)


## Flow chevrons: one 3-point chevron per `spacing` px of arc, centred on the line and
## pointing along it (L.drawWire "flow-chevrons": base 2×2.5 back, tip 1.5 forward).
static func chevrons(pts: PackedVector2Array, spacing: float) -> Array:
	var out: Array = []
	var plen := poly_len(pts)
	var k := maxi(1, int(floorf(plen / spacing)))
	for i in range(1, k + 1):
		var t := (i - 0.5) / k
		var s := sample(pts, t)
		var x: Vector2 = s[0]
		var u: Vector2 = s[1]
		var n := Vector2(-u.y, u.x)
		out.append(PackedVector2Array([
			x - u * 2.5 + n * 3.0,
			x + u * 1.5,
			x - u * 2.5 - n * 3.0,
		]))
	return out


## Split a polyline into dash/gap segments measured along arc length. Returns an Array of
## PackedVector2Array, one per dash. The gap is skipped between consecutive dashes.
static func dash_poly(pts: PackedVector2Array, dash: float, gap: float) -> Array:
	var out: Array = []
	var total := poly_len(pts)
	if total <= 0.0:
		return out
	var d0 := 0.0
	while d0 < total:
		var d1 := minf(d0 + dash, total)
		out.append(sub_poly(pts, d0 / total, d1 / total))
		d0 = d1 + gap
	return out