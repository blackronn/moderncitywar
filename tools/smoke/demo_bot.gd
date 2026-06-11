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
