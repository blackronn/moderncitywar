extends Node
## Host-otoriter simulasyon: physics tick'inde (30 Hz) kosar, YALNIZCA host'ta
## var olur. Istemci komutlari Net uzerinden handle_* fonksiyonlarina gelir.
## Tick sirasi: uretim -> ekonomi -> birimler (hareket/toplama/insaat) ->
## savas -> zafer -> snapshot.

const D := preload("res://scripts/autoload/defs.gd")
const MapGen := preload("res://scripts/sim/map_gen.gd")

var game: Node2D = null              # game.gd
var pathing = null                   # pathing.gd (RefCounted)
var rng := RandomNumberGenerator.new()
var next_id := 1
var tick := 0
var debug_speed := 1.0               # --speed=N ile hizlandirma (smoke testler)
var node_res := {}                   # Vector2i -> kalan kaynak (orman/tas)
var _res_dirty := false


func _ready() -> void:
	rng.seed = GameState.seed_v + 7
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="):
			debug_speed = maxf(1.0, float(arg.get_slice("=", 1)))


func start_match() -> void:
	if GameState.match_running:
		return
	node_res.clear()
	for y in D.MAP_H:
		for x in D.MAP_W:
			var t := GameState.grid[y * D.MAP_W + x]
			if t == D.Tile.FOREST:
				node_res[Vector2i(x, y)] = D.FOREST_WOOD
			elif t == D.Tile.STONE:
				node_res[Vector2i(x, y)] = D.STONE_AMOUNT
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
	_tick_units(dt)
	_tick_combat(dt)
	if tick % 15 == 0 and _res_dirty:
		_res_dirty = false
		Bus.resources_changed.emit(1)
		Bus.resources_changed.emit(2)
		Net.bc_resources(1)
		Net.bc_resources(2)
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
	# footprint solid isaretlemesi ve cell hesabi game.spawn_entity_visual'da
	# (iki ucta ortak yol)
	var bdef := D.building(def_id)
	var size: Vector2i = bdef["size"]
	var pos := (Vector2(top_left) + Vector2(size) / 2.0) * D.TILE
	var id := next_id
	next_id += 1
	var n: Node = game.spawn_entity_visual(id, def_id, pid, pos)
	if not completed:
		n.start_construction()
	Net.bc_spawn(id, def_id, pid, pos)
	if not completed:
		# istemci insaat halini snapshot progress'inden anlar; ilk paket gelene
		# kadar yarim gorunmesin diye hemen bir snapshot itelim
		_broadcast_snapshot()
	return n


func despawn(node: Node, reason: int) -> void:
	var id: int = node.id
	game.despawn_entity_visual(id, reason)
	Net.bc_despawn(id, reason)
	recount_pop()
	_res_dirty = true


# === komut isleyiciler ===

func handle_move(pid: int, ids: PackedInt32Array, target: Vector2) -> void:
	var cell := _px_to_cell(target)
	for u in _owned_units(pid, ids):
		_set_move(u, cell)


func handle_gather(pid: int, ids: PackedInt32Array, cell: Vector2i) -> void:
	var t := GameState.grid_at(cell)
	if not D.TILE_RES.has(t):
		handle_move(pid, ids, cell_center(cell))
		return
	for u in _owned_units(pid, ids):
		if u.def_id == &"worker":
			u.task = {"kind": &"gather", "cell": cell, "tile": t}
			_repath(u)
		else:
			_set_move(u, cell)


func handle_build(pid: int, def_id: StringName, top_left: Vector2i, builders: PackedInt32Array) -> void:
	if not D.is_building(def_id) or def_id == &"city_hall":
		Net.reject_to(pid, D.Reject.INVALID)
		return
	var bdef := D.building(def_id)
	var afford: bool = GameState.can_afford(pid, bdef["cost"])
	var verdict := validate_placement(
		GameState.grid, pathing, _unit_cells(), _own_building_rects(pid), bdef, top_left, afford)
	if verdict != -1:
		Net.reject_to(pid, verdict)
		return
	GameState.pay(pid, bdef["cost"])
	_res_dirty = true
	var b := spawn_building(def_id, pid, top_left, false)
	_on_grid_blocked(Rect2i(top_left, bdef["size"]))
	for u in _owned_units(pid, builders):
		if u.def_id == &"worker":
			_assign_build(u, b)


func handle_train(pid: int, building_id: int, def_id: StringName) -> void:
	var b: Node = GameState.ent(building_id)
	if b == null or not b.def.has("size") or b.owner_pid != pid or not b.is_complete():
		Net.reject_to(pid, D.Reject.INVALID)
		return
	var trains: Array = b.def.get("trains", [])
	if not trains.has(def_id):
		Net.reject_to(pid, D.Reject.INVALID)
		return
	if b.queue.size() >= D.TRAIN_QUEUE_MAX:
		Net.reject_to(pid, D.Reject.QUEUE_FULL)
		return
	var udef := D.unit(def_id)
	if GameState.pop_used[pid] + int(udef["pop"]) > GameState.pop_cap[pid]:
		Net.reject_to(pid, D.Reject.POP_FULL)
		return
	if not GameState.can_afford(pid, udef["cost"]):
		Net.reject_to(pid, D.Reject.NO_RES)
		return
	GameState.pay(pid, udef["cost"])
	_res_dirty = true
	b.queue.append(def_id)
	if b.queue.size() == 1:
		b.queue_t = udef["train_s"]


func handle_cancel_train(pid: int, building_id: int, index: int) -> void:
	var b: Node = GameState.ent(building_id)
	if b == null or not b.def.has("size") or b.owner_pid != pid:
		return
	if index < 0 or index >= b.queue.size():
		return
	GameState.refund(pid, D.unit(b.queue[index])["cost"])
	_res_dirty = true
	b.queue.remove_at(index)
	if index == 0 and not b.queue.is_empty():
		b.queue_t = D.unit(b.queue[0])["train_s"]


func handle_attack(_pid: int, _ids: PackedInt32Array, _target_id: int) -> void:
	pass   # M2


func handle_declare_war(_pid: int) -> void:
	pass   # M2


func force_game_over(winner: int, reason: int) -> void:
	Net.game_over(winner, reason)


# === yerlestirme dogrulamasi (saf/statik: testler dogrudan cagirir) ===

static func validate_placement(grid: PackedInt32Array, p_pathing, unit_cells: Array,
		own_rects: Array, bdef: Dictionary, top_left: Vector2i, afford: bool) -> int:
	## -1 = gecerli, aksi halde D.Reject.* nedeni.
	var size: Vector2i = bdef["size"]
	for dy in size.y:
		for dx in size.x:
			var c := top_left + Vector2i(dx, dy)
			if c.x < 0 or c.y < 0 or c.x >= D.MAP_W or c.y >= D.MAP_H:
				return D.Reject.BAD_SPOT
			if grid[c.y * D.MAP_W + c.x] != D.Tile.GRASS:
				return D.Reject.BAD_SPOT
			if p_pathing.is_solid(c):
				return D.Reject.BLOCKED
			if unit_cells.has(c):
				return D.Reject.BLOCKED
	var rect := Rect2i(top_left, size)
	var near_own := false
	for r: Rect2i in own_rects:
		if _rect_chebyshev(rect, r) <= D.BUILD_RADIUS_TILES:
			near_own = true
			break
	if not near_own:
		return D.Reject.TOO_FAR
	if not afford:
		return D.Reject.NO_RES
	return -1


static func _rect_chebyshev(a: Rect2i, b: Rect2i) -> int:
	## Iki hucre dikdortgeni arasindaki en kisa chebyshev mesafesi (kapsayan=0).
	var dx := maxi(0, maxi(b.position.x - (a.position.x + a.size.x - 1),
		a.position.x - (b.position.x + b.size.x - 1)))
	var dy := maxi(0, maxi(b.position.y - (a.position.y + a.size.y - 1),
		a.position.y - (b.position.y + b.size.y - 1)))
	return maxi(dx, dy)


# === tick adimlari ===

func _tick_production(dt: float) -> void:
	for b in _buildings():
		if not b.is_complete() or b.queue.is_empty():
			continue
		b.queue_t = maxf(0.0, b.queue_t - dt)
		if b.queue_t > 0.0:
			continue
		var def_id: StringName = b.queue[0]
		var udef := D.unit(def_id)
		# nufus dolu ise kuyruk basinda bekle
		if GameState.pop_used[b.owner_pid] + int(udef["pop"]) > GameState.pop_cap[b.owner_pid]:
			continue
		var sc: Vector2i = pathing.nearest_free(b.cell + Vector2i(0, b.def["size"].y), 5)
		if sc == Vector2i(-1, -1):
			continue
		spawn_unit(def_id, b.owner_pid, cell_center(sc))
		b.queue.pop_front()
		if not b.queue.is_empty():
			b.queue_t = D.unit(b.queue[0])["train_s"]
		recount_pop()
		_res_dirty = true


func _tick_economy(dt: float) -> void:
	for b in _buildings():
		if not b.is_complete():
			continue
		var rate: Dictionary = b.def.get("rate", {})
		for kind in rate:
			GameState.res[b.owner_pid][kind] += rate[kind] * dt
			_res_dirty = true


func _tick_units(dt: float) -> void:
	var builders_on := {}   # building id -> kanal yapan isci sayisi
	for u in _units():
		u.flags = 0
		var kind: StringName = u.task.get("kind", &"idle")
		match kind:
			&"move":
				if _follow(u, dt):
					u.task = {"kind": &"idle"}
				else:
					u.flags |= D.FLAG_MOVING
			&"gather":
				var c: Vector2i = u.task["cell"]
				if u.cell() == c and u.path_i >= u.path.size():
					u.flags |= D.FLAG_GATHERING
					_do_gather(u, c, dt)
				elif _follow(u, dt):
					if u.cell() != c:
						_retarget_gather(u, c)   # ulasamadi; yakinda baskasi var mi
				else:
					u.flags |= D.FLAG_MOVING
			&"build":
				var b: Node = GameState.ent(u.task.get("bid", 0))
				if b == null or b.is_complete():
					u.task = {"kind": &"idle"}
				elif _adjacent_to(u.cell(), b):
					u.flags |= D.FLAG_CONSTRUCTING
					builders_on[b.id] = builders_on.get(b.id, 0) + 1
				elif _follow(u, dt):
					pass   # vardi; bitisiklik kontrolu gelecek tick
				else:
					u.flags |= D.FLAG_MOVING
	for bid in builders_on:
		var b: Node = GameState.ent(bid)
		if b == null:
			continue
		var n: int = mini(builders_on[bid], D.MAX_BUILDERS)
		b.set_construction(b.construction + dt * float(n) / maxf(b.def["build_s"], 0.01))
		if b.is_complete():
			recount_pop()
			_res_dirty = true


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


# === hareket / toplama ic mantigi ===

func _set_move(u: Node, cell: Vector2i) -> void:
	u.task = {"kind": &"move", "cell": cell}
	_repath(u)


func _repath(u: Node) -> void:
	var goal: Vector2i = u.task.get("cell", u.cell())
	u.path = pathing.find(u.cell(), goal, true)
	u.path_i = 0
	if u.path.is_empty():
		u.task = {"kind": &"idle"}


func _follow(u: Node, dt: float) -> bool:
	## Yol uzerinde ilerletir; yol bitti/bitmisti ise true.
	if u.path_i >= u.path.size():
		return true
	var next_c: Vector2i = u.path[u.path_i]
	if pathing.is_solid(next_c) and next_c != u.cell():
		# onumuz kapandi (yeni bina vs) -> ayni hedefe yeniden yol
		_repath(u)
		if u.path.is_empty():
			return true
		next_c = u.path[u.path_i]
	var target := cell_center(next_c)
	var speed: float = u.def["speed_t"] * D.TILE
	var d: Vector2 = target - u.position
	var step := speed * dt
	if d.length() <= step:
		u.position = target
		u.path_i += 1
		return u.path_i >= u.path.size()
	u.position += d.normalized() * step
	return false


func _do_gather(u: Node, c: Vector2i, dt: float) -> void:
	var t := GameState.grid_at(c)
	if not D.TILE_RES.has(t):
		_retarget_gather(u, c)
		return
	var res_kind: String = D.TILE_RES[t]
	var rate: float = D.GATHER_RATES[t]
	var amount := minf(rate * dt, node_res.get(c, 0.0))
	node_res[c] = node_res.get(c, 0.0) - amount
	GameState.res[u.owner_pid][res_kind] += amount
	_res_dirty = true
	if node_res.get(c, 0.0) <= 0.0:
		node_res.erase(c)
		Net.ev(D.Ev.DEPLETED, [c])   # grid'i iki ucta da GRASS yapar
		for w in _units():
			if w.task.get("kind") == &"gather" and w.task.get("cell") == c:
				_retarget_gather(w, c)


func _retarget_gather(u: Node, from_c: Vector2i) -> void:
	var tile_kind: int = u.task.get("tile", -1)
	var best := _nearest_node(from_c, tile_kind)
	if best == Vector2i(-1, -1):
		u.task = {"kind": &"idle"}
		Net.toast_to(u.owner_pid, &"depleted")
	else:
		u.task = {"kind": &"gather", "cell": best, "tile": tile_kind}
		_repath(u)


func _nearest_node(from_c: Vector2i, tile_kind: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 9999
	for c: Vector2i in node_res:
		if GameState.grid_at(c) != tile_kind:
			continue
		var dd := maxi(absi(c.x - from_c.x), absi(c.y - from_c.y))
		if dd <= D.GATHER_RETARGET_T and dd < best_d:
			best_d = dd
			best = c
	return best


func _assign_build(u: Node, b: Node) -> void:
	var spot := _adjacent_spot(b, u.cell())
	if spot == Vector2i(-1, -1):
		u.task = {"kind": &"idle"}
		return
	u.task = {"kind": &"build", "bid": b.id, "cell": spot}
	_repath(u)


func _adjacent_spot(b: Node, from_c: Vector2i) -> Vector2i:
	## Footprint cevresindeki bos hucrelerden from_c'ye en yakini.
	var size: Vector2i = b.def["size"]
	var best := Vector2i(-1, -1)
	var best_d := 9999
	for dy in range(-1, size.y + 1):
		for dx in range(-1, size.x + 1):
			if dx >= 0 and dx < size.x and dy >= 0 and dy < size.y:
				continue   # ic hucre
			var c: Vector2i = b.cell + Vector2i(dx, dy)
			if pathing.is_solid(c):
				continue
			var dd := maxi(absi(c.x - from_c.x), absi(c.y - from_c.y))
			if dd < best_d:
				best_d = dd
				best = c
	return best


func _adjacent_to(c: Vector2i, b: Node) -> bool:
	return _rect_chebyshev(Rect2i(c, Vector2i.ONE), Rect2i(b.cell, b.def["size"])) <= 1


func _on_grid_blocked(rect: Rect2i) -> void:
	## Yeni bina dikildi: kalan yolu bu dikdortgenden gecenler yeniden yol arar.
	var grown := rect.grow(0)
	for u in _units():
		for i in range(u.path_i, u.path.size()):
			if grown.has_point(u.path[i]):
				_repath(u)
				break


# === yardimcilar ===

func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c) * D.TILE + Vector2(D.TILE, D.TILE) / 2.0


func _px_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(p.x / D.TILE), 0, D.MAP_W - 1),
		clampi(int(p.y / D.TILE), 0, D.MAP_H - 1))


func _units(pid := 0) -> Array:
	var out: Array = []
	for e in GameState.entities.values():
		if e.def.has("speed_t") and (pid == 0 or e.owner_pid == pid):
			out.append(e)
	return out


func _buildings(pid := 0) -> Array:
	var out: Array = []
	for e in GameState.entities.values():
		if e.def.has("size") and (pid == 0 or e.owner_pid == pid):
			out.append(e)
	return out


func _owned_units(pid: int, ids: PackedInt32Array) -> Array:
	var out: Array = []
	for id in ids:
		var e: Node = GameState.ent(id)
		if e != null and e.owner_pid == pid and e.def.has("speed_t"):
			out.append(e)
	return out


func _unit_cells() -> Array:
	var out: Array = []
	for u in _units():
		out.append(u.cell())
	return out


func _own_building_rects(pid: int) -> Array:
	var out: Array = []
	for b in _buildings(pid):
		out.append(Rect2i(b.cell, b.def["size"]))
	return out


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
