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
const DECAL_FILES := [
	"board/decal_zone.svg",
	"board/decal_tracebundle.svg",
	"board/decal_vias.svg",
	"board/decal_fiducial.svg",
	"board/decal_mounthole.svg",
	"board/decal_silkmark.svg",
]

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
	_draw_decals(sim, size, board)


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