extends Node
## M0 host smoke botu: mac baslayinca SMOKE_PASS_HOST basar, kisa sure sonra
## cikar (istemcinin de gormesi icin). Zaman asiminda FAIL + exit 1.

const TIMEOUT_S := 60.0


func _ready() -> void:
	if GameState.match_running:
		_pass()
		return
	Bus.match_started.connect(_pass)
	get_tree().create_timer(TIMEOUT_S).timeout.connect(_fail)


func _pass() -> void:
	print("SMOKE_PASS_HOST")
	await get_tree().create_timer(2.0).timeout
	get_tree().quit(0)


func _fail() -> void:
	printerr("SMOKE_FAIL_HOST timeout")
	get_tree().quit(1)
