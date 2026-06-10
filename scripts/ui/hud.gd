extends Control
## HUD: ust bar (kaynaklar + nufus + savas durumu), toast akisi, alt panel
## (secim bilgisi + insa menusu + uretim kuyrugu) ve oyun sonu overlay'i.

const D := preload("res://scripts/autoload/defs.gd")
const FONT := preload("res://assets/fonts/PublicPixel.ttf")

const BUILDABLE: Array[StringName] = [
	&"house", &"greenhouse", &"bank", &"lumber_camp", &"quarry",
	&"barracks", &"factory", &"turret",
]

var game: Node2D = null
var input_ctrl: Node = null

var res_labels := {}
var pop_label: Label
var metro_label: Label
var map_label: Label
var toasts: VBoxContainer
var bottom: PanelContainer
var sel_label: Label
var action_box: HBoxContainer
var queue_label: Label
var end_overlay: Control
var end_title: Label
var end_reason: Label

var _sel: Array = []
var _refresh_t := 0.0


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
	metro_label = _mk_label(8)
	metro_label.modulate = Color(1, 1, 1, 0.55)
	bar.add_child(metro_label)
	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(stretch)
	# savas ilani kalkti (her an saldirilabilir); sag ust artik harita adini gosterir
	var map_keys: Array[StringName] = [&"map_river", &"map_lake", &"map_plains"]
	map_label = _mk_label(10)
	map_label.text = Tr.t(&"map_label") % Tr.t(map_keys[GameState.map_type])
	map_label.modulate = Color(1, 1, 1, 0.7)
	bar.add_child(map_label)

	# --- toast akisi ---
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toasts.offset_top = 28.0
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)

	# --- alt panel ---
	bottom = PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -64.0
	bottom.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bottom)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 14)
	bottom.add_child(brow)
	var info_box := VBoxContainer.new()
	info_box.custom_minimum_size = Vector2(240, 0)
	brow.add_child(info_box)
	sel_label = _mk_label(10)
	info_box.add_child(sel_label)
	queue_label = _mk_label(8)
	queue_label.modulate = Color(1, 1, 1, 0.8)
	info_box.add_child(queue_label)
	action_box = HBoxContainer.new()
	action_box.add_theme_constant_override("separation", 6)
	brow.add_child(action_box)
	bottom.visible = false

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
	Bus.toast.connect(_toast)
	Bus.game_over.connect(_on_game_over)
	Bus.selection_changed.connect(_on_sel)
	Bus.build_rejected.connect(_on_reject)
	Bus.entity_level_changed.connect(_on_level_changed)
	_on_res(GameState.my_pid)


func _process(dt: float) -> void:
	_refresh_t += dt
	if _refresh_t >= 0.25:
		_refresh_t = 0.0
		_refresh_queue()


func _on_level_changed(id: int) -> void:
	if id in _sel:
		_refresh_panel()


func _fit_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _mk_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _cost_str(cost: Dictionary) -> String:
	## Maliyeti tam kaynak adlariyla yazar: "50 Odun, 40 Taş"
	var parts: Array[String] = []
	for kind in cost:
		parts.append("%d %s" % [cost[kind], Tr.t(StringName(kind))])
	return ", ".join(parts)


# === ust bar ===

func _on_res(pid: int) -> void:
	if pid != GameState.my_pid:
		return
	for kind in D.RES_KINDS:
		var v: float = GameState.res[GameState.my_pid][kind]
		res_labels[kind].text = "%s %d" % [Tr.t(StringName(kind)), int(v)]
	pop_label.text = "%s %d/%d" % [
		Tr.t(&"pop"), GameState.pop_used[GameState.my_pid], GameState.pop_cap[GameState.my_pid]
	]
	# metropol ilerlemesi: nufus + tamamlanmis farkli bina turu sayisi
	var have := {}
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid and e.def.has("size") and e.is_complete():
			have[e.def_id] = true
	metro_label.text = Tr.t(&"metro_short") % [
		GameState.pop_used[GameState.my_pid], D.METROPOLIS_POP, have.size(), D.BUILDINGS.size()
	]


# === alt panel ===

func _on_sel(ids: Array) -> void:
	_sel = ids.duplicate()
	_refresh_panel()


func _refresh_panel() -> void:
	for c in action_box.get_children():
		c.queue_free()
	queue_label.text = ""
	if _sel.is_empty():
		bottom.visible = false
		return
	var first: Node = GameState.ent(_sel[0])
	if first == null:
		bottom.visible = false
		return
	bottom.visible = true

	var units: Array = []
	var has_worker := false
	for id in _sel:
		var e: Node = GameState.ent(id)
		if e != null and e.def.has("speed_t"):
			units.append(e)
			if e.def_id == &"worker":
				has_worker = true

	if units.size() > 1:
		sel_label.text = Tr.t(&"n_units") % units.size()
	elif first.def.has("size"):
		var lvl_txt := " L%d" % first.level if first.level > 1 else ""
		sel_label.text = "%s%s  %d/%d" % [Tr.t(first.def_id), lvl_txt, int(first.hp), int(first.max_hp)]
	else:
		sel_label.text = "%s  %d/%d" % [Tr.t(first.def_id), int(first.hp), int(first.max_hp)]

	if has_worker:
		for bid in BUILDABLE:
			var bdef := D.building(bid)
			var btn := _action_btn("%s\n%s" % [Tr.t(bid), _cost_str(bdef["cost"])])
			btn.pressed.connect(input_ctrl.start_placement.bind(bid))
			action_box.add_child(btn)
	elif units.is_empty() and first.def.has("size") and first.owner_pid == GameState.my_pid \
			and first.is_complete():
		if first.def.has("trains"):
			for uid: StringName in first.def["trains"]:
				var udef := D.unit(uid)
				var btn := _action_btn("%s\n%s\n%s" % [Tr.t(uid), _cost_str(udef["cost"]), _stat_str(udef)])
				btn.pressed.connect(Net.send_train.bind(first.id, uid))
				action_box.add_child(btn)
			var cancel := _action_btn(Tr.t(&"cancel"))
			cancel.pressed.connect(Net.send_cancel_train.bind(first.id, 0))
			action_box.add_child(cancel)
		# gelistirme: maliyet + ne kazanacagi acikca yazilir
		if first.def.has("up_cost") and first.level < D.MAX_LEVEL:
			var up_cost := D.scaled_cost(first.def["up_cost"], first.level)
			var up := _action_btn("%s L%d\n%s\n%s" % [
				Tr.t(&"upgrade"), first.level + 1, _cost_str(up_cost), _benefit_str(first.def)])
			up.modulate = Color(0.85, 1.0, 0.85)
			up.pressed.connect(Net.send_upgrade.bind(first.id))
			action_box.add_child(up)
		_refresh_queue()


func _stat_str(udef: Dictionary) -> String:
	## Uretim butonunda birimin cani/hasari gorunsun
	if udef.has("heal_rate"):
		return "%s %d, %s" % [Tr.t(&"hp_short"), udef["hp"], Tr.t(&"heals_label")]
	if udef.get("dmg", 0) <= 0:
		return "%s %d" % [Tr.t(&"hp_short"), udef["hp"]]
	return "%s %d, %s %d" % [Tr.t(&"hp_short"), udef["hp"], Tr.t(&"dmg_short"), udef["dmg"]]


func _benefit_str(bdef: Dictionary) -> String:
	if bdef.has("up_pop"):
		return Tr.t(&"benefit_pop") % int(bdef["up_pop"])
	if bdef.has("up_rate"):
		return Tr.t(&"benefit_rate") % int(bdef["up_rate"] * 100.0)
	if bdef.has("up_dmg"):
		return Tr.t(&"benefit_dmg") % int(bdef["up_dmg"])
	if bdef.has("up_speed"):
		return Tr.t(&"benefit_speed") % int(bdef["up_speed"] * 100.0)
	return ""


func _action_btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 8)
	b.custom_minimum_size = Vector2(150, 56)
	return b


func _refresh_queue() -> void:
	if _sel.is_empty():
		return
	var first: Node = GameState.ent(_sel[0])
	if first == null or not first.def.has("size"):
		return
	if not first.is_complete():
		queue_label.text = Tr.t(&"under_construction") + " %d%%" % int(first.construction * 100.0)
		return
	if not first.def.has("trains"):
		return
	var q: Array[StringName] = first.queue
	if q.is_empty():
		queue_label.text = ""
		return
	var names: Array[String] = []
	for uid in q:
		names.append(Tr.t(uid))
	var prog: float = first.display_progress() if Net.is_host() else first._display_progress_client()
	queue_label.text = "%s: %s (%d%%)" % [Tr.t(&"queue"), ", ".join(names), int(prog * 100.0)]


func _on_reject(reason: int) -> void:
	var key: StringName
	match reason:
		D.Reject.NO_RES: key = &"reject_no_res"
		D.Reject.BAD_SPOT: key = &"reject_bad_spot"
		D.Reject.TOO_FAR: key = &"reject_too_far"
		D.Reject.POP_FULL: key = &"reject_pop_full"
		D.Reject.BLOCKED: key = &"reject_blocked"
		D.Reject.QUEUE_FULL: key = &"reject_queue_full"
		D.Reject.PEACE: key = &"reject_peace"
		D.Reject.MAX_LEVEL: key = &"reject_max_level"
		_: key = &"reject_bad_spot"
	_toast(Tr.t(key))


# === toast / oyun sonu ===

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
