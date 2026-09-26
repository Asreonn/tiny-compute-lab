class_name CopperView
extends Node2D
## P10c: the power copper layer. ONE node draws every copper run on the board — the layer is
## embedded: it sits UNDER the wires (World moves it directly below the WireLayer, above the
## BoardView). Read-only over SimulationManager.sim / sim.power_net.
##
## Geometry is cached by on_layout() (tiles, segments, terminals, taps + a layout key);
## refresh() recomputes a cheap state key only when sim.tick changed and calls queue_redraw()
## only when either key changed — no per-frame allocation while idle. When sim.power_net is
## null every tile is "normal" with no taps and no terminal pads.

const T := Palette.TILE  # 64
## Copper width by type (px).
const W := {
	"power_rail": 10.0,
	"power_rail_heavy": 16.0,
	"power_plane": 22.0,
	"power_plane_heavy": 32.0,
}
## Taps are 5 px wide on the heavy copper classes, 3 px elsewhere.
const HEAVY_TAP := ["power_rail_heavy", "power_plane_heavy"]
## Vias are drawn on planes only.
const PLANES := ["power_plane", "power_plane_heavy"]

## Cached geometry (rebuilt by on_layout()).
var _tiles: Array = []  # copper tile Vector2i, in sorted_machine_ids order
var _tile_type: Dictionary = {}  # tile -> copper type
var _tile_w: Dictionary = {}  # tile -> copper width
var _segments: Array = []  # {cell, dir, len} — one half-segment / stub per direction
var _terminals: Array = []  # {cell, dir} — power-part terminal pads
var _taps: Array = []  # {x, y0, y1, tw} — vertical traces from machines onto the rail
var _layout_key := ""
var _state_key := ""
var _seen_tick := -2
var _last_layout_key := ""
var _last_state_key := ""


## Rebuild the cached geometry list and the layout key (a layout change: rails, terminals,
## taps). Redraws immediately; refresh() keeps the state key in sync afterwards.
func on_layout() -> void:
	var sim := SimulationManager.sim
	_tiles.clear()
	_tile_type.clear()
	_tile_w.clear()
	_segments.clear()
	_terminals.clear()
	_taps.clear()
	if sim == null:
		_layout_key = ""
		queue_redraw()
		return
	var pn: PowerNetwork = sim.power_net
	var copper := {}
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type in PowerNetwork.COPPER:
			_tiles.append(m.cell)
			_tile_type[m.cell] = m.type
			_tile_w[m.cell] = W[m.type]
			copper[m.cell] = true
	# half segments toward every orthogonally adjacent copper tile (one joined run)
	var has_seg := {}
	for cell in _tiles:
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			if copper.has(cell + d):
				_segments.append({"cell": cell, "dir": d, "len": 32.0})
				has_seg[cell] = true
	# terminal stubs + pads (power parts feed copper on their terminals)
	if pn != null:
		for e in pn.terminal_tiles():
			var t: Vector2i = e["tile"]
			if _tile_type.has(t):
				_terminals.append({"cell": t, "dir": e["dir"]})
				_segments.append({"cell": t, "dir": e["dir"], "len": 32.0})
				has_seg[t] = true
	# a tile with neither a neighbour nor a terminal gets one horizontal ±24 segment
	for cell in _tiles:
		if not has_seg.has(cell):
			_segments.append({"cell": cell, "dir": Vector2i.RIGHT, "len": 24.0})
			_segments.append({"cell": cell, "dir": Vector2i.LEFT, "len": 24.0})
	# taps: non-locked machines fed from live copper directly south of them
	if pn != null:
		for id in sim.sorted_machine_ids():
			var m: Machine = sim.machines[id]
			if m.locked:
				continue
			var contacts: Array = pn.tapped_contacts(id)
			if contacts.is_empty():
				continue
			for t in contacts:
				var t2: Vector2i = t
				if not _tile_type.has(t2):
					continue
				var tw := 5.0 if _tile_type[t2] in HEAVY_TAP else 3.0
				_taps.append({
					"x": t2.x * T + 32.0,
					"y0": t2.y * T,
					"y1": t2.y * T + 32.0 - _tile_w[t2] / 2.0,
					"tw": tw,
				})
	_layout_key = _layout_key_of()
	queue_redraw()


## Every frame: recompute the cheap state key only when sim.tick changed, redraw only when
## either the layout key or the state key changed.
func refresh() -> void:
	var sim := SimulationManager.sim
	var tick := sim.tick if sim != null else -1
	if tick != _seen_tick:
		_seen_tick = tick
		_state_key = _state_key_of(sim)
	if _state_key != _last_state_key or _layout_key != _last_layout_key:
		_last_state_key = _state_key
		_last_layout_key = _layout_key
		queue_redraw()


## The state key: every copper tile's tile_state plus the tapped contact tiles. "" when there
## is no live power network (everything is "normal", no taps).
func _state_key_of(sim: Simulation) -> String:
	if sim == null or sim.power_net == null:
		return ""
	var pn: PowerNetwork = sim.power_net
	var parts := PackedStringArray()
	for cell in _tiles:
		parts.append(pn.tile_state(cell))
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.locked:
			continue
		var contacts: Array = pn.tapped_contacts(id)
		if contacts.is_empty():
			continue
		for t in contacts:
			parts.append("%d,%d" % [t.x, t.y])
	return "|".join(parts)


## A string that changes exactly when the cached geometry changes.
func _layout_key_of() -> String:
	var parts := PackedStringArray()
	for cell in _tiles:
		parts.append("t%d,%d:%s" % [cell.x, cell.y, _tile_type[cell]])
	for s in _segments:
		parts.append("s%d,%d:%d,%d:%d" % [s["cell"].x, s["cell"].y, s["dir"].x, s["dir"].y, int(s["len"])])
	for e in _terminals:
		parts.append("e%d,%d:%d,%d" % [e["cell"].x, e["cell"].y, e["dir"].x, e["dir"].y])
	for p in _taps:
		parts.append("p%d,%d,%d,%d" % [int(p["x"]), int(p["y0"]), int(p["y1"]), int(p["tw"])])
	return "|".join(parts)


# ---------------------------------------------------------------- drawing

## Per-tile layers in passes (all tiles' layer 1, then all layer 2, …) so neighbours merge
## seamlessly: seat · pour · wash · lines · vias, then terminal pads (after layer 5), then the
## overload markers, then the taps.
func _draw() -> void:
	var sim := SimulationManager.sim
	var pn: PowerNetwork = sim.power_net if sim != null else null
	# layer 1: seat
	for s in _segments:
		_draw_segment(s, Palette.BOARD_PAD_EDGE, _tile_w[s["cell"]] + 2.0)
	# layer 2: pour
	for s in _segments:
		_draw_segment(s, Palette.BOARD_PAD, _tile_w[s["cell"]])
	# layer 3: wash
	for s in _segments:
		_draw_segment(s, Color(Palette.MATERIAL_GOLD, 0.10), _tile_w[s["cell"]])
	# layer 4: lines
	for s in _segments:
		_draw_lines(s)
	# layer 5: vias
	for s in _segments:
		_draw_vias(s)
	# terminal pads (drawn after layer 5)
	for e in _terminals:
		_draw_terminal(e)
	# layer 6: overload
	if pn != null:
		for s in _segments:
			if pn.tile_state(s["cell"]) == "over":
				_draw_overload(s)
	# taps
	for p in _taps:
		_draw_tap(p)


func _centre(cell: Vector2i) -> Vector2:
	return Vector2(cell) * T + Vector2(32, 32)


func _draw_segment(s: Dictionary, color: Color, width: float) -> void:
	var c := _centre(s["cell"])
	var d := Vector2(s["dir"])
	var length := float(s["len"])
	draw_line(c, c + d * length, color, width)


## Layer 4: power_rail gets one centre line; every other class gets two lines offset
## ±(W/2 − 2) perpendicular to the segment.
func _draw_lines(s: Dictionary) -> void:
	var c := _centre(s["cell"])
	var d := Vector2(s["dir"])
	var length := float(s["len"])
	var t: String = _tile_type[s["cell"]]
	if t == "power_rail":
		draw_line(c, c + d * length, Color(Palette.MATERIAL_GOLD, 0.62), 1.4)
		return
	var p := Vector2(-d.y, d.x)
	var off: float = _tile_w[s["cell"]] / 2.0 - 2.0
	draw_line(c + p * off, c + d * length + p * off, Color(Palette.MATERIAL_GOLD, 0.62), 1.3)
	draw_line(c - p * off, c + d * length - p * off, Color(Palette.MATERIAL_GOLD, 0.62), 1.3)


## Layer 5 (planes only): along each segment of length ≥ 20, vias at t = 10 and 26 px from the
## tile centre; power_plane_heavy puts two rows at ±5 px perpendicular, power_plane one row on
## the centre.
func _draw_vias(s: Dictionary) -> void:
	var t: String = _tile_type[s["cell"]]
	if not t in PLANES:
		return
	var c := _centre(s["cell"])
	var d := Vector2(s["dir"])
	var length := float(s["len"])
	if length < 20.0:
		return
	var p := Vector2(-d.y, d.x)
	for tdist: float in [10.0, 26.0]:
		if tdist > length:
			continue
		var pt: Vector2 = c + d * tdist
		if t == "power_plane_heavy":
			_draw_via(pt + p * 5.0)
			_draw_via(pt)
			_draw_via(pt - p * 5.0)
		else:
			_draw_via(pt)


## One via: a r 1.5 BG_VOID circle with a 0.8 px MATERIAL_GOLD α 0.45 ring.
func _draw_via(pt: Vector2) -> void:
	draw_circle(pt, 1.5, Palette.BG_VOID)
	draw_arc(pt, 1.5, 0.0, TAU, 12, Color(Palette.MATERIAL_GOLD, 0.45), 0.8)


## Terminal pad: a 26×18 rounded rect (18×26 when the direction is vertical), centred on the
## tile edge point, fill MATERIAL_GOLD α 0.22 with a 1 px MATERIAL_GOLD α 0.35 outline.
func _draw_terminal(e: Dictionary) -> void:
	var c := _centre(e["cell"])
	var d := Vector2(e["dir"])
	var edge := c + d * 32.0
	var vertical := d.y != 0
	var size := Vector2(26, 18) if not vertical else Vector2(18, 26)
	var r := Rect2(edge - size / 2.0, size)
	SystemsDraw.rrect(self, r, 3.0, Color(Palette.MATERIAL_GOLD, 0.22))
	SystemsDraw.rrect_outline(self, r, 3.0, Color(Palette.MATERIAL_GOLD, 0.35), 1.0)


## Layer 6: two 1 px STATE_BLOCKED α 0.8 lines at ±(W/2 + 2) along every segment of an
## overloaded tile.
func _draw_overload(s: Dictionary) -> void:
	var c := _centre(s["cell"])
	var d := Vector2(s["dir"])
	var length := float(s["len"])
	var p := Vector2(-d.y, d.x)
	var off: float = _tile_w[s["cell"]] / 2.0 + 2.0
	draw_line(c + p * off, c + d * length + p * off, Color(Palette.STATE_BLOCKED, 0.8), 1.0)
	draw_line(c - p * off, c + d * length - p * off, Color(Palette.STATE_BLOCKED, 0.8), 1.0)


## Tap: from the machine's bottom edge down to the rail's upper edge — a BOARD_PAD_EDGE seat
## (tw + 2), a MATERIAL_GOLD α 0.6 trace (tw), then a solder pad at the rail edge.
func _draw_tap(p: Dictionary) -> void:
	var a := Vector2(float(p["x"]), float(p["y0"]))
	var b := Vector2(float(p["x"]), float(p["y1"]))
	var tw := float(p["tw"])
	draw_line(a, b, Palette.BOARD_PAD_EDGE, tw + 2.0)
	draw_line(a, b, Color(Palette.MATERIAL_GOLD, 0.6), tw)
	draw_circle(b, 3.4, Color(Palette.MATERIAL_GOLD, 0.55))
	draw_arc(b, 3.4, 0.0, TAU, 16, Palette.BOARD_PAD_EDGE, 1.0)
	draw_circle(b, 1.2, Palette.BG_VOID)


# ---------------------------------------------------------------- ghost

## Placement ghost: an isolated tile (horizontal segment ±24 px through (32, 32)) with layers
## 1–5. `ci` is the CanvasItem to draw on (a small painter child of a ghost MachineView).
static func draw_ghost(ci: CanvasItem, type: String) -> void:
	var w: float = W[type]
	var c := Vector2(32, 32)
	var segs := [Vector2.RIGHT, Vector2.LEFT]
	# layer 1: seat
	for d in segs:
		ci.draw_line(c, c + d * 24.0, Palette.BOARD_PAD_EDGE, w + 2.0)
	# layer 2: pour
	for d in segs:
		ci.draw_line(c, c + d * 24.0, Palette.BOARD_PAD, w)
	# layer 3: wash
	for d in segs:
		ci.draw_line(c, c + d * 24.0, Color(Palette.MATERIAL_GOLD, 0.10), w)
	# layer 4: lines
	for d in segs:
		if type == "power_rail":
			ci.draw_line(c, c + d * 24.0, Color(Palette.MATERIAL_GOLD, 0.62), 1.4)
			continue
		var p := Vector2(-d.y, d.x)
		var off := w / 2.0 - 2.0
		ci.draw_line(c + p * off, c + d * 24.0 + p * off, Color(Palette.MATERIAL_GOLD, 0.62), 1.3)
		ci.draw_line(c - p * off, c + d * 24.0 - p * off, Color(Palette.MATERIAL_GOLD, 0.62), 1.3)
	# layer 5: vias (planes only)
	if type in PLANES:
		for d in segs:
			var p := Vector2(-d.y, d.x)
			for tdist: float in [10.0, 26.0]:
				if tdist > 24.0:
					continue
				var pt: Vector2 = c + d * tdist
				if type == "power_plane_heavy":
					ci.draw_circle(pt + p * 5.0, 1.5, Palette.BG_VOID)
					ci.draw_arc(pt + p * 5.0, 1.5, 0.0, TAU, 12, Color(Palette.MATERIAL_GOLD, 0.45), 0.8)
					ci.draw_circle(pt, 1.5, Palette.BG_VOID)
					ci.draw_arc(pt, 1.5, 0.0, TAU, 12, Color(Palette.MATERIAL_GOLD, 0.45), 0.8)
					ci.draw_circle(pt - p * 5.0, 1.5, Palette.BG_VOID)
					ci.draw_arc(pt - p * 5.0, 1.5, 0.0, TAU, 12, Color(Palette.MATERIAL_GOLD, 0.45), 0.8)
				else:
					ci.draw_circle(pt, 1.5, Palette.BG_VOID)
					ci.draw_arc(pt, 1.5, 0.0, TAU, 12, Color(Palette.MATERIAL_GOLD, 0.45), 0.8)