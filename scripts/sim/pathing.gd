extends RefCounted
## AStarGrid2D sarmalayici. Solid: su (kopru haric) + bina footprint'leri.
## Orman/tas yurunebilir (isci kaynak tile'inin ustunde durur).

const D := preload("res://scripts/autoload/defs.gd")
const MapGen := preload("res://scripts/sim/map_gen.gd")

var astar := AStarGrid2D.new()


func setup(grid: PackedInt32Array) -> void:
	astar.region = Rect2i(0, 0, D.MAP_W, D.MAP_H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in D.MAP_H:
		for x in D.MAP_W:
			astar.set_point_solid(Vector2i(x, y), not MapGen.walkable(grid[y * D.MAP_W + x]))


func set_rect_solid(top_left: Vector2i, size: Vector2i, solid: bool) -> void:
	for dy in size.y:
		for dx in size.x:
			var c := top_left + Vector2i(dx, dy)
			if in_bounds(c):
				astar.set_point_solid(c, solid)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < D.MAP_W and c.y < D.MAP_H


func is_solid(c: Vector2i) -> bool:
	return not in_bounds(c) or astar.is_point_solid(c)


func find(from_c: Vector2i, to_c: Vector2i, partial := false) -> Array[Vector2i]:
	## Hucre yolu dondurur (bos = ulasilamaz). Hedef/solid baslangic toleransli.
	## partial=true: ulasilamiyorsa en yakin noktaya kadar gider (kovalamaca
	## icin); varsayilan false ki "yol var mi" sorusu net cevaplansin.
	var out: Array[Vector2i] = []
	if not in_bounds(from_c) or not in_bounds(to_c):
		return out
	var start := from_c
	if astar.is_point_solid(start):
		start = nearest_free(start, 3)
		if start == Vector2i(-1, -1):
			return out
	var goal := to_c
	if astar.is_point_solid(goal):
		goal = nearest_free(goal, 4)
		if goal == Vector2i(-1, -1):
			return out
	var pts := astar.get_id_path(start, goal, partial)
	out.assign(pts)
	return out


func nearest_free(c: Vector2i, max_r: int) -> Vector2i:
	## c'den disa dogru halka halka ilk solid olmayan hucre; yoksa (-1,-1).
	if in_bounds(c) and not astar.is_point_solid(c):
		return c
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if in_bounds(n) and not astar.is_point_solid(n):
					return n
	return Vector2i(-1, -1)
