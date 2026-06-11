extends Control
## VoxGard ana menu: amblem + wordmark + soft butonlar.
## Komut satiri bayraklarini da burasi isler:
##   --smoke-host / --smoke-join=IP [--scenario=...] : headless e2e botlari
##   --preview / --demo [--screenshot=yol] [--end]   : onizleme/screenshot
##   --speed=N                                       : sim hizlandirma

const D := preload("res://scripts/autoload/defs.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const LobbyScript := preload("res://scripts/ui/lobby.gd")

var status: Label


func _ready() -> void:
	_build_ui()
	_handle_cli()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	# amblem panel DISINDA, basligin tepesinde
	var emblem := TextureRect.new()
	emblem.texture = load("res://assets/ui/voxgard-emblem.png")
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.custom_minimum_size = Vector2(170, 170)
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(emblem)

	# celik panel (percinli) icinde wordmark + butonlar
	var panel := PanelContainer.new()
	UiKit.panel(panel, 0.0, 16.0)
	col.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	var wordmark := TextureRect.new()
	wordmark.texture = load("res://assets/ui/voxgard-wordmark.png")
	wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wordmark.custom_minimum_size = Vector2(330, 64)
	box.add_child(wordmark)

	var sub := Label.new()
	sub.text = Tr.t(&"subtitle")
	UiKit.label(sub, 7, UiKit.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	box.add_child(_spacer(8.0))
	box.add_child(_menu_button(Tr.t(&"host_game"), _on_host, UiKit.ACCENT_BLUE))
	box.add_child(_menu_button(Tr.t(&"join_game"), _on_join, Color.TRANSPARENT))
	box.add_child(_menu_button(Tr.t(&"single_player"), _on_single, Color.TRANSPARENT))
	box.add_child(_menu_button(Tr.t(&"quit"), _on_quit, Color.TRANSPARENT))

	status = Label.new()
	UiKit.label(status, 8, Color(1.0, 0.6, 0.5))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)

	var ver := Label.new()
	ver.text = "v" + D.VERSION
	UiKit.label(ver, 7, Color(1, 1, 1, 0.3))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ver)


func _menu_button(label: String, fn: Callable, accent: Color) -> Button:
	var b := Button.new()
	b.text = label
	UiKit.button(b, 14, accent)
	b.custom_minimum_size = Vector2(320, 46)
	b.pressed.connect(fn)
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _on_host() -> void:
	var err := Net.host_game()
	if err != OK:
		status.text = Tr.t(&"connection_failed") + " (port 8910)"
		return
	LobbyScript.mode = "host"
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_join() -> void:
	LobbyScript.mode = "join"
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_single() -> void:
	## Tek kisilik kesif: ag yok, sim lokal kosar. Karsida hareketsiz bir
	## rakip sehri olur — istersen savas ilan edip yik, istersen sadece kur.
	Net.leave()
	GameState.reset((randi() % 899999) + 100000)
	GameState.my_pid = 1
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_quit() -> void:
	get_tree().quit()


func _menu_screenshot(path: String) -> void:
	if path.is_relative_path():
		path = ProjectSettings.globalize_path("res://") + path
	for _i in 20:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("SCREENSHOT_SAVED " if err == OK else "SCREENSHOT_FAILED ", path)
	get_tree().quit(0 if err == OK else 1)


func _handle_cli() -> void:
	var join_ip := ""
	var smoke_host := false
	var preview := false
	var demo := false
	var menu_shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--smoke-host":
			smoke_host = true
		elif arg.begins_with("--smoke-join"):
			join_ip = arg.get_slice("=", 1) if arg.contains("=") else "127.0.0.1"
		elif arg == "--preview":
			preview = true
		elif arg == "--demo":
			preview = true
			demo = true
		elif arg.begins_with("--screenshot="):
			menu_shot = arg.get_slice("=", 1)
	if smoke_host:
		var bot: Node = load("res://tools/smoke/host_bot.gd").new()
		get_tree().root.add_child.call_deferred(bot)
		var err := Net.host_game()
		if err != OK:
			printerr("SMOKE_FAIL host_game err=", err)
			get_tree().quit(1)
	elif join_ip != "":
		var bot: Node = load("res://tools/smoke/client_bot.gd").new()
		get_tree().root.add_child.call_deferred(bot)
		var err := Net.join_game(join_ip)
		if err != OK:
			printerr("SMOKE_FAIL join_game err=", err)
			get_tree().quit(1)
	elif preview:
		GameState.reset(D.DEFAULT_SEED)
		GameState.my_pid = 1
		if demo:
			var dbot: Node = load("res://tools/smoke/demo_bot.gd").new()
			get_tree().root.add_child.call_deferred(dbot)
		get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")
	elif menu_shot != "":
		_menu_screenshot(menu_shot)
