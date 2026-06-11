extends Control
## Lobi: host modunda "rakip bekleniyor", join modunda IP girisi.
## Esleme basarili olunca sahne degisimini Net yonetir (sv_hello akisi).

static var mode := "host"

const FONT := preload("res://assets/fonts/PublicPixel.ttf")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

var status: Label
var ip_edit: LineEdit


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var wordmark := TextureRect.new()
	wordmark.texture = load("res://assets/ui/voxgard-wordmark.png")
	wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wordmark.custom_minimum_size = Vector2(280, 56)
	box.add_child(wordmark)

	var title := Label.new()
	title.text = Tr.t(&"host_game") if mode == "host" else Tr.t(&"join_game")
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.93, 0.89, 0.62))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	status = Label.new()
	status.add_theme_font_override("font", FONT)
	status.add_theme_font_size_override("font_size", 10)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)

	if mode == "host":
		status.text = Tr.t(&"waiting_opponent")
		var hint := Label.new()
		hint.text = Tr.t(&"your_ip_hint") + "\n" + _local_ips()
		hint.add_theme_font_override("font", FONT)
		hint.add_theme_font_size_override("font_size", 8)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.modulate = Color(1, 1, 1, 0.6)
		box.add_child(hint)
	else:
		ip_edit = LineEdit.new()
		ip_edit.placeholder_text = Tr.t(&"ip_address")
		ip_edit.text = "127.0.0.1"
		ip_edit.custom_minimum_size = Vector2(300, 38)
		ip_edit.add_theme_font_override("font", FONT)
		ip_edit.add_theme_font_size_override("font_size", 12)
		box.add_child(ip_edit)
		var connect_btn := Button.new()
		connect_btn.text = Tr.t(&"connect")
		UiKit.button(connect_btn, 14, UiKit.ACCENT_BLUE)
		connect_btn.custom_minimum_size = Vector2(300, 44)
		connect_btn.pressed.connect(_on_connect)
		box.add_child(connect_btn)

	var back := Button.new()
	back.text = Tr.t(&"back")
	UiKit.button(back, 11)
	back.custom_minimum_size = Vector2(300, 36)
	back.pressed.connect(_on_back)
	box.add_child(back)

	Bus.lobby_status.connect(_set_status)
	Bus.net_error.connect(_set_status)


func _local_ips() -> String:
	var out: Array[String] = []
	for addr in IP.get_local_addresses():
		if addr.contains(".") and not addr.begins_with("127."):
			out.append(addr)
		if out.size() >= 3:
			break
	return ", ".join(out) if not out.is_empty() else "?"


func _set_status(msg: String) -> void:
	status.text = msg


func _on_connect() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		return
	_set_status(Tr.t(&"connecting"))
	var err := Net.join_game(ip)
	if err != OK:
		_set_status(Tr.t(&"connection_failed"))


func _on_back() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
