extends Node
## M2 host botu: P2 icin kucuk bir ordu spawn eder (sim kisayolu; ekonomi
## hatti M1 smoke'unda zaten test edildi). Sonra istemcinin savas ilani +
## saldirisiyla kendi Belediyesi'nin yikilmasini bekler: winner=2 ve
## reason=DESTRUCTION dogrulanirsa SMOKE_PASS_HOST.

const D := preload("res://scripts/autoload/defs.gd")
const TIMEOUT_S := 110.0

var _finished := false


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_S).timeout.connect(_fail)
	Bus.game_over.connect(_on_over)
	if GameState.match_running:
		_run()
	else:
		Bus.match_started.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var sim: Node = Net.sim
	if sim == null:
		_fail()
		return
	var p2_tl: Vector2i = GameState.spawns[1]
	for off in [Vector2i(-2, 1), Vector2i(-2, 3), Vector2i(-3, 2)]:
		sim.spawn_unit(&"rifleman", 2, sim.cell_center(p2_tl + off))
	sim.spawn_unit(&"rpg", 2, sim.cell_center(p2_tl + Vector2i(-3, 4)))
	sim.recount_pop()
	print("BOT_HOST P2 ordusu hazir")


func _on_over(winner: int, reason: int) -> void:
	if _finished:
		return
	_finished = true
	if winner == 2 and reason == D.Reason.DESTRUCTION:
		print("SMOKE_PASS_HOST")
		get_tree().quit(0)
	else:
		printerr("SMOKE_FAIL_HOST yanlis sonuc w=%d r=%d" % [winner, reason])
		get_tree().quit(1)


func _fail() -> void:
	if _finished:
		return
	_finished = true
	printerr("SMOKE_FAIL_HOST timeout")
	get_tree().quit(1)
