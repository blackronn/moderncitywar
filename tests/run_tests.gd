extends SceneTree
## Mini test kosucusu: tests/test_*.gd dosyalarini yukler, her birinin run()
## fonksiyonunu cagirir. run() hata mesajlari dizisi dondurur (bos = PASS).
## Kullanim: tools/godot.ps1 --headless --path . --script res://tests/run_tests.gd


func _initialize() -> void:
	# once derleme taramasi: bir script parse edilemiyorsa GDScript hatalari
	# sessizce yutup testleri sahte-PASS yapabiliyor; burada sert duvar var.
	var compile_fails := 0
	for dir in ["res://scripts", "res://tests", "res://tools"]:
		compile_fails += _compile_sweep(dir)
	if compile_fails > 0:
		print("TESTS_FAILED compile_errors=", compile_fails)
		quit(1)
		return

	var failures := 0
	var files := DirAccess.get_files_at("res://tests")
	files.sort()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			failures += 1
			print("FAIL ", f, " (derlenemedi)")
			continue
		var inst: RefCounted = script.new()
		var result: Variant = inst.run()
		if typeof(result) != TYPE_ARRAY:
			failures += 1
			print("FAIL ", f, " (run() Array dondurmedi - script hatasi?)")
			continue
		var errs: Array = result
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


func _compile_sweep(dir: String) -> int:
	var bad := 0
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var s: GDScript = load(dir + "/" + f)
			if s == null or not s.can_instantiate():
				print("COMPILE_FAIL ", dir, "/", f)
				bad += 1
	for d in DirAccess.get_directories_at(dir):
		bad += _compile_sweep(dir + "/" + d)
	return bad
