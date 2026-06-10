extends RefCounted
## Yol bulma sarmalayicisi: hedefte bitme, bina engeli, nearest_free.

const D := preload("res://scripts/autoload/defs.gd")
const MapGen := preload("res://scripts/sim/map_gen.gd")
const Pathing := preload("res://scripts/sim/pathing.gd")


func run() -> Array:
	var errs: Array = []
	var g := MapGen.generate(7)
	var grid: PackedInt32Array = g["grid"]
	var spawns: Array = g["spawns"]
	var p := Pathing.new()
	p.setup(grid)

	var a: Vector2i = spawns[0]
	var b: Vector2i = spawns[1]

	var path := p.find(a, b)
	if path.is_empty():
		errs.append("yol bulunamadi")
	elif path[path.size() - 1] != b:
		errs.append("yol hedefte bitmiyor: %s" % str(path[path.size() - 1]))

	# bina engeli: spawn yani temiz cim (radius 5) -> 2x2 koy, solid olsun
	var site := a + Vector2i(0, 3)
	p.set_rect_solid(site, Vector2i(2, 2), true)
	if not p.is_solid(site) or not p.is_solid(site + Vector2i(1, 1)):
		errs.append("set_rect_solid hucreleri kapatmadi")
	var nf := p.nearest_free(site, 3)
	if nf == Vector2i(-1, -1) or p.is_solid(nf):
		errs.append("nearest_free bos hucre bulamadi")
	# kapali hedefe yol istenince bitisige yonlenmeli
	var to_blocked := p.find(a, site)
	if to_blocked.is_empty():
		errs.append("kapali hedef icin bitisik yol bulunamadi")
	elif p.is_solid(to_blocked[to_blocked.size() - 1]):
		errs.append("kapali hedefe giden yol solid hucrede bitti")
	p.set_rect_solid(site, Vector2i(2, 2), false)
	if p.is_solid(site):
		errs.append("set_rect_solid geri acmadi")

	# su gecilmez: nehir ortasina yol istenince bos donmemeli ama suya basmamali
	var river_cell := Vector2i(D.MAP_W / 2, 5)
	var to_water := p.find(a, river_cell)
	for pt in to_water:
		if grid[pt.y * D.MAP_W + pt.x] == D.Tile.WATER:
			errs.append("yol su hucresinden gecti: %s" % str(pt))
			break

	return errs
