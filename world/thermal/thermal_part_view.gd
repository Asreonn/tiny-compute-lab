class_name ThermalPartView2
extends Node2D
## P10d2: the thermal chassis parts — the manifold (thermal_manifold), fin stack
## (fin_stack), radiators (radiator / radiator_large) and the fan family (blower /
## blower_hp / fan_bank). A child of the rotating MachineView body, drawn unrotated in
## body-local px over the shell and under the state overlays. refresh() recomputes a state
## key (sink heat + starve flag) on a new sim.tick and a cheap layout signature every frame
## (power teeth on the contacts change without a tick); it redraws only when either changed,
## or while a fan impeller is spinning. When sim.thermal is null every sink value is 0 and
## every radiator reads "normal".

var machine: Machine

## Fan types: the impeller spins while the run plays and the fan draws power.
const FAN_TYPES := ["blower", "blower_hp", "fan_bank"]
## Sink types: their fin core shows the dump/effective heat wash (0 when unknown).
const SINK_TYPES := ["fin_stack", "radiator", "radiator_large"]

var _seen_tick := -2
var _state_key := ""
var _layout_key := -1
var _last_state_key := ""
var _last_layout_key := -1
var _spin := 0.0  # radians
var _speed := 0.0  # turns per second (fan types)


## Every frame: recompute the state key only when sim.tick changed (sink heat + starve), the
## layout signature always (power teeth on the contacts); redraw only when either changed,
## or while a fan impeller turns (it eases in/out over 0.4 s).
func refresh(delta: float) -> void:
	var sim := SimulationManager.sim
	var tick := sim.tick if sim != null else -1
	if tick != _seen_tick:
		_seen_tick = tick
		_state_key = _state_key_of(sim)
	var layout_key := _layout_key_of(sim)
	var redraw := _state_key != _last_state_key or layout_key != _last_layout_key
	# Fan spin: target 1 turn/s while the run plays and the fan draws power, else 0; the
	# speed eases toward the target over 0.4 s and the impeller redraws while it turns.
	if machine.type in FAN_TYPES:
		var target := 1.0 if (SimulationManager.running and sim != null and sim.work_rate(machine) > 0) else 0.0
		_speed = move_toward(_speed, target, delta / 0.4)
		if _speed > 0.0:
			_spin = fmod(_spin + _speed * TAU * delta, TAU)
			redraw = true
	if redraw:
		_last_state_key = _state_key
		_last_layout_key = layout_key
		queue_redraw()


## The LED override: "blocked" when a radiator's sink is starved (needs airflow it is not
## getting), "" when the stock machine-state LED stands.
func led_name() -> String:
	if machine.type in ["radiator", "radiator_large"] and _starved(SimulationManager.sim):
		return "blocked"
	return ""


## The state part of the redraw key: the sink heat ratio (dump / effective, 0 when unknown)
## and the radiator starve flag. "" for the static parts (fans animate on their own clock).
func _state_key_of(sim: Simulation) -> String:
	var parts := PackedStringArray()
	match machine.type:
		"fin_stack":
			parts.append(str(_heat01(sim)))
		"radiator", "radiator_large":
			parts.append(str(_heat01(sim)))
			parts.append("1" if _starved(sim) else "0")
		_:
			parts.append("static")
	return "|".join(parts)


## Cheap int signature of the layout-derived dims (power teeth on the south contacts),
## recomputed every frame so a layout change redraws even while the sim is paused.
func _layout_key_of(sim: Simulation) -> int:
	if int(machine.def().get("power", 0)) <= 0 or sim == null or sim.power_net == null:
		return 0
	var tapped: Array = sim.power_net.tapped_contacts(machine.id)
	var cols := Catalog.size_of(machine.type, 0).x
	var rows := int(Catalog.SIZES[str(machine.def()["size"])].y)
	var k := 0
	for c in cols:
		if tapped.has(Vector2i(machine.cell.x + c, machine.cell.y + rows)):
			k |= 1 << c
	return k


## The sink's heat ratio: last_alloc["dump"][id] / the sink's effective capacity, clamped to
## 0..1 (0 when the sink is unknown or nothing was dumped).
func _heat01(sim: Simulation) -> float:
	if sim == null or sim.thermal == null:
		return 0.0
	var dump: Dictionary = sim.thermal.last_alloc.get("dump", {})
	var d := int(dump.get(machine.id, 0))
	if d <= 0:
		return 0.0
	var eff := int(_sink(sim).get("effective", 0))
	if eff <= 0:
		return 0.0
	return clampf(float(d) / float(eff), 0.0, 1.0)


## True when the sink needs airflow it is not getting (need > 0 and airflow < need).
func _starved(sim: Simulation) -> bool:
	var s := _sink(sim)
	var need := int(s.get("need", 0))
	return need > 0 and int(s.get("airflow", 0)) < need


## This machine's sink record from the live ThermalNetwork, {} when there is none.
func _sink(sim: Simulation) -> Dictionary:
	if sim == null or sim.thermal == null or sim.thermal.net == null:
		return {}
	for s in sim.thermal.net.sinks():
		if int(s["id"]) == machine.id:
			return s
	return {}


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var sim := SimulationManager.sim
	match machine.type:
		"thermal_manifold":
			_draw_manifold()
		"fin_stack":
			_draw_fin_stack(_heat01(sim))
		"radiator", "radiator_large":
			_draw_radiator(_heat01(sim))
		"blower", "blower_hp", "fan_bank":
			_draw_fan()


## A thermal contact socket: copper-dim pad, die body with a copper ring, vent bore. Drawn
## LAST (over every chassis element, like the power ports).
static func thermal_socket(ci: CanvasItem, c: Vector2) -> void:
	SystemsDraw.rrect(ci, Rect2(c - Vector2(9, 9), Vector2(18, 18)), 4.0, Palette.MATERIAL_COPPER_DIM)
	ci.draw_circle(c, 7.0, Palette.MATERIAL_DIE)
	ci.draw_arc(c, 7.0, 0.0, TAU, 24, Color(Palette.MATERIAL_COPPER, 0.9), 2.0, true)
	ci.draw_circle(c, 3.0, Palette.MATERIAL_VENT)
	ci.draw_arc(c, 3.0, 0.0, TAU, 16, Color(Palette.MATERIAL_COPPER, 0.6), 0.8, true)


## A screen window: filled rounded rect + a 1 px frame.
static func window(ci: CanvasItem, rect: Rect2) -> void:
	SystemsDraw.rrect(ci, rect, 3.0, Palette.MACHINE_SCREEN)
	SystemsDraw.rrect_outline(ci, rect, 3.0, Palette.MATERIAL_FRAME, 1.0)


## A passive fin core: screen window, vertical plate fins every 3.4 px, and a heat wash that
## rises from the bottom of the fins (STATE_BLOCKED at heat·0.75 α, fading to 0 at 60 % of the
## height) while the sink is dumping.
static func fin_core(ci: CanvasItem, rect: Rect2, heat: float) -> void:
	window(ci, rect)
	var x := rect.position.x + 3.0
	while x < rect.end.x - 3.0:
		SystemsDraw.rrect(ci, Rect2(x, rect.position.y + 2.0, 1.5, rect.size.y - 4.0), 0.5, Palette.MATERIAL_PLATE_HI)
		x += 3.4
	if heat > 0.02:
		var fade := rect.size.y * 0.6
		var pts := PackedVector2Array([
			Vector2(rect.position.x, rect.end.y),
			Vector2(rect.end.x, rect.end.y),
			Vector2(rect.end.x, rect.end.y - fade),
			Vector2(rect.position.x, rect.end.y - fade),
		])
		var cols := PackedColorArray([
			Color(Palette.STATE_BLOCKED, heat * 0.75),
			Color(Palette.STATE_BLOCKED, heat * 0.75),
			Color(Palette.STATE_BLOCKED, 0.0),
			Color(Palette.STATE_BLOCKED, 0.0),
		])
		ci.draw_polygon(pts, cols)


## Vent slots along the top edge (the air goes north into the sink above).
static func exhaust_mark(ci: CanvasItem, w: float) -> void:
	var x := 20.0
	while x <= w - 20.0:
		SystemsDraw.rrect(ci, Rect2(x, 1.0, 4.0, 4.0), 0.5, Palette.MATERIAL_VENT)
		x += 8.0


## An impeller: screen disk + frame, 14 silk blades swept by `spin` (radians), plate hub with
## a copper ring.
static func fan(ci: CanvasItem, c: Vector2, r: float, spin: float) -> void:
	ci.draw_circle(c, r, Palette.MACHINE_SCREEN)
	ci.draw_arc(c, r, 0.0, TAU, 32, Palette.MATERIAL_FRAME, 1.0, true)
	var blade := Color(Palette.MATERIAL_SILK, 0.5)
	for i in 14:
		var a := spin + float(i) * TAU / 14.0
		ci.draw_line(
			c + Vector2(cos(a), sin(a)) * (0.35 * r),
			c + Vector2(cos(a + 0.4), sin(a + 0.4)) * (0.85 * r),
			blade, 1.1)
	ci.draw_circle(c, r * 0.3, Palette.MATERIAL_PLATE_HI)
	ci.draw_arc(c, r * 0.3, 0.0, TAU, 16, Palette.MATERIAL_COPPER, 1.0, true)


## Gold power teeth along the south edge, one column of three per footprint column. Bright
## when the contact tile (cell.x + k, cell.y + h/64) is tapped by the live power chain, dim
## otherwise. Only for defs with "power" > 0.
static func power_teeth(ci: CanvasItem, machine: Machine, w: float, h: float) -> void:
	if int(machine.def().get("power", 0)) <= 0:
		return
	var sim := SimulationManager.sim
	var pn: PowerNetwork = sim.power_net if sim != null else null
	var tapped: Array = pn.tapped_contacts(machine.id) if pn != null else []
	var cols := Catalog.size_of(machine.type, 0).x
	var row := machine.cell.y + int(h / 64.0)
	for k in cols:
		var a := 0.95 if tapped.has(Vector2i(machine.cell.x + k, row)) else 0.4
		for i in 3:
			var x := 32.0 + 64.0 * float(k) - 8.0 + 1.0 + float(i) * 5.5
			SystemsDraw.rrect(ci, Rect2(x, h - 5.0, 3.5, 4.0), 0.5, Color(Palette.MATERIAL_GOLD, a))


## a) thermal_manifold (Module-M, 128×64): a copper header over the window with three stub
## risers, and a contact socket on every side.
func _draw_manifold() -> void:
	window(self, Rect2(16, 18, 84, 30))
	var header := Rect2(20, 26, 76, 14)
	SystemsDraw.rrect(self, header, 5.0, Palette.MATERIAL_COPPER_DIM)
	SystemsDraw.rrect_outline(self, header, 5.0, Color(Palette.MATERIAL_COPPER, 0.9), 1.2)
	SystemsDraw.rrect(self, Rect2(24, 28.5, 68, 1.3), 0.5, Color(Palette.MATERIAL_GOLD, 0.35))
	for sx in [32, 58, 84]:
		SystemsDraw.rrect(self, Rect2(sx - 3.0, 20.0, 6.0, 6.0), 1.0, Color(Palette.MATERIAL_COPPER, 0.6))
	thermal_socket(self, Vector2(0, 32))
	thermal_socket(self, Vector2(32, 0))
	thermal_socket(self, Vector2(32, 64))
	thermal_socket(self, Vector2(128, 32))


## b) fin_stack (Module-M, 128×64): a passive fin core over a copper base, vents on top, one
## west socket.
func _draw_fin_stack(heat: float) -> void:
	fin_core(self, Rect2(30, 16, 72, 34), heat)
	var base := Rect2(26, 48, 80, 5)
	SystemsDraw.rrect(self, base, 2.0, Palette.MATERIAL_COPPER_DIM)
	SystemsDraw.rrect_outline(self, base, 2.0, Color(Palette.MATERIAL_COPPER, 1.0), 0.8)
	exhaust_mark(self, 128.0)
	thermal_socket(self, Vector2(0, 32))


## c) radiator / radiator_large (Module-L, 128×128): a tall fin core over a copper base with
## gold sheens (the large one gets a second sheen), vents on top, two west sockets and the
## power teeth.
func _draw_radiator(heat: float) -> void:
	fin_core(self, Rect2(22, 22, 90, 72), heat)
	var base := Rect2(18, 96, 98, 8)
	SystemsDraw.rrect(self, base, 3.0, Palette.MATERIAL_COPPER_DIM)
	SystemsDraw.rrect_outline(self, base, 3.0, Color(Palette.MATERIAL_COPPER, 1.0), 1.0)
	SystemsDraw.rrect(self, Rect2(22, 98, 90, 1.2), 0.5, Color(Palette.MATERIAL_GOLD, 0.35))
	if machine.type == "radiator_large":
		SystemsDraw.rrect(self, Rect2(22, 101, 90, 1.2), 0.5, Color(Palette.MATERIAL_GOLD, 0.35))
	exhaust_mark(self, 128.0)
	thermal_socket(self, Vector2(0, 32))
	thermal_socket(self, Vector2(0, 96))
	power_teeth(self, machine, 128.0, 128.0)


## d) blower / blower_hp / fan_bank: one, two or four impellers, vents on top (the air goes
## north into the sink) and the power teeth.
func _draw_fan() -> void:
	match machine.type:
		"blower":
			fan(self, Vector2(30, 36), 18.0, _spin)
			exhaust_mark(self, 64.0)
			power_teeth(self, machine, 64.0, 64.0)
		"blower_hp":
			fan(self, Vector2(40, 38), 19.0, _spin)
			fan(self, Vector2(86, 38), 19.0, _spin)
			exhaust_mark(self, 128.0)
			power_teeth(self, machine, 128.0, 64.0)
		"fan_bank":
			fan(self, Vector2(40, 44), 24.0, _spin)
			fan(self, Vector2(90, 44), 24.0, _spin)
			fan(self, Vector2(40, 96), 24.0, _spin)
			fan(self, Vector2(90, 96), 24.0, _spin)
			exhaust_mark(self, 128.0)
			power_teeth(self, machine, 128.0, 128.0)