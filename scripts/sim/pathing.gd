extends RefCounted
## AStarGrid2D sarmalayici. Solid: su (kopru haric) + bina footprint'leri.
## Orman/tas yurunebilir (isci kaynak tile'inin ustunde durur).
## Baris sinirlari: her oyuncu icin rakip yarisi kapali ek grid'ler tutulur;
## savas ilan edilmeden birimler orta hatti GECEMEZ.

const D := preload("res://scripts/autoload/defs.gd")
const MapGen := preload("res://scripts/sim/map_gen.gd")

var astar := AStarGrid2D.new()
var astar_half := {}    # pid -> AStarGrid2D (1: x < W/2 serbest, 2: x >= W/2 serbest)


func setup(grid: PackedInt32Array) -> void:
	_setup_one(astar, grid, 0)
	for pid in [1, 2]:
		var a := AStarGrid2D.new()
		_setup_one(a, grid, pid)
		astar_half[pid] = a


func _setup_one(a: AStarGrid2D, grid: PackedInt32Array, half_pid: int) -> void:
	a.region = Rect2i(0, 0, D.MAP_W, D.MAP_H)
	a.cell_size = Vector2(1, 1)
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.update()
	var mid := D.MAP_W / 2
	for y in D.MAP_H:
		for x in D.MAP_W:
			var solid := not MapGen.walkable(grid[y * D.MAP_W + x])
			if half_pid == 1 and x >= mid:
				solid = true
			elif half_pid == 2 and x < mid:
				solid = true
			a.set_point_solid(Vector2i(x, y), solid)


func set_rect_solid(top_left: Vector2i, size: Vector2i, solid: bool) -> void:
	for dy in size.y:
		for dx in size.x:
			var c := top_left + Vector2i(dx, dy)
			if in_bounds(c):
				astar.set_point_solid(c, solid)
				var mid := D.MAP_W / 2
				if c.x < mid:
					astar_half[1].set_point_solid(c, solid)
				else:
					astar_half[2].set_point_solid(c, solid)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < D.MAP_W and c.y < D.MAP_H


func is_solid(c: Vector2i) -> bool:
	return not in_bounds(c) or astar.is_point_solid(c)


func find(from_c: Vector2i, to_c: Vector2i, partial := false, half_pid := 0) -> Array[Vector2i]:
	## Hucre yolu dondurur (bos = ulasilamaz). Hedef/solid baslangic toleransli.
	## partial=true: ulasilamiyorsa en yakin noktaya kadar gider (kovalamaca
	## icin). half_pid 1/2: BARIS grid'i — rakip yari kapali.
	var a: AStarGrid2D = astar if half_pid == 0 else astar_half[half_pid]
	var out: Array[Vector2i] = []
	if not in_bounds(from_c) or not in_bounds(to_c):
		return out
	var start := from_c
	if a.is_point_solid(start):
		start = _nearest_free_on(a, start, 3)
		if start == Vector2i(-1, -1):
			return out
	var goal := to_c
	if a.is_point_solid(goal):
		goal = _nearest_free_on(a, goal, 4)
		if goal == Vector2i(-1, -1):
			return out
	var pts := a.get_id_path(start, goal, partial)
	out.assign(pts)
	return out


func nearest_free(c: Vector2i, max_r: int) -> Vector2i:
	return _nearest_free_on(astar, c, max_r)


func _nearest_free_on(a: AStarGrid2D, c: Vector2i, max_r: int) -> Vector2i:
	## c'den disa dogru halka halka ilk solid olmayan hucre; yoksa (-1,-1).
	if in_bounds(c) and not a.is_point_solid(c):
		return c
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if in_bounds(n) and not a.is_point_solid(n):
					return n
	return Vector2i(-1, -1)
