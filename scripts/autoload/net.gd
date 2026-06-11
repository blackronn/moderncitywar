extends Node
## Tum ag yuzeyi TEK dosyada: ENet kurulumu, projedeki butun @rpc'ler,
## snapshot kodegi ve sahne-hazir-degilken-gelen-cagri tamponu.
## RPC'ler dinamik node'larda degil hep /root/Net uzerinde yasar (iki ucta
## ayni NodePath sart); entity'ler paketlerde int id ile anilir.
## Host otoriterdir: istemci yalnizca cmd_* gonderir, simulasyonu host kosar.

const D := preload("res://scripts/autoload/defs.gd")

const PORT := 8910

var net_active := false              # gercek baglanti var mi (offline onizleme = false)
var client_peer_id := 0              # host tarafinda istemcinin ENet peer id'si
var game_ready := false              # lokal game sahnesi sv_* almaya hazir mi
var sim: Node = null                 # host'ta game.gd kaydeder (sim.gd)
var _buffer: Array = []              # game_ready oncesi gelen [metod, argv] cagrilari
var _host_scene_ready := false
var _client_ready := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return multiplayer.is_server()    # offline'da da true


func host_game() -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(PORT, 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = p
	net_active = true
	GameState.my_pid = 1
	return OK


func join_game(ip: String) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = p
	net_active = true
	GameState.my_pid = 2
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	net_active = false
	client_peer_id = 0
	game_ready = false
	sim = null
	_buffer.clear()
	_host_scene_ready = false
	_client_ready = false


# === baglanti akisi ===

func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	client_peer_id = id
	# mac seed'i: degeri rastgele olabilir, onemli olan iki uca ayni gitmesi
	GameState.reset((randi() % 899999) + 100000)
	GameState.my_pid = 1
	sv_hello.rpc_id(id, 2, GameState.seed_v, D.defs_hash())
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_peer_disconnected(_id: int) -> void:
	if not is_host():
		return
	client_peer_id = 0
	_client_ready = false
	if GameState.match_running and GameState.result.is_empty():
		_apply_game_over(1, D.Reason.OPPONENT_LEFT)
	else:
		Bus.lobby_status.emit(Tr.t(&"opponent_left"))


func _on_connected_ok() -> void:
	Bus.lobby_status.emit(Tr.t(&"connected_waiting"))


func _on_connection_failed() -> void:
	leave()
	Bus.net_error.emit(Tr.t(&"connection_failed"))


func _on_server_disconnected() -> void:
	var was_running: bool = GameState.match_running and GameState.result.is_empty()
	leave()
	if was_running:
		_apply_game_over(GameState.my_pid, D.Reason.OPPONENT_LEFT)
	else:
		Bus.net_error.emit(Tr.t(&"connection_lost"))


@rpc("authority", "call_remote", "reliable")
func sv_hello(pid: int, p_seed: int, defs_h: int) -> void:
	# istemcide calisir: surum kontrolu + ayni seed'le haritayi lokal uret
	if defs_h != D.defs_hash():
		Bus.net_error.emit(Tr.t(&"version_mismatch"))
		leave()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	GameState.reset(p_seed)
	GameState.my_pid = pid
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func set_game_ready() -> void:
	## game.gd _ready sonunda cagirir: harita uretildi, gorseller kuruldu.
	game_ready = true
	var pending := _buffer.duplicate()
	_buffer.clear()
	for call_data in pending:
		callv(call_data[0], call_data[1])
	if is_host():
		_host_scene_ready = true
		_try_start_match()
	else:
		cmd_client_ready.rpc_id(1, GameState.map_hash)


func _try_start_match() -> void:
	if not _host_scene_ready or GameState.match_running or not GameState.result.is_empty():
		return
	if net_active and not _client_ready:
		return
	if sim != null:
		sim.start_match()


func _buffered(method: StringName, argv: Array) -> bool:
	if game_ready:
		return false
	_buffer.append([method, argv])
	return true


@rpc("any_peer", "call_remote", "reliable")
func cmd_client_ready(map_hash: int) -> void:
	if not is_host() or client_peer_id == 0:
		return
	if multiplayer.get_remote_sender_id() != client_peer_id:
		return
	_client_ready_check(map_hash)


func _client_ready_check(map_hash: int) -> void:
	# host sahnesi henuz hazir degilse erteleyip ayni kontrolu sonra yap
	if _buffered(&"_client_ready_check", [map_hash]):
		return
	if map_hash != GameState.map_hash:
		push_error("Harita hash uyusmazligi: host=%d istemci=%d" % [GameState.map_hash, map_hash])
		if multiplayer.multiplayer_peer != null and client_peer_id != 0:
			multiplayer.multiplayer_peer.disconnect_peer(client_peer_id)
		return
	_client_ready = true
	_try_start_match()


# === komutlar: UI iki tarafta da send_* cagirir, host'ta dogrudan sim'e,
# === istemcide rpc ile host'a gider. Host istemci payload'ina degil
# === get_remote_sender_id()'ye guvenir.

func _cmd_pid() -> int:
	if not is_host() or client_peer_id == 0:
		return 0
	return 2 if multiplayer.get_remote_sender_id() == client_peer_id else 0


func send_move(ids: PackedInt32Array, target: Vector2) -> void:
	if is_host():
		if sim != null: sim.handle_move(1, ids, target)
	else:
		cmd_move.rpc_id(1, ids, target)


func send_gather(ids: PackedInt32Array, cell: Vector2i) -> void:
	if is_host():
		if sim != null: sim.handle_gather(1, ids, cell)
	else:
		cmd_gather.rpc_id(1, ids, cell)


func send_build(def_id: StringName, cell: Vector2i, builder_ids: PackedInt32Array) -> void:
	if is_host():
		if sim != null: sim.handle_build(1, def_id, cell, builder_ids)
	else:
		cmd_build.rpc_id(1, def_id, cell, builder_ids)


func send_assign_build(ids: PackedInt32Array, building_id: int) -> void:
	if is_host():
		if sim != null: sim.handle_assign_build(1, ids, building_id)
	else:
		cmd_assign_build.rpc_id(1, ids, building_id)


func send_upgrade(building_id: int) -> void:
	if is_host():
		if sim != null: sim.handle_upgrade(1, building_id)
	else:
		cmd_upgrade.rpc_id(1, building_id)


func send_train(building_id: int, def_id: StringName) -> void:
	if is_host():
		if sim != null: sim.handle_train(1, building_id, def_id)
	else:
		cmd_train.rpc_id(1, building_id, def_id)


func send_cancel_train(building_id: int, index: int) -> void:
	if is_host():
		if sim != null: sim.handle_cancel_train(1, building_id, index)
	else:
		cmd_cancel_train.rpc_id(1, building_id, index)


func send_attack(ids: PackedInt32Array, target_id: int) -> void:
	if is_host():
		if sim != null: sim.handle_attack(1, ids, target_id)
	else:
		cmd_attack.rpc_id(1, ids, target_id)


func send_declare_war() -> void:
	if is_host():
		if sim != null: sim.handle_declare_war(1)
	else:
		cmd_declare_war.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func cmd_move(ids: PackedInt32Array, target: Vector2) -> void:
	if _cmd_pid() == 2 and sim != null:
		sim.handle_move(2, ids, target)


@rpc("any_peer", "call_remote", "reliable")
func cmd_gather(ids: PackedInt32Array, cell: Vector2i) -> void:
	if _cmd_pid() == 2 and sim != null:
		sim.handle_gather(2, ids, cell)


@rpc("any_peer", "call_remote", "reliable")
func cmd_build(def_id: StringName, cell: Vector2i, builder_ids: PackedInt32Array) -> void:
	if _cmd_pid() == 2 and sim != null:
		sim.handle_build(2, def_id, cell, builder_ids)


@rpc("any_peer", "call_remote", "reliable")
func cmd_assign_build(ids: PackedInt32Array, building_id: int) -> void:
	if _cmd_pid() == 2 and sim != null:
		sim.handle_assign_build(2, ids, building_id)


@rpc("any_peer", "call_remote", "reliable")
func cmd_upgrade(building_id: int) -> void:
	if _cmd_pid() == 2 and sim != null:
		sim.handle_upgrade(2, building_id)


@rpc("any_peer", "call_remote", "reliable")
func cmd_train(building_id: int, def_id: StringName) -> void:
	if _cmd_pid() == 2 and sim != null:
		sim.handle_train(2, building_id, def_id)


@rpc("any_peer", "call_remote", "reliable")
func cmd_cancel_train(building_id: int, index: int) -> void:
	if _cmd_pid() == 2 and sim != null:
		sim.handle_cancel_train(2, building_id, index)


@rpc("any_peer", "call_remote", "reliable")
func cmd_attack(ids: PackedInt32Array, target_id: int) -> void:
	if _cmd_pid() == 2 and sim != null:
		sim.handle_attack(2, ids, target_id)


@rpc("any_peer", "call_remote", "reliable")
func cmd_declare_war() -> void:
	if _cmd_pid() == 2 and sim != null:
		sim.handle_declare_war(2)


# === host -> istemci yayinlari (sim cagirir) ===

func _client_connected() -> bool:
	return net_active and client_peer_id != 0


func bc_spawn(id: int, def_id: StringName, owner_pid: int, pos: Vector2) -> void:
	if _client_connected():
		sv_spawn.rpc_id(client_peer_id, id, def_id, owner_pid, pos)


func bc_despawn(id: int, reason: int) -> void:
	if _client_connected():
		sv_despawn.rpc_id(client_peer_id, id, reason)


func ev(kind: int, args: Array = []) -> void:
	## host'ta lokal uygula + istemciye ilet
	_apply_event(kind, args)
	if _client_connected():
		sv_event.rpc_id(client_peer_id, kind, args)


func toast_to(pid: int, key: StringName) -> void:
	## tek oyuncuya ozel toast (orn. "savas ilan ettin" / "rakip ilan etti")
	if pid == 1:
		Bus.toast.emit(Tr.t(key))
	elif _client_connected():
		sv_event.rpc_id(client_peer_id, D.Ev.TOAST_KEY, [key])


func reject_to(pid: int, reason: int) -> void:
	if pid == 1:
		Bus.build_rejected.emit(reason)
	elif _client_connected():
		sv_event.rpc_id(client_peer_id, D.Ev.BUILD_REJECTED, [reason])


func bc_resources(pid: int) -> void:
	if not _client_connected():
		return
	var r: Dictionary = GameState.res[pid]
	sv_resources.rpc_id(client_peer_id, pid,
		int(r["wood"]), int(r["stone"]), int(r["food"]), int(r["money"]),
		GameState.pop_used[pid], GameState.pop_cap[pid])


func game_over(winner: int, reason: int) -> void:
	if _client_connected():
		sv_game_over.rpc_id(client_peer_id, winner, reason)
	_apply_game_over(winner, reason)


func bc_snapshot(blob: PackedByteArray) -> void:
	if _client_connected():
		sv_snapshot.rpc_id(client_peer_id, blob)


# === istemci tarafi alicilar ===

@rpc("authority", "call_remote", "reliable")
func sv_spawn(id: int, def_id: StringName, owner_pid: int, pos: Vector2) -> void:
	if _buffered(&"sv_spawn", [id, def_id, owner_pid, pos]):
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("spawn_entity_visual"):
		scene.spawn_entity_visual(id, def_id, owner_pid, pos)


@rpc("authority", "call_remote", "reliable")
func sv_despawn(id: int, reason: int) -> void:
	if _buffered(&"sv_despawn", [id, reason]):
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("despawn_entity_visual"):
		scene.despawn_entity_visual(id, reason)


@rpc("authority", "call_remote", "reliable")
func sv_event(kind: int, args: Array) -> void:
	if _buffered(&"sv_event", [kind, args]):
		return
	_apply_event(kind, args)


@rpc("authority", "call_remote", "reliable")
func sv_resources(pid: int, wood: int, stone: int, food: int, money: int, p_used: int, p_cap: int) -> void:
	if _buffered(&"sv_resources", [pid, wood, stone, food, money, p_used, p_cap]):
		return
	GameState.res[pid] = {
		"wood": float(wood), "stone": float(stone),
		"food": float(food), "money": float(money),
	}
	GameState.pop_used[pid] = p_used
	GameState.pop_cap[pid] = p_cap
	Bus.resources_changed.emit(pid)


@rpc("authority", "call_remote", "reliable")
func sv_game_over(winner: int, reason: int) -> void:
	if _buffered(&"sv_game_over", [winner, reason]):
		return
	_apply_game_over(winner, reason)


@rpc("authority", "call_remote", "unreliable_ordered")
func sv_snapshot(blob: PackedByteArray) -> void:
	if not game_ready:
		return    # snapshot tamponlanmaz, siradaki nasil olsa gelir
	apply_snapshot(blob)


func _apply_event(kind: int, args: Array) -> void:
	match kind:
		D.Ev.MATCH_STARTED:
			GameState.match_running = true
			Bus.match_started.emit()
			Bus.toast.emit(Tr.t(&"match_started"))
			print("MATCH_STARTED pid=", GameState.my_pid)   # smoke testler bunu arar
		D.Ev.WAR_STATE:
			GameState.war_state = args[0]
			GameState.war_t_left = args[1]
			Bus.war_changed.emit(args[0], args[1])
		D.Ev.DEPLETED:
			var cell: Vector2i = args[0]
			GameState.grid_set(cell, D.Tile.GRASS)
			var scene := get_tree().current_scene
			if scene != null and scene.has_method("on_tile_depleted"):
				scene.on_tile_depleted(cell)
		D.Ev.BUILD_REJECTED:
			Bus.build_rejected.emit(args[0])
		D.Ev.TRACER:
			var scene := get_tree().current_scene
			if scene != null and scene.has_method("show_tracer"):
				scene.show_tracer(args[0], args[1], args[2] if args.size() > 2 else 0)
		D.Ev.TOAST_KEY:
			Bus.toast.emit(Tr.t(args[0]))
		D.Ev.LEVEL:
			var node: Node = GameState.entities.get(args[0])
			if node != null:
				node.level = args[1]
				node.queue_redraw()
				Bus.entity_level_changed.emit(args[0])
		D.Ev.IMPACT:
			var scene := get_tree().current_scene
			if scene != null and scene.has_method("spawn_fx"):
				scene.spawn_fx(&"explosion", args[0], args[1])


func _apply_game_over(winner: int, reason: int) -> void:
	GameState.result = {"winner": winner, "reason": reason}
	GameState.match_running = false
	Bus.game_over.emit(winner, reason)
	print("GAME_OVER winner=", winner, " reason=", reason, " pid=", GameState.my_pid)


# === snapshot kodegi ===
# kayit: u16 id | u16 x*8 | u16 y*8 | u16 hp | u8 bayraklar | u8 ilerleme(0-100)

static func encode_snapshot(ents: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u16(ents.size())
	for e in ents:
		buf.put_u16(e.id)
		buf.put_u16(clampi(int(e.position.x * 8.0), 0, 65535))
		buf.put_u16(clampi(int(e.position.y * 8.0), 0, 65535))
		buf.put_u16(clampi(int(ceilf(e.hp)), 0, 65535))
		buf.put_u8(e.snapshot_flags())
		buf.put_u8(clampi(int(e.display_progress() * 100.0), 0, 100))
	return buf.data_array


func apply_snapshot(blob: PackedByteArray) -> void:
	var buf := StreamPeerBuffer.new()
	buf.data_array = blob
	var count := buf.get_u16()
	var now := Time.get_ticks_msec() / 1000.0
	for _i in count:
		var id := buf.get_u16()
		var px := buf.get_u16() / 8.0
		var py := buf.get_u16() / 8.0
		var hp := buf.get_u16()
		var flags := buf.get_u8()
		var progress := buf.get_u8() / 100.0
		var node: Node = GameState.entities.get(id)
		if node != null:
			node.net_update(Vector2(px, py), hp, flags, progress, now)
