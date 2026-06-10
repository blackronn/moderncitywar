extends Node
## Host-otoriter simulasyon: physics tick'inde (30 Hz) kosar, YALNIZCA host'ta
## var olur. Istemci komutlari Net uzerinden handle_* fonksiyonlarina gelir.
## Tick sirasi: uretim -> ekonomi -> hareket -> savas -> zafer -> snapshot.

const D := preload("res://scripts/autoload/defs.gd")
const MapGen := preload("res://scripts/sim/map_gen.gd")

var game: Node2D = null              # game.gd
var pathing = null                   # pathing.gd (RefCounted)
var rng := RandomNumberGenerator.new()
var next_id := 1
var tick := 0
var debug_speed := 1.0               # --speed=N ile hizlandirma (smoke testler)
var node_res := {}                   # Vector2i -> kalan kaynak (orman/tas)


func _ready() -> void:
	rng.seed = GameState.seed_v + 7
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="):
			debug_speed = maxf(1.0, float(arg.get_slice("=", 1)))


func start_match() -> void:
	if GameState.match_running:
		return
	# kaynak node stoklari
	node_res.clear()
	for y in D.MAP_H:
		for x in D.MAP_W:
			var t := GameState.grid[y * D.MAP_W + x]
			if t == D.Tile.FOREST:
				node_res[Vector2i(x, y)] = D.FOREST_WOOD
			elif t == D.Tile.STONE:
				node_res[Vector2i(x, y)] = D.STONE_AMOUNT
	# baslangic varliklari: belediye + 1 isci
	for pid in [1, 2]:
		var tl: Vector2i = GameState.spawns[pid - 1]
		spawn_building(&"city_hall", pid, tl, true)
		var wc: Vector2i = pathing.nearest_free(tl + Vector2i(1, 2), 4)
		if wc != Vector2i(-1, -1):
			spawn_unit(&"worker", pid, cell_center(wc))
	recount_pop()
	Net.ev(D.Ev.MATCH_STARTED)
	Net.bc_resources(1)
	Net.bc_resources(2)


func _physics_process(delta: float) -> void:
	if not GameState.match_running:
		return
	var dt := delta * debug_speed
	tick += 1
	_tick_production(dt)
	_tick_economy(dt)
	_tick_movement(dt)
	_tick_combat(dt)
	if tick % D.TICK_RATE == 0:
		_check_victory()
	if tick % D.SNAPSHOT_EVERY_TICKS == 0:
		_broadcast_snapshot()


# === spawn / despawn ===

func spawn_unit(def_id: StringName, pid: int, pos: Vector2) -> Node:
	var id := next_id
	next_id += 1
	var n: Node = game.spawn_entity_visual(id, def_id, pid, pos)
	Net.bc_spawn(id, def_id, pid, pos)
	return n


func spawn_building(def_id: StringName, pid: int, top_left: Vector2i, completed: bool) -> Node:
	var bdef := D.building(def_id)
	var size: Vector2i = bdef["size"]
	var pos := (Vector2(top_left) + Vector2(size) / 2.0) * D.TILE
	var id := next_id
	next_id += 1
	var n: Node = game.spawn_entity_visual(id, def_id, pid, pos)
	n.cell = top_left
	if not completed:
		n.start_construction()
	pathing.set_rect_solid(top_left, size, true)
	Net.bc_spawn(id, def_id, pid, pos)
	return n


func despawn(node: Node, reason: int) -> void:
	if node.def.has("size"):
		pathing.set_rect_solid(node.cell, node.def["size"], false)
	var id: int = node.id
	game.despawn_entity_visual(id, reason)
	Net.bc_despawn(id, reason)
	recount_pop()
	Net.bc_resources(1)
	Net.bc_resources(2)


# === komut isleyiciler (M1/M2'de dolacak) ===

func handle_move(_pid: int, _ids: PackedInt32Array, _target: Vector2) -> void:
	pass   # M1


func handle_gather(_pid: int, _ids: PackedInt32Array, _cell: Vector2i) -> void:
	pass   # M1


func handle_build(_pid: int, _def_id: StringName, _cell: Vector2i, _builders: PackedInt32Array) -> void:
	pass   # M1


func handle_train(_pid: int, _building_id: int, _def_id: StringName) -> void:
	pass   # M1


func handle_cancel_train(_pid: int, _building_id: int, _index: int) -> void:
	pass   # M1


func handle_attack(_pid: int, _ids: PackedInt32Array, _target_id: int) -> void:
	pass   # M2


func handle_declare_war(_pid: int) -> void:
	pass   # M2


func force_game_over(winner: int, reason: int) -> void:
	Net.game_over(winner, reason)


# === tick adimlari (M1/M2'de dolacak) ===

func _tick_production(_dt: float) -> void:
	pass   # M1


func _tick_economy(_dt: float) -> void:
	pass   # M1


func _tick_movement(_dt: float) -> void:
	pass   # M1


func _tick_combat(_dt: float) -> void:
	pass   # M2


func _check_victory() -> void:
	pass   # M2/M3


func _broadcast_snapshot() -> void:
	if not Net.net_active:
		return
	var ents: Array = GameState.entities.values()
	var i := 0
	while i < ents.size():
		Net.bc_snapshot(Net.encode_snapshot(ents.slice(i, i + D.SNAP_MAX_ENTS)))
		i += D.SNAP_MAX_ENTS


# === yardimcilar ===

func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c) * D.TILE + Vector2(D.TILE, D.TILE) / 2.0


func recount_pop() -> void:
	for pid in [1, 2]:
		var used := 0
		var cap := 0
		for e in GameState.entities.values():
			if e.owner_pid != pid:
				continue
			if e.def.has("speed_t"):
				used += int(e.def["pop"])
			elif e.is_complete():
				cap += int(e.def.get("pop_cap", 0))
		GameState.pop_used[pid] = used
		GameState.pop_cap[pid] = cap
