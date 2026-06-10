extends Node
## M1 host botu: belediyeden isci egitir (dogrudan sim yolu), nufus 1->2
## olunca SMOKE_PASS_HOST basar; istemci ayrilip game_over gelince cikar.

const D := preload("res://scripts/autoload/defs.gd")
const TIMEOUT_S := 110.0

var _passed := false


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_S).timeout.connect(_fail)
	Bus.game_over.connect(_on_over)
	if GameState.match_running:
		_run()
	else:
		Bus.match_started.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var hall := _find_own(&"city_hall")
	if hall == null:
		_fail()
		return
	print("BOT_HOST train worker")
	Net.send_train(hall.id, &"worker")
	while not _passed and GameState.pop_used[1] < 2:
		await get_tree().create_timer(0.25).timeout
	if _passed:
		return
	_passed = true
	print("SMOKE_PASS_HOST")
	# istemci senaryosunu bitirip ayrilinca game_over -> _on_over cikar


func _on_over(_winner: int, _reason: int) -> void:
	get_tree().quit(0)


func _find_own(def_id: StringName) -> Node:
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid and e.def_id == def_id:
			return e
	return null


func _fail() -> void:
	if _passed:
		return
	printerr("SMOKE_FAIL_HOST timeout/assert")
	get_tree().quit(1)
