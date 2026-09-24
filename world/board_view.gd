class_name BoardView
extends Node2D
## Draws the mission board substrate (Slice A4a part 2): BG_BOARD fill, 1 px grid with the
## every-4th line major emphasis, a 2 px board zone edge, and 3-5 sparse board decals
## (assets/art/board/*.svg at 35 % alpha on empty tiles, placed deterministically from a
## hash of the mission id so a mission always looks the same). Everything outside the board
## rect is BG_VOID. Read-only over the Simulation.

const T := Palette.TILE  # 64
const DECAL_ALPHA := 0.35  # BoardDecal opacity cap (VISUAL_SYSTEM §16: stays below player wires)
const VOID_MARGIN := 4000.0  # BG_VOID backdrop drawn around the board rect
const REVEAL_DURATION := 2.5  # s, lab-expansion build reveal (fade out)
const REVEAL_TINT := 0.10  # STATE_BUILD tint on newly added tiles
const REVEAL_BORDER := 0.40  # STATE_BUILD border alpha on the new-area edge
const DECAL_FILES := [
	"board/decal_zone.svg",
	"board/decal_tracebundle.svg",
	"board/decal_vias.svg",
	"board/decal_fiducial.svg",
	"board/decal_mounthole.svg",
	"board/decal_silkmark.svg",
]

## Board ambience master switch (MOTION_SYSTEM §9). Set false to disable all ambience.
const AMBIENCE := true
## TraceBundle decal line polylines in decal-local px (from assets/art/board/decal_tracebundle.svg).
const TRACEBUNDLE_LINES := [
	[Vector2(0, 16), Vector2(110, 16), Vector2(150, 56), Vector2(256, 56)],
	[Vector2(0, 26), Vector2(100, 26), Vector2(140, 66), Vector2(256, 66)],
	[Vector2(0, 36), Vector2(90, 36), Vector2(130, 76), Vector2(256, 76)],
]
## Via positions in decal-local px (from assets/art/board/decal_vias.svg).
const VIAS := [Vector2(12.5, 12.5), Vector2(32.5, 16.5), Vector2(20.5, 36.5), Vector2(48.5, 40.5), Vector2(34.5, 56.5)]
const SWEEP_SPEED := 120.0  # px/s
const SWEEP_LEN := 24.0  # px
const VIA_DURATION := 1.2  # s
const VIA_DOT_R := 1.5  # 3 px dot

## Lab-expansion reveal state (views only READ the sim; the animation clock is local).
var _prev_size := Vector2i.ZERO
var _reveal_old := Vector2i.ZERO
var _reveal_start := -1.0

## Board ambience state (deterministic per board size + mission id, never the simulation).
var _amb_rng := RandomNumberGenerator.new()
var _amb_key := ""
var _trace_rect := Rect2()  # world rect of the placed TraceBundle decal (empty if none)
var _vias_rect := Rect2()  # world rect of the placed vias decal (empty if none)
var _sweep_active := false
var _sweep_t := 0.0
var _sweep_interval := 8.0
var _sweep_line := PackedVector2Array()
var _sweep_len := 0.0
var _sweep_pos := 0.0
var _via_active := false
var _via_t := 0.0
var _via_interval := 3.0
var _via_elapsed := 0.0
var _via_pos := Vector2.ZERO
var _vignette: CanvasLayer
## Success sweep (MOTION_SYSTEM §6): a state.valid band at 12 % crosses the board left → right in
## 450 ms when a mission passes or a Lab level is complete.
const SUCCESS_SWEEP := 0.45
var _success_start := -1.0
var _success_level := -1


func _ready() -> void:
	SimulationManager.run_finished.connect(func(status: int):
		if status == MissionRun.Status.PASS:
			_start_success())
	if not AMBIENCE:
		return
	_vignette = CanvasLayer.new()
	_vignette.name = "AmbienceVignette"
	_vignette.layer = 1  # above the world canvas, below the HUD (added after World in main.tscn)
	add_child(_vignette)
	var v := Vignette.new()
	v.name = "Vignette"
	_vignette.add_child(v)

## Draws from SimulationManager.sim; deterministic per mission, decals never sit under a
## machine that is on the board at layout time.
func _draw() -> void:
	var sim := SimulationManager.sim
	var size := sim.size if sim != null else Vector2i(16, 10)
	var board := Rect2(Vector2.ZERO, Vector2(size) * T)
	var center := board.get_center()
	draw_rect(Rect2(center - Vector2.ONE * VOID_MARGIN, Vector2.ONE * VOID_MARGIN * 2.0), Palette.BG_VOID)
	draw_rect(board, Palette.BG_BOARD)
	# grid lines: minor on every tile boundary, the every-4th line uses BG_GRID_MAJOR
	for i in range(size.x + 1):
		var x := float(i * T)
		var c := Palette.BG_GRID_MAJOR if i % 4 == 0 else Palette.BG_GRID
		draw_line(Vector2(x, 0.0), Vector2(x, board.size.y), c, 1.0)
	for j in range(size.y + 1):
		var y := float(j * T)
		var c := Palette.BG_GRID_MAJOR if j % 4 == 0 else Palette.BG_GRID
		draw_line(Vector2(0.0, y), Vector2(board.size.x, y), c, 1.0)
	# 2 px zone edge border
	draw_rect(board, Palette.BOARD_ZONE_EDGE, false, 2.0)
	_draw_reveal(sim, size, board)
	_draw_decals(sim, size, board)
	_draw_ambience(board)
	_draw_success(board)


func _start_success() -> void:
	if HudKit.REDUCED_MOTION:
		return
	_success_start = Time.get_ticks_msec() / 1000.0


func _draw_success(board: Rect2) -> void:
	if _success_start < 0.0:
		return
	var el := Time.get_ticks_msec() / 1000.0 - _success_start
	if el >= SUCCESS_SWEEP:
		_success_start = -1.0
		return
	var bw := board.size.x * 0.25
	var cx := lerpf(-bw, board.size.x + bw, 1.0 - pow(1.0 - el / SUCCESS_SWEEP, 3.0))  # cubic-out
	var x0 := clampf(cx - bw, 0.0, board.size.x)
	var x1 := clampf(cx, 0.0, board.size.x)
	var x2 := clampf(cx + bw, 0.0, board.size.x)
	var c0 := Color(Palette.STATE_VALID, 0.0)
	var c1 := Color(Palette.STATE_VALID, 0.12)
	var h := board.size.y
	if x1 > x0:
		draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, h), Vector2(x0, h)]), PackedColorArray([c0, c1, c1, c0]))
	if x2 > x1:
		draw_polygon(PackedVector2Array([Vector2(x1, 0), Vector2(x2, 0), Vector2(x2, h), Vector2(x1, h)]), PackedColorArray([c1, c0, c0, c1]))


## Lab-expansion reveal: when the board grows (level-up), newly added tiles get a STATE_BUILD
## tint + a 1 px border along the new area's edge, both fading out over REVEAL_DURATION.
## The clock is local to this view; it only reads the simulation's size.
func _draw_reveal(_sim, size: Vector2i, _board: Rect2) -> void:
	if _reveal_start < 0.0:
		return
	var elapsed := (Time.get_ticks_msec() / 1000.0) - _reveal_start
	if elapsed >= REVEAL_DURATION:
		_reveal_start = -1.0
		return
	var a := 1.0 - elapsed / REVEAL_DURATION
	var old := Vector2(_reveal_old) * T
	# New tiles form the right strip and the bottom strip beyond the old board.
	if size.x > _reveal_old.x:
		var x := float(_reveal_old.x) * T
		draw_rect(Rect2(Vector2(x, 0.0), Vector2(size.x * T - x, size.y * T)), Color(Palette.STATE_BUILD, REVEAL_TINT * a))
	if size.y > _reveal_old.y:
		var y := float(_reveal_old.y) * T
		draw_rect(Rect2(Vector2(0.0, y), Vector2(old.x, size.y * T - y)), Color(Palette.STATE_BUILD, REVEAL_TINT * a))
	# 1 px STATE_BUILD border along the new area's inner edge (the L-shape between old/new).
	var border := Color(Palette.STATE_BUILD, REVEAL_BORDER * a)
	if size.x > _reveal_old.x:
		draw_line(Vector2(old.x, 0.0), Vector2(old.x, size.y * T), border, 1.0)
	if size.y > _reveal_old.y:
		draw_line(Vector2(0.0, old.y), Vector2(old.x, old.y), border, 1.0)


func _process(delta: float) -> void:
	var sim := SimulationManager.sim
	if sim == null:
		return
	# Detect a board-size growth (lab level-up) and start the reveal for the new region.
	if sim.size != _prev_size:
		if sim.size.x > _prev_size.x or sim.size.y > _prev_size.y:
			_reveal_old = _prev_size
			_reveal_start = Time.get_ticks_msec() / 1000.0
		_prev_size = sim.size
	if _reveal_start >= 0.0:
		queue_redraw()  # drive the fade
	var lr = SimulationManager.lab_run
	if lr != null:
		if _success_level >= 0 and lr.level > _success_level:
			_start_success()  # a Lab level is complete
		_success_level = lr.level
	else:
		_success_level = -1
	if _success_start >= 0.0:
		queue_redraw()
	_update_ambience(delta, sim)


## Mission-id-seeded scatter of 3-5 sparse decals on empty tiles.
func _draw_decals(sim, size: Vector2i, board: Rect2) -> void:
	var mission_id := SimulationManager.mission.id if SimulationManager.mission != null else "default"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(mission_id)
	var count: int = 3 + absi(hash(mission_id + ":decal_count")) % 3  # 3..5 decals
	var placed := 0
	var used := []
	for attempt in 80:
		if placed >= count:
			break
		var tile := Vector2i(rng.randi() % maxi(size.x, 1), rng.randi() % maxi(size.y, 1))
		if _occupied_by_machine(sim, tile):
			continue
		var rel: String = DECAL_FILES[rng.randi() % DECAL_FILES.size()]
		if rel in used and attempt < 60:  # prefer variety; repeats only when nothing else fits
			continue
		var t := Art.tex(rel)
		if t == null:
			continue
		var scaled := Vector2(t.get_width() / Art.SCALE, t.get_height() / Art.SCALE)
		var rect := Rect2(board.position + Vector2(tile) * T + (Vector2(T, T) - scaled) / 2.0, scaled)
		# The whole decal stays inside the board and one tile clear of every machine.
		if not board.encloses(rect) or _near_machine(sim, rect, board):
			continue
		draw_texture_rect(t, rect, false, Color(1.0, 1.0, 1.0, DECAL_ALPHA))
		used.append(rel)
		placed += 1
		# Remember where the ambience-relevant decals landed (trace sweep / via twinkle).
		if rel == "board/decal_tracebundle.svg" and _trace_rect.size == Vector2.ZERO:
			_trace_rect = rect
		elif rel == "board/decal_vias.svg" and _vias_rect.size == Vector2.ZERO:
			_vias_rect = rect


func _occupied_by_machine(sim, tile: Vector2i) -> bool:
	if sim == null:
		return false
	for id in sim.sorted_machine_ids():
		if tile in sim.machines[id].footprint():
			return true
	return false


func _near_machine(sim, rect: Rect2, board: Rect2) -> bool:
	if sim == null:
		return false
	var grown := rect.grow(T)
	for id in sim.sorted_machine_ids():
		for c in sim.machines[id].footprint():
			if grown.intersects(Rect2(board.position + Vector2(c) * T, Vector2(T, T))):
				return true
	return false


func redraw() -> void:
	queue_redraw()


# ------------------------------------------------------------------ board ambience (MOTION_SYSTEM §9)

## Reseed the ambience RNG when the board size or mission/level changes. Deterministic per
## (size, mission id) so a board always ambiences the same way; never the simulation.
func _amb_seed_key(sim) -> String:
	var mission_id := SimulationManager.mission.id if SimulationManager.mission != null else "default"
	return "%dx%d:%s" % [sim.size.x, sim.size.y, mission_id]


func _update_ambience(delta: float, sim) -> void:
	if not AMBIENCE:
		return
	var key := _amb_seed_key(sim)
	if key != _amb_key:
		_amb_key = key
		_amb_rng.seed = hash(key)
	var running := SimulationManager.running
	var redraw := false
	# Trace sweep: at most one at a time; travels at SWEEP_SPEED along the chosen line.
	if _sweep_active:
		_sweep_pos += SWEEP_SPEED * delta
		if _sweep_pos >= _sweep_len:
			_sweep_active = false
			_sweep_t = 0.0
			_sweep_interval = _amb_rng.randf_range(8.0, 12.0) * (0.7 if running else 1.0)
		else:
			redraw = true
	else:
		_sweep_t += delta
		if _sweep_t >= _sweep_interval:
			_start_sweep(sim)
			redraw = true
	# Via twinkle: one via at a time brightens over VIA_DURATION.
	if _via_active:
		_via_elapsed += delta
		if _via_elapsed >= VIA_DURATION:
			_via_active = false
			_via_t = 0.0
			_via_interval = _amb_rng.randf_range(3.0, 6.0)
		else:
			redraw = true
	else:
		_via_t += delta
		if _via_t >= _via_interval:
			_start_via()
			redraw = true
	if redraw:
		queue_redraw()


func _start_sweep(sim) -> void:
	var line := PackedVector2Array()
	if _trace_rect.size != Vector2.ZERO:
		# One of the TraceBundle decal's lines, in world space.
		var local: Array = TRACEBUNDLE_LINES[_amb_rng.randi() % TRACEBUNDLE_LINES.size()]
		line = PackedVector2Array()
		for p in local:
			line.append(_trace_rect.position + p)
	else:
		# Fallback: a random major grid line segment of 6-10 tiles.
		var horizontal := _amb_rng.randf() < 0.5
		var tiles := _amb_rng.randi_range(6, 10)
		var a := Vector2.ZERO
		var b := Vector2.ZERO
		if horizontal:
			tiles = mini(tiles, maxi(sim.size.x, 1))
			var row := (_amb_rng.randi() % (maxi(sim.size.y, 1) / 4 + 1)) * 4
			var col0 := _amb_rng.randi() % maxi(sim.size.x - tiles + 1, 1)
			a = Vector2(col0 * T, row * T)
			b = Vector2((col0 + tiles) * T, row * T)
		else:
			tiles = mini(tiles, maxi(sim.size.y, 1))
			var col := (_amb_rng.randi() % (maxi(sim.size.x, 1) / 4 + 1)) * 4
			var row0 := _amb_rng.randi() % maxi(sim.size.y - tiles + 1, 1)
			a = Vector2(col * T, row0 * T)
			b = Vector2(col * T, (row0 + tiles) * T)
		line = PackedVector2Array([a, b])
	_sweep_line = line
	_sweep_len = _pline_len(line)
	_sweep_pos = 0.0
	_sweep_active = _sweep_len > 0.0


func _start_via() -> void:
	if _vias_rect.size == Vector2.ZERO:
		_via_interval = _amb_rng.randf_range(3.0, 6.0)  # no vias: wait and retry
		return
	var local: Vector2 = VIAS[_amb_rng.randi() % VIAS.size()]
	_via_pos = _vias_rect.position + local
	_via_elapsed = 0.0
	_via_active = true


func _draw_ambience(_board: Rect2) -> void:
	if not AMBIENCE:
		return
	# Trace sweep band: DATA_NUMBER α .06, 24 px long, 2 px wide, round caps.
	if _sweep_active and _sweep_line.size() >= 2:
		var head := _pline_pt(_sweep_line, _sweep_pos)
		var tail := _pline_pt(_sweep_line, maxf(0.0, _sweep_pos - SWEEP_LEN))
		draw_polyline(PackedVector2Array([tail, head]), Color(Palette.DATA_NUMBER, 0.06), 2.0, true)
	# Via twinkle: a 3 px dot of DATA_NUMBER brightening α .04 → .1 → .04 over VIA_DURATION.
	if _via_active:
		var ph := clampf(_via_elapsed / VIA_DURATION, 0.0, 1.0)
		var a: float
		if ph < 0.5:
			a = 0.04 + (0.1 - 0.04) * (ph / 0.5)
		else:
			a = 0.1 - (0.1 - 0.04) * ((ph - 0.5) / 0.5)
		draw_circle(_via_pos, VIA_DOT_R, Color(Palette.DATA_NUMBER, a))


static func _pline_len(pts: PackedVector2Array) -> float:
	var d := 0.0
	for i in range(1, pts.size()):
		d += pts[i].distance_to(pts[i - 1])
	return d


static func _pline_pt(pts: PackedVector2Array, s: float) -> Vector2:
	var d := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i] - pts[i - 1]
		var l := seg.length()
		if l <= 0.0:
			continue
		if d + l >= s:
			return pts[i - 1] + seg * ((s - d) / l)
		d += l
	return pts[pts.size() - 1]


# ------------------------------------------------------------------ vignette

## Static radial vignette over the viewport edges (MOTION_SYSTEM §9): BG_VOID α .35 at the
## corners → 0 at 60 % radius. Lives in a CanvasLayer above the world / below the HUD,
## ignores the mouse, and scales with the window.
class Vignette extends Control:
	var _tex: GradientTexture2D

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		g.colors = PackedColorArray([Color(Palette.BG_VOID, 0.0), Color(Palette.BG_VOID, 0.0), Color(Palette.BG_VOID, 0.35)])
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.fill = GradientTexture2D.FILL_RADIAL
		resized.connect(queue_redraw)

	func _draw() -> void:
		if _tex == null:
			return
		var s := size
		if s.x <= 1.0 or s.y <= 1.0:
			return
		if _tex.width != int(s.x) or _tex.height != int(s.y):
			_tex.width = int(ceil(s.x))
			_tex.height = int(ceil(s.y))
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, s), false)