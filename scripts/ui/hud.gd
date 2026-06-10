extends Control
## HUD: ust bar (kaynaklar + nufus + savas durumu), toast akisi ve oyun sonu
## overlay'i. Insa menusu + secim paneli M1'de eklenir.

const D := preload("res://scripts/autoload/defs.gd")
const FONT := preload("res://assets/fonts/PublicPixel.ttf")

var res_labels := {}
var pop_label: Label
var war_label: Label
var toasts: VBoxContainer
var end_overlay: Control
var end_title: Label
var end_reason: Label


func _ready() -> void:
	# CanvasLayer altindaki kok Control'de anchor'a guvenme: viewport'a elle otur
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- ust bar ---
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 22)
	top.add_child(bar)
	for kind in D.RES_KINDS:
		var l := _mk_label(10)
		res_labels[kind] = l
		bar.add_child(l)
	pop_label = _mk_label(10)
	bar.add_child(pop_label)
	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(stretch)
	war_label = _mk_label(10)
	war_label.text = Tr.t(&"peace")
	war_label.modulate = Color(0.6, 0.95, 0.6)
	bar.add_child(war_label)

	# --- toast akisi ---
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toasts.offset_top = 28.0
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)

	# --- oyun sonu overlay ---
	end_overlay = ColorRect.new()
	(end_overlay as ColorRect).color = Color(0.0, 0.0, 0.0, 0.65)
	end_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_overlay.visible = false
	end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(end_overlay)
	var end_center := CenterContainer.new()
	end_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_overlay.add_child(end_center)
	var end_box := VBoxContainer.new()
	end_box.add_theme_constant_override("separation", 16)
	end_center.add_child(end_box)
	end_title = _mk_label(40)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_box.add_child(end_title)
	end_reason = _mk_label(10)
	end_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_box.add_child(end_reason)
	var menu_btn := Button.new()
	menu_btn.text = Tr.t(&"main_menu")
	menu_btn.add_theme_font_override("font", FONT)
	menu_btn.add_theme_font_size_override("font_size", 14)
	menu_btn.custom_minimum_size = Vector2(240, 40)
	menu_btn.pressed.connect(_on_main_menu)
	end_box.add_child(menu_btn)

	Bus.resources_changed.connect(_on_res)
	Bus.war_changed.connect(_on_war)
	Bus.toast.connect(_toast)
	Bus.game_over.connect(_on_game_over)
	_on_res(GameState.my_pid)


func _process(_dt: float) -> void:
	# savas geri sayimini yumusak guncelle (her sn rpc yerine lokal sayar)
	if GameState.war_state == D.War.COUNTDOWN:
		GameState.war_t_left = maxf(0.0, GameState.war_t_left - _dt)
		war_label.text = Tr.t(&"war_countdown") % int(ceilf(GameState.war_t_left))


func _fit_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _mk_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	return l


func _on_res(pid: int) -> void:
	if pid != GameState.my_pid:
		return
	for kind in D.RES_KINDS:
		var v: float = GameState.res[GameState.my_pid][kind]
		res_labels[kind].text = "%s %d" % [Tr.t(StringName(kind)), int(v)]
	pop_label.text = "%s %d/%d" % [
		Tr.t(&"pop"), GameState.pop_used[GameState.my_pid], GameState.pop_cap[GameState.my_pid]
	]


func _on_war(state: int, _t_left: float) -> void:
	match state:
		D.War.PEACE:
			war_label.text = Tr.t(&"peace")
			war_label.modulate = Color(0.6, 0.95, 0.6)
		D.War.COUNTDOWN:
			war_label.modulate = Color(1.0, 0.8, 0.3)
		D.War.WAR:
			war_label.text = Tr.t(&"at_war")
			war_label.modulate = Color(1.0, 0.35, 0.3)


func _toast(msg: String) -> void:
	var l := Label.new()
	l.text = msg
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", 9)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(1.0, 0.97, 0.85))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 1)
	toasts.add_child(l)
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func _on_game_over(winner: int, reason: int) -> void:
	end_overlay.visible = true
	var won := winner == GameState.my_pid
	end_title.text = Tr.t(&"victory") if won else Tr.t(&"defeat")
	end_title.add_theme_color_override("font_color",
		Color(0.95, 0.85, 0.3) if won else Color(0.9, 0.35, 0.3))
	match reason:
		D.Reason.DESTRUCTION:
			end_reason.text = Tr.t(&"reason_destruction")
		D.Reason.METROPOLIS:
			end_reason.text = Tr.t(&"reason_metropolis")
		D.Reason.OPPONENT_LEFT:
			end_reason.text = Tr.t(&"reason_opponent_left")


func _on_main_menu() -> void:
	Net.leave()
	GameState.match_running = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
