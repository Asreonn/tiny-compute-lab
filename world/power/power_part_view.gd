class_name PowerPartView
extends Node2D
## P10c: the power family chassis — the lab jack (power_input), the VRM controller
## (power_controller) and the distribution board (power_board). A child of the rotating
## MachineView body, drawn unrotated in body-local px over the shell and under the state
## overlays. refresh() recomputes a state key (states + loads) on a new sim.tick and a cheap
## layout signature every frame (copper on the terminals changes without a tick); it redraws
## only when either changed. When sim.power_net is null every load is 0 and every state is
## "normal" (the board's sides still show used/unused from copper tiles).

var machine: Machine

## Board terminal offsets (N, E, S) from the board's cell.
const _BOARD_SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(2, 0), Vector2i(0, 1)]
## Controller phases per tier.
const _PHASES := {"ctrl": 2, "basic": 3, "eff": 3, "hc": 5}

var _seen_tick := -2
var _state_key := ""
var _layout_key := -1
var _last_state_key := ""
var _last_layout_key := -1


## Every frame: recompute the state key only when sim.tick changed (states + loads), the
## layout signature always (copper on the terminals); redraw only when either changed.
func refresh() -> void:
	var sim := SimulationManager.sim
	var tick := sim.tick if sim != null else -1
	if tick != _seen_tick:
		_seen_tick = tick
		_state_key = _state_key_of(sim)
	var layout_key := _layout_key_of(sim)
	if _state_key != _last_state_key or layout_key != _last_layout_key:
		_last_state_key = _state_key
		_last_layout_key = layout_key
		queue_redraw()


## The LED override: "error" / "blocked" per part, "" when the stock machine-state LED stands.
func led_name() -> String:
	var sim := SimulationManager.sim
	var pn: PowerNetwork = sim.power_net if sim != null else null
	match Catalog.base_type(machine.type):
		"power_controller":
			if pn != null and pn.state("ctrl") == "over":
				return "error"
			if pn != null and pn.state("ctrl") == "near":
				return "blocked"
		"power_board":
			if pn != null:
				var any_over := false
				var any_near := false
				for side in _BOARD_SIDES:
					var term := machine.cell + side
					if not _copper_at(sim, term):
						continue
					match pn.tile_state(term):
						"over":
							any_over = true
						"near":
							any_near = true
				if any_over:
					return "error"
				if any_near:
					return "blocked"
	return ""


## The state part of the redraw key: the controller's stage + load ratio, or every used
## board side's tile stage. "" when there is no live power network (all "normal", loads 0).
func _state_key_of(sim: Simulation) -> String:
	var pn: PowerNetwork = sim.power_net if sim != null else null
	var parts := PackedStringArray()
	match Catalog.base_type(machine.type):
		"power_controller":
			if pn != null and pn.nodes.has("ctrl"):
				var n: Dictionary = pn.nodes["ctrl"]
				var cap := int(n["cap"])
				var load := int(n["load"])
				parts.append(pn.state("ctrl"))
				parts.append(str(int(clampf(float(load) / float(cap) if cap > 0 else 0.0, 0.0, 1.0) * 100.0)))
			else:
				parts.append("normal")
				parts.append("0")
		"power_board":
			for side in _BOARD_SIDES:
				var term := machine.cell + side
				if _copper_at(sim, term):
					parts.append(pn.tile_state(term) if pn != null else "normal")
				else:
					parts.append("-")
		_:
			parts.append("static")
	return "|".join(parts)


## Cheap int signature of the layout-derived dims (copper on the terminals), recomputed every
## frame so a layout change redraws even while the sim is paused.
func _layout_key_of(sim: Simulation) -> int:
	var k := 0
	match Catalog.base_type(machine.type):
		"power_controller":
			k = 1 if _copper_at(sim, machine.cell + Vector2i(2, 0)) else 0
			k |= (2 if _copper_at(sim, machine.cell + Vector2i(1, 2)) else 0)
		"power_board":
			for i in 3:
				k |= (1 << i) if _copper_at(sim, machine.cell + _BOARD_SIDES[i]) else 0
	return k


## True when a copper machine's footprint covers `tile`.
static func _copper_at(sim: Simulation, tile: Vector2i) -> bool:
	if sim == null:
		return false
	var m := sim.machine_at(tile)
	return m != null and m.type in PowerNetwork.COPPER


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var sim := SimulationManager.sim
	var pn: PowerNetwork = sim.power_net if sim != null else null
	match Catalog.base_type(machine.type):
		"power_input":
			_draw_input()
		"power_controller":
			_draw_controller(pn, sim)
		"power_board":
			_draw_board(pn, sim)


## A power contact port (18×18): copper-dim pad, die body with a gold ring, gold core.
## `dim` fades the gold (a terminal with no copper on it). Ports are drawn LAST.
static func power_port(ci: CanvasItem, c: Vector2, dim := false) -> void:
	SystemsDraw.rrect(ci, Rect2(c - Vector2(9, 9), Vector2(18, 18)), 4.0, Palette.MATERIAL_COPPER_DIM)
	var body := Rect2(c - Vector2(7, 7), Vector2(14, 14))
	SystemsDraw.rrect(ci, body, 2.5, Palette.MATERIAL_DIE)
	SystemsDraw.rrect_outline(ci, body, 2.5, Color(Palette.MATERIAL_GOLD, 0.45 if dim else 0.85), 2.0)
	SystemsDraw.rrect(ci, Rect2(c - Vector2(2.5, 2.5), Vector2(5, 5)), 1.0, Color(Palette.MATERIAL_GOLD, 0.4 if dim else 0.9))


## a) power_input — the Lab jack face set into the laptop edge (EdgeIn-M, 128×64).
func _draw_input() -> void:
	var frame := Rect2(-6, 14, 18, 36)
	SystemsDraw.rrect(self, frame, 3.0, Palette.MACHINE_FRAME_HOVER)
	SystemsDraw.rrect_outline(self, frame, 3.0, Color(Palette.MATERIAL_SILK, 0.45), 1.0)
	var bore := Vector2(4, 28)
	draw_circle(bore, 7.0, Palette.MATERIAL_VENT)
	draw_arc(bore, 7.0, 0.0, TAU, 24, Palette.MATERIAL_FRAME, 1.0, true)
	draw_circle(bore, 2.0, Color(Palette.MATERIAL_GOLD, 0.9))
	# the Lab jack is always plugged: the copper plug ring stays
	draw_arc(bore, 5.0, 0.0, TAU, 24, Color(Palette.MATERIAL_COPPER, 0.85), 1.6, true)
	# input-filter window
	var win := Rect2(26, 20, 54, 24)
	SystemsDraw.rrect(self, win, 3.0, Palette.MACHINE_SCREEN)
	SystemsDraw.rrect_outline(self, win, 3.0, Palette.MATERIAL_FRAME, 1.0)
	var pts := PackedVector2Array()
	for p in [[4, 12], [10, 12], [13, 6], [18, 18], [23, 6], [28, 18], [31, 12], [50, 12]]:
		pts.append(win.position + Vector2(p[0], p[1]))
	draw_polyline(pts, Color(Palette.MATERIAL_GOLD, 0.55), 1.2, true)
	power_port(self, Vector2(128, 32))


## b) power_controller — the VRM (Module-L, 128×128): one phase cell per tier phase count,
## a load fill per cell, and the E / S outputs dim when their terminal has no copper.
func _draw_controller(pn: PowerNetwork, sim: Simulation) -> void:
	var tier := str(machine.params.get("tier", "ctrl"))
	var n: int = int(_PHASES.get(tier, 2))
	var cap := 0
	var load := 0
	if pn != null and pn.nodes.has("ctrl"):
		cap = int(pn.nodes["ctrl"]["cap"])
		load = int(pn.nodes["ctrl"]["load"])
	var L := clampf(float(load) / float(cap) if cap > 0 else 0.0, 0.0, 1.0)
	var over := pn != null and pn.state("ctrl") == "over"
	var win := Rect2(16, 22, 96, 44)
	SystemsDraw.rrect(self, win, 3.0, Palette.MACHINE_SCREEN)
	SystemsDraw.rrect_outline(self, win, 3.0, Palette.MATERIAL_FRAME, 1.0)
	var cw := (96.0 - 8.0 - float(n - 1) * 4.0) / float(n)
	for i in n:
		var px := 20.0 + float(i) * (cw + 4.0)
		var cell := Rect2(px, 26, cw, 36)
		SystemsDraw.rrect(self, cell, 2.0, Palette.MATERIAL_DIE)
		SystemsDraw.rrect_outline(self, cell, 2.0, Palette.MATERIAL_FRAME, 0.75)
		SystemsDraw.rrect_outline(self, Rect2(px + cw / 2.0 - 5.0, 30, 10, 10), 2.5, Color(Palette.MATERIAL_COPPER, 0.7), 1.0)
		var fill_h := 14.0 * L
		if over:
			fill_h = 14.0
		if fill_h > 0.0:
			SystemsDraw.rrect(self, Rect2(px + 3, 58.0 - fill_h, cw - 6.0, fill_h), 1.0, Color(Palette.STATE_BLOCKED if over else Palette.MATERIAL_GOLD, 0.55))
	# embedded thermal pickup on the north edge (eff / hc tiers)
	if tier in ["eff", "hc"]:
		var recess := Rect2(50, 2, 28, 7)
		SystemsDraw.rrect(self, recess, 1.5, Palette.MATERIAL_VENT)
		SystemsDraw.rrect_outline(self, recess, 1.5, Palette.MATERIAL_FRAME, 0.75)
		SystemsDraw.rrect(self, Rect2(52, 3.5, 24, 4), 1.0, Color(Palette.MATERIAL_COPPER, 0.75))
	power_port(self, Vector2(0, 32))
	power_port(self, Vector2(128, 32), not _copper_at(sim, machine.cell + Vector2i(2, 0)))
	power_port(self, Vector2(96, 128), not _copper_at(sim, machine.cell + Vector2i(1, 2)))


## c) power_board — the distribution board (Module-M, 128×64): one breaker per used side
## (N / E / S), a dash for unused sides, and the output ports dim when their side is unused.
func _draw_board(pn: PowerNetwork, sim: Simulation) -> void:
	var win := Rect2(16, 18, 84, 34)
	SystemsDraw.rrect(self, win, 3.0, Palette.MACHINE_SCREEN)
	SystemsDraw.rrect_outline(self, win, 3.0, Palette.MATERIAL_FRAME, 1.0)
	for i in 3:
		var bx := 21.0 + float(i) * 26.0
		var body := Rect2(bx, 21, 22, 28)
		SystemsDraw.rrect(self, body, 2.0, Palette.MATERIAL_DIE)
		SystemsDraw.rrect_outline(self, body, 2.0, Palette.MATERIAL_FRAME, 0.75)
		var term := machine.cell + _BOARD_SIDES[i]
		if not _copper_at(sim, term):
			SystemsDraw.rrect(self, Rect2(bx + 4, 32, 14, 2), 1.0, Palette.MATERIAL_FRAME)
			continue
		var st := pn.tile_state(term) if pn != null else "normal"
		var lever := Rect2(bx + 6, 35.0 if st == "over" else 25.0, 10, 9)
		SystemsDraw.rrect(self, lever, 1.5, Color(Palette.STATE_BLOCKED, 0.9) if st == "over" else Color(Palette.TEXT_SECONDARY, 0.55))
		var lamp: Color = Color(Palette.MATERIAL_GOLD, 0.55) if st == "normal" else (Palette.STATE_BLOCKED if st == "near" else Palette.STATE_ERROR)
		draw_circle(Vector2(bx + 11, 46), 2.0, lamp)
	power_port(self, Vector2(0, 32))
	power_port(self, Vector2(32, 0), not _copper_at(sim, machine.cell + _BOARD_SIDES[0]))
	power_port(self, Vector2(128, 32), not _copper_at(sim, machine.cell + _BOARD_SIDES[1]))
	power_port(self, Vector2(32, 64), not _copper_at(sim, machine.cell + _BOARD_SIDES[2]))