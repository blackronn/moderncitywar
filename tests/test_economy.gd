extends RefCounted
## Yerlestirme dogrulamasi (sim.gd'deki saf statik fonksiyon) senaryolari.

const D := preload("res://scripts/autoload/defs.gd")
const MapGen := preload("res://scripts/sim/map_gen.gd")
const Pathing := preload("res://scripts/sim/pathing.gd")
const Sim := preload("res://scripts/sim/sim.gd")


func run() -> Array:
	var errs: Array = []
	# seed % 5 == 0 -> NEHIR tipi (su-ustune-insa senaryosu nehir ister)
	var g := MapGen.generate(40)
	var grid: PackedInt32Array = g["grid"]
	var p := Pathing.new()
	p.setup(grid)
	var spawns: Array = g["spawns"]
	var hall_tl: Vector2i = spawns[0]
	p.set_rect_solid(hall_tl, Vector2i(2, 2), true)
	var own_rects: Array = [Rect2i(hall_tl, Vector2i(2, 2))]
	var house := D.building(&"house")

	var spot := hall_tl + Vector2i(3, 0)
	var v := Sim.validate_placement(grid, p, [], own_rects, house, spot, true)
	if v != -1:
		errs.append("gecerli yer reddedildi: %d" % v)
	v = Sim.validate_placement(grid, p, [], own_rects, house, spot, false)
	if v != D.Reject.NO_RES:
		errs.append("NO_RES beklenirdi: %d" % v)
	v = Sim.validate_placement(grid, p, [], own_rects, house, hall_tl, true)
	if v != D.Reject.BLOCKED:
		errs.append("BLOCKED beklenirdi (bina ustu): %d" % v)
	v = Sim.validate_placement(grid, p, [spot], own_rects, house, spot, true)
	if v != D.Reject.BLOCKED:
		errs.append("BLOCKED beklenirdi (birim ustu): %d" % v)
	v = Sim.validate_placement(grid, p, [], own_rects, house, Vector2i(D.MAP_W / 2, 3), true)
	if v != D.Reject.BAD_SPOT:
		errs.append("BAD_SPOT beklenirdi (su): %d" % v)

	# radius disi: belediyeden 10+ uzak GARANTI cim hucre bul, oraya dene
	var far := Vector2i(-1, -1)
	for y in range(D.MAP_H - 2, 1, -1):
		var c := Vector2i(hall_tl.x, y)
		if Sim._rect_chebyshev(Rect2i(c, Vector2i.ONE), own_rects[0]) > D.BUILD_RADIUS_TILES \
				and grid[c.y * D.MAP_W + c.x] == D.Tile.GRASS and not p.is_solid(c):
			far = c
			break
	if far != Vector2i(-1, -1):
		v = Sim.validate_placement(grid, p, [], own_rects, house, far, true)
		if v != D.Reject.TOO_FAR:
			errs.append("TOO_FAR beklenirdi: %d" % v)
	else:
		errs.append("TOO_FAR senaryosu icin uzak cim hucre bulunamadi")

	if Sim._rect_chebyshev(Rect2i(0, 0, 2, 2), Rect2i(5, 0, 1, 1)) != 4:
		errs.append("rect_chebyshev: ayrik dikdortgenlerde 4 bekleniyordu")
	if Sim._rect_chebyshev(Rect2i(0, 0, 2, 2), Rect2i(1, 1, 2, 2)) != 0:
		errs.append("rect_chebyshev: kesisimde 0 bekleniyordu")

	return errs
