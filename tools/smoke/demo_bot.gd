extends Node
## --demo: gorsel dogrulama icin host sehrine tum bina/birim turlerini dizer
## (sprite koordinatlarinin sheet'te dogru secildigini tek karede gosterir).

const D := preload("res://scripts/autoload/defs.gd")


func _ready() -> void:
	if GameState.match_running:
		_go()
	else:
		Bus.match_started.connect(_go, CONNECT_ONE_SHOT)


func _go() -> void:
	var sim: Node = Net.sim
	if sim == null:
		return
	var tl: Vector2i = GameState.spawns[0]
	var b_offsets := {
		&"house": Vector2i(4, 0),
		&"greenhouse": Vector2i(4, 2),
		&"bank": Vector2i(6, 0),
		&"lumber_camp": Vector2i(6, 2),
		&"quarry": Vector2i(2, 2),
		&"barracks": Vector2i(4, 4),
		&"factory": Vector2i(0, 4),
		&"turret": Vector2i(6, 5),
	}
	for bid: StringName in b_offsets:
		sim.spawn_building(bid, 1, tl + b_offsets[bid], true)
	sim.spawn_building(&"mine", 1, tl + Vector2i(0, -2), true)
	sim.spawn_building(&"sandbags", 1, tl + Vector2i(-2, 2), true)
	var u_offsets := {
		&"rifleman": Vector2i(-2, 4),
		&"sniper": Vector2i(-1, 5),
		&"rpg": Vector2i(-2, 5),
		&"mg": Vector2i(-3, 5),
		&"commando": Vector2i(-4, 5),
		&"mortar": Vector2i(-3, 6),
		&"tank": Vector2i(-3, 2),
		&"healer": Vector2i(-4, 3),
	}
	for uid: StringName in u_offsets:
		sim.spawn_unit(uid, 1, sim.cell_center(tl + u_offsets[uid]))
	# gelistirme gorseli: bir ev L2 olsun (altin pip + panel etiketi)
	for e in GameState.entities.values():
		if e.owner_pid == 1 and e.def_id == &"house":
			sim.handle_upgrade(1, e.id)
			break
	# catisma onizlemesi: kuzeyden yaklasan dusman mangasi + dogrudan savas hali
	sim.spawn_unit(&"rifleman", 2, sim.cell_center(tl + Vector2i(4, -4)))
	sim.spawn_unit(&"rifleman", 2, sim.cell_center(tl + Vector2i(5, -3)))
	sim.spawn_unit(&"tank", 2, sim.cell_center(tl + Vector2i(6, -4)))
	sim.recount_pop()
	Net.ev(D.Ev.WAR_STATE, [D.War.WAR, 0.0])
	# su varsa kopru gosterimi: TAMAMLANMIS kopru + ustunde duran asker
	# (koprunun birimin ALTINDA cizildigini dogrular — GroundDecals katmani)
	_demo_bridge(sim)
	# isciyi sec: alt panel insa menusu (2 satir, kum torbasi dahil) acilir
	var game := get_tree().current_scene
	var ic: Node = game.get_node_or_null("InputController")
	if ic != null:
		for e in GameState.entities.values():
			if e.owner_pid == 1 and e.def_id == &"worker":
				var sel: Array[int] = [e.id]
				ic._set_selection(sel)
				break


func _demo_bridge(sim: Node) -> void:
	for y in range(12, D.MAP_H):
		for x in range(2, D.MAP_W / 2):
			var c := Vector2i(x, y)
			if GameState.grid_at(c) != D.Tile.WATER:
				continue
			var t_left := GameState.grid_at(c + Vector2i.LEFT)
			if t_left == D.Tile.WATER or t_left == -1 or t_left == D.Tile.MOUNTAIN:
				continue
			var b: Node = sim.spawn_building(&"bridge_seg", 1, c, true)
			if b != null:
				sim.pathing.set_cell_walk(c, true)
				sim.spawn_unit(&"rifleman", 1, sim.cell_center(c))
				# --cam-bridge: kamerayi kopruye kilitle (gorsel dogrulama)
				for arg in OS.get_cmdline_user_args():
					if arg == "--cam-bridge":
						get_tree().current_scene.cam.position = b.position
				return
