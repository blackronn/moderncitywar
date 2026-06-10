extends Node
## M0 istemci smoke botu: mac baslayinca SMOKE_PASS_CLIENT basar ve cikar.

const TIMEOUT_S := 60.0


func _ready() -> void:
	if GameState.match_running:
		_pass()
		return
	Bus.match_started.connect(_pass)
	get_tree().create_timer(TIMEOUT_S).timeout.connect(_fail)


func _pass() -> void:
	print("SMOKE_PASS_CLIENT")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _fail() -> void:
	printerr("SMOKE_FAIL_CLIENT timeout")
	get_tree().quit(1)
