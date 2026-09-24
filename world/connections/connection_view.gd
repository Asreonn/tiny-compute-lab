class_name ConnectionView
extends Node2D
## Slice A4b: one read-only view per Connection, a child of World.WireLayer. Renders the
## Signal System V1 layer stack (design/reference/signal_system_v1.js → L.drawWire /
## L.drawBus) with identical geometry, layer order, widths, opacities and Palette colour
## tokens. The view only reads the Simulation: state is derived every frame in refresh().
##
## Node tree (draw order = tree order):
##   SelectHalo (Line2D) · Teardrops (polygons) · TrenchEdge (Line2D) · Trench (Line2D)
##   · Core (Line2D) · Lane0..3 (Line2D, buses) · Overlays (dash/comets/chevrons/tag).

const T := Palette.TILE
const TAG_FONT := 7  # WidthTag digits (Penpot 7.5; Godot font sizes are integers)
const COMET_TAIL_PX := 40.0  # packet comet tail length, clamped at the wire start
const DASH_LEN := 6.0        # boolean core dash length (px of arc)
const DASH_GAP := 4.0        # boolean core dash gap

## Optional provider of this wire's packet positions: a Callable returning an Array of
## arc-length floats (px along the chamfered path) for the comet heads. When unset, a
## comet head is drawn at each occupied slot's cell centre.
var packet_positions: Callable = Callable()
## Set by tools (future wire tool / selection): interaction states layer over Idle.
var hovered := false
var selected := false

var connection: Connection

var _bus := false
var _path := PackedVector2Array()  # simplified + chamfered draw path
var _teardrops: Array = []         # PackedVector2Array teardrop polygons (from, to)
var _halo: Line2D
var _edge: Line2D
var _trench: Line2D
var _core: Line2D
var _lanes: Array = []             # Line2D bus lanes
var _under: TeardropLayer
var _over: OverlayLayer

var _state := "Idle"
var _edge_color := Palette.BOARD_PAD_EDGE
var _edge_op := 1.0
var _core_color := Palette.DATA_NUMBER_DIM
var _core_op := 1.0
var _core_w := Palette.SIG_CORE
var _halo_on := false
var _chevrons_on := false
var _dash_on := false
var _comet_color := Palette.DATA_NUMBER
var _comets: Array = []  # float arc lengths


func setup(c: Connection) -> ConnectionView:
	connection = c
	name = "Connection_%d" % c.id
	var sim := SimulationManager.sim
	var fm: Machine = sim.machines[c.from_id]
	var tm: Machine = sim.machines[c.to_id]
	_bus = bool(fm.port_geom(c.from_port).get("bus", false)) and bool(tm.port_geom(c.to_port).get("bus", false))
	_build_path()
	# draw order: select-halo (bottom) → teardrop-edge → trench-edge → trench → core
	_halo = _make_line(Palette.SIG_SELECT_HALO)
	_halo.name = "SelectHalo"
	add_child(_halo)
	_under = TeardropLayer.new()
	_under.name = "Teardrops"
	_under.host = self
	add_child(_under)
	_edge = _make_line(Palette.SIG_BUS_EDGE if _bus else Palette.SIG_EDGE)
	_edge.name = "TrenchEdge"
	add_child(_edge)
	_trench = _make_line(Palette.SIG_BUS_TRENCH if _bus else Palette.SIG_TRENCH)
	_trench.name = "Trench"
	add_child(_trench)
	_core = _make_line(Palette.SIG_CORE)
	_core.name = "Core"
	add_child(_core)
	if _bus:
		for i in Palette.SIG_BUS_LANES:
			var ln := _make_line(Palette.SIG_BUS_LANE_WIDTH)
			var off := (i - (float(Palette.SIG_BUS_LANES) - 1.0) * 0.5) * Palette.SIG_BUS_LANE_GAP
			ln.points = SignalGeom.offset_poly(_path, off)
			ln.name = "Lane%d" % i
			add_child(ln)
			_lanes.append(ln)
	_over = OverlayLayer.new()
	_over.name = "Overlays"
	_over.host = self
	add_child(_over)
	return self


## Pts = [port_world(from)] + [tile centres of Connection.cells] + [port_world(to)],
## then simplify (collinear port stubs collapse) and chamfer (bus: 18, trace: 14).
func _build_path() -> void:
	var sim := SimulationManager.sim
	var fm: Machine = sim.machines[connection.from_id]
	var tm: Machine = sim.machines[connection.to_id]
	var pts := PackedVector2Array()
	pts.append(MachineView.port_world(fm, connection.from_port))
	for cell in connection.cells:
		pts.append(Vector2(cell) * T + Vector2.ONE * (T * 0.5))
	pts.append(MachineView.port_world(tm, connection.to_port))
	var raw := SignalGeom.simplify(pts)
	_path = SignalGeom.chamfer(raw, Palette.SIG_BUS_CHAMFER if _bus else Palette.SIG_CHAMFER)
	# PCB teardrop into BOTH terminals, pointing at the port anchors (L.drawWire ends[]).
	_teardrops = []
	if _path.size() >= 2:
		var from_u := (_path[1] - _path[0]).normalized()
		_teardrops.append(SignalGeom.teardrop(_path[0], from_u))
		var to_u := (_path[_path.size() - 2] - _path[_path.size() - 1]).normalized()
		_teardrops.append(SignalGeom.teardrop(_path[_path.size() - 1], to_u))


func _make_line(w: float) -> Line2D:
	var ln := Line2D.new()
	ln.antialiased = true
	ln.width = w
	ln.joint_mode = Line2D.LINE_JOINT_SHARP
	ln.begin_cap_mode = Line2D.LINE_CAP_NONE
	ln.end_cap_mode = Line2D.LINE_CAP_NONE
	ln.points = _path if _path.size() >= 2 else PackedVector2Array([Vector2.ZERO, Vector2.ONE])
	return ln


# ------------------------------------------------------------------ per frame

func refresh(_delta: float) -> void:
	if connection == null:
		return
	_state = _wire_state()
	_comets = _comet_arcs()
	_apply_layers()
	_under.queue_redraw()
	_over.queue_redraw()


## Model → visual state (L.wireLook states). Error > Blocked beat tool interaction so a
## live alarm is never hidden; Selected/Hover are tool-driven and beat ActiveTransfer.
func _wire_state() -> String:
	var sim := SimulationManager.sim
	if sim == null or not sim.machines.has(connection.from_id) or not sim.machines.has(connection.to_id):
		return "Idle"
	var src: Machine = sim.machines[connection.from_id]
	var dst: Machine = sim.machines[connection.to_id]
	var run := SimulationManager.run
	if run != null and run.status == MissionRun.Status.FAIL:
		var fm: Array = run.failure.get("machines", [])
		if src.id in fm and dst.id in fm:
			return "Error"
	if connection.blocked:
		return "Blocked"
	if src.state == Machine.State.BLOCKED and src.outq.get(connection.from_port, null) != null:
		return "Blocked"
	if selected:
		return "Selected"
	if hovered:
		return "Hover"
	if connection.has_packets():
		return "ActiveTransfer"
	return "Idle"


## Comet arc lengths (px along _path) for every packet on this wire. Uses the optional
## packet_positions provider when set, otherwise the occupied slot cell centres.
func _comet_arcs() -> Array:
	if connection == null or _state != "ActiveTransfer":
		return []
	if packet_positions.is_valid():
		return packet_positions.call()
	var out := []
	var path_len := SignalGeom.poly_len(_path)
	for i in connection.slots.size():
		if connection.slots[i] == null or i >= connection.cells.size():
			continue
		var centre := Vector2(connection.cells[i]) * T + Vector2.ONE * (T * 0.5)
		out.append(SignalGeom.project(_path, centre) * path_len)
	return out


## Colours / widths / dashes / halo per L.wireLook + L.drawBus, applied to the Line2D
## layer children. The opaque overlay node re-draws dashes, comets, chevrons and the
## bus width tag on top.
func _apply_layers() -> void:
	var col := Palette.datatype(connection.width)
	var dim := Palette.datatype_dim(connection.width)
	_dash_on = connection.width == 1 and not _bus
	_comet_color = col
	_halo_on = false
	_chevrons_on = false
	match _state:
		"Hover":
			_edge_color = Palette.STATE_HOVER
			_edge_op = 0.75
			_core_color = col
			_core_op = Palette.SIG_HOVER_CORE_OPACITY
			_core_w = Palette.SIG_CORE
		"Selected":
			_halo_on = true
			_edge_color = Palette.BOARD_PAD_EDGE
			_edge_op = 1.0
			_core_color = col
			_core_op = 1.0
			_core_w = Palette.SIG_CORE_LIT
			_chevrons_on = true
		"ActiveTransfer":
			_edge_color = Palette.BOARD_PAD_EDGE
			_edge_op = 1.0
			_core_color = col
			_core_op = Palette.SIG_ACTIVE_CORE_OPACITY
			_core_w = Palette.SIG_CORE
		"Blocked":
			_edge_color = Palette.STATE_BLOCKED
			_edge_op = 0.7
			_core_color = Palette.STATE_BLOCKED
			_core_op = 1.0
			_core_w = Palette.SIG_CORE_LIT
		"Error":
			_edge_color = Palette.STATE_ERROR
			_edge_op = 0.8
			_core_color = Palette.STATE_ERROR
			_core_op = 1.0
			_core_w = Palette.SIG_CORE_LIT
		_:
			_edge_color = Palette.BOARD_PAD_EDGE
			_edge_op = 1.0
			_core_color = dim
			_core_op = 1.0
			_core_w = Palette.SIG_CORE
	_halo.width = 20.0 if _bus else float(Palette.SIG_SELECT_HALO)
	_halo.visible = _halo_on
	_halo.default_color = Color(Palette.STATE_SELECT, 0.9)
	_edge.default_color = Color(_edge_color, _edge_op)
	_trench.default_color = Palette.MATERIAL_VENT
	_core.visible = not _dash_on and not _bus  # boolean cores are dashed by the overlay
	if not _bus:
		_core.default_color = Color(_core_color, _core_op)
		_core.width = _core_w
	var lit := _state == "ActiveTransfer" or _state == "Selected"
	for ln in _lanes:
		var lane_c := Palette.STATE_BLOCKED if _state == "Blocked" else (col if lit else dim)
		ln.default_color = Color(lane_c, 0.9 if lit else 1.0)


## One comet: glow (sub 0.35..1, 10 px @ 0.2), tail (sub 0..0.4, 3 px @ 0.35) and a
## bright head (sub 0.4..1, 3.5 px opaque) that all follow the chamfered path with the
## head exactly at the packet position s (L.drawWire "comet-*" layers).
func _draw_comet(canvas: CanvasItem, s: float) -> void:
	var plen := SignalGeom.poly_len(_path)
	if plen <= 0.0:
		return
	var w0 := maxf(s - COMET_TAIL_PX, 0.0)
	var f0 := clampf(w0 / plen, 0.0, 1.0)
	var f1 := clampf(s / plen, 0.0, 1.0)
	var glow := SignalGeom.sub_poly(_path, f0 + (f1 - f0) * 0.35, f1)
	canvas.draw_polyline(glow, Color(_comet_color, Palette.SIG_COMET_GLOW_OPACITY), float(Palette.SIG_GLOW), true)
	var tail := SignalGeom.sub_poly(_path, f0, f0 + (f1 - f0) * Palette.SIG_COMET_TAIL_FRACTION)
	canvas.draw_polyline(tail, Color(_comet_color, Palette.SIG_COMET_TAIL_OPACITY), float(Palette.SIG_CORE_LIT), true)
	var head := SignalGeom.sub_poly(_path, f0 + (f1 - f0) * Palette.SIG_COMET_TAIL_FRACTION, f1)
	canvas.draw_polyline(head, _comet_color, float(Palette.SIG_PULSE), true)


func _draw_width_tag(canvas: CanvasItem) -> void:
	var mid: Vector2 = SignalGeom.sample(_path, 0.5)[0]
	var tex := Art.tex(Art.widthtag_file(connection.width))
	if tex != null:
		var scaled := Vector2(tex.get_width(), tex.get_height()) / Art.SCALE
		canvas.draw_texture_rect(tex, Rect2(mid - scaled * 0.5, scaled), false)
	var f := TclTheme.font("ExtraBold")
	var label := str(connection.width)
	var tw := 14.0 if label.length() <= 1 else 18.0
	var ascent := f.get_ascent(TAG_FONT)
	var descent := f.get_descent(TAG_FONT)
	canvas.draw_string(f, Vector2(mid.x - tw * 0.5, mid.y + (ascent - descent) * 0.5), label,
		HORIZONTAL_ALIGNMENT_CENTER, tw, TAG_FONT, Palette.DATA_NUMBER)


# ------------------------------------------------------------------ previews

## Static helper for the (future) wire tool: draws a no-trench preview exactly as
## L.drawWire does for ConnectionPreview / ValidTarget / InvalidTarget.
## Wire-tool preview (L.wireLook preview states) drawn on the LIVE route: a translucent
## hologram of the final trench (edge + trench, same chamfered geometry as the placed wire)
## under the canonical preview marks. Preview dashes flow from the source toward the cursor.
static func draw_preview(canvas: CanvasItem, pts: PackedVector2Array, state: String, flow := 0.0) -> void:
	var p := SignalGeom.simplify(pts)
	p = SignalGeom.chamfer(p, Palette.SIG_CHAMFER)
	if p.size() < 2:
		return
	var end := p[p.size() - 1]
	var holo := 0.45 if state != "InvalidTarget" else 0.25
	canvas.draw_polyline(p, Color(Palette.BOARD_PAD_EDGE, holo), float(Palette.SIG_EDGE), true)
	canvas.draw_polyline(p, Color(Palette.MATERIAL_VENT, holo), float(Palette.SIG_TRENCH), true)
	match state:
		"ConnectionPreview":
			for seg in SignalGeom.dash_poly(p, DASH_LEN, DASH_GAP, flow):
				if seg.size() >= 2:
					canvas.draw_polyline(seg, Palette.STATE_BUILD, float(Palette.SIG_CORE), true)
			canvas.draw_circle(end, 4.0, Palette.STATE_BUILD)
			canvas.draw_arc(end, 4.0, 0.0, TAU, 16, Palette.STATE_BUILD, 1.0, true)
		"ValidTarget":
			canvas.draw_polyline(p, Palette.STATE_VALID, float(Palette.SIG_CORE_LIT), true)
			canvas.draw_arc(end, 11.0, 0.0, TAU, 48, Palette.STATE_VALID, 2.0, true)
		"InvalidTarget":
			for seg in SignalGeom.dash_poly(p, DASH_LEN, DASH_GAP, flow):
				if seg.size() >= 2:
					canvas.draw_polyline(seg, Palette.STATE_INVALID, float(Palette.SIG_CORE), true)
			canvas.draw_line(end - Vector2(6, 6), end + Vector2(6, 6), Palette.STATE_INVALID, 2.5, true)
			canvas.draw_line(Vector2(end.x + 6, end.y - 6), Vector2(end.x - 6, end.y + 6), Palette.STATE_INVALID, 2.5, true)


static func _draw_dashed(canvas: CanvasItem, pts: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	for seg in SignalGeom.dash_poly(pts, dash, gap):
		if seg.size() >= 2:
			canvas.draw_polyline(seg, color, width, true)


# ------------------------------------------------------------------ child layers

## Bottom teardrop polygons: PCB landings that widen the trace into both port pads.
class TeardropLayer extends Node2D:
	var host: ConnectionView
	func _draw() -> void:
		var h := host
		if h == null or h._bus:
			return
		if h._teardrops.is_empty():
			return
		var col := Palette.BOARD_PAD_EDGE if h._halo_on else h._edge_color
		for td in h._teardrops:
			var poly := td as PackedVector2Array
			if poly.size() >= 3:
				draw_colored_polygon(poly, col)


## Top overlays: dashed boolean core, packet comets, selected flow chevrons and the
## bus width tag — everything that is not a constant-width stroke.
class OverlayLayer extends Node2D:
	var host: ConnectionView
	func _draw() -> void:
		var h := host
		if h == null:
			return
		if h._dash_on:
			ConnectionView._draw_dashed(self, h._path, Color(h._core_color, h._core_op), h._core_w, ConnectionView.DASH_LEN, ConnectionView.DASH_GAP)
		if not h._comets.is_empty():
			if h._bus:
				# L.drawBus comet-glow: one wide chord from the comet tail to its head.
				var s: float = h._comets[0]
				var plen := SignalGeom.poly_len(h._path)
				var tail := maxf(s - ConnectionView.COMET_TAIL_PX, 0.0)
				var a: Vector2 = SignalGeom.sample(h._path, tail / maxf(plen, 1.0))[0]
				var z: Vector2 = SignalGeom.sample(h._path, s / maxf(plen, 1.0))[0]
				draw_line(a, z, Color(Palette.DATA_NUMBER, 0.18), 16.0, true)
			else:
				for s in h._comets:
					h._draw_comet(self, s)
		if h._chevrons_on:
			for ch in SignalGeom.chevrons(h._path, float(Palette.SIG_CHEVRON_SPACING)):
				draw_polyline(ch, Color(Palette.STATE_SELECT, 0.9), 1.5, true)
		if h._bus and SignalGeom.poly_len(h._path) >= float(Palette.SIG_BUS_TAG_MIN_LENGTH):
			h._draw_width_tag(self)