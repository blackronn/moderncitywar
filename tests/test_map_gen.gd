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
		var first_gold := Vector2i(-1, -1)
		for y in D.MAP_H:
			for x in range(mid - D.NEUTRAL_HALF_W, mid + D.NEUTRAL_HALF_W):
				if grid[y * D.MAP_W + x] == D.Tile.GOLD:
					gold_n += 1
					if first_gold == Vector2i(-1, -1):
						first_gold = Vector2i(x, y)
		if gold_n < 2:
			errs.append("seed %d: tarafsiz bolgede altin yok (%d)" % [seed_v, gold_n])

		# CABA kurali: nehir/golde altin adada -> koprusuz ULASILMAZ;
		# ova/karda dag cemberi var (gecitlerden gidilir)
		if first_gold != Vector2i(-1, -1):
			var pg := Pathing.new()
			pg.setup(grid)
			if map_type == D.MapType.RIVER or map_type == D.MapType.LAKE:
				if not pg.find(spawns[0], first_gold).is_empty():
					errs.append("seed %d: altina koprusuz ulasilabiliyor (ada delik)" % seed_v)
			elif map_type == D.MapType.SNOW or map_type == D.MapType.PLAINS:
				var mtn := 0
				for i in grid.size():
					if grid[i] == D.Tile.MOUNTAIN:
						mtn += 1
				if mtn < 8:
					errs.append("seed %d: altin cevresinde dag cemberi yok (%d)" % [seed_v, mtn])
				if pg.find(spawns[0], first_gold).is_empty():
					errs.append("seed %d: altina gecitlerden ulasilamiyor" % seed_v)

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

	# === 4 OYUNCULU uretim: iki eksende simetri + 4 spawn + baglanti ===
	for seed_v in [40, 41, 42, 43, 44]:
		var g4 := MapGen.generate(seed_v, 4)
		var grid4: PackedInt32Array = g4["grid"]
		var spawns4: Array = g4["spawns"]
		if spawns4.size() != 4:
			errs.append("4p seed %d: 4 spawn bekleniyordu, %d" % [seed_v, spawns4.size()])
			continue
		# determinizm
		if g4["hash"] != MapGen.generate(seed_v, 4)["hash"]:
			errs.append("4p seed %d: deterministik degil" % seed_v)
		# x VE y simetrisi
		for y in D.MAP_H:
			for x in D.MAP_W:
				if grid4[y * D.MAP_W + x] != grid4[y * D.MAP_W + (D.MAP_W - 1 - x)]:
					errs.append("4p seed %d: x-aynasi bozuk" % seed_v)
					y = D.MAP_H
					break
		for y in range(0, D.MAP_H / 2):
			for x in D.MAP_W:
				if grid4[y * D.MAP_W + x] != grid4[(D.MAP_H - 1 - y) * D.MAP_W + x]:
					errs.append("4p seed %d: y-aynasi bozuk" % seed_v)
					y = D.MAP_H
					break
		# 4 spawn da insa edilebilir zemin
		for s: Vector2i in spawns4:
			for dy in 2:
				for dx in 2:
					var t4 := grid4[(s.y + dy) * D.MAP_W + (s.x + dx)]
					if not D.BUILDABLE_TILES.has(t4):
						errs.append("4p seed %d: spawn %s zemin degil" % [seed_v, s])
		# altin var ve TUM harita baglantili (savas grid'i): P1 -> P3 ve P1 -> P2
		var p4 := Pathing.new()
		p4.setup(grid4, 4)
		if p4.find(spawns4[0], spawns4[2]).is_empty():
			errs.append("4p seed %d: ust-alt baglanti yok" % seed_v)
		if p4.find(spawns4[0], spawns4[1]).is_empty():
			errs.append("4p seed %d: sol-sag baglanti yok" % seed_v)
		var gold4 := 0
		for i in grid4.size():
			if grid4[i] == D.Tile.GOLD:
				gold4 += 1
		if gold4 < 2:
			errs.append("4p seed %d: altin yok" % seed_v)

	return errs
