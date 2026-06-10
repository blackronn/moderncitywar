extends SceneTree
## Mini test kosucusu: tests/test_*.gd dosyalarini yukler, her birinin run()
## fonksiyonunu cagirir. run() hata mesajlari dizisi dondurur (bos = PASS).
## Kullanim: tools/godot.ps1 --headless --path . --script res://tests/run_tests.gd


func _initialize() -> void:
	var failures := 0
	var files := DirAccess.get_files_at("res://tests")
	files.sort()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		var script: GDScript = load("res://tests/" + f)
		var inst: RefCounted = script.new()
		var errs: Array = inst.run()
		if errs.is_empty():
			print("PASS ", f)
		else:
			failures += errs.size()
			print("FAIL ", f)
			for e in errs:
				print("  - ", e)
	if failures == 0:
		print("ALL_TESTS_PASSED")
		quit(0)
	else:
		print("TESTS_FAILED count=", failures)
		quit(1)
