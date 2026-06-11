extends Control
## Lobi: host modunda "rakip bekleniyor", join modunda IP girisi.
## Esleme basarili olunca sahne degisimini Net yonetir (sv_hello akisi).

static var mode := "host"

const FONT := preload("res://assets/fonts/PublicPixel.ttf")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

var status: Label
var ip_edit: LineEdit
var players_label: Label
var start_btn: Button
var _vote_buttons := {}


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	UiKit.panel(panel, 0.0, 16.0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var wordmark := TextureRect.new()
	wordmark.texture = load("res://assets/ui/voxgard-wordmark.png")
	wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wordmark.custom_minimum_size = Vector2(280, 56)
	box.add_child(wordmark)

	var title := Label.new()
	title.text = (Tr.t(&"host_game") if mode == "host" else Tr.t(&"join_game")).to_upper()
	UiKit.label(title, 13, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	status = Label.new()
	status.add_theme_font_override("font", FONT)
	status.add_theme_font_size_override("font_size", 10)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)

	# --- harita oylamasi: iki oyuncu da oy verir; ayni -> o harita,
	# --- farkli -> ikisinden rastgele ---
	var vote_title := Label.new()
	vote_title.text = Tr.t(&"map_vote")
	UiKit.label(vote_title, 8, Color(1, 1, 1, 0.5))
	vote_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(vote_title)
	var vote_row := HBoxContainer.new()
	vote_row.add_theme_constant_override("separation", 5)
	vote_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(vote_row)
	var opts: Array = [
		[-1, &"random_map"], [0, &"map_river"], [1, &"map_lake"],
		[2, &"map_plains"], [3, &"map_snow"], [4, &"map_valley"],
	]
	for o in opts:
		var vb := Button.new()
		vb.text = Tr.t(o[1])
		UiKit.button(vb, 7, UiKit.ACCENT_BLUE if Net.my_map_vote == o[0] else Color.TRANSPARENT)
		vb.pressed.connect(_on_vote.bind(o[0]))
		_vote_buttons[o[0]] = vb
		vote_row.add_child(vb)

	# oyuncu sayaci (2-4 kisi; host dahil)
	players_label = Label.new()
	UiKit.label(players_label, 9, UiKit.ACCENT)
	players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	players_label.text = Tr.t(&"players_in_lobby") % [1, 4]
	box.add_child(players_label)

	if mode == "host":
		status.text = Tr.t(&"waiting_opponent")
		var st_tw := create_tween().set_loops()
		st_tw.tween_property(status, "modulate:a", 0.35, 0.7)
		st_tw.tween_property(status, "modulate:a", 1.0, 0.7)
		var hint_pod := PanelContainer.new()
		UiKit.pod(hint_pod, 8)
		box.add_child(hint_pod)
		var hint := Label.new()
		hint.text = Tr.t(&"your_ip_hint") + "\n" + _local_ips()
		UiKit.label(hint, 7, UiKit.TEXT_DIM)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint_pod.add_child(hint)
		# 2-4 oyuncu: host istedigi an baslatir (en az 1 rakip baglanmis olmali)
		start_btn = Button.new()
		start_btn.text = Tr.t(&"start_match")
		UiKit.button(start_btn, 14, UiKit.ACCENT_BLUE)
		start_btn.custom_minimum_size = Vector2(300, 44)
		start_btn.disabled = true
		start_btn.pressed.connect(func(): Net.host_start())
		box.add_child(start_btn)
	else:
		var ip_pod := PanelContainer.new()
		UiKit.pod(ip_pod, 4)
		box.add_child(ip_pod)
		ip_edit = LineEdit.new()
		ip_edit.placeholder_text = Tr.t(&"ip_address")
		ip_edit.text = "127.0.0.1"
		ip_edit.custom_minimum_size = Vector2(290, 34)
		ip_edit.add_theme_font_override("font", FONT)
		ip_edit.add_theme_font_size_override("font_size", 11)
		ip_edit.add_theme_color_override("font_color", UiKit.INK)
		ip_edit.add_theme_color_override("caret_color", UiKit.ACCENT)
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0, 0, 0, 0)
		ip_edit.add_theme_stylebox_override("normal", flat)
		ip_edit.add_theme_stylebox_override("focus", flat)
		ip_pod.add_child(ip_edit)
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
	Bus.lobby_players.connect(_on_players)
	if mode == "host":
		_on_players(Net.player_total(), 4)


func _on_players(count: int, max_p: int) -> void:
	players_label.text = Tr.t(&"players_in_lobby") % [count, max_p]
	if start_btn != null:
		start_btn.disabled = count < 2
		start_btn.tooltip_text = Tr.t(&"need_two_players") if count < 2 else ""
	if mode != "host":
		status.text = Tr.t(&"waiting_host_start")


func _local_ips() -> String:
	var out: Array[String] = []
	for addr in IP.get_local_addresses():
		if addr.contains(".") and not addr.begins_with("127."):
			out.append(addr)
		if out.size() >= 3:
			break
	return ", ".join(out) if not out.is_empty() else "?"


func _on_vote(v: int) -> void:
	Net.my_map_vote = v
	for key in _vote_buttons:
		var b: Button = _vote_buttons[key]
		UiKit.button(b, 7, UiKit.ACCENT_BLUE if key == v else Color.TRANSPARENT)


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
