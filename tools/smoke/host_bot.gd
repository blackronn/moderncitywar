extends Node
## Host smoke botu. --scenario= ile senaryo secer:
##   war (varsayilan): P2'ye ordu spawn eder, istemcinin savas ilani +
##     saldirisiyla yikilmayi bekler -> (2, DESTRUCTION) PASS
##   disconnect: hicbir sey yapmaz; istemci kacinca -> (1, OPPONENT_LEFT) PASS
##   metro: P1'e tam metropol kurar -> (1, METROPOLIS) PASS
##   ffa: 4 oyuncu (3 istemci); savas baslayinca P3/P4/P2 belediyelerini
##     sirayla yikar -> 3x ELIMINATED + (1, DESTRUCTION) PASS
## Lobi akisi: yeterli istemci baglaninca host_start() cagrilir (lobideki
## "Maci Baslat" butonunun yaptigi isin aynisi).

const D := preload("res://scripts/autoload/defs.gd")
const TIMEOUT_S := 110.0

var scenario := "war"
var _finished := false
var _started := false
var _ffa_seq := false
var _elims := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.get_slice("=", 1)
	get_tree().create_timer(TIMEOUT_S).timeout.connect(_fail)
	Bus.game_over.connect(_on_over)
	multiplayer.peer_connected.connect(_on_peer)
	if scenario == "ffa":
		Bus.war_changed.connect(_on_war_ffa)
		Bus.player_eliminated.connect(func(_pid): _elims += 1)
	if GameState.match_running:
		_run()
	else:
		Bus.match_started.connect(_run, CONNECT_ONE_SHOT)


func _need_clients() -> int:
	return 3 if scenario == "ffa" else 1


func _on_peer(_id: int) -> void:
	if _started or Net.peers.size() < _need_clients():
		return
	_started = true
	# istemci oylarinin gelmesi icin kisa bekleme, sonra lobi baslatma
	await get_tree().create_timer(0.8).timeout
	print("BOT_HOST mac baslatiliyor (%d oyuncu)" % Net.player_total())
	Net.host_start()


func _run() -> void:
	var sim: Node = Net.sim
	if sim == null:
		_fail()
		return
	match scenario:
		"war":
			var p2_tl: Vector2i = GameState.spawns[1]
			for off in [Vector2i(-2, 1), Vector2i(-2, 3), Vector2i(-3, 2)]:
				sim.spawn_unit(&"rifleman", 2, sim.cell_center(p2_tl + off))
			sim.spawn_unit(&"rpg", 2, sim.cell_center(p2_tl + Vector2i(-3, 4)))
			sim.recount_pop()
			print("BOT_HOST P2 ordusu hazir")
		"metro":
			_build_metropolis(sim)
			print("BOT_HOST metropol kuruldu")
		"disconnect":
			print("BOT_HOST istemcinin kacmasini bekliyor")
		"ffa":
			print("BOT_HOST ffa: P2'nin savas ilani bekleniyor")


func _on_war_ffa(state: int, _t: float) -> void:
	## Savas basladi: belediyeleri sirayla yik — her biri ELIMINATED uretmeli,
	## sonuncusunda tek kisi (P1) kalir ve mac biter.
	if state != D.War.WAR or _ffa_seq or Net.sim == null:
		return
	_ffa_seq = true
	await get_tree().create_timer(0.5).timeout
	for victim in [3, 4, 2]:
		if _finished:
			return
		_kill_hall(victim)
		await get_tree().create_timer(0.8).timeout


func _kill_hall(pid: int) -> void:
	for e in GameState.entities.values():
		if e.owner_pid == pid and e.def_id == &"city_hall":
			Net.sim._apply_damage([[e, 99999.0]])
			print("BOT_HOST P%d belediyesi yikildi" % pid)
			return


func _build_metropolis(sim: Node) -> void:
	var tl: Vector2i = GameState.spawns[0]
	# 9 ev (5 + 36 = 41 kapasite) + diger tum turler, tamamlanmis
	var house_offs := [
		Vector2i(4, 0), Vector2i(6, 0), Vector2i(8, 0),
		Vector2i(4, 2), Vector2i(6, 2), Vector2i(8, 2),
		Vector2i(4, 4), Vector2i(6, 4), Vector2i(8, 4),
	]
	for o: Vector2i in house_offs:
		sim.spawn_building(&"house", 1, tl + o, true)
	sim.spawn_building(&"greenhouse", 1, tl + Vector2i(0, 4), true)
	sim.spawn_building(&"bank", 1, tl + Vector2i(2, 4), true)
	sim.spawn_building(&"lumber_camp", 1, tl + Vector2i(0, 8), true)
	sim.spawn_building(&"quarry", 1, tl + Vector2i(2, 8), true)
	sim.spawn_building(&"barracks", 1, tl + Vector2i(0, 6), true)
	sim.spawn_building(&"factory", 1, tl + Vector2i(3, 6), true)
	sim.spawn_building(&"turret", 1, tl + Vector2i(6, 6), true)
	sim.recount_pop()
	# nufusu 40'a tamamla (1 isci zaten var)
	for i in 39:
		var c: Vector2i = sim.pathing.nearest_free(tl + Vector2i(2 + (i % 6), -2 - (i / 6)), 6)
		if c != Vector2i(-1, -1):
			sim.spawn_unit(&"worker", 1, sim.cell_center(c))
	sim.recount_pop()


func _on_over(winner: int, reason: int) -> void:
	if _finished:
		return
	_finished = true
	var ok := false
	match scenario:
		"war":
			ok = winner == 2 and reason == D.Reason.DESTRUCTION
		"disconnect":
			ok = winner == 1 and reason == D.Reason.OPPONENT_LEFT
		"metro":
			ok = winner == 1 and reason == D.Reason.METROPOLIS
		"ffa":
			ok = winner == 1 and reason == D.Reason.DESTRUCTION and _elims >= 3
	if ok:
		print("SMOKE_PASS_HOST")
		# sv_game_over paketinin istemcilere ulasmasi icin cikmadan once bekle
		# (aninda quit ENet kuyrugunu flush etmeden sureci oldurur)
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)
	else:
		printerr("SMOKE_FAIL_HOST yanlis sonuc w=%d r=%d elim=%d senaryo=%s" % [winner, reason, _elims, scenario])
		get_tree().quit(1)


func _fail() -> void:
	if _finished:
		return
	_finished = true
	printerr("SMOKE_FAIL_HOST timeout (senaryo=%s)" % scenario)
	get_tree().quit(1)
