class_name ChassisMarks
extends RefCounted
## Chassis marks (P10b): lane slices on the rotating Body + board-aligned machine contacts.
## Two independent painters, each redrawing only when its own key changes. Read-only over the
## Machine / SimulationManager; never mutates the simulation. Palette colours only.

const T := Palette.TILE


## Lane slices (FACTORY_SYSTEMS §3.3): one slice per lane on the chassis showing each lane's
## busy fill, plus the MKn silk. A child of the rotating Body so it rotates with the chassis
## like other silk (tiny geometry, no text -> no upright problem). Drawn only when lanes > 1;
## the ProcessProgress ring covers the 1-lane case.
class LaneSlices extends Node2D:
	var machine: Machine
	var rot := 0  # machine.rot % 4 at build (the view is rebuilt when it changes)
	var lanes := 0  # last seen machine.lanes(); 0 = not refreshed yet
	var _key := ""

	## Recompute the draw key on a new tick (progress moves per tick); redraw only on change.
	func refresh(new_tick: bool) -> void:
		if not new_tick:
			return
		rot = machine.rot % 4
		var l := machine.lanes()
		if l != lanes:
			lanes = l
			visible = l > 1
			_key = ""  # the key includes lanes: force the redraw below
		var key := _make_key()
		if key != _key:
			_key = key
			queue_redraw()

	## Key = lanes + every lane's progress rounded to 1/24 steps.
	func _make_key() -> String:
		var k := str(lanes)
		for p in machine.lane_progress():
			k += "|%d" % int(round(float(p) * 24.0))
		return k

	func _draw() -> void:
		if lanes <= 1:
			return
		var d := machine.def()
		var size_key := str(d["size"]).to_lower()
		var prog: Array = machine.lane_progress()
		var fam := Palette.family(str(d["family"]))
		match size_key:
			"s":
				for k in lanes:
					var top := 16.0 + 31.0 - (k + 1) * 3.0 - k * 1.0
					_draw_slice(Rect2(45, top, 6, 3), k, prog, fam, true)
			"m":
				for k in lanes:
					_draw_slice(Rect2(64 + k * 6.0, 44, 4, 10), k, prog, fam, false)
			"l":
				for k in lanes:
					_draw_slice(Rect2(64 + k * 7.0, 98, 5, 14), k, prog, fam, false)
		_draw_silk(size_key)

	## One lane slice: die body + hover frame, busy fill inset 0.75 px. `horizontal` fills
	## left-to-right (S column); the M/L rows fill bottom-up.
	func _draw_slice(rect: Rect2, k: int, prog: Array, fam: Color, horizontal: bool) -> void:
		SystemsDraw.rrect(self, rect, 0.5, Palette.MATERIAL_DIE)
		SystemsDraw.rrect_outline(self, rect, 0.5, Color(Palette.MACHINE_FRAME_HOVER, 0.8), 0.75)
		var fill := float(prog[k]) if k < prog.size() else 0.0
		if fill <= 0.0:
			return
		var inner := Rect2(rect.position + Vector2(0.75, 0.75), rect.size - Vector2(1.5, 1.5))
		var col := Color(fam, 0.85)
		if horizontal:
			SystemsDraw.rrect(self, Rect2(inner.position, Vector2(inner.size.x * clampf(fill, 0.0, 1.0), inner.size.y)), 0.5, col)
		else:
			var h := inner.size.y * clampf(fill, 0.0, 1.0)
			SystemsDraw.rrect(self, Rect2(inner.position.x, inner.end.y - h, inner.size.x, h), 0.5, col)

	## "MK2" / "MK3" / "MK4" silk (M/L only); at rot == 2 the body is upside down, so the
	## string is drawn rotated 180° about its own centre to stay upright.
	func _draw_silk(size_key: String) -> void:
		var label := ""
		var pos := Vector2.ZERO
		match size_key:
			"m":
				label = "MK" + str({2: "2", 4: "3", 8: "4"}[lanes])
				pos = Vector2(18, 53)
			"l":
				label = "MK" + str({2: "2", 4: "3", 8: "4"}[lanes])
				pos = Vector2(16, 110)
			_:
				return
		var f := TclTheme.font("ExtraBold")
		var col := Color(Palette.MATERIAL_SILK, 0.5)
		pos.y += f.get_ascent(7)  # Penpot places the text box's top; draw_string takes the baseline
		if rot == 2:
			var size := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7)
			var center := pos + Vector2(size.x * 0.5, -f.get_ascent(7) + size.y * 0.5)
			draw_set_transform(center, PI, Vector2.ONE)
			draw_string(f, Vector2(-size.x * 0.5, f.get_ascent(7) - size.y * 0.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_string(f, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)


## Machine chassis contacts (P5b): the north thermal pickup and the south power teeth, drawn
## in board space (a child of the MachineView, not the rotating Body). Placement aid for
## ghosts; never drawn for locked machines or power/thermal parts.
class MachineContacts extends Node2D:
	var machine: Machine
	var _key := ""

	## Recompute the key on a new tick or a layout change; redraw only on change.
	func refresh(new_tick: bool) -> void:
		if not new_tick:
			return
		var key := _make_key()
		if key != _key:
			_key = key
			queue_redraw()

	## Key = the tapped power-teeth mask + the heat stage (both change per tick / layout).
	func _make_key() -> String:
		var m := machine
		var sim := SimulationManager.sim
		var pn: PowerNetwork = sim.power_net if sim != null else null
		var mask := 0
		if pn != null and int(m.def().get("power", 0)) > 0:
			var s := Catalog.size_of(m.type, m.rot)
			var tapped: Array = pn.tapped_contacts(m.id)
			for k in s.x:
				if Vector2i(m.cell.x + k, m.cell.y + s.y) in tapped:
					mask |= 1 << k
		return "%d|%d" % [mask, m.heat_stage]

	func _draw() -> void:
		var m := machine
		var d := m.def()
		var s := Catalog.size_of(m.type, m.rot)
		var W := float(s.x) * T
		var H := float(s.y) * T
		if int(d.get("heat", 0)) > 0:
			_draw_thermal_pickup(W, H)
		if int(d.get("power", 0)) > 0:
			_draw_power_teeth(W, H, s)

	## North-edge thermal pickup: vent recess + copper plate, amber wash by heat stage.
	func _draw_thermal_pickup(W: float, H: float) -> void:
		var cx := 64.0 if W == 128.0 and H == 128.0 else 32.0
		var recess := Rect2(cx - 14, 2, 28, 7)
		SystemsDraw.rrect(self, recess, 1.5, Palette.MATERIAL_VENT)
		SystemsDraw.rrect_outline(self, recess, 1.5, Palette.MATERIAL_FRAME, 0.75)
		var plate := Rect2(cx - 12, 3.5, 24, 4)
		SystemsDraw.rrect(self, plate, 1.0, Color(Palette.MATERIAL_COPPER, 0.75))
		var hot := _hot_alpha(machine.heat_stage)
		if hot > 0.0:
			SystemsDraw.rrect(self, plate, 1.0, Color(Palette.STATE_BLOCKED, hot * 0.4))

	static func _hot_alpha(stage: int) -> float:
		match stage:
			ThermalGrid.Stage.WARM: return 0.35
			ThermalGrid.Stage.HOT: return 0.7
			ThermalGrid.Stage.THROTTLING, ThermalGrid.Stage.CRITICAL: return 1.0
		return 0.0

	## South-edge power teeth: one 3-tooth gold group per footprint tile column, lit when the
	## contact tile south of that column is tapped by the live power network.
	func _draw_power_teeth(W: float, H: float, s: Vector2i) -> void:
		var sim := SimulationManager.sim
		var pn: PowerNetwork = sim.power_net if sim != null else null
		var tapped: Array = pn.tapped_contacts(machine.id) if pn != null else []
		for k in s.x:
			var lit := Vector2i(machine.cell.x + k, machine.cell.y + s.y) in tapped
			var origin := Vector2(32.0 + 64.0 * k - 8.0, H - 5.0)
			for i in 3:
				var tooth := Rect2(origin + Vector2(1.0 + i * 5.5, 0.0), Vector2(3.5, 4.0))
				SystemsDraw.rrect(self, tooth, 0.5, Color(Palette.MATERIAL_GOLD, 0.95 if lit else 0.4))