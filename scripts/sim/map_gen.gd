extends RefCounted
## Deterministik, dikey orta eksene gore aynali harita ureteci.
## Iki uc da ayni seed'den BIREBIR ayni grid'i uretmek zorunda (map_hash ile
## dogrulanir); o yuzden tum rastgelelik tek seed'li RNG'den akar.

const D := preload("res://scripts/autoload/defs.gd")


static func generate(seed_v: int) -> Dictionary:
	var w := D.MAP_W
	var h := D.MAP_H
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var map_type := absi(seed_v) % 3   # seed harita tipini de belirler

	var grid := PackedInt32Array()
	grid.resize(w * h)
	grid.fill(D.Tile.GRASS)

	var cl := w / 2 - 1    # orta eksenin sol kolonu (23)
	var cr := w / 2        # orta eksenin sag kolonu (24)
	var bridge_rows: Array[int] = []

	match map_type:
		D.MapType.RIVER:
			# --- nehir: orta iki kolon + simetrik rastgele genisleme ---
			for y in h:
				grid[y * w + cl] = D.Tile.WATER
				grid[y * w + cr] = D.Tile.WATER
				if rng.randf() < 0.3:
					grid[y * w + (cl - 1)] = D.Tile.WATER
					grid[y * w + (cr + 1)] = D.Tile.WATER
			# --- kopruler: 2-3 adet, aralarinda en az 8 satir ---
			var bridge_count := 2 + (rng.randi() % 2)
			var tries := 0
			while bridge_rows.size() < bridge_count and tries < 200:
				tries += 1
				var y := rng.randi_range(6, h - 7)
				var ok := true
				for prev in bridge_rows:
					if absi(y - prev) < 8:
						ok = false
						break
				if ok:
					bridge_rows.append(y)
			if bridge_rows.size() < bridge_count:
				var fallback: Array[int] = [12, 24, 36]
				bridge_rows.assign(fallback.slice(0, bridge_count))
			bridge_rows.sort()
			for y in bridge_rows:
				for x in range(cl - 1, cr + 2):
					if grid[y * w + x] == D.Tile.WATER:
						grid[y * w + x] = D.Tile.BRIDGE
		D.MapType.LAKE:
			# --- merkez gol: ust/alt kiyilardan dolasilir, kopru yok ---
			var rx := 6.0 + rng.randf() * 4.0
			var ry := 6.0 + rng.randf() * 4.0
			var cx := (w - 1) / 2.0
			var cy := (h - 1) / 2.0
			for y in h:
				for x in range(0, cl + 1):
					var dx := (float(x) - cx) / rx
					var dy := (float(y) - cy) / ry
					if dx * dx + dy * dy <= 1.0:
						grid[y * w + x] = D.Tile.WATER
		D.MapType.PLAINS:
			pass   # su yok: acik ova, dogrudan cephe

	# --- spawn'lar: belediye 2x2'nin sol-ust kosesi ---
	var spawn1 := Vector2i(4, h / 2 - 1)
	var spawn2 := Vector2i(w - 4 - 2, h / 2 - 1)
	var center1 := spawn1 + Vector2i(1, 1)

	# --- garanti baslangic kaynaklari: spawn yakini orman + tas ---
	_walk_blob(rng, grid, cl, Vector2i(center1.x + 1, center1.y - 7), D.Tile.FOREST, 12, center1)
	_walk_blob(rng, grid, cl, Vector2i(center1.x + 1, center1.y + 7), D.Tile.STONE, 7, center1)

	# --- sol yariya dagilmis orman/tas alanlari (ovada daha bol) ---
	var forest_blobs := 11 if map_type == D.MapType.PLAINS else 7
	var stone_blobs := 4 if map_type == D.MapType.PLAINS else 3
	for _i in forest_blobs:
		var start := Vector2i(rng.randi_range(1, cl - 2), rng.randi_range(1, h - 2))
		_walk_blob(rng, grid, cl, start, D.Tile.FOREST, rng.randi_range(6, 14), center1)
	for _i in stone_blobs:
		var start := Vector2i(rng.randi_range(1, cl - 2), rng.randi_range(1, h - 2))
		_walk_blob(rng, grid, cl, start, D.Tile.STONE, rng.randi_range(3, 6), center1)

	# --- aynala: sol yari [0..cl] -> sag yari ---
	for y in h:
		for x in range(0, cl + 1):
			grid[y * w + (w - 1 - x)] = grid[y * w + x]

	return {
		"grid": grid,
		"spawns": [spawn1, spawn2],
		"bridge_rows": bridge_rows,
		"map_type": map_type,
		"hash": hash(grid),
	}


static func _walk_blob(rng: RandomNumberGenerator, grid: PackedInt32Array, cl: int,
		start: Vector2i, kind: int, size: int, avoid_center: Vector2i) -> void:
	## start'tan rastgele yuruyup cim hucrelere kind boyar; sol yari sinirinda
	## kalir ve spawn temiz bolgesine girmez. (rng cagri SAYISI sabit: size adim)
	var w := D.MAP_W
	var h := D.MAP_H
	var cur := start
	for _i in size:
		if cur.x >= 1 and cur.x <= cl - 2 and cur.y >= 1 and cur.y <= h - 2:
			var chev := maxi(absi(cur.x - avoid_center.x), absi(cur.y - avoid_center.y))
			if chev > D.SPAWN_CLEAR_RADIUS and grid[cur.y * w + cur.x] == D.Tile.GRASS:
				grid[cur.y * w + cur.x] = kind
		var dirs := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
		cur += dirs[rng.randi() % 4]
		cur.x = clampi(cur.x, 1, cl - 2)
		cur.y = clampi(cur.y, 1, h - 2)


static func walkable(tile: int) -> bool:
	## BRIDGE/FOREST/STONE/GRASS yurunebilir; isciler kaynak tile'inin ustunde durur.
	return tile == D.Tile.GRASS or tile == D.Tile.BRIDGE \
		or tile == D.Tile.FOREST or tile == D.Tile.STONE
