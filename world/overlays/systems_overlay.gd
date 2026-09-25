class_name SystemsOverlay
extends Node2D
## The board VIEWS drawn over the machines (docs/VISUAL_SYSTEM.md §21.2, systems_v1.js
## OVERLAYS): Data (B: what kind of data every wire carries, and how wide), Flow (F: how busy or
## blocked every machine is, the bottleneck, stuck wires), Heat (T) and Power (P). Read-only: it
## draws SimulationManager.sim every frame while shown, visible tiles only. One view at a time
## with a 150 ms cross-fade; World fades the machines to α .55 by `fade`. The dock and the legend
## are HUD panels (ui/hud/view_dock.gd, ui/hud/overlay_legend.gd).

const T := Palette.TILE
const FADE := 0.15
## Tile α per stage (WARM · HOT · THROTTLING in state.blocked, CRITICAL in state.error).
const TILE_A := [0.0, 0.12, 0.26, 0.42, 0.38]
const COVER_LABEL := {"heatsink": "heatsink r1", "blower": "blower r2", "radiator": "radiator r2"}

var fade := 0.0  # 0 hidden … 1 shown
var _kind := ""  # overlay being drawn (kept while it fades out)


func _process(delta: float) -> void:
	var want: String = SimulationManager.overlay
	if want != _kind:
		fade = move_toward(fade, 0.0, delta / FADE)
		if fade <= 0.0:
			_kind = want
	else:
		fade = move_toward(fade, 1.0 if _kind != "" else 0.0, delta / FADE)
	visible = fade > 0.0 and _kind != ""
	modulate.a = fade
	if visible:
		queue_redraw()


func _visible_tiles(sim: Simulation) -> Rect2i:
	var vr := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
	var a := Vector2i((vr.position / T).floor()).clamp(Vector2i.ZERO, sim.size)
	var b := Vector2i((vr.end / T).ceil()).clamp(Vector2i.ZERO, sim.size)
	return Rect2i(a, b - a)


func _draw() -> void:
	var sim := SimulationManager.sim
	if sim == null:
		return
	match _kind:
		"thermal": _draw_thermal(sim)
		"power": _draw_power(sim)
		"data": _draw_data(sim)
		"flow": _draw_flow(sim)


func _route_pts(c: Connection) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for cell in c.cells:
		pts.append((Vector2(cell) + Vector2(0.5, 0.5)) * T)
	return pts


func _chip(center: Vector2, text: String, col: Color, bold := true) -> void:
	var f := TclTheme.font("ExtraBold" if bold else "Medium")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 10.0
	var r := Rect2(center - Vector2(w * 0.5, 8.0), Vector2(w, 16.0))
	SystemsDraw.rrect(self, r, 4.0, Palette.SURFACE_SUNKEN)
	SystemsDraw.rrect_outline(self, r, 4.0, Color(col, 0.8), 1.0)
	draw_string(f, r.position + Vector2(5.0, 12.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)


# ------------------------------------------------------------------ data

## Every wire as a wide band in the colour of what it carries (bits: data.number, raw values:
## family.io) with its width at the middle: "3b", "5b", "RAW".
func _draw_data(sim: Simulation) -> void:
	for cid in sim.sorted_connection_ids():
		var c: Connection = sim.connections[cid]
		var src: Machine = sim.machines.get(c.from_id)
		if src == null or c.cells.is_empty():
			continue
		var raw := src.port_role(c.from_port) == Catalog.ROLE_RAW
		var col := Palette.FAMILY_IO if raw else Palette.DATA_NUMBER
		var pts := _route_pts(c)
		if pts.size() >= 2:
			draw_polyline(pts, Color(col, 0.3), 12.0, true)
		_chip(pts[pts.size() / 2], "RAW" if raw else "%db" % c.width, col)
	# each USB stick names what it streams
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "usb_input" and m.device != "":
			var raw := Devices.out_kind(m.device) == "raw"
			var fp := Rect2(Vector2(m.cell) * T, Vector2(Catalog.size_of(m.type, m.rot)) * T)
			_chip(Vector2(fp.get_center().x, fp.end.y + 10.0), Devices.display_name(m.device).replace(" module", ""), Palette.FAMILY_IO if raw else Palette.DATA_NUMBER)


# ------------------------------------------------------------------ flow

## How the factory flows: a busy / blocked bar on every machine (share of the run so far), the
## bottleneck outlined, wires that are stuck (their head could not move) in state.blocked, and
## values lost at a USB stick.
func _draw_flow(sim: Simulation) -> void:
	for cid in sim.sorted_connection_ids():
		var c: Connection = sim.connections[cid]
		if c.cells.is_empty():
			continue
		var full := 0
		for sl in c.slots:
			if sl != null:
				full += 1
		var load := float(full) / float(maxi(c.slots.size(), 1))
		var col := Palette.STATE_BLOCKED if c.blocked else Palette.STATE_VALID
		var pts := _route_pts(c)
		if pts.size() >= 2 and (c.blocked or load > 0.0):
			draw_polyline(pts, Color(col, 0.18 + 0.4 * load), 6.0 + 8.0 * load, true)
	var ticks := maxi(sim.tick, 1)
	var bn := sim.bottleneck()
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		var fp := Rect2(Vector2(m.cell) * T, Vector2(Catalog.size_of(m.type, m.rot)) * T)
		if m.type == "usb_input":
			if m.lost > 0:
				_chip(Vector2(fp.get_center().x, fp.position.y + 10.0), "lost %d" % m.lost, Palette.STATE_ERROR)
			continue
		if m.locked:
			continue
		var busy := clampf(float(m.busy_ticks) / ticks, 0.0, 1.0)
		var blocked := clampf(float(m.blocked_ticks) / ticks, 0.0, 1.0 - busy)
		var bar := Rect2(Vector2(fp.get_center().x - 30.0, fp.position.y + 6.0), Vector2(60.0, 12.0))
		SystemsDraw.rrect(self, bar.grow(2.0), 4.0, Palette.SURFACE_SUNKEN)
		SystemsDraw.rrect(self, Rect2(bar.position, Vector2(bar.size.x * busy, bar.size.y)), 2.0, Palette.STATE_VALID)
		SystemsDraw.rrect(self, Rect2(bar.position + Vector2(bar.size.x * busy, 0), Vector2(bar.size.x * blocked, bar.size.y)), 2.0, Palette.STATE_BLOCKED)
		var pct := "%d%%" % roundi(busy * 100.0)
		draw_string(TclTheme.font("ExtraBold"), Vector2(bar.end.x + 5.0, bar.position.y + 10.0), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.TEXT_PRIMARY if busy >= 0.05 else Palette.TEXT_MUTED)
		if bn != null and bn.id == m.id:
			SystemsDraw.rrect_outline(self, fp.grow(-2.0), 8.0, Palette.STATE_BLOCKED, 2.0)
			_chip(Vector2(fp.get_center().x, fp.end.y - 10.0), "BOTTLENECK", Palette.STATE_BLOCKED)


# ------------------------------------------------------------------ thermal

func _draw_thermal(sim: Simulation) -> void:
	var th := sim.thermal
	if th == null or th.size != sim.size:
		return
	var vis := _visible_tiles(sim)
	for y in range(vis.position.y, vis.end.y):
		for x in range(vis.position.x, vis.end.x):
			var st := ThermalGrid.stage_for(th.t[y * th.size.x + x], 0)
			if st == ThermalGrid.Stage.NORMAL:
				continue
			var col := Palette.STATE_ERROR if st == ThermalGrid.Stage.CRITICAL else Palette.STATE_BLOCKED
			SystemsDraw.rrect(self, Rect2(x * T + 2, y * T + 2, T - 4, T - 4), 4.0, Color(col, TILE_A[st]))
	# cooling coverage: Chebyshev squares, dashed copper
	var font := TclTheme.font(SystemsDraw.FONT)
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if not ThermalGrid.COOLERS.has(m.type):
			continue
		var r: int = ThermalGrid.COOLERS[m.type][1]
		var a := (m.cell - Vector2i(r, r)).clamp(Vector2i.ZERO, sim.size)
		var b := (m.cell + Catalog.size_of(m.type, m.rot) + Vector2i(r, r)).clamp(Vector2i.ZERO, sim.size)
		var rect := Rect2(Vector2(a) * T + Vector2(1, 1), Vector2(b - a) * T - Vector2(2, 2))
		SystemsDraw.rrect_dashed(self, rect, 4.0, Color(Palette.MATERIAL_COPPER, 0.7), 1.0, 10.0, 6.0)  # Penpot 19 C′
		draw_string(font, rect.position + Vector2(6, 13), str(COVER_LABEL[m.type]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(Palette.MATERIAL_COPPER, 0.9))
	_draw_pipe_flow(sim, th)


## Heat-pipe flow: 6x10 gold chevrons from the chain's hot pad towards its cold pad.
func _draw_pipe_flow(sim: Simulation, th: ThermalGrid) -> void:
	var pipes := {}  # cell -> Machine
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "heat_pipe":
			pipes[m.cell] = m
	if pipes.is_empty():
		return
	var seen := {}
	var cells := pipes.keys()
	cells.sort()
	for start in cells:
		if seen.has(start):
			continue
		# chain + its pads (open axis ends and the tile each one touches)
		var chain := []
		var stack := [start]
		var pads := []  # [pipe cell, dir, temp]
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			if seen.has(c):
				continue
			seen[c] = true
			chain.append(c)
			for d in _links(pipes, c):
				stack.append(c + d)
			for d in _open_ends(pipes, c):
				pads.append([c, d, th.at(c + d)])
		if pads.size() < 2:
			continue
		var hot: Array = pads[0]
		var cold: Array = pads[0]
		for p in pads:
			if int(p[2]) > int(hot[2]):
				hot = p
			if int(p[2]) < int(cold[2]):
				cold = p
		if int(hot[2]) - int(cold[2]) < 20:
			continue
		# distances from the hot pad's pipe; each tile points to the next tile further away
		var dist := {hot[0]: 0}
		var q := [hot[0]]
		while not q.is_empty():
			var c2: Vector2i = q.pop_front()
			for d in _links(pipes, c2):
				if not dist.has(c2 + d):
					dist[c2 + d] = int(dist[c2]) + 1
					q.append(c2 + d)
		for c3 in chain:
			var dir := Vector2i.ZERO
			for d in _links(pipes, c3):
				if dist.has(c3 + d) and int(dist[c3 + d]) > int(dist.get(c3, 0)):
					dir = d
			if dir == Vector2i.ZERO and c3 == cold[0]:
				dir = cold[1]
			if dir != Vector2i.ZERO:
				_chevron(Vector2(c3) * T + Vector2(T, T) * 0.5, Vector2(dir))


func _links(pipes: Dictionary, c: Vector2i) -> Array:
	var out := []
	var horiz: bool = (pipes[c] as Machine).rot % 2 == 0
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if pipes.has(c + d):
			var nh: bool = (pipes[c + d] as Machine).rot % 2 == 0
			var edge_h: bool = d.x != 0
			if horiz == edge_h or nh == edge_h:
				out.append(d)
	return out


func _open_ends(pipes: Dictionary, c: Vector2i) -> Array:
	var out := []
	var horiz: bool = (pipes[c] as Machine).rot % 2 == 0
	var links := _links(pipes, c)
	for d in ([Vector2i.LEFT, Vector2i.RIGHT] if horiz else [Vector2i.UP, Vector2i.DOWN]):
		if not links.has(d):
			out.append(d)
	return out


func _chevron(center: Vector2, dir: Vector2) -> void:
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([center - dir * 3.0 + side * 5.0, center + dir * 3.0, center - dir * 3.0 - side * 5.0])
	draw_polyline(pts, Color(Palette.MATERIAL_GOLD, 0.8), 2.0, true)


# ------------------------------------------------------------------ power

## Per-machine demand chip: its power pips (rated × clock) on a surface.sunken chip at the top of
## the footprint. The brownout is global, so no machine is marked red.
func _draw_power(sim: Simulation) -> void:
	var vis := Rect2(_visible_tiles(sim))
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.locked:
			continue
		var dem := m.power_demand()
		var fp := Rect2(Vector2(m.cell) * T, Vector2(Catalog.size_of(m.type, m.rot)) * T)
		if not Rect2(vis.position * T, vis.size * T).intersects(fp):
			continue
		var pips := mini(dem, 8)
		var w := 8.0 + (pips * 5.0 if dem > 0 else 5.0) + (5.0 if dem > 8 else 0.0)
		var chip := Rect2(Vector2(fp.get_center().x - w * 0.5, fp.position.y + 4.0), Vector2(w, 14))
		SystemsDraw.rrect(self, chip, 4.0, Palette.SURFACE_SUNKEN)
		SystemsDraw.rrect_outline(self, chip, 4.0, Palette.SURFACE_BORDER, 1.0)
		var x := chip.position.x + 4.0
		if dem == 0:
			SystemsDraw.rrect_outline(self, Rect2(x, chip.position.y + 3, 3, 8), 0.5, Color(Palette.MATERIAL_SILK, 0.35), 0.75)
		for i in pips:
			SystemsDraw.rrect(self, Rect2(x, chip.position.y + 3, 3, 8), 0.5, Color(Palette.MATERIAL_GOLD, 0.9))
			x += 5.0
		if dem > 8:
			draw_rect(Rect2(x, chip.position.y + 6.5, 3, 1), Palette.MATERIAL_GOLD)
			draw_rect(Rect2(x + 1, chip.position.y + 5.5, 1, 3), Palette.MATERIAL_GOLD)
