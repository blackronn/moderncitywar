extends Control
## Ana menu. UI kodla kurulur. Komut satiri bayraklarini da burasi isler:
##   --smoke-host / --smoke-join=IP  : headless e2e botlari
##   --preview [--screenshot=yol]    : agsiz tek pencere onizleme
##   --speed=N                       : sim hizlandirma (sim.gd okur)

const D := preload("res://scripts/autoload/defs.gd")
const FONT := preload("res://assets/fonts/PublicPixel.ttf")
const LobbyScript := preload("res://scripts/ui/lobby.gd")

var status: Label


func _ready() -> void:
	_build_ui()
	_handle_cli()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.13, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = Tr.t(&"app_title")
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.93, 0.89, 0.62))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = Tr.t(&"subtitle")
	sub.add_theme_font_override("font", FONT)
	sub.add_theme_font_size_override("font_size", 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.65)
	box.add_child(sub)

	box.add_child(_spacer(10.0))
	box.add_child(_button(Tr.t(&"host_game"), _on_host))
	box.add_child(_button(Tr.t(&"join_game"), _on_join))
	box.add_child(_button(Tr.t(&"quit"), _on_quit))
	box.add_child(_spacer(6.0))

	status = Label.new()
	status.add_theme_font_override("font", FONT)
	status.add_theme_font_size_override("font_size", 8)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.modulate = Color(1.0, 0.6, 0.5)
	box.add_child(status)

	var ver := Label.new()
	ver.text = "v" + D.VERSION
	ver.add_theme_font_override("font", FONT)
	ver.add_theme_font_size_override("font_size", 8)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.modulate = Color(1, 1, 1, 0.35)
	box.add_child(ver)


func _button(label: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(300, 42)
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
