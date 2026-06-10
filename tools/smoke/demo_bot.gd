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
		&"barracks": Vector2i(4, 4),
		&"factory": Vector2i(0, 4),
		&"turret": Vector2i(6, 5),
	}
	for bid: StringName in b_offsets:
		sim.spawn_building(bid, 1, tl + b_offsets[bid], true)
	var u_offsets := {
		&"rifleman": Vector2i(-2, 4),
		&"sniper": Vector2i(-1, 5),
		&"rpg": Vector2i(-2, 5),
		&"tank": Vector2i(-3, 2),
	}
	for uid: StringName in u_offsets:
		sim.spawn_unit(uid, 1, sim.cell_center(tl + u_offsets[uid]))
	sim.recount_pop()
