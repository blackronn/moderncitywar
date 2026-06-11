extends RefCounted
## Deterministik, dikey orta eksene gore aynali harita ureteci.
## Iki uc da ayni seed'den BIREBIR ayni grid'i uretmek zorunda (map_hash ile
## dogrulanir); o yuzden tum rastgelelik tek seed'li RNG'den akar.

const D := preload("res://scripts/autoload/defs.gd")


static func seed_with_type(base: int, map_type: int) -> int:
	## Oylama sonucu secilen tipi seed'e gomer (map_type = seed % 5).
	base = absi(base)
	return base - (base % 5) + clampi(map_type, 0, 4)


static func generate(seed_v: int) -> Dictionary:
	var w := D.MAP_W
	var h := D.MAP_H
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var map_type := absi(seed_v) % 5   # seed harita tipini de belirler

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
		D.MapType.SNOW:
			# kar ovasi: her sey yavaslar (TILE_SPEED), zemin kar
			for i in grid.size():
				grid[i] = D.Tile.SNOW
			# birkac kayalik engebe
			for _i in 3:
				var hs := Vector2i(rng.randi_range(2, cl - 3), rng.randi_range(4, h - 5))
				_walk_blob_kind(rng, grid, cl, hs, D.Tile.HILL, rng.randi_range(5, 9), D.Tile.SNOW)
		D.MapType.VALLEY:
			# vadi: orta gecide bakan kalin kayalik sirtlar, 2 gecit
			var ridge_x := cl - 9
			var gap1 := rng.randi_range(6, 16)
			var gap2 := rng.randi_range(30, 40)
			for y in h:
				if absi(y - gap1) <= 2 or absi(y - gap2) <= 2:
					continue   # gecitler
				for dx in 3:
					grid[y * w + (ridge_x + dx)] = D.Tile.HILL
			# sirt uzerinde tek tuk kaya cikintisi disari
			for _i in 4:
				var hs := Vector2i(ridge_x + rng.randi_range(-2, 4), rng.randi_range(3, h - 4))
				_walk_blob_kind(rng, grid, cl, hs, D.Tile.HILL, rng.randi_range(3, 6), D.Tile.GRASS)

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

	# --- tarafsiz bolge altin rezervleri (orta bant; iki taraf da kazabilir) ---
	var mid := w / 2
	var placed := 0
	var gtries := 0
	while placed < 3 and gtries < 80:
		gtries += 1
		var gx := rng.randi_range(mid - D.NEUTRAL_HALF_W, mid - 2)
		var gy := rng.randi_range(4, h - 5)
		var gi := gy * w + gx
		if grid[gi] == D.Tile.GRASS or grid[gi] == D.Tile.SNOW:
			grid[gi] = D.Tile.GOLD
			if grid[gi + w] == D.Tile.GRASS or grid[gi + w] == D.Tile.SNOW:
				grid[gi + w] = D.Tile.GOLD   # 2'li damar
			placed += 1

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
	## start'tan rastgele yuruyup zemin (cim/kar) hucrelere kind boyar; sol yari
	## sinirinda kalir ve spawn temiz bolgesine girmez. (rng cagri sayisi sabit)
	var w := D.MAP_W
	var h := D.MAP_H
	var cur := start
	for _i in size:
		if cur.x >= 1 and cur.x <= cl - 2 and cur.y >= 1 and cur.y <= h - 2:
			var chev := maxi(absi(cur.x - avoid_center.x), absi(cur.y - avoid_center.y))
			var ground := grid[cur.y * w + cur.x]
			if chev > D.SPAWN_CLEAR_RADIUS and (ground == D.Tile.GRASS or ground == D.Tile.SNOW):
				grid[cur.y * w + cur.x] = kind
		var dirs := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
		cur += dirs[rng.randi() % 4]
		cur.x = clampi(cur.x, 1, cl - 2)
		cur.y = clampi(cur.y, 1, h - 2)


static func _walk_blob_kind(rng: RandomNumberGenerator, grid: PackedInt32Array, cl: int,
		start: Vector2i, kind: int, size: int, base: int) -> void:
	## _walk_blob gibi ama spawn bolgesi kontrolu olmadan, verilen zemine boyar.
	var w := D.MAP_W
	var h := D.MAP_H
	var cur := start
	for _i in size:
		if cur.x >= 1 and cur.x <= cl - 2 and cur.y >= 1 and cur.y <= h - 2:
			if grid[cur.y * w + cur.x] == base:
				grid[cur.y * w + cur.x] = kind
		var dirs := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
		cur += dirs[rng.randi() % 4]
		cur.x = clampi(cur.x, 1, cl - 2)
		cur.y = clampi(cur.y, 1, h - 2)


static func walkable(tile: int) -> bool:
	## Su ve engebe (HILL... HILL yurunur ama yavas; sadece su gecilmez).
	return tile != D.Tile.WATER and tile != -1
