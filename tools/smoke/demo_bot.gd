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
	# --spread-test: 12 piyadeyi tek noktaya yuru emriyle gonder; spiral
	# hedef dagitimi + ayrisma sayesinde IC ICE GIRMEDEN dizilmeliler
	if arg_has(&"--spread-test"):
		var ids := PackedInt32Array()
		for i in 12:
			var u2: Node = sim.spawn_unit(&"rifleman", 1,
				sim.cell_center(tl + Vector2i(-4 + (i % 4), 6 + (i / 4))))
			ids.append(u2.id)
		sim.recount_pop()
		var rally: Vector2 = sim.cell_center(tl + Vector2i(8, 8))
		Net.send_move(ids, rally)
		get_tree().current_scene.cam.position = rally
		_spread_diag.call_deferred(ids, rally)

	# --hold-test: P1 piyadesi KONUSLU, P2 piyadesi 5 tile oteden aggro'yla
	# kosup gelir; konuslu olan YERINDEN OYNAMAMALI ama menzile gireni vurmali
	if arg_has(&"--hold-test"):
		# sehirdeki demo birimlerinden UZAK bir arena (karismasinlar)
		var hu: Node = sim.spawn_unit(&"rifleman", 1, sim.cell_center(tl + Vector2i(14, -14)))
		sim.handle_hold(1, PackedInt32Array([hu.id]), true)
		var foe: Node = sim.spawn_unit(&"rifleman", 2, sim.cell_center(tl + Vector2i(19, -14)))
		sim.recount_pop()
		_hold_diag.call_deferred(hu, hu.position, foe)

	# --dodge-test: iki izole arena; konuslu havanlar yanal mekik atan
	# hedeflere atis yapar. TANK (22 px/sn) yakalanmali, KOMANDO (48) kacmali.
	if arg_has(&"--dodge-test"):
		var ma: Node = sim.spawn_unit(&"mortar", 2, sim.cell_center(tl + Vector2i(20, -17)))
		var mb: Node = sim.spawn_unit(&"mortar", 2, sim.cell_center(tl + Vector2i(20, -7)))
		sim.handle_hold(2, PackedInt32Array([ma.id, mb.id]), true)
		ma.setup_t = 0.0
		mb.setup_t = 0.0
		var tank: Node = sim.spawn_unit(&"tank", 1, sim.cell_center(tl + Vector2i(14, -18)))
		var cmd: Node = sim.spawn_unit(&"commando", 1, sim.cell_center(tl + Vector2i(14, -8)))
		sim.recount_pop()
		_dodge_walk(tank, tl + Vector2i(14, -18))
		_dodge_walk(cmd, tl + Vector2i(14, -8))
		_dodge_diag.call_deferred(tank, cmd)

	# secim: varsayilan isci (insa menusu); --select=<birim> ile degisir
	# (orn. --select=mortar -> menzil halkasi gorseli)
	var want: StringName = &"worker"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--select="):
			want = StringName(arg.get_slice("=", 1))
	var game := get_tree().current_scene
	var ic: Node = game.get_node_or_null("InputController")
	if ic != null:
		for e in GameState.entities.values():
			if e.owner_pid == 1 and e.def_id == want:
				var sel: Array[int] = [e.id]
				ic._set_selection(sel)
				if arg_has(&"--cam-select"):
					game.cam.position = e.position
				break


func _spread_diag(ids: PackedInt32Array, rally: Vector2) -> void:
	await get_tree().create_timer(3.0).timeout
	var moved := 0
	var cells := {}
	for id in ids:
		var e: Node = GameState.ent(id)
		if e == null:
			continue
		if e.position.distance_to(rally) < 80.0:
			moved += 1
		cells[e.cell()] = cells.get(e.cell(), 0) + 1
	var worst := 0
	for c in cells:
		worst = maxi(worst, cells[c])
	print("SPREAD_DIAG yakin=", moved, "/", ids.size(), " ayni_hucre_max=", worst,
		" ilk_task=", GameState.ent(ids[0]).task if GameState.ent(ids[0]) != null else "?")


func _dodge_walk(u: Node, base: Vector2i) -> void:
	## 12 sn boyunca 3'er hucre yanal mekik: surekli hareket = kacma denemesi.
	for i in 6:
		if not is_instance_valid(u) or not GameState.entities.has(u.id):
			return
		var off := Vector2i(0, 3 if i % 2 == 0 else -3)
		Net.sim.handle_move(1, PackedInt32Array([u.id]), Net.sim.cell_center(base + off))
		await get_tree().create_timer(2.0).timeout


func _dodge_diag(tank: Node, cmd: Node) -> void:
	await get_tree().create_timer(13.0).timeout
	var t_hp: float = tank.hp if is_instance_valid(tank) and GameState.entities.has(tank.id) else 0.0
	var c_hp: float = cmd.hp if is_instance_valid(cmd) and GameState.entities.has(cmd.id) else 0.0
	print("DODGE_DIAG tank_hp=%.0f/450 komando_hp=%.0f/120" % [t_hp, c_hp])


func _hold_diag(hu: Node, start: Vector2, foe: Node) -> void:
	await get_tree().create_timer(5.0).timeout
	var moved: float = hu.position.distance_to(start) if is_instance_valid(hu) else -1.0
	var foe_hp: float = foe.hp if is_instance_valid(foe) and GameState.entities.has(foe.id) else 0.0
	var hold_s: String = str(hu.hold) if is_instance_valid(hu) else "?"
	print("HOLD_DIAG p1_moved_px=%.1f hold=%s foe_hp=%.0f" % [moved, hold_s, foe_hp])


func arg_has(flag: StringName) -> bool:
	for arg in OS.get_cmdline_user_args():
		if StringName(arg) == flag:
			return true
	return false


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
