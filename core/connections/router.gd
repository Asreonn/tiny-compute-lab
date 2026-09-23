class_name Router
extends RefCounted
## Orthogonal PCB-style auto-router. Dijkstra over tiles: 1 per step + penalty per turn,
## so routes prefer long straight runs. Machine tiles are walls; existing wires may be
## crossed (at a small cost) but not run along. Fully deterministic (fixed neighbour order).

const TURN_COST := 3
const CROSS_COST := 4
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]


## start/goal: tiles adjacent to the ports. start_dir/goal_dir: direction leaving the source
## port / entering the target port (used to prefer straight entry).
## Returns [] when no route exists.
static func route(size: Vector2i, blocked: Dictionary, wired: Dictionary, start: Vector2i, start_dir: Vector2i, goal: Vector2i, goal_dir: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not _inside(size, start) or not _inside(size, goal):
		return empty
	if blocked.has(start) or blocked.has(goal):
		return empty
	# state = (cell, dir index); cost map
	var best := {}
	var prev := {}
	var open: Array = []  # [cost, seq, cell, dir]
	var seq := 0
	var sd := DIRS.find(start_dir)
	var k0 := _key(start, sd)
	best[k0] = 0
	open.append([0, seq, start, sd])
	while not open.is_empty():
		# pop min (small boards: linear scan is fine and deterministic)
		var mi := 0
		for i in range(1, open.size()):
			if open[i][0] < open[mi][0] or (open[i][0] == open[mi][0] and open[i][1] < open[mi][1]):
				mi = i
		var cur: Array = open[mi]
		open.remove_at(mi)
		var cost: int = cur[0]
		var cell: Vector2i = cur[2]
		var d: int = cur[3]
		if cost > best.get(_key(cell, d), 1 << 30):
			continue
		if cell == goal:
			return _rebuild(prev, cell, d, start, sd)
		for nd in 4:
			var n := cell + DIRS[nd]
			if not _inside(size, n) or blocked.has(n):
				continue
			var c := cost + 1
			if nd != d:
				c += TURN_COST
				if (nd + 2) % 4 == d:
					continue  # no U-turns
			if wired.has(n):
				c += CROSS_COST
			if n == goal and DIRS[nd] != goal_dir:
				c += TURN_COST  # arriving sideways means one more bend at the port
			var kn := _key(n, nd)
			if c < best.get(kn, 1 << 30):
				best[kn] = c
				prev[kn] = _key(cell, d)
				seq += 1
				open.append([c, seq, n, nd])
	return empty


static func _rebuild(prev: Dictionary, cell: Vector2i, d: int, start: Vector2i, sd: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [cell]
	var k := _key(cell, d)
	var k0 := _key(start, sd)
	while k != k0 and prev.has(k):
		k = prev[k]
		out.push_front(_unkey(k))
	return out


static func _key(c: Vector2i, d: int) -> int:
	return ((c.x + 512) << 12) | ((c.y + 512) << 2) | (d & 3)


static func _unkey(k: int) -> Vector2i:
	return Vector2i(((k >> 12) & 0xFFFFF) - 512, ((k >> 2) & 0x3FF) - 512)


static func _inside(size: Vector2i, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y
