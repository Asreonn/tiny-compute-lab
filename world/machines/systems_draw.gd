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



# ================================================================ PSU gauge (page 15 / 04)

## Power gauge: one cell per power unit in `rows` rows; gold, amber at >= 75 %, red plus an
## overflow chevron above 100 %. `pos` = top-left, `w` = width (height = rows * 9 + 6).
static func gauge(ci: CanvasItem, pos: Vector2, w: float, cap: int, used: int, rows: int) -> void:
	if cap <= 0:
		return
	var per := ceili(float(cap) / float(rows))
	var cw := (w - 6.0 - (per - 1) * 2.0) / float(per)
	var over := used > cap
	var near := not over and float(used) / float(cap) >= 0.75
	var lit := Palette.STATE_ERROR if over else (Palette.STATE_BLOCKED if near else Palette.MATERIAL_GOLD)
	var box := Rect2(pos, Vector2(w, rows * 9 + 6))
	rrect(ci, box, 3.0, Palette.MACHINE_SCREEN)
	rrect_outline(ci, box, 3.0, Palette.MATERIAL_FRAME, 1.0)
	for i in cap:
		var r := i / per
		var c := i % per
		rrect(ci, Rect2(pos + Vector2(3 + c * (cw + 2.0), 3 + r * 9), Vector2(cw, 7)), 1.0, lit if i < used else Palette.MATERIAL_PLATE_LO)
	if over:
		var o := pos + Vector2(w + 4.0, box.size.y * 0.5 - 5.0)
		for dx in [0.0, 6.0]:
			ci.draw_polyline(PackedVector2Array([o + Vector2(1 + dx, 1), o + Vector2(5 + dx, 5), o + Vector2(1 + dx, 9)]), Palette.STATE_ERROR, 2.0, true)


# ================================================================ thermal family (page 16 / 07)
# Board-level copper hardware: no chassis, no data ports, no LED. Copper = heat; warmth is only a
# faint amber gradient (the thermal overlay carries the full picture).

## Fin-tip warmth α by level: 0 cool (< WARM), 1 warm, 2 hot (>= HOT).
const WARMTH := [0.0, 0.3, 0.75]


## `color` at α `from` along the top edge of `rect`, fading to 0 at `stop` of its height.
static func gradient_down(ci: CanvasItem, rect: Rect2, color: Color, from: float, stop: float) -> void:
	var mid := rect.position.y + rect.size.y * stop
	var c0 := Color(color, from)
	var c1 := Color(color, 0.0)
	ci.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, mid), Vector2(rect.position.x, mid)]), PackedColorArray([c0, c0, c1, c1]))


## PCB footprint: board.pad fill, copper-dim outline, silk corner marks.
static func thermal_footprint(ci: CanvasItem, pos: Vector2, w: float, h: float) -> void:
	var r := Rect2(pos + Vector2(2, 2), Vector2(w - 4, h - 4))
	rrect(ci, r, 4.0, Palette.BOARD_PAD)
	rrect_outline(ci, r, 4.0, Palette.MATERIAL_COPPER_DIM, 1.0)
	var silk := Palette.BOARD_SILK
	for c in [[Vector2(2, 8), Vector2(2, 2), Vector2(8, 2)], [Vector2(w - 8, 2), Vector2(w - 2, 2), Vector2(w - 2, 8)],
			[Vector2(w - 2, h - 8), Vector2(w - 2, h - 2), Vector2(w - 8, h - 2)], [Vector2(8, h - 2), Vector2(2, h - 2), Vector2(2, h - 8)]]:
		ci.draw_polyline(PackedVector2Array([pos + c[0], pos + c[1], pos + c[2]]), silk, 1.5)


## Heatsink (S 64x64, passive, r1): copper spreader, 11 dense fins, 4 screws.
static func heatsink(ci: CanvasItem, pos: Vector2, warmth: int) -> void:
	thermal_footprint(ci, pos, 64, 64)
	var sp := Rect2(pos + Vector2(7, 7), Vector2(50, 50))
	rrect(ci, sp, 3.0, Palette.MATERIAL_COPPER_DIM)
	rrect_outline(ci, sp, 3.0, Color(Palette.MATERIAL_COPPER, 0.7), 1.0)
	for i in 11:
		rrect(ci, Rect2(pos + Vector2(12 + i * 4, 11), Vector2(2, 42)), 0.6, Palette.MATERIAL_PLATE_HI)
		ci.draw_rect(Rect2(pos + Vector2(12 + i * 4, 11), Vector2(2, 1.2)), Color(Palette.MATERIAL_COPPER, 0.8))
	if warmth > 0:
		gradient_down(ci, Rect2(pos + Vector2(11, 11), Vector2(44, 42)), Palette.STATE_BLOCKED, WARMTH[warmth], 0.45)
	for s in [Vector2(11, 11), Vector2(53, 11), Vector2(11, 53), Vector2(53, 53)]:
		ci.draw_circle(pos + s, 2.0, Palette.MATERIAL_FRAME)
		ci.draw_arc(pos + s, 2.0, 0.0, TAU, 12, Palette.MATERIAL_VENT, 0.5, true)


## Blower (S 64x64, active, r2): volute housing, 18-blade impeller rotated by `spin` (radians),
## hairline airflow at the outlet, 3-pin gold power header. `level`: 0 idle, 1 running, 2 high load.
static func blower(ci: CanvasItem, pos: Vector2, spin: float, level: int) -> void:
	thermal_footprint(ci, pos, 64, 64)
	var ctr := pos + Vector2(30, 31)
	var vol := PackedVector2Array()
	for i in 37:
		var a := -PI / 2.0 - (1.5 * PI) * float(i) / 36.0
		vol.append(ctr + Vector2(cos(a), sin(a)) * 23.0)
	for p in [Vector2(53, 18), Vector2(58, 18), Vector2(58, 8), Vector2(30, 8)]:
		vol.append(pos + p)
	ci.draw_colored_polygon(vol, Palette.MACHINE_SCREEN)
	ci.draw_polyline(vol, Palette.MATERIAL_FRAME, 1.5, true)
	ci.draw_rect(Rect2(pos + Vector2(53, 8), Vector2(5, 10)), Palette.MATERIAL_COPPER_DIM)
	var run := level > 0
	var blade := Color(Palette.MATERIAL_SILK, 0.4 if run else 0.6)
	for i in 18:
		var a := spin + float(i) / 18.0 * TAU
		ci.draw_line(ctr + Vector2(cos(a), sin(a)) * 7.0, ctr + Vector2(cos(a + 0.35), sin(a + 0.35)) * 16.0, blade, 1.2, true)
	ci.draw_circle(ctr, 6.0, Palette.MATERIAL_PLATE_HI)
	ci.draw_arc(ctr, 6.0, 0.0, TAU, 20, Color(Palette.MATERIAL_COPPER, 0.8), 1.0, true)
	if run:
		for i in (3 if level >= 2 else 2):
			ci.draw_line(pos + Vector2(60, 10 + i * 3), pos + Vector2(70 + i * 2, 10 + i * 3), Color(Palette.MATERIAL_SILK, 0.35), 1.0)
	for i in 3:
		ci.draw_rect(Rect2(pos + Vector2(8 + i * 4, 55), Vector2(2, 3)), Color(Palette.MATERIAL_GOLD, 0.95 if run else 0.6))


## Radiator (L 128x128, edge panel, r2): 26 fins between copper manifolds, inlets, brackets.
static func radiator(ci: CanvasItem, pos: Vector2, warmth: int) -> void:
	thermal_footprint(ci, pos, 128, 128)
	var core := Rect2(pos + Vector2(10, 22), Vector2(108, 84))
	rrect(ci, core, 2.0, Palette.MACHINE_SCREEN)
	rrect_outline(ci, core, 2.0, Palette.MATERIAL_FRAME, 1.0)
	for i in 26:
		ci.draw_rect(Rect2(pos + Vector2(13 + i * 4, 24), Vector2(1.6, 80)), Palette.MATERIAL_PLATE_HI)
	if warmth > 0:
		gradient_down(ci, Rect2(pos + Vector2(12, 24), Vector2(104, 80)), Palette.STATE_BLOCKED, WARMTH[warmth] * 0.8, 0.35)
	for my in [12, 106]:
		var mf := Rect2(pos + Vector2(8, my), Vector2(112, 10))
		rrect(ci, mf, 3.0, Palette.MATERIAL_COPPER_DIM)
		rrect_outline(ci, mf, 3.0, Color(Palette.MATERIAL_COPPER, 0.8), 1.0)
	for ix in [20, 44]:
		var c := pos + Vector2(ix + 6, 16)
		ci.draw_circle(c, 6.0, Palette.MATERIAL_COPPER)
		ci.draw_arc(c, 6.0, 0.0, TAU, 20, Palette.MATERIAL_VENT, 1.0, true)
		ci.draw_circle(c, 2.5, Palette.MATERIAL_VENT)
	for b in [Vector2(2, 2), Vector2(118, 2), Vector2(2, 118), Vector2(118, 118)]:
		rrect(ci, Rect2(pos + b, Vector2(8, 8)), 2.0, Palette.MATERIAL_FRAME)


## One heat-pipe tile (64x64 at `pos`), drawn as part of a routed copper conduit: a half segment
## from the tile centre towards every connected neighbour (`links`, unit directions) and a square
## thermal pad on each axis end without a pipe (`pads`). Copper only — never a data colour, no
## ports, no packets. `warmth` 0..1 tints the copper core amber.
static func heat_pipe(ci: CanvasItem, pos: Vector2, links: Array, pads: Array, warmth: float) -> void:
	var c := pos + Vector2(32, 32)
	var ends := []
	for d in links:
		ends.append([c + Vector2(d) * 32.0, Vector2(d)])
	for d in pads:
		ends.append([c + Vector2(d) * 22.0, Vector2(d)])
	for layer in [[Palette.MATERIAL_VENT, 12.0], [Palette.MATERIAL_COPPER_DIM, 9.0], [Color(Palette.MATERIAL_COPPER, 0.85), 2.5]]:
		for e in ends:
			ci.draw_line(c, e[0], layer[0], layer[1])
		ci.draw_rect(Rect2(c - Vector2.ONE * layer[1] * 0.5, Vector2.ONE * layer[1]), layer[0])
	if warmth > 0.01:
		for e in ends:
			ci.draw_line(c, e[0], Color(Palette.STATE_BLOCKED, clampf(warmth, 0.0, 1.0) * 0.75), 3.0)
	for e in ends:
		var dv: Vector2 = e[1]
		var off := Vector2(0, -2.5) if absf(dv.x) > 0.0 else Vector2(-2.5, 0)
		ci.draw_line(c + off, e[0] + off, Color(Palette.MATERIAL_GOLD, 0.35), 0.8)
	for d in pads:
		var p := c + Vector2(d) * 22.0
		var r := Rect2(p - Vector2(8, 8), Vector2(16, 16))
		rrect(ci, r, 3.0, Palette.MATERIAL_COPPER_DIM)
		rrect_outline(ci, r, 3.0, Palette.MATERIAL_COPPER, 1.2)
		ci.draw_circle(p, 3.0, Color(Palette.MATERIAL_COPPER, 0.9))
