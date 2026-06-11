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
			elif t == D.Tile.GOLD:
				# tarafsiz bolge altini: stok olmadan dogup aninda "tukeniyordu"
				node_res[Vector2i(x, y)] = D.GOLD_AMOUNT
	for pid in [1, 2]:
		var tl: Vector2i = GameState.spawns[pid - 1]
		spawn_building(&"city_hall", pid, tl, true)
		var wc: Vector2i = pathing.nearest_free(tl + Vector2i(1, 2), 4)
		if wc != Vector2i(-1, -1):
			spawn_unit(&"worker", pid, cell_center(wc))
	recount_pop()
	Net.ev(D.Ev.MATCH_STARTED)
	# mac BARISTA baslar: sinirlar kapali, saldiri yok; "Savas Ilan Et" ->
	# 30 sn geri sayim -> savas (sinirlar acilir, catisma serbest)
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
	_tick_healers(dt)
	_tick_mines()
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
	if node.def.has("bridge") and node.is_complete():
		pathing.set_cell_walk(node.cell, false)   # kopru yikildi: su geri geldi
	var id: int = node.id
	game.despawn_entity_visual(id, reason)
	Net.bc_despawn(id, reason)
	recount_pop()
	_res_dirty = true


# === komut isleyiciler ===

func handle_move(pid: int, ids: PackedInt32Array, target: Vector2) -> void:
	var cell := _clamp_half(pid, _px_to_cell(target), true)
	for u in _owned_units(pid, ids):
		_set_move(u, cell)


func handle_gather(pid: int, ids: PackedInt32Array, cell: Vector2i) -> void:
	cell = _clamp_half(pid, cell, true)
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


func _at_peace() -> bool:
	return GameState.war_state != D.War.WAR


func _half_pid(pid: int) -> int:
	## Baristayken yol aramalari oyuncunun kendi yarisina kisitlanir.
	return pid if _at_peace() else 0


func _clamp_half(pid: int, c: Vector2i, toast: bool = false) -> Vector2i:
	## Baristayken hedefi kendi yari + tarafsiz bant icine ceker.
	if not _at_peace():
		return c
	var mid := D.MAP_W / 2
	var out := c
	if pid == 1 and c.x >= mid + D.NEUTRAL_HALF_W:
		out = Vector2i(mid + D.NEUTRAL_HALF_W - 1, c.y)
	elif pid == 2 and c.x < mid - D.NEUTRAL_HALF_W:
		out = Vector2i(mid - D.NEUTRAL_HALF_W, c.y)
	if toast and out != c:
		Net.reject_to(pid, D.Reject.BORDER)
	return out


func handle_build(pid: int, def_id: StringName, top_left: Vector2i, builders: PackedInt32Array) -> void:
	if not D.is_building(def_id) or def_id == &"city_hall":
		Net.reject_to(pid, D.Reject.INVALID)
		return
	var bdef := D.building(def_id)
	var afford: bool = GameState.can_afford(pid, bdef["cost"])
	var mid := D.MAP_W / 2
	# bolge sinirlari: normal binalar baristayken KENDI yarisinda; mayin, kopru
	# ve siper tarafsiz banda da kurulabilir (altin yolu / nehir gecisi / cephe)
	var reach_neutral: bool = bdef.has("mine") or bdef.has("bridge") or bdef.has("cover")
	var bmin := -1
	var bmax := 9999
	if _at_peace():
		if pid == 1:
			bmax = (mid + D.NEUTRAL_HALF_W - 1) if reach_neutral else (mid - D.NEUTRAL_HALF_W - 1)
		else:
			bmin = (mid - D.NEUTRAL_HALF_W) if reach_neutral else (mid + D.NEUTRAL_HALF_W)
	var verdict: int
	if bdef.has("bridge"):
		verdict = _validate_bridge(top_left, afford, bmin, bmax)
	elif bdef.has("mine") or bdef.has("cover"):
		verdict = _validate_mine(top_left, afford, bmin, bmax)
	else:
		verdict = validate_placement(
			GameState.grid, pathing, _unit_cells(), _own_building_rects(pid), bdef, top_left,
			afford, bmin, bmax)
	if verdict != -1:
		Net.reject_to(pid, verdict)
		return
	GameState.pay(pid, bdef["cost"])
	_res_dirty = true
	var b := spawn_building(def_id, pid, top_left, false)
	if not bdef.has("bridge") and not bdef.has("mine"):
		_on_grid_blocked(Rect2i(top_left, bdef["size"]))
	for u in _owned_units(pid, builders):
		if u.def_id == &"worker":
			_assign_build(u, b)


func _validate_bridge(cell: Vector2i, afford: bool, bmin: int, bmax: int) -> int:
	## Kopru parcasi: SU hucresine, yurunebilir bir komsuya bitisik (adim adim).
	if GameState.grid_at(cell) != D.Tile.WATER:
		return D.Reject.BAD_SPOT
	if cell.x < bmin or cell.x > bmax:
		return D.Reject.BORDER
	for b in _buildings():
		if b.def.has("bridge") and b.cell == cell:
			return D.Reject.BLOCKED
	var has_anchor := false
	for off: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n := cell + off
		var t := GameState.grid_at(n)
		if t != -1 and t != D.Tile.WATER and t != D.Tile.HILL:
			has_anchor = true
			break
		if _bridge_entity_at(n) != null:
			has_anchor = true
			break
	if not has_anchor:
		return D.Reject.BAD_SPOT
	if not afford:
		return D.Reject.NO_RES
	return -1


func _bridge_entity_at(cell: Vector2i) -> Node:
	for b in _buildings():
		if b.def.has("bridge") and b.cell == cell and b.is_complete():
			return b
	return null


func _validate_mine(cell: Vector2i, afford: bool, bmin: int, bmax: int) -> int:
	## Mayin/siper: zemine, bina ustune degil; sehir yaricapi kurali YOK
	## (ileri hatta kurulur). Ayni hucrede ikinci mayin/siper olamaz.
	var t := GameState.grid_at(cell)
	if not D.BUILDABLE_TILES.has(t):
		return D.Reject.BAD_SPOT
	if cell.x < bmin or cell.x > bmax:
		return D.Reject.BORDER
	if pathing.is_solid(cell):
		return D.Reject.BLOCKED
	for b in _buildings():
		if (b.def.has("mine") or b.def.has("cover")) and b.cell == cell:
			return D.Reject.BLOCKED
	if not afford:
		return D.Reject.NO_RES
	return -1


func _in_cover(u: Node) -> bool:
	## Birim, SAGLAM dost kum torbasinin yaninda mi (cover_t yaricapi)?
	for b in _buildings(u.owner_pid):
		if b.def.has("cover") and b.is_complete():
			if u.position.distance_to(b.position) / float(D.TILE) <= float(b.def["cover_t"]):
				return true
	return false


func handle_demolish(pid: int, building_id: int) -> void:
	## Kendi binani yik (kopru dahil). Belediye yikilamaz.
	var b: Node = GameState.ent(building_id)
	if b == null or not b.def.has("size") or b.owner_pid != pid or b.def_id == &"city_hall":
		return
	despawn(b, 2)


func handle_assign_build(pid: int, ids: PackedInt32Array, building_id: int) -> void:
	## Yarim kalmis kendi insaatina isci atama (sag tikla devam etme).
	var b: Node = GameState.ent(building_id)
	if b == null or not b.def.has("size") or b.owner_pid != pid or b.is_complete():
		return
	for u in _owned_units(pid, ids):
		if u.def_id == &"worker":
			_assign_build(u, b)


func handle_upgrade(pid: int, building_id: int) -> void:
	var b: Node = GameState.ent(building_id)
	if b == null or not b.def.has("size") or b.owner_pid != pid or not b.is_complete():
		Net.reject_to(pid, D.Reject.INVALID)
		return
	if not b.def.has("up_cost"):
		Net.reject_to(pid, D.Reject.INVALID)
		return
	if b.level >= D.MAX_LEVEL:
		Net.reject_to(pid, D.Reject.MAX_LEVEL)
		return
	var cost := D.scaled_cost(b.def["up_cost"], b.level)
	if not GameState.can_afford(pid, cost):
		Net.reject_to(pid, D.Reject.NO_RES)
		return
	GameState.pay(pid, cost)
	_res_dirty = true
	b.level += 1
	b.queue_redraw()
	Net.ev(D.Ev.LEVEL, [b.id, b.level])
	recount_pop()   # ev gelistirmesi nufus kapasitesini degistirir
	Net.bc_resources(pid)


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
		b.queue_t = _train_time(b, def_id)


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
		b.queue_t = _train_time(b, b.queue[0])


func handle_attack(pid: int, ids: PackedInt32Array, target_id: int) -> void:
	if GameState.war_state != D.War.WAR:
		Net.reject_to(pid, D.Reject.PEACE)
		return
	var tgt: Node = GameState.ent(target_id)
	if tgt == null or tgt.owner_pid == pid:
		return
	for u in _owned_units(pid, ids):
		if u.def["dmg"] > 0:
			u.task = {"kind": &"attack", "tid": target_id, "ptid": target_id, "cell": _cell_of(tgt)}
			u.repath_block = 0
		else:
			_set_move(u, _cell_of(tgt))   # silahsizlar (isci) sadece yurur


func handle_declare_war(pid: int) -> void:
	if GameState.war_state != D.War.PEACE:
		return
	Net.ev(D.Ev.WAR_STATE, [D.War.COUNTDOWN, D.WAR_COUNTDOWN_S])
	Net.toast_to(pid, &"war_declared_by_you")
	Net.toast_to(GameState.enemy_of(pid), &"war_declared_by_enemy")


func force_game_over(winner: int, reason: int) -> void:
	Net.game_over(winner, reason)


# === yerlestirme dogrulamasi (saf/statik: testler dogrudan cagirir) ===

static func validate_placement(grid: PackedInt32Array, p_pathing, unit_cells: Array,
		own_rects: Array, bdef: Dictionary, top_left: Vector2i, afford: bool,
		min_x := -1, max_x := 9999) -> int:
	## -1 = gecerli, aksi halde D.Reject.* nedeni.
	## min_x/max_x: baris sinirlari (kendi yarin disina insaat yok).
	var size: Vector2i = bdef["size"]
	for dy in size.y:
		for dx in size.x:
			var c := top_left + Vector2i(dx, dy)
			if c.x < 0 or c.y < 0 or c.x >= D.MAP_W or c.y >= D.MAP_H:
				return D.Reject.BAD_SPOT
			if c.x < min_x or c.x > max_x:
				return D.Reject.BORDER
			if not D.BUILDABLE_TILES.has(grid[c.y * D.MAP_W + c.x]):
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
			b.queue_t = _train_time(b, b.queue[0])
		recount_pop()
		_res_dirty = true


func _tick_economy(dt: float) -> void:
	for b in _buildings():
		if not b.is_complete():
			continue
		var rate: Dictionary = b.def.get("rate", {})
		if rate.is_empty():
			continue
		# gelistirme: her seviye uretimi up_rate kadar artirir (orn. +%50)
		var mult := 1.0 + float(b.def.get("up_rate", 0.0)) * float(b.level - 1)
		for kind in rate:
			GameState.res[b.owner_pid][kind] += rate[kind] * mult * dt
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
			&"attack":
				pass   # hareket + ates _tick_combat'ta
			&"heal":
				pass   # hareket + iyilestirme _tick_healers'ta
	_separate_units()
	for bid in builders_on:
		var b: Node = GameState.ent(bid)
		if b == null:
			continue
		var n: int = mini(builders_on[bid], D.MAX_BUILDERS)
		b.set_construction(b.construction + dt * float(n) / maxf(b.def["build_s"], 0.01))
		if b.is_complete():
			if b.def.has("bridge"):
				pathing.set_cell_walk(b.cell, true)   # kopru bitti: su artik gecilir
			recount_pop()
			_res_dirty = true


func _tick_combat(dt: float) -> void:
	# geri sayim
	if GameState.war_state == D.War.COUNTDOWN:
		GameState.war_t_left = maxf(0.0, GameState.war_t_left - dt)
		if GameState.war_t_left <= 0.0:
			Net.ev(D.Ev.WAR_STATE, [D.War.WAR, 0.0])
			Net.ev(D.Ev.TOAST_KEY, [&"war_began"])
	if GameState.war_state != D.War.WAR:
		return
	# birimler
	for u in _units():
		if u.def["dmg"] <= 0:
			continue
		u.cooldown = maxf(0.0, u.cooldown - dt)
		var tgt: Node = null
		if u.task.get("kind") == &"attack":
			tgt = GameState.ent(u.task.get("tid", 0))
			# asil hedef (oyuncunun emri) ayri tutulur: araya giren olunce donulur
			var ptid: int = u.task.get("ptid", 0)
			if tgt == null and ptid != 0:
				tgt = GameState.ent(ptid)
				if tgt != null:
					u.task["tid"] = ptid
					u.repath_block = 0
			# savas zekasi: hedef bina ise ve menzile dusman BIRIMI girdiyse
			# once onu hallet (binayi doverken kesilmemek icin)
			if tgt != null and tgt.def.has("size"):
				var intr := _nearest_enemy_unit(u, u.def["aggro_t"])
				if intr != null:
					tgt = intr
					u.task["tid"] = intr.id
					u.repath_block = 0
			if tgt == null:
				u.task = {"kind": &"idle"}
		if tgt == null and u.task.get("kind") == &"idle":
			tgt = _nearest_enemy(u, u.def["aggro_t"])
			if tgt != null:
				u.task = {"kind": &"attack", "tid": tgt.id, "ptid": 0, "cell": _cell_of(tgt)}
				u.repath_block = 0
		if tgt != null:
			_combat_step(u, tgt, dt)
	# taretler
	for b in _buildings():
		if b.def.get("dmg", 0) <= 0 or not b.is_complete():
			continue
		b.cooldown = maxf(0.0, b.cooldown - dt)
		var tgt := _nearest_enemy(b, b.def["range_t"])
		if tgt != null and b.cooldown <= 0.0:
			_fire(b, tgt)


func _combat_step(u: Node, tgt: Node, dt: float) -> void:
	var dist := _dist_t(u, tgt)
	if dist <= float(u.def["range_t"]):
		u.path.clear()   # atama degil: u.path tipli Array, Variant uzerinden [] atanamaz
		u.path_i = 0
		u.flags |= D.FLAG_ATTACKING
		if u.cooldown <= 0.0:
			_fire(u, tgt)
		return
	# kovala: hedef yer degistirdiyse yeniden yol (15 tick frenli)
	u.flags |= D.FLAG_MOVING
	_chase(u, tgt, dt)


func _chase(u: Node, tgt: Node, dt: float) -> void:
	## Hedefe dogru yurur; hedef yer degistirdikce yolu tazeler (frenli).
	if u.repath_block > 0:
		u.repath_block -= 1
	var goal := _cell_of(tgt)
	var need: bool = u.path_i >= u.path.size()
	if not need and u.repath_block <= 0 and not u.path.is_empty():
		var endc: Vector2i = u.path[u.path.size() - 1]
		need = maxi(absi(endc.x - goal.x), absi(endc.y - goal.y)) > 1
	if need:
		u.task["cell"] = goal
		u.path = pathing.find(u.cell(), goal, true, _half_pid(u.owner_pid))
		u.path_i = 0
		if u.path.size() > 1 and u.path[0] == u.cell():
			u.path_i = 1
		u.repath_block = 15
	_follow(u, dt)


func _tick_mines() -> void:
	## Savastayken ustune dusman birimi basan mayin patlar: genis alan hasari,
	## zirhliya x1.5 (tank avcisi). Birden fazla hucreyi ayni anda vurur.
	if GameState.war_state != D.War.WAR:
		return
	for m in _buildings():
		if not m.def.has("mine") or not m.is_complete():
			continue
		var trig: float = m.def["m_trigger_t"]
		var fired := false
		for o in GameState.entities.values():
			if o.owner_pid == m.owner_pid or not o.def.has("speed_t"):
				continue
			if o.position.distance_to(m.position) / float(D.TILE) <= trig:
				fired = true
				break
		if not fired:
			continue
		var victim_pid: int = GameState.enemy_of(m.owner_pid)
		Net.ev(D.Ev.IMPACT, [m.position, 1.6])
		var victims: Array = []
		for o in GameState.entities.values():
			if o.owner_pid != victim_pid:
				continue
			if o.position.distance_to(m.position) / float(D.TILE) <= m.def["m_splash_t"]:
				var dmg: float = m.def["m_dmg"]
				if o.def.get("klass", D.Klass.BUILDING) == D.Klass.ARMOR:
					dmg *= 1.5
				victims.append([o, dmg])
		_apply_damage(victims)
		despawn(m, 1)
		return   # tick basina tek patlama yeter (zincirleme sonraki tick)


func _tick_healers(dt: float) -> void:
	## Sihhiyeci: bos/iyilestirme gorevindeyken yakindaki hasarli dostu bulur,
	## menzile yuruyup saniyede heal_rate kadar can doldurur. Savas durumundan
	## bagimsiz calisir; oyuncunun yuru/saldiri emri her zaman oncelikli.
	for u in _units():
		if not u.def.has("heal_rate"):
			continue
		var kind: StringName = u.task.get("kind", &"idle")
		if kind != &"idle" and kind != &"heal":
			continue
		var tgt: Node = null
		if kind == &"heal":
			tgt = GameState.ent(u.task.get("tid", 0))
			if tgt == null or tgt.hp >= tgt.max_hp \
					or (tgt.def.has("size") and not tgt.is_complete()):
				tgt = null
				u.task = {"kind": &"idle"}
		if tgt == null:
			tgt = _nearest_damaged_friendly(u, u.def["aggro_t"])
			if tgt != null:
				u.task = {"kind": &"heal", "tid": tgt.id, "cell": _cell_of(tgt)}
				u.repath_block = 0
		if tgt == null:
			continue
		if _dist_t(u, tgt) <= float(u.def["range_t"]):
			u.path.clear()
			u.path_i = 0
			u.flags |= D.FLAG_HEALING
			tgt.set_hp(minf(tgt.max_hp, tgt.hp + u.def["heal_rate"] * dt))
			var fx_t: float = u.task.get("fx", 0.0) - dt
			if fx_t <= 0.0:
				Net.ev(D.Ev.TRACER, [u.position, tgt.position, 1])   # yesil isin
				fx_t = 0.5
			u.task["fx"] = fx_t
		else:
			u.flags |= D.FLAG_MOVING
			_chase(u, tgt, dt)


func _nearest_damaged_friendly(e: Node, range_t: float) -> Node:
	var best: Node = null
	var bd := 1e9
	for o in GameState.entities.values():
		if o.owner_pid != e.owner_pid or o == e:
			continue
		if o.hp >= o.max_hp:
			continue
		if o.def.has("size") and not o.is_complete():
			continue   # insaat isciden, iyilestirme sihhiyeciden
		var d := _dist_t(e, o)
		if d <= range_t and d < bd:
			bd = d
			best = o
	return best


func _fire(att: Node, tgt: Node) -> void:
	att.cooldown = att.def["cooldown_s"]
	var splash: float = att.def.get("splash_t", 0.0)

	# --- havan: mermi her zaman hedefin CEVRESINE sacilir, alana vurur ---
	if att.def.get("arc", false):
		var sc: float = att.def.get("scatter_t", 0.0) * D.TILE
		var sa := rng.randf() * TAU
		var impact: Vector2 = tgt.position + Vector2(cos(sa), sin(sa)) * (rng.randf() * sc)
		Net.ev(D.Ev.TRACER, [att.position, impact, 0])
		Net.ev(D.Ev.IMPACT, [impact, 0.9])
		_apply_area(att, tgt.owner_pid, impact, splash, 1.0)
		return

	# --- SIPER: hedef saglam dost kum torbasinin yanindaysa direkt atislarin
	# --- cogu iskalanir (3'te 1 isabet). Havan ve alan hasari siperi DELER.
	var miss_c: float = att.def.get("miss", 0.0)
	if not tgt.def.has("size") and _in_cover(tgt):
		miss_c = maxf(miss_c, D.COVER_MISS)

	# --- iska: mermi sapar, nereye gittigi gorunur (toz pufu) ---
	if miss_c > 0.0 and not tgt.def.has("size") and rng.randf() < miss_c:
		var ma := rng.randf() * TAU
		var mp: Vector2 = tgt.position + Vector2(cos(ma), sin(ma)) \
			* (D.TILE * (0.5 + rng.randf() * D.MISS_SPREAD_T))
		Net.ev(D.Ev.TRACER, [att.position, mp, 0])
		if splash > 0.0:
			# sapan roket yine patlar: dustugu yerde alan hasari
			Net.ev(D.Ev.IMPACT, [mp, 0.8])
			_apply_area(att, tgt.owner_pid, mp, splash, 0.5)
		else:
			Net.ev(D.Ev.MISS_FX, [mp])
		return

	# --- isabet ---
	var dmg := attack_damage(att.def_id, att.def, tgt.def_id, tgt.def, _dist_t(att, tgt))
	if att.def.has("up_dmg"):
		dmg += float(att.def["up_dmg"]) * float(att.level - 1)
	Net.ev(D.Ev.TRACER, [att.position, tgt.position, 0])
	var victims: Array = [[tgt, dmg]]
	if splash > 0.0:
		Net.ev(D.Ev.IMPACT, [tgt.position, 0.8])
		for o in GameState.entities.values():
			if o == tgt or o.owner_pid != tgt.owner_pid:
				continue
			if _dist_t(o, tgt) <= splash:
				victims.append([o, attack_damage(att.def_id, att.def, o.def_id, o.def, 0.0) * 0.5])
	_apply_damage(victims)


func _apply_area(att: Node, victim_pid: int, at: Vector2, radius_t: float, mult: float) -> void:
	## Noktasal patlama: yaricap icindeki TUM victim_pid varliklarina hasar.
	var victims: Array = []
	for o in GameState.entities.values():
		if o.owner_pid != victim_pid:
			continue
		var d: float = o.position.distance_to(at) / float(D.TILE)
		if o.def.has("size"):
			var r: Rect2 = o.footprint_px()
			d = at.clamp(r.position, r.position + r.size).distance_to(at) / float(D.TILE)
		if d <= radius_t:
			victims.append([o, attack_damage(att.def_id, att.def, o.def_id, o.def, 0.0) * mult])
	_apply_damage(victims)


func _apply_damage(victims: Array) -> void:
	for v in victims:
		var n: Node = v[0]
		n.set_hp(n.hp - v[1])
	for v in victims:
		var n: Node = v[0]
		if GameState.entities.has(n.id) and n.hp <= 0.0:
			_kill(n)


func _kill(tgt: Node) -> void:
	var was_hall: bool = tgt.def_id == &"city_hall"
	var owner: int = tgt.owner_pid
	despawn(tgt, 1)
	if was_hall and GameState.result.is_empty():
		Net.game_over(GameState.enemy_of(owner), D.Reason.DESTRUCTION)


static func attack_damage(att_id: StringName, att: Dictionary, def_id: StringName,
		dfn: Dictionary, dist_t: float) -> float:
	## Saf hasar hesabi: matris + counter istisnalari. Testler dogrudan cagirir.
	var att_klass: int = att.get("klass", D.Klass.BUILDING)
	var def_klass: int = dfn.get("klass", D.Klass.BUILDING)
	var mult: float = D.DMG_MATRIX[att_klass][def_klass]
	if att_id == &"sniper" and def_klass == D.Klass.INFANTRY:
		mult = D.SNIPER_VS_INFANTRY
	elif att_id == &"rpg" and (def_klass == D.Klass.ARMOR or def_klass == D.Klass.BUILDING):
		mult = D.RPG_VS_ARMOR_BUILDING
	elif att_id == &"rifleman" and def_id == &"sniper" and dist_t <= D.RIFLE_VS_SNIPER_RANGE_T:
		mult = D.RIFLE_VS_SNIPER_CLOSE
	return float(att["dmg"]) * mult


func _dist_t(a: Node, b: Node) -> float:
	## Iki varlik arasi mesafe (tile); binalarda footprint'in en yakin noktasi.
	var p: Vector2 = a.position
	var q: Vector2 = b.position
	if b.def.has("size"):
		var rb: Rect2 = b.footprint_px()
		q = p.clamp(rb.position, rb.position + rb.size)
	if a.def.has("size"):
		var ra: Rect2 = a.footprint_px()
		p = q.clamp(ra.position, ra.position + ra.size)
	return p.distance_to(q) / float(D.TILE)


func _nearest_enemy_unit(e: Node, range_t: float) -> Node:
	var enemy := GameState.enemy_of(e.owner_pid)
	var best: Node = null
	var bd := 1e9
	for o in GameState.entities.values():
		if o.owner_pid != enemy or not o.def.has("speed_t"):
			continue
		var d := _dist_t(e, o)
		if d <= range_t and d < bd:
			bd = d
			best = o
	return best


func _nearest_enemy(e: Node, range_t: float) -> Node:
	## Menzildeki en yakin dusman; birimler binalara tercih edilir.
	var enemy := GameState.enemy_of(e.owner_pid)
	var best_u: Node = null
	var bu := 1e9
	var best_b: Node = null
	var bb := 1e9
	for o in GameState.entities.values():
		if o.owner_pid != enemy:
			continue
		var d := _dist_t(e, o)
		if d > range_t:
			continue
		if o.def.has("speed_t"):
			if d < bu:
				bu = d
				best_u = o
		elif d < bb:
			bb = d
			best_b = o
	return best_u if best_u != null else best_b


func _cell_of(e: Node) -> Vector2i:
	if e.def.has("size"):
		return e.cell
	return e.cell()


func _check_victory() -> void:
	## Metropol Zaferi: nufus hedefi + her bina turunden >=1 tamamlanmis.
	## (Yikim zaferi _kill aninda verilir.)
	if not GameState.result.is_empty():
		return
	for pid in [1, 2]:
		if GameState.pop_used[pid] < D.METROPOLIS_POP:
			continue
		var have := {}
		for b in _buildings(pid):
			if b.is_complete() and not b.def.has("bridge") and not b.def.has("mine") \
					and not b.def.has("cover"):
				have[b.def_id] = true
		if have.size() >= D.metro_types():
			Net.game_over(pid, D.Reason.METROPOLIS)
			return


func _broadcast_snapshot() -> void:
	if not Net.net_active:
		return
	var ents: Array = GameState.entities.values()
	var i := 0
	while i < ents.size():
		Net.bc_snapshot(Net.encode_snapshot(ents.slice(i, i + D.SNAP_MAX_ENTS)))
		i += D.SNAP_MAX_ENTS


func _separate_units() -> void:
	## Ayni hucrede ust uste binen birimleri yumusakca iter (fizik yok).
	var buckets := {}
	for u in _units():
		var c: Vector2i = u.cell()
		if not buckets.has(c):
			buckets[c] = []
		buckets[c].append(u)
	for c in buckets:
		var arr: Array = buckets[c]
		if arr.size() < 2:
			continue
		for i in arr.size():
			for j in range(i + 1, arr.size()):
				var a: Node = arr[i]
				var b: Node = arr[j]
				# aktif yol izleyenleri itme: hareketle bogusup titremesinler
				var a_idle: bool = a.path_i >= a.path.size()
				var b_idle: bool = b.path_i >= b.path.size()
				if not a_idle and not b_idle:
					continue
				var dv: Vector2 = a.position - b.position
				var dl := dv.length()
				if dl >= 10.0:
					continue
				var push := dv.normalized() * 0.5 if dl > 0.01 else Vector2(0.5, 0.0)
				if a_idle and not pathing.is_solid(_px_to_cell(a.position + push)):
					a.position += push
				if b_idle and not pathing.is_solid(_px_to_cell(b.position - push)):
					b.position -= push


# === hareket / toplama ic mantigi ===

func _set_move(u: Node, cell: Vector2i) -> void:
	u.task = {"kind": &"move", "cell": cell}
	_repath(u)


func _repath(u: Node) -> void:
	var goal: Vector2i = u.task.get("cell", u.cell())
	u.path = pathing.find(u.cell(), goal, true, _half_pid(u.owner_pid))
	u.path_i = 0
	# ilk nokta zaten icinde oldugumuz hucreyse atla: birim once kendi hucre
	# merkezine GERI yurumesin (sag-tik gecikmesi/ileri-geri titremesi buydu)
	if u.path.size() > 1 and u.path[0] == u.cell():
		u.path_i = 1
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
	# engebe: arazi turu hareket kabiliyetini belirler (kar yavas, kayalik cok yavas)
	var terrain_mult: float = D.TILE_SPEED.get(GameState.grid_at(u.cell()), 1.0)
	var speed: float = u.def["speed_t"] * D.TILE * terrain_mult
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
		var base := D.Tile.SNOW if GameState.map_type == D.MapType.SNOW else D.Tile.GRASS
		Net.ev(D.Ev.DEPLETED, [c, base])   # tukenen hucre zemine doner (cim/kar)
		for w in _units():
			if w.task.get("kind") == &"gather" and w.task.get("cell") == c:
				_retarget_gather(w, c)


func _retarget_gather(u: Node, from_c: Vector2i) -> void:
	var tile_kind: int = u.task.get("tile", -1)
	var best := _nearest_node(from_c, tile_kind, u.owner_pid)
	if best == Vector2i(-1, -1):
		u.task = {"kind": &"idle"}
		Net.toast_to(u.owner_pid, &"depleted")
	else:
		u.task = {"kind": &"gather", "cell": best, "tile": tile_kind}
		_repath(u)


func _nearest_node(from_c: Vector2i, tile_kind: int, pid: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 9999
	var mid := D.MAP_W / 2
	for c: Vector2i in node_res:
		if GameState.grid_at(c) != tile_kind:
			continue
		if _at_peace() and ((pid == 1 and c.x >= mid) or (pid == 2 and c.x < mid)):
			continue   # baristayken sinir otesindeki kaynaga gidilmez
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


func _train_time(b: Node, def_id: StringName) -> float:
	## Egitim suresi; gelistirilmis kisla/fabrika seviye basina up_speed kadar hizlanir.
	var base: float = D.unit(def_id)["train_s"]
	if b.def.has("up_speed"):
		base *= maxf(0.4, 1.0 - float(b.def["up_speed"]) * float(b.level - 1))
	return base


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
				# gelistirilmis ev: seviye basina ek nufus
				cap += int(e.def.get("up_pop", 0)) * (e.level - 1)
		GameState.pop_used[pid] = used
		GameState.pop_cap[pid] = cap
