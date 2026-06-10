extends Node
## M1 istemci botu: UI'in kullandigi ayni Net.send_* yolundan isciyle odun
## toplar (120'ye kadar), ev kurar, nufus kapasitesinin 5->9 olmasini bekler.

const D := preload("res://scripts/autoload/defs.gd")
const TIMEOUT_S := 110.0

var _done := false


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_S).timeout.connect(_fail)
	if GameState.match_running:
		_run()
	else:
		Bus.match_started.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var worker := _find_own(&"worker")
	if worker == null:
		_fail()
		return
	var forest := _nearest_tile(worker.cell(), D.Tile.FOREST)
	if forest == Vector2i(-1, -1):
		_fail()
		return
	print("BOT_CLIENT gather -> ", forest)
	Net.send_gather(PackedInt32Array([worker.id]), forest)
	while not _done and GameState.res[2]["wood"] < 120.0:
		await get_tree().create_timer(0.25).timeout
	if _done:
		return
	var hall := _find_own(&"city_hall")
	if hall == null:
		_fail()
		return
	var tl := _house_spot(hall)
	if tl == Vector2i(-99, -99):
		_fail()
		return
	print("BOT_CLIENT build house -> ", tl)
	Net.send_build(&"house", tl, PackedInt32Array([worker.id]))
	while not _done and GameState.pop_cap[2] < 9:
		await get_tree().create_timer(0.25).timeout
	if _done:
		return
	_done = true
	print("SMOKE_PASS_CLIENT")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _find_own(def_id: StringName) -> Node:
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid and e.def_id == def_id:
			return e
	return null


func _nearest_tile(from_c: Vector2i, kind: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 99999
	for y in D.MAP_H:
		for x in D.MAP_W:
			if GameState.grid[y * D.MAP_W + x] != kind:
				continue
			var dd := maxi(absi(x - from_c.x), absi(y - from_c.y))
			if dd < best_d:
				best_d = dd
				best = Vector2i(x, y)
	return best


func _house_spot(hall: Node) -> Vector2i:
	var game: Node2D = get_tree().current_scene
	for r in range(2, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c: Vector2i = hall.cell + Vector2i(dx, dy)
				if c.x < 1 or c.y < 1 or c.x >= D.MAP_W - 1 or c.y >= D.MAP_H - 1:
					continue
				if GameState.grid_at(c) != D.Tile.GRASS:
					continue
				if game.pathing.is_solid(c):
					continue
				return c
	return Vector2i(-99, -99)


func _fail() -> void:
	if _done:
		return
	_done = true
	printerr("SMOKE_FAIL_CLIENT timeout/assert")
	get_tree().quit(1)
