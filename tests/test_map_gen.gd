extends RefCounted
## Harita ureteci: determinizm, ayna simetrisi, kopru sayisi, baglanti.

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

	for seed_v in [1, 42, 1337, 99999, 123456]:
		var g := MapGen.generate(seed_v)
		var grid: PackedInt32Array = g["grid"]
		var spawns: Array = g["spawns"]

		# ayna simetrisi
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

		# kopru satir sayisi 2-3
		var bridge_rows := {}
		for y in D.MAP_H:
			for x in D.MAP_W:
				if grid[y * D.MAP_W + x] == D.Tile.BRIDGE:
					bridge_rows[y] = true
		if bridge_rows.size() < 2 or bridge_rows.size() > 3:
			errs.append("seed %d: kopru satiri %d (2-3 olmali)" % [seed_v, bridge_rows.size()])

		# spawn footprint'leri cim
		for s: Vector2i in spawns:
			for dy in 2:
				for dx in 2:
					var t := grid[(s.y + dy) * D.MAP_W + (s.x + dx)]
					if t != D.Tile.GRASS:
						errs.append("seed %d: spawn %s cim degil" % [seed_v, s])

		# baglanti: spawnlar arasi yol var ve koprudan geciyor
		var p := Pathing.new()
		p.setup(grid)
		var path := p.find(spawns[0], spawns[1])
		if path.is_empty():
			errs.append("seed %d: spawnlar arasi yol yok" % seed_v)
		else:
			var crosses := false
			for pt in path:
				if grid[pt.y * D.MAP_W + pt.x] == D.Tile.BRIDGE:
					crosses = true
					break
			if not crosses:
				errs.append("seed %d: yol koprusuz gecmis (nehir delik?)" % seed_v)

		# kopruler kapaninca iki yaka ayrilmali
		for y in D.MAP_H:
			for x in D.MAP_W:
				if grid[y * D.MAP_W + x] == D.Tile.BRIDGE:
					p.astar.set_point_solid(Vector2i(x, y), true)
		if not p.find(spawns[0], spawns[1]).is_empty():
			errs.append("seed %d: kopru olmadan da yol var" % seed_v)

	return errs
