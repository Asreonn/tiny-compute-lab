class_name ThermalNetView
extends Node2D
## P10d1: the thermal transport layer. ONE node draws every heat pipe / trunk / spreader run,
## the T-junction plates, the clips, the risers and the cooling-assembly shrouds. The layer is
## embedded: it sits ABOVE the wires and BELOW the machines (World moves it directly above the
## WireLayer, below the MachineLayer) — thermal hardware is raised over data and copper.
## Read-only over SimulationManager.sim / sim.thermal.
##
## Geometry is cached by on_layout() (tiles, segments, tees, clips, spreaders, shrouds + a
## layout key); refresh() recomputes a cheap heat key only when sim.tick changed and calls
## queue_redraw() only when either key changed — no per-frame allocation while idle. When
## sim.thermal is null every tile has no flow (no heat wash).

const T := Palette.TILE  # 64
## Band width by pipe/trunk type (px). thermal_spreader is drawn as a flat bar, not a band.
## A spreader's bar centre sits this far below its tile centre (bar at y 50–58 of the tile).
const SPREADER_DROP := 22.0
const W := {
	"heat_pipe": 10.0,
	"heat_pipe_heavy": 14.0,
	"thermal_trunk": 22.0,
}
const PIPE_TYPES := ["heat_pipe", "heat_pipe_heavy", "thermal_trunk"]

## Cached geometry (rebuilt by on_layout()).
var _tiles: Array = []  # transport tile Vector2i, in sorted_machine_ids order
var _tile_type: Dictionary = {}  # tile -> transport type
var _tile_w: Dictionary = {}  # tile -> band width
var _segments: Array = []  # {cell, dir, len} — pipe/trunk half segments
var _tees: Array = []  # pipe/trunk tiles with >= 3 joined sides
var _clips: Array = []  # {cell, v} — straight pipe/trunk tiles (two opposite joins, (x+y)%3==0)
var _spreaders: Array = []  # {x0, y0, left, right, riser}
var _shrouds: Array = []  # {rect, duct} — cooling-assembly shrouds
var _layout_key := ""
var _heat_key := ""
var _seen_tick := -2
var _last_layout_key := ""
var _last_heat_key := ""


## Rebuild the cached geometry list and the layout key (a layout change: tiles, segments, tees,
## clips, spreaders, shrouds). Redraws immediately; refresh() keeps the heat key in sync.
func on_layout() -> void:
	var sim := SimulationManager.sim
	_tiles.clear()
	_tile_type.clear()
	_tile_w.clear()
	_segments.clear()
	_tees.clear()
	_clips.clear()
	_spreaders.clear()
	_shrouds.clear()
	if sim == null:
		_layout_key = ""
		queue_redraw()
		return
	# network tiles: transport bands + manifold footprints (both are joins for the runs)
	var net_tiles := {}
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type in ThermalNetwork.TRANSPORT or m.type == ThermalNetwork.MANIFOLD:
			for c in m.footprint():
				net_tiles[c] = true
				if m.type in ThermalNetwork.TRANSPORT:
					_tiles.append(c)
					_tile_type[c] = m.type
					_tile_w[c] = float(W.get(m.type, 10.0))  # spreaders draw a bar, not a band
	# sink inlet tiles (the column directly west of every sink, every row)
	var sink_inlets := {}
	# heat-machine contacts: the transport tile directly north of a heat machine's top row
	var contacts := {}
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type in ThermalNetwork.SINKS:
			var s: Vector2i = Catalog.size_of(m.type, 0)
			for y in s.y:
				sink_inlets[Vector2i(m.cell.x - 1, m.cell.y + y)] = true
		if m.locked:
			continue
		if int(m.def().get("heat", 0)) <= 0:
			continue
		if str(m.def().get("family", "")) in ["thermal", "power"]:
			continue
		var fs: Vector2i = Catalog.size_of(m.type, m.rot)
		for x in fs.x:
			var t := Vector2i(m.cell.x + x, m.cell.y - 1)
			if _tile_type.has(t):
				contacts[t] = true
	# pipe/trunk segments + tees/clips
	for cell in _tiles:
		if _tile_type[cell] == "thermal_spreader":
			continue
		var dirs := []
		var joined := []
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			if net_tiles.has(cell + d):
				dirs.append(d)
				joined.append(d)
		if sink_inlets.has(cell):
			dirs.append(Vector2i.RIGHT)
		if contacts.has(cell):
			dirs.append(Vector2i.DOWN)
		# a side join into a spreader lands on its bar (hugging the tile's south edge): drop to
		# the bar's centre line, then run to the edge there
		for d in [Vector2i.RIGHT, Vector2i.LEFT]:
			if d in dirs and _tile_type.get(cell + d, "") == "thermal_spreader":
				dirs.erase(d)
				_segments.append({"cell": cell, "dir": Vector2i.DOWN, "len": SPREADER_DROP})
				_segments.append({"cell": cell, "dir": d, "len": 32.0, "o": Vector2(0, SPREADER_DROP)})
		if dirs.is_empty() and joined.is_empty():
			_segments.append({"cell": cell, "dir": Vector2i.RIGHT, "len": 24.0})
			_segments.append({"cell": cell, "dir": Vector2i.LEFT, "len": 24.0})
		else:
			for d in dirs:
				# a machine pickup runs 3 px past the tile edge onto the machine's contact
				var ln := 35.0 if d == Vector2i.DOWN and contacts.has(cell) else 32.0
				_segments.append({"cell": cell, "dir": d, "len": ln})
		# joined sides are the network joins (transport / manifold): tees at >= 3, clips on a
		# straight run (exactly two opposite joins, every third tile)
		if joined.size() >= 3:
			_tees.append(cell)
		elif joined.size() == 2 and joined[0] == -joined[1] and (cell.x + cell.y) % 3 == 0:
			_clips.append({"cell": cell, "v": joined[0].y != 0})
	# spreaders (flat copper bars) + risers up to a pipe/trunk neighbour above
	for cell in _tiles:
		if _tile_type[cell] != "thermal_spreader":
			continue
		var x0: float = cell.x * T
		var y0: float = cell.y * T
		var left: bool = _tile_type.get(cell + Vector2i.LEFT, "") == "thermal_spreader"
		var right: bool = _tile_type.get(cell + Vector2i.RIGHT, "") == "thermal_spreader"
		var up: String = _tile_type.get(cell + Vector2i.UP, "")
		_spreaders.append({
			"x0": x0, "y0": y0, "left": left, "right": right,
			"riser": up != "" and up != "thermal_spreader",
		})
	# cooling-assembly shrouds: every sink with blowers, before everything else
	if sim.thermal != null and sim.thermal.net != null:
		var tn: ThermalNetwork = sim.thermal.net
		for s in tn.sinks():
			var sid: int = int(s["id"])
			var blowers: Array = tn.blowers_of(sid)
			if blowers.is_empty():
				continue
			var sm: Machine = sim.machines[sid]
			var srect := Rect2(Vector2(sm.cell) * T, Vector2(Catalog.size_of(sm.type, 0)) * T)
			var rect := srect
			for bid in blowers:
				var bm: Machine = sim.machines[bid]
				rect = rect.merge(Rect2(Vector2(bm.cell) * T, Vector2(Catalog.size_of(bm.type, 0)) * T))
			rect = rect.grow_individual(6.0, 6.0, 6.0, 6.0)
			var duct := Rect2(srect.position.x + 4.0, srect.end.y - 4.0, srect.size.x - 8.0, 8.0)
			_shrouds.append({"rect": rect, "duct": duct})
	_layout_key = _layout_key_of()
	queue_redraw()


## Every frame: recompute the cheap heat key only when sim.tick changed, redraw only when either
## the layout key or the heat key changed.
func refresh() -> void:
	var sim := SimulationManager.sim
	var tick := sim.tick if sim != null else -1
	if tick != _seen_tick:
		_seen_tick = tick
		_heat_key = _heat_key_of(sim)
	if _heat_key != _last_heat_key or _layout_key != _last_layout_key:
		_last_heat_key = _heat_key
		_last_layout_key = _layout_key
		queue_redraw()


## The heat key: every transport tile's flow ratio (flow / tile_cap, 0 when unknown) quantised
## to 1/8. "" when there is no live thermal network (no heat wash anywhere).
func _heat_key_of(sim: Simulation) -> String:
	if sim == null or sim.thermal == null or sim.thermal.net == null:
		return ""
	var flow: Dictionary = sim.thermal.last_alloc.get("flow", {})
	var tn: ThermalNetwork = sim.thermal.net
	var parts := PackedStringArray()
	for cell in _tiles:
		var cap: int = tn.tile_cap(cell)
		var r := 0.0
		if cap > 0 and flow.has(cell):
			r = float(flow[cell]) / float(cap)
		parts.append("h%d,%d:%d" % [cell.x, cell.y, int(r * 8.0)])
	return "|".join(parts)


## A string that changes exactly when the cached geometry changes.
func _layout_key_of() -> String:
	var parts := PackedStringArray()
	for cell in _tiles:
		parts.append("t%d,%d:%s" % [cell.x, cell.y, _tile_type[cell]])
	for s in _segments:
		parts.append("s%d,%d:%d,%d:%d" % [s["cell"].x, s["cell"].y, s["dir"].x, s["dir"].y, int(s["len"])])
	for c in _tees:
		parts.append("j%d,%d" % [c.x, c.y])
	for c in _clips:
		parts.append("c%d,%d:%d" % [c["cell"].x, c["cell"].y, 1 if c["v"] else 0])
	for p in _spreaders:
		parts.append("p%d,%d:%d:%d:%d" % [int(p["x0"]), int(p["y0"]), 1 if p["left"] else 0, 1 if p["right"] else 0, 1 if p["riser"] else 0])
	for h in _shrouds:
		var rr: Rect2 = h["rect"]
		var dd: Rect2 = h["duct"]
		parts.append("h%d,%d,%d,%d|%d,%d,%d,%d" % [int(rr.position.x), int(rr.position.y), int(rr.size.x), int(rr.size.y), int(dd.position.x), int(dd.position.y), int(dd.size.x), int(dd.size.y)])
	return "|".join(parts)


# ---------------------------------------------------------------- drawing

## Passes so neighbours merge seamlessly: shrouds first, then all tiles' layer 1, layer 2, …
## (seat · edge · face · heat wash · detail), then tees, clips and the spreaders (each with its
## riser first).
func _draw() -> void:
	var sim := SimulationManager.sim
	var flow := {}
	var tn: ThermalNetwork = null
	if sim != null and sim.thermal != null and sim.thermal.net != null:
		tn = sim.thermal.net
		flow = sim.thermal.last_alloc.get("flow", {})
	# 0: cooling-assembly shrouds, before everything else
	for h in _shrouds:
		_draw_shroud(h)
	# 1: seat
	for s in _segments:
		_draw_segment(s, Palette.BOARD_PAD_EDGE, _tile_w[s["cell"]] + 3.0)
	# 2: edge
	for s in _segments:
		_draw_segment(s, Color(Palette.MATERIAL_COPPER, 0.9), _tile_w[s["cell"]])
	# 3: face
	for s in _segments:
		_draw_segment(s, Palette.MATERIAL_COPPER_DIM, _tile_w[s["cell"]] - 2.4)
	# 4: heat wash
	for s in _segments:
		var r := _ratio(s["cell"], flow, tn)
		if r > 0.02:
			_draw_segment(s, Color(Palette.STATE_BLOCKED, minf(0.6, r * 0.6)), _tile_w[s["cell"]] - 3.0)
	# 5: pipes / trunks
	for s in _segments:
		_draw_detail(s)
	# tees
	for c in _tees:
		_draw_tee(c)
	# clips
	for c in _clips:
		_draw_clip(c)
	# spreaders (each draws its riser first, then the mount + bar)
	for p in _spreaders:
		_draw_spreader(p)


## The quantised flow ratio of a tile: flow / tile_cap, 0 when unknown.
func _ratio(cell: Vector2i, flow: Dictionary, tn: ThermalNetwork) -> float:
	if tn == null:
		return 0.0
	var cap: int = tn.tile_cap(cell)
	if cap <= 0 or not flow.has(cell):
		return 0.0
	return int(float(flow[cell]) / float(cap) * 8.0) / 8.0


func _centre(cell: Vector2i) -> Vector2:
	return Vector2(cell) * T + Vector2(32, 32)


## A half segment from the tile centre (plus its optional offset "o"), started half a band width
## behind the centre so corners and tees close without a notch.
func _draw_segment(s: Dictionary, color: Color, width: float) -> void:
	var c: Vector2 = _centre(s["cell"]) + s.get("o", Vector2.ZERO)
	var d := Vector2(s["dir"])
	var length := float(s["len"])
	draw_line(c - d * width * 0.5, c + d * length, color, width)


## Layer 5: pipes get a gold sheen on the upper/left side of the band; trunks get two dotted
## pillar rows at ±w/4 and a gold centre line.
func _draw_detail(s: Dictionary) -> void:
	var c: Vector2 = _centre(s["cell"]) + s.get("o", Vector2.ZERO)
	var d := Vector2(s["dir"])
	var length := float(s["len"])
	var w: float = _tile_w[s["cell"]]
	if _tile_type[s["cell"]] == "thermal_trunk":
		var p := Vector2(-d.y, d.x)
		var off := w / 4.0
		var t := 0.0
		while t <= length:
			draw_circle(c + d * t + p * off, 0.8, Color(Palette.MATERIAL_COPPER, 0.35))
			draw_circle(c + d * t - p * off, 0.8, Color(Palette.MATERIAL_COPPER, 0.35))
			t += 6.6
		draw_line(c, c + d * length, Color(Palette.MATERIAL_GOLD, 0.25), 1.0)
		return
	var off_dir := Vector2(0, -1) if s["dir"].x != 0 else Vector2(-1, 0)
	var off: float = w / 2.0 - 2.5
	draw_line(c + off_dir * off, c + d * length + off_dir * off, Color(Palette.MATERIAL_GOLD, 0.3), 1.2)


## T-junction: a 26×26 plate with a copper disc and four screws, on a tile with >= 3 joins.
func _draw_tee(c: Vector2i) -> void:
	var p := _centre(c)
	var r := Rect2(p - Vector2(13, 13), Vector2(26, 26))
	SystemsDraw.rrect(self, r, 4.0, Palette.MACHINE_BODY)
	SystemsDraw.rrect_outline(self, r, 4.0, Palette.MACHINE_FRAME, 1.0)
	draw_circle(p, 7.0, Palette.MATERIAL_COPPER_DIM)
	draw_arc(p, 7.0, 0.0, TAU, 24, Palette.MATERIAL_COPPER, 1.2)
	for sx in [-9.0, 9.0]:
		for sy in [-9.0, 9.0]:
			draw_circle(p + Vector2(sx, sy), 1.75, Palette.MATERIAL_FRAME)


## Clip: a clamp across the band of a straight run (two opposite joins), rotated for vertical
## runs, with a screw at each end.
func _draw_clip(c: Dictionary) -> void:
	var p := _centre(c["cell"])
	var w: float = _tile_w[c["cell"]]
	var size := Vector2(8, w + 8) if not c["v"] else Vector2(w + 8, 8)
	var r := Rect2(p - size / 2.0, size)
	SystemsDraw.rrect(self, r, 2.0, Palette.MACHINE_BODY)
	SystemsDraw.rrect_outline(self, r, 2.0, Palette.MACHINE_FRAME, 1.0)
	var end := (w + 8) / 2.0 - 1.5
	if c["v"]:
		draw_circle(p + Vector2(-end, 0), 1.5, Palette.MATERIAL_FRAME)
		draw_circle(p + Vector2(end, 0), 1.5, Palette.MATERIAL_FRAME)
	else:
		draw_circle(p + Vector2(0, -end), 1.5, Palette.MATERIAL_FRAME)
		draw_circle(p + Vector2(0, end), 1.5, Palette.MATERIAL_FRAME)


## Spreader: a flat copper bar hugging the south edge of the tile, sitting on the machine
## pickups below. A riser pipe band (w 10, layers 1-3) connects it to a pipe/trunk above first.
## The mount and bar extend 4 px into adjacent spreaders so a run reads as one rail.
func _draw_spreader(p: Dictionary) -> void:
	var x0 := float(p["x0"])
	var y0 := float(p["y0"])
	if bool(p["riser"]):
		var rx := x0 + 32.0
		draw_line(Vector2(rx, y0), Vector2(rx, y0 + 50.0), Palette.BOARD_PAD_EDGE, 13.0)
		draw_line(Vector2(rx, y0), Vector2(rx, y0 + 50.0), Color(Palette.MATERIAL_COPPER, 0.9), 10.0)
		draw_line(Vector2(rx, y0), Vector2(rx, y0 + 50.0), Palette.MATERIAL_COPPER_DIM, 7.6)
	var mx0 := x0 - 4.0 if p["left"] else x0
	var mw := 64.0 + (4.0 if p["left"] else 0.0) + (4.0 if p["right"] else 0.0)
	var mount := Rect2(mx0, y0 + 45.0, mw, 18.0)
	SystemsDraw.rrect(self, mount, 4.0, Palette.MACHINE_BODY)
	SystemsDraw.rrect_outline(self, mount, 4.0, Palette.MACHINE_FRAME, 1.0)
	var bx0 := x0 + 2.0 - 4.0 if p["left"] else x0 + 2.0
	var bw := 60.0 + (4.0 if p["left"] else 0.0) + (4.0 if p["right"] else 0.0)
	var bar := Rect2(bx0, y0 + 50.0, bw, 8.0)
	SystemsDraw.rrect(self, bar, 2.5, Color(Palette.MATERIAL_COPPER, 0.85))
	SystemsDraw.rrect_outline(self, bar, 2.5, Palette.MATERIAL_COPPER_DIM, 1.0)
	draw_line(Vector2(bx0, y0 + 50.5), Vector2(bx0 + bw, y0 + 50.5), Color(Palette.MATERIAL_GOLD, 0.3), 1.2)
	for sx in [x0 + 16.0, x0 + 48.0]:
		draw_circle(Vector2(sx, y0 + 54.0), 1.5, Palette.MATERIAL_FRAME)


## Cooling assembly: a shroud around the sink + its blowers (grown 6 px) with corner screws,
## and a vent duct across the sink's bottom edge.
func _draw_shroud(h: Dictionary) -> void:
	var rr: Rect2 = h["rect"]
	SystemsDraw.rrect(self, rr, 8.0, Color(Palette.MACHINE_BODY, 0.55))
	SystemsDraw.rrect_outline(self, rr, 8.0, Palette.MACHINE_FRAME, 1.5)
	for s in [Vector2(7, 7), Vector2(rr.size.x - 7, 7), Vector2(7, rr.size.y - 7), Vector2(rr.size.x - 7, rr.size.y - 7)]:
		draw_circle(rr.position + s, 2.5, Palette.MATERIAL_FRAME)
	var dd: Rect2 = h["duct"]
	draw_rect(dd, Palette.MATERIAL_VENT)


# ---------------------------------------------------------------- ghost

## Placement ghost: one isolated tile of that type. Pipes/trunks: a horizontal band ± 24 px
## through (32, 32), layers 1-3 and 5. Spreader: its mount + bar. `ci` is the CanvasItem to draw
## on (a small painter child of a ghost MachineView).
static func draw_ghost(ci: CanvasItem, type: String) -> void:
	if type == "thermal_spreader":
		var mount := Rect2(0, 45, 64, 18)
		SystemsDraw.rrect(ci, mount, 4.0, Palette.MACHINE_BODY)
		SystemsDraw.rrect_outline(ci, mount, 4.0, Palette.MACHINE_FRAME, 1.0)
		var bar := Rect2(2, 50, 60, 8)
		SystemsDraw.rrect(ci, bar, 2.5, Color(Palette.MATERIAL_COPPER, 0.85))
		SystemsDraw.rrect_outline(ci, bar, 2.5, Palette.MATERIAL_COPPER_DIM, 1.0)
		ci.draw_line(Vector2(2, 50.5), Vector2(62, 50.5), Color(Palette.MATERIAL_GOLD, 0.3), 1.2)
		for sx in [16.0, 48.0]:
			ci.draw_circle(Vector2(sx, 54.0), 1.5, Palette.MATERIAL_FRAME)
		return
	var w: float = W[type]
	var c := Vector2(32, 32)
	var segs := [Vector2.RIGHT, Vector2.LEFT]
	for d in segs:
		ci.draw_line(c, c + d * 24.0, Palette.BOARD_PAD_EDGE, w + 3.0)
	for d in segs:
		ci.draw_line(c, c + d * 24.0, Color(Palette.MATERIAL_COPPER, 0.9), w)
	for d in segs:
		ci.draw_line(c, c + d * 24.0, Palette.MATERIAL_COPPER_DIM, w - 2.4)
	if type == "thermal_trunk":
		for d in segs:
			var p := Vector2(-d.y, d.x)
			var off := w / 4.0
			var t := 0.0
			while t <= 24.0:
				ci.draw_circle(c + d * t + p * off, 0.8, Color(Palette.MATERIAL_COPPER, 0.35))
				ci.draw_circle(c + d * t - p * off, 0.8, Color(Palette.MATERIAL_COPPER, 0.35))
				t += 6.6
			ci.draw_line(c, c + d * 24.0, Color(Palette.MATERIAL_GOLD, 0.25), 1.0)
	else:
		for d in segs:
			var off := w / 2.0 - 2.5
			ci.draw_line(c + Vector2(0, -1) * off, c + d * 24.0 + Vector2(0, -1) * off, Color(Palette.MATERIAL_GOLD, 0.3), 1.2)