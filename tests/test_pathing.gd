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

	# baris sinir grid'leri: kendi yarisinda yol VAR, rakip yariya YOK
	var own_target := Vector2i(D.MAP_W / 2 - 3, 6)
	if p.find(a, own_target, false, 1).is_empty():
		errs.append("baris grid'i kendi yarisinda yol bulamadi")
	if not p.find(a, b, false, 1).is_empty():
		errs.append("baris grid'i rakip yariya yol verdi (sinir delik!)")
	if not p.find(b, a, false, 2).is_empty():
		errs.append("baris grid'i (P2) rakip yariya yol verdi")
	# SINIR KESINDIR: cizgi otesi hedef istenince yol en fazla cizgiye kadar
	# gider (find kapali hedefi kendi yakasindaki en yakin hucreye yonlendirir);
	# yolun HICBIR hucresi obur yakada olamaz
	for pt in p.find(a, Vector2i(D.MAP_W / 2, 6), false, 1):
		if pt.x >= D.MAP_W / 2:
			errs.append("P1 baristayken orta cizgiyi gecebildi: %s" % str(pt))
			break
	for pt in p.find(b, Vector2i(D.MAP_W / 2 - 1, 6), false, 2):
		if pt.x < D.MAP_W / 2:
			errs.append("P2 baristayken orta cizgiyi gecebildi: %s" % str(pt))
			break

	# === 4 oyuncu: ceyrek bolgeleri — kendi ceyrek VAR, capraz ceyrek YOK ===
	var g4 := MapGen.generate(42, 4)   # 42 -> OVA (su yok, saf bolge testi)
	var p4 := Pathing.new()
	p4.setup(g4["grid"], 4)
	var s4: Array = g4["spawns"]
	if p4.find(s4[0], s4[0] + Vector2i(6, 4), false, 1).is_empty():
		errs.append("4p: P1 kendi ceyreginde yol bulamadi")
	if not p4.find(s4[0], s4[3], false, 1).is_empty():
		errs.append("4p: P1 baris grid'i capraz ceyrege (P4) yol verdi")
	if not p4.find(s4[0], s4[2], false, 1).is_empty():
		errs.append("4p: P1 baris grid'i alt ceyrege (P3) yol verdi")
	if not p4.find(s4[2], s4[1], false, 3).is_empty():
		errs.append("4p: P3 baris grid'i capraz ceyrege (P2) yol verdi")
	# tarafsiz HAC banti: P1 dikey bandin ust kismina girebilmeli
	var band_cell := Vector2i(D.MAP_W / 2 - 2, 6)
	if p4.find(s4[0], band_cell, false, 1).is_empty():
		errs.append("4p: P1 tarafsiz banda giremedi")

	# bolge yardimcilari tutarli: in_home -> in_zone alt kumesi
	for pid in [1, 2, 3, 4]:
		for cell: Vector2i in [Vector2i(3, 3), Vector2i(44, 3), Vector2i(3, 44), Vector2i(44, 44), Vector2i(24, 24)]:
			if D.in_home(pid, cell, 4) and not D.in_zone(pid, cell, 4):
				errs.append("in_home in_zone alt kumesi degil: pid %d %s" % [pid, cell])

	return errs
