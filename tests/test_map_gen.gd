extends RefCounted
## Harita ureteci: determinizm, ayna simetrisi, tip bazli kurallar, baglanti.

const D := preload("res://scripts/autoload/defs.gd")
const MapGen := preload("res://scripts/sim/map_gen.gd")
const Pathing := preload("res://scripts/sim/pathing.gd")


func run() -> Array:
	var errs: Array = []

	# determinizm
	var a := MapGen.generate(42)
	var b := MapGen.generate(42)
	if a["grid"] != b["grid"]:
		errs.append("ayni seed farkli harita uretti")
	if a["hash"] != b["hash"]:
		errs.append("ayni seed farkli hash uretti")
	var c := MapGen.generate(43)
	if a["hash"] == c["hash"]:
		errs.append("farkli seed ayni hash uretti (supheli)")

	var seen_types := {}
	for seed_v in [40, 41, 42, 43, 44, 1337]:
		var g := MapGen.generate(seed_v)
		var grid: PackedInt32Array = g["grid"]
		var spawns: Array = g["spawns"]
		var map_type: int = g["map_type"]
		seen_types[map_type] = true

		# ayna simetrisi (tum tipler)
		var sym_ok := true
		for y in D.MAP_H:
			for x in D.MAP_W:
				if grid[y * D.MAP_W + x] != grid[y * D.MAP_W + (D.MAP_W - 1 - x)]:
					sym_ok = false
					break
			if not sym_ok:
				break
		if not sym_ok:
			errs.append("seed %d: harita aynali degil" % seed_v)

		# spawn footprint'leri insa edilebilir zemin (cim/kar)
		for s: Vector2i in spawns:
			for dy in 2:
				for dx in 2:
					var t := grid[(s.y + dy) * D.MAP_W + (s.x + dx)]
					if not D.BUILDABLE_TILES.has(t):
						errs.append("seed %d: spawn %s zemin degil" % [seed_v, s])

		# tarafsiz bolgede altin rezervi olmali (tum tipler)
		var gold_n := 0
		var mid := D.MAP_W / 2
		for y in D.MAP_H:
			for x in range(mid - D.NEUTRAL_HALF_W, mid + D.NEUTRAL_HALF_W):
				if grid[y * D.MAP_W + x] == D.Tile.GOLD:
					gold_n += 1
		if gold_n < 2:
			errs.append("seed %d: tarafsiz bolgede altin yok (%d)" % [seed_v, gold_n])

		# baglanti (tum tipler): spawnlar arasi yol var
		var p := Pathing.new()
		p.setup(grid)
		var path := p.find(spawns[0], spawns[1])
		if path.is_empty():
			errs.append("seed %d (tip %d): spawnlar arasi yol yok" % [seed_v, map_type])

		match map_type:
			D.MapType.RIVER:
				# kopru sayisi 2-3
				var bridge_rows := {}
				for y in D.MAP_H:
					for x in D.MAP_W:
						if grid[y * D.MAP_W + x] == D.Tile.BRIDGE:
							bridge_rows[y] = true
				if bridge_rows.size() < 2 or bridge_rows.size() > 3:
					errs.append("seed %d: kopru satiri %d (2-3 olmali)" % [seed_v, bridge_rows.size()])
				# yol koprudan gecmeli
				var crosses := false
				for pt in path:
					if grid[pt.y * D.MAP_W + pt.x] == D.Tile.BRIDGE:
						crosses = true
						break
				if not path.is_empty() and not crosses:
					errs.append("seed %d: yol koprusuz gecmis (nehir delik?)" % seed_v)
				# kopruler kapaninca iki yaka ayrilmali
				for y in D.MAP_H:
					for x in D.MAP_W:
						if grid[y * D.MAP_W + x] == D.Tile.BRIDGE:
							p.astar.set_point_solid(Vector2i(x, y), true)
				if not p.find(spawns[0], spawns[1]).is_empty():
					errs.append("seed %d: kopru olmadan da yol var" % seed_v)
			D.MapType.LAKE:
				# golde su olmali ama kopru olmamali
				var has_water := false
				for i in grid.size():
					if grid[i] == D.Tile.WATER:
						has_water = true
					elif grid[i] == D.Tile.BRIDGE:
						errs.append("seed %d: gol haritasinda kopru olmamali" % seed_v)
						break
				if not has_water:
					errs.append("seed %d: gol haritasinda su yok" % seed_v)
			D.MapType.PLAINS:
				for i in grid.size():
					if grid[i] == D.Tile.WATER or grid[i] == D.Tile.BRIDGE:
						errs.append("seed %d: ova haritasinda su/kopru olmamali" % seed_v)
						break
			D.MapType.SNOW:
				var has_snow := false
				for i in grid.size():
					if grid[i] == D.Tile.SNOW:
						has_snow = true
					elif grid[i] == D.Tile.WATER:
						errs.append("seed %d: kar haritasinda su olmamali" % seed_v)
						break
				if not has_snow:
					errs.append("seed %d: kar haritasinda kar yok" % seed_v)
			D.MapType.VALLEY:
				var has_hill := false
				for i in grid.size():
					if grid[i] == D.Tile.HILL:
						has_hill = true
						break
				if not has_hill:
					errs.append("seed %d: vadi haritasinda engebe yok" % seed_v)

	if seen_types.size() < 5:
		errs.append("test seed'leri 5 harita tipini de kapsamiyor (%d tip)" % seen_types.size())

	return errs
