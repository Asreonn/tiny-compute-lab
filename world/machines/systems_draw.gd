class_name SystemsDraw
extends RefCounted
## Procedural drawing of the Systems Expansion V1 geometry (design/reference/systems_v1.js):
## raw ports, raw tokens, the USB port face, data modules and the 0.5-scale mini module.
##
## Pure `_draw()` helpers: every function takes the CanvasItem and draws in its local space
## with Palette tokens only (docs/VISUAL_SYSTEM.md §21, docs/STYLE_GUIDE.md §14). No nodes,
## no state, no allocations beyond small PackedVector2Arrays. Positions are top-left px of the
## element's bounding box (rawPort 24x24, portFace 16x36, dataModule 96x56), matching the
## Penpot drawers 1:1.

const FONT := "ExtraBold"


# ================================================================ primitives

## Filled rounded rectangle (radius r) from a small perimeter polygon.
static func rrect(ci: CanvasItem, rect: Rect2, r: float, color: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	if r <= 0.0:
		ci.draw_rect(rect, color)
		return
	ci.draw_colored_polygon(_round_rect_pts(rect, minf(r, minf(rect.size.x, rect.size.y) * 0.5), 6), color)


## Rounded-rectangle outline, 1 px default.
static func rrect_outline(ci: CanvasItem, rect: Rect2, r: float, color: Color, w := 1.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	if r <= 0.0:
		ci.draw_rect(rect, color, false, w)
		return
	ci.draw_polyline(_round_rect_pts(rect, minf(r, minf(rect.size.x, rect.size.y) * 0.5), 6), color, w, true)


## Dashed rounded-rectangle outline (queued raw token ring).
static func rrect_dashed(ci: CanvasItem, rect: Rect2, r: float, color: Color, w := 1.0, dash := 3.0, gap := 3.0) -> void:
	_dashed_path(ci, _round_rect_pts(rect, minf(r, minf(rect.size.x, rect.size.y) * 0.5), 6), color, w, dash, gap)


## Closed perimeter of a rounded rectangle, corners sampled with `seg` segments each.
static func _round_rect_pts(rect: Rect2, r: float, seg: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI / 2.0, 0.0],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0, PI / 2.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI / 2.0, PI],
		[Vector2(rect.position.x + r, rect.position.y + r), PI, PI * 1.5],
	]
	for c in corners:
		var ctr: Vector2 = c[0]
		var a0: float = c[1]
		var a1: float = c[2]
		for i in seg + 1:
			var a := a0 + (a1 - a0) * float(i) / float(seg)
			pts.append(ctr + Vector2(cos(a), sin(a)) * r)
	pts.append(pts[0])
	return pts


static func _dashed_path(ci: CanvasItem, pts: PackedVector2Array, color: Color, w: float, dash: float, gap: float) -> void:
	var on := true
	var remain := dash
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var d := a.distance_to(b)
		var t := 0.0
		while d - t > 0.001:
			var step := minf(remain, d - t)
			if on:
				ci.draw_line(a.lerp(b, t / d), a.lerp(b, (t + step) / d), color, w, true)
			t += step
			remain -= step
			if remain <= 0.001:
				on = not on
				remain = dash if on else gap


## Text centred in a box (vertical centre by ascent/descent), ExtraBold.
static func text_center(ci: CanvasItem, box: Rect2, text: String, size: float, color: Color) -> void:
	if text == "":
		return
	var f := TclTheme.font(FONT)
	var asc := f.get_ascent(size)
	var desc := f.get_descent(size)
	var base := Vector2(box.position.x, box.position.y + (box.size.y - (asc + desc)) * 0.5 + asc)
	ci.draw_string(f, base, text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, size, color)


# ================================================================ raw port (24x24)

## rawPort(dir, state): USB-style receptacle on the copper pad. `pos` = top-left of the 24x24.
## state: "Idle" | "Connected" | "Active" (Active adds the 1 px contact ring, VFX L1).
static func raw_port(ci: CanvasItem, pos: Vector2, dir: String, state: String) -> void:
	var is_out := dir == "Output" or dir == "out"
	var lit := state != "Idle"
	var op := 1.0 if lit else 0.45
	# lead
	ci.draw_rect(Rect2(pos + Vector2(21 if is_out else 0, 11), Vector2(3, 2)), Palette.MATERIAL_COPPER_DIM)
	# contact pad
	rrect(ci, Rect2(pos + Vector2(3, 3), Vector2(18, 18)), 4.0, Palette.MATERIAL_COPPER_DIM)
	# contact ring (Active only)
	if state == "Active":
		rrect_outline(ci, Rect2(pos + Vector2(1.5, 1.5), Vector2(21, 21)), 5.0, Color(Palette.FAMILY_IO, 0.6), 1.0)
	# body
	var body := Rect2(pos + Vector2(5, 7), Vector2(14, 10))
	rrect(ci, body, 2.0, Palette.MATERIAL_DIE)
	rrect_outline(ci, body, 2.0, Color(Palette.FAMILY_IO, op), 2.0)
	# core
	var core_y := 11.5 if is_out else 9.5
	var core_col := Palette.TEXT_PRIMARY if state == "Active" else Palette.FAMILY_IO
	rrect(ci, Rect2(pos + Vector2(8, core_y), Vector2(8, 3)), 1.0, Color(core_col, op))
	# flow chevron
	var chev := PackedVector2Array([
		pos + Vector2(1, 1), pos + Vector2(5, 5), pos + Vector2(1, 9),
	])
	ci.draw_polyline(chev, Color(Palette.FAMILY_IO, op), 2.0, true)


# ================================================================ raw token (pill)

## rawToken(zoom, state, glyph): pill with NO halo. `center` = token centre.
## zoom: "far" | "normal" | "close". state: "normal" | "queued" | "entering" | "accepted".
## entering/absorbing draws the whole token at alpha `alpha` (default .45).
static func raw_token(ci: CanvasItem, center: Vector2, zoom: String, state: String, glyph: String, font: Font, alpha := 1.0) -> void:
	var dims := {
		"Normal": [24.0, 16.0, 20.0, 12.0, 8.0],
		"Close": [40.0, 22.0, 36.0, 18.0, 11.0],
		"Far": [16.0, 16.0, 8.0, 8.0, 0.0],
	}
	var key := zoom.capitalize()
	if not dims.has(key):
		key = "Normal"
	var d: Array = dims[key]
	var W: float = d[0]
	var H: float = d[1]
	var bw: float = d[2]
	var bh: float = d[3]
	var fs: float = d[4]
	var ox := (W - bw) * 0.5
	var oy := (H - bh) * 0.5
	var origin := center - Vector2(W, H) * 0.5
	var a := 0.45 if state == "entering" else 1.0
	a *= alpha
	if state == "queued":
		rrect_dashed(ci, Rect2(origin + Vector2(ox - 2, oy - 2), Vector2(bw + 4, bh + 4)), (bh + 4) * 0.5, Color(Palette.FAMILY_IO, 0.5), 1.0)
	elif state == "accepted":
		rrect_outline(ci, Rect2(origin + Vector2(ox - 2, oy - 2), Vector2(bw + 4, bh + 4)), (bh + 4) * 0.5, Color(Palette.STATE_VALID, 0.9), 1.0)
	var body := Rect2(origin + Vector2(ox, oy), Vector2(bw, bh))
	if key == "Far":
		rrect(ci, body, bh * 0.5, Color(Palette.FAMILY_IO, a))
		return
	rrect(ci, body, bh * 0.5, Color(Palette.MATERIAL_DIE, a))
	rrect_outline(ci, body, bh * 0.5, Color(Palette.FAMILY_IO, a), 1.5 if key == "Close" else 1.25)
	if glyph != "" and font != null:
		text_center(ci, Rect2(body.position, Vector2(body.size.x, body.size.y)), glyph, fs, Color(Palette.FAMILY_IO, a))


# ================================================================ USB port face (16x36)

## portFace(x, y, plugged, lit, flip): female USB-A face set into the locked edge sprite.
static func port_face(ci: CanvasItem, pos: Vector2, plugged: bool, lit: bool, flip: bool) -> void:
	var frame := Rect2(pos, Vector2(16, 36))
	rrect(ci, frame, 2.0, Palette.MACHINE_FRAME_HOVER)
	rrect_outline(ci, frame, 2.0, Color(Palette.MATERIAL_SILK, 0.45), 1.0)
	rrect(ci, Rect2(pos + Vector2(2.5, 2.5), Vector2(11, 31)), 1.0, Palette.MATERIAL_PLATE_HI if plugged else Palette.MATERIAL_VENT)
	var tx := pos.x + (3.5 if flip else 7.5)
	rrect(ci, Rect2(Vector2(tx, pos.y + 4), Vector2(5, 28)), 1.0, Palette.MATERIAL_PLATE_LO)
	rrect_outline(ci, Rect2(Vector2(tx, pos.y + 4), Vector2(5, 28)), 1.0, Palette.MACHINE_FRAME, 0.5)
	for i in 4:
		var cx := tx + (2.5 if flip else 0.0)
		ci.draw_rect(Rect2(Vector2(cx, pos.y + 7 + i * 6.5), Vector2(2.5, 4)), Color(Palette.MATERIAL_GOLD, 0.5 if plugged else 0.95))
	if lit:
		var sx := pos.x + (16.0 if flip else -1.5)
		ci.draw_rect(Rect2(Vector2(sx, pos.y + 3), Vector2(1.5, 30)), Color(Palette.TEXT_PRIMARY, 0.55))


# ================================================================ data module (96x56)

const MOD_END := {
	"bit": "square",
	"number": "chamfer",
	"text": "round",
	"key": "notch",
	"sensor": "fins",
	"job": "slant",
	"monitor": "bezel",
}
## The glyph a module shows in its window (systems_v1.js MOD).
const MOD_GLYPH := {"bit": "010", "number": "42", "text": "Aa", "key": "K#", "sensor": "~"}


static func kind_glyph(kind: String) -> String:
	return str(MOD_GLYPH.get(kind, ""))


## dataModule(kind, opts): 96x56 module with a male USB-A plug. `pos` = top-left of the body.
## opts: flip, inserted, ghost, cursor (0..29 lit block), fill (0..1), glyph, acc, alpha.
static func data_module(ci: CanvasItem, pos: Vector2, kind: String, opts: Dictionary = {}) -> void:
	var flip: bool = opts.get("flip", false)
	var inserted: bool = opts.get("inserted", false)
	var ghost: bool = opts.get("ghost", false)
	var alpha: float = opts.get("alpha", 1.0)
	var glyph: String = opts.get("glyph", "")
	var acc: Color = opts.get("acc", Palette.FAMILY_IO)
	var cursor: int = int(opts.get("cursor", -1))
	var fill: Variant = opts.get("fill", null)
	var end: String = MOD_END.get(kind, "square")
	var plug_x := -22.0 if flip else 96.0
	if not inserted and not ghost:
		male_plug(ci, pos + Vector2(plug_x, 14), flip, alpha)
	# silhouette
	var path := _mod_path(end, flip)
	var pts := PackedVector2Array()
	for p in path:
		pts.append(pos + p)
	if ghost:
		ci.draw_polyline(pts, Color(Palette.STATE_HOVER, 1.0), 1.0, true)
		rrect_outline(ci, Rect2(pos + Vector2(plug_x, 14), Vector2(22, 28)), 1.5, Color(Palette.STATE_HOVER, 0.8), 1.0)
		return
	ci.draw_colored_polygon(pts, Color(Palette.MATERIAL_PLATE, alpha))
	ci.draw_polyline(pts, Color(Palette.MACHINE_FRAME, alpha), 1.5, true)
	# bevel
	ci.draw_rect(Rect2(pos + Vector2(_fx(16, 60, flip), 2), Vector2(60, 1)), Color(Palette.MATERIAL_PLATE_HI, alpha))
	# family key bar
	rrect(ci, Rect2(pos + Vector2(_fx(16, 22, flip), 6), Vector2(22, 3)), 1.0, Color(acc, alpha))
	# screen window
	var win := Rect2(pos + Vector2(_fx(16, 48, flip), 12), Vector2(48, 18))
	rrect(ci, win, 3.0, Color(Palette.MACHINE_SCREEN, alpha))
	rrect_outline(ci, win, 3.0, Color(Palette.MATERIAL_FRAME, alpha), 1.0)
	if glyph != "":
		text_center(ci, win, glyph, 11.0 if glyph.length() > 2 else 13.0, Color(acc, alpha))
	# 10x3 data store
	for r in 3:
		for c in 10:
			var idx := r * 10 + c
			var tok := Palette.MATERIAL_PLATE_HI
			var op := 1.0
			if fill != null:
				if idx < int(round(float(fill) * 30.0)):
					tok = Palette.STATE_SUCCESS if float(fill) >= 1.0 else acc
			else:
				tok = acc
				op = 1.0 if cursor == idx else 0.28
			rrect(ci, Rect2(pos + Vector2(_fx(16 + c * 7, 5, flip), 34 + r * 6), Vector2(5, 4)), 0.5, Color(tok, op * alpha))
	# plug collar
	var collar := Rect2(pos + Vector2(_fx(88, 8, flip), 10), Vector2(8, 36))
	rrect(ci, collar, 1.0, Color(Palette.MATERIAL_PLATE_HI, alpha))
	rrect_outline(ci, collar, 1.0, Color(Palette.MACHINE_FRAME, alpha), 1.0)
	if end == "fins":
		for fy in [10.0, 38.0]:
			var fr := Rect2(pos + Vector2(_fx(0, 6, flip), fy), Vector2(6, 8))
			rrect(ci, fr, 1.0, Color(Palette.MATERIAL_PLATE_HI, alpha))
			rrect_outline(ci, fr, 1.0, Color(Palette.MACHINE_FRAME, alpha), 1.0)
	elif end == "square":
		for i in 3:
			ci.draw_rect(Rect2(pos + Vector2(_fx(5 + i * 3, 1, flip), 16), Vector2(1, 24)), Color(Palette.MACHINE_FRAME, alpha))


## Male USB-A plug (22x28): metal shell, two square holes, dark collar line at the body side.
static func male_plug(ci: CanvasItem, pos: Vector2, flip: bool, alpha := 1.0) -> void:
	var shell := Rect2(pos, Vector2(22, 28))
	rrect(ci, shell, 1.5, Color(Palette.MACHINE_FRAME_HOVER, alpha))
	rrect_outline(ci, shell, 1.5, Color(Palette.MATERIAL_SILK, 0.35 * alpha), 1.0)
	var hx := pos.x + (13.0 if flip else 4.0)
	rrect(ci, Rect2(Vector2(hx, pos.y + 6), Vector2(5, 5)), 0.5, Color(Palette.MATERIAL_VENT, alpha))
	rrect(ci, Rect2(Vector2(hx, pos.y + 17), Vector2(5, 5)), 0.5, Color(Palette.MATERIAL_VENT, alpha))
	var cx := pos.x + (0.0 if flip else 20.0)
	ci.draw_rect(Rect2(Vector2(cx, pos.y), Vector2(2, 28)), Color(Palette.MATERIAL_VENT, 0.6 * alpha))


## Mirror helper: body-local x for a shape at `px` of width `w` (flip mirrors around 96).
static func _fx(px: float, w: float, flip: bool) -> float:
	return 96.0 - px - w if flip else px


## Outer silhouette vertices (body-local, x 0..96) per family end.
static func _mod_path(end: String, flip: bool) -> PackedVector2Array:
	var raw: Array
	match end:
		"chamfer":
			raw = [[12, 0], [96, 0], [96, 56], [12, 56], [0, 44], [0, 12]]
		"round":
			raw = [[24, 0], [96, 0], [96, 56], [24, 56], [0, 44], [0, 32], [0, 20]]
		"notch":
			raw = [[5, 0], [96, 0], [96, 56], [5, 56], [0, 51], [0, 36], [7, 36], [7, 20], [0, 20], [0, 5]]
		"fins":
			raw = [[10, 0], [96, 0], [96, 56], [10, 56], [5, 51], [5, 5]]
		"slant":
			raw = [[16, 0], [96, 0], [96, 56], [0, 56], [0, 16]]
		"bezel":
			raw = [[6, 0], [96, 0], [96, 56], [6, 56], [0, 50], [0, 6]]
		_:
			raw = [[5, 0], [96, 0], [96, 56], [5, 56], [0, 51], [0, 5]]
	var out := PackedVector2Array()
	for p in raw:
		out.append(Vector2(96.0 - float(p[0]) if flip else float(p[0]), float(p[1])))
	return out


# ================================================================ mini module (0.5x)

## miniModule(kind, alpha): 0.5-scale thumbnail (48x28) used by the Device Tray rows.
## `pos` = top-left of the thumbnail.
static func mini_module(ci: CanvasItem, pos: Vector2, kind: String, alpha := 1.0) -> void:
	ci.draw_set_transform(pos, 0.0, Vector2(0.5, 0.5))
	data_module(ci, Vector2.ZERO, kind, {"ghost": false, "alpha": alpha, "acc": _kind_accent(kind)})
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _kind_accent(kind: String) -> Color:
	return Palette.DATA_NUMBER if kind == "bit" else Palette.FAMILY_IO


# ================================================================ monitor (output device)

## Monitor (Penpot 15 / 02c): bezel silhouette, state.select key bar, a wide screen with the last
## value and a 10-sample history strip. Output-side device, plug on the west (flip) like the job
## drive. `hist` = up to 10 heights in 0..1 (oldest first). `pos` = top-left of the body.
static func monitor(ci: CanvasItem, pos: Vector2, value: String, hist: Array, accent: Color, opts: Dictionary = {}) -> void:
	var alpha: float = opts.get("alpha", 1.0)
	var inserted: bool = opts.get("inserted", false)
	if not inserted:
		male_plug(ci, pos + Vector2(-22, 14), true, alpha)
	var pts := PackedVector2Array()
	for p in _mod_path("bezel", true):
		pts.append(pos + p)
	ci.draw_colored_polygon(pts, Color(Palette.MATERIAL_PLATE, alpha))
	ci.draw_polyline(pts, Color(Palette.MACHINE_FRAME, alpha), 1.5, true)
	ci.draw_rect(Rect2(pos + Vector2(20, 2), Vector2(60, 1)), Color(Palette.MATERIAL_PLATE_HI, alpha))
	rrect(ci, Rect2(pos + Vector2(54, 6), Vector2(22, 3)), 1.0, Color(Palette.STATE_SELECT, 0.8 * alpha))
	var scr := Rect2(pos + Vector2(14, 12), Vector2(70, 26))
	rrect(ci, scr, 3.0, Color(Palette.MACHINE_SCREEN, alpha))
	rrect_outline(ci, scr, 3.0, Color(Palette.MATERIAL_FRAME, alpha), 1.0)
	if value != "":
		text_center(ci, scr, value, 13.0 if value.length() > 4 else 15.0, Color(accent, alpha))
	var n := hist.size()
	for i in n:
		var h := clampf(float(hist[i]), 0.08, 1.0) * 10.0
		rrect(ci, Rect2(pos + Vector2(18 + i * 6.4, 50 - h), Vector2(4, h)), 0.5, Color(accent, (0.25 + 0.075 * i) * alpha))
	var collar := Rect2(pos + Vector2(0, 10), Vector2(8, 36))
	rrect(ci, collar, 1.0, Color(Palette.MATERIAL_PLATE_HI, alpha))
	rrect_outline(ci, collar, 1.0, Color(Palette.MACHINE_FRAME, alpha), 1.0)

