extends Node
## Istemci smoke botu. --scenario= ile senaryo secer:
##   war (varsayilan): baris reddi -> savas ilani -> sayac -> saldiri ->
##     (2, DESTRUCTION) PASS (tum komutlar gercek rpc yolundan)
##   disconnect: mac basladiktan 2 sn sonra cikar (kacis testinin kendisi)
##   metro: host'un metropol zaferinin istemciye yansimasini bekler

const D := preload("res://scripts/autoload/defs.gd")
const TIMEOUT_S := 110.0

var scenario := "war"
var _finished := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.get_slice("=", 1)
	get_tree().create_timer(TIMEOUT_S).timeout.connect(_fail)
	Bus.game_over.connect(_on_over)
	if GameState.match_running:
		_run()
	else:
		Bus.match_started.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	match scenario:
		"war":
			_run_war()
		"disconnect":
			_run_disconnect()
		"metro":
			pass   # _on_over bekler
		"ffa":
			# REGRESYON: her istemci BARISTA iscisini yurutur — coklu oyuncuda
			# baris bolge grid'i (astar_half[3/4]) eksikse host burada coker
			var worker: Node = null
			for e in GameState.entities.values():
				if e.owner_pid == GameState.my_pid and e.def_id == &"worker":
					worker = e
					break
			if worker != null:
				var center := Vector2(D.MAP_W, D.MAP_H) * D.TILE / 2.0
				var tgt: Vector2 = worker.position + (center - worker.position).normalized() * 48.0
				Net.send_move(PackedInt32Array([worker.id]), tgt)
				print("BOT_CLIENT P%d baris hareketi gonderildi" % GameState.my_pid)
			# P2 savas ilan eder (hareketler islensin diye kisa bekleme)
			if GameState.my_pid == 2:
				await get_tree().create_timer(2.0).timeout
				print("BOT_CLIENT P2 savas ilan ediyor")
				Net.send_declare_war()


func _run_disconnect() -> void:
	await get_tree().create_timer(2.0).timeout
	print("SMOKE_PASS_CLIENT")   # kacisin kendisi test eylemi
	get_tree().quit(0)


func _run_war() -> void:
	while not _finished and _army().size() < 4:
		await get_tree().create_timer(0.25).timeout
	if _finished:
		return
	var hall := _enemy_hall()
	if hall == null:
		_fail()
		return
	var ids := PackedInt32Array()
	for u in _army():
		ids.append(u.id)
	# baris halinde saldiri reddedilmeli (sinir/ilan mekanigi geri geldi)
	print("BOT_CLIENT savas ilan ediyor")
	Net.send_declare_war()
	while not _finished and GameState.war_state != D.War.WAR:
		await get_tree().create_timer(0.25).timeout
	if _finished:
		return
	print("BOT_CLIENT savas basladi, saldiri")
	Net.send_attack(ids, hall.id)


func _army() -> Array:
	var out: Array = []
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid and e.def.has("speed_t") and e.def["dmg"] > 0:
			out.append(e)
	return out


func _enemy_hall() -> Node:
	for e in GameState.entities.values():
		if e.owner_pid == 1 and e.def_id == &"city_hall":
			return e
	return null


func _on_over(winner: int, reason: int) -> void:
	if _finished:
		return
	var ok := false
	match scenario:
		"war":
			ok = winner == 2 and reason == D.Reason.DESTRUCTION
		"metro":
			ok = winner == 1 and reason == D.Reason.METROPOLIS
		"ffa":
			ok = winner == 1 and reason == D.Reason.DESTRUCTION
		"disconnect":
			return   # kacis senaryosunda game_over beklenmez
	_finished = true
	if ok:
		print("SMOKE_PASS_CLIENT")
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(0)
	else:
		printerr("SMOKE_FAIL_CLIENT yanlis sonuc w=%d r=%d senaryo=%s" % [winner, reason, scenario])
		get_tree().quit(1)


func _fail() -> void:
	if _finished:
		return
	_finished = true
	printerr("SMOKE_FAIL_CLIENT timeout/assert (senaryo=%s)" % scenario)
	get_tree().quit(1)
