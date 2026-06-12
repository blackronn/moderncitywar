extends Control
## TAS & DEMIR HUD (HUD Redesign.dc.html portu): percinli celik paneller,
## cokuk pod'lar, ikon kartli insa/uretim menusu, portreli secim kutusu,
## stat cipleri, metro noktalari, ORDU paneli ve MINIMAP.

const D := preload("res://scripts/autoload/defs.gd")
const Bible := preload("res://scripts/sim/bible.gd")
const TileCatalog := preload("res://scripts/sim/tile_catalog.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const FONT := preload("res://assets/fonts/PublicPixel.ttf")

const BUILDABLE: Array[StringName] = [
	&"house", &"greenhouse", &"bank", &"lumber_camp", &"quarry",
	&"barracks", &"factory", &"turret", &"bridge_seg", &"mine", &"sandbags",
]
const ARMY_TYPES: Array[StringName] = [
	&"worker", &"rifleman", &"sniper", &"rpg", &"mg", &"commando",
	&"mortar", &"healer", &"tank",
]
const MINI_COLORS := {
	D.Tile.GRASS: Color("#5fb84f"), D.Tile.WATER: Color("#2f7fcf"),
	D.Tile.BRIDGE: Color("#b07a43"), D.Tile.FOREST: Color("#2f8a3e"),
	D.Tile.STONE: Color("#9aa0a9"), D.Tile.GOLD: Color("#f3c64a"),
	D.Tile.SNOW: Color("#e6edf3"), D.Tile.HILL: Color("#8d8273"),
	D.Tile.MOUNTAIN: Color("#4f4a55"),
}

var game: Node2D = null
var input_ctrl: Node = null

var res_value_labels := {}
var res_income_labels := {}
var pop_label: Label
var pop_bar := {}
var metro_pop_label: Label
var metro_bar := {}
var metro_dots: Array = []
var map_value: Label
var war_btn: Button
var _war_tween: Tween

var toasts: VBoxContainer
var army_rows := {}
var army_pop: Label
var mini_rect: TextureRect
var _mini_tex: ImageTexture

var bottom: PanelContainer
var portrait_icon: TextureRect
var sel_label: Label
var sel_hp_label: Label
var sel_hp_bar := {}
var queue_label: Label
var queue_bar := {}
var queue_pct: Label
var queue_box: Control
var action_box: HFlowContainer
var form_box: HBoxContainer

var end_overlay: Control
var end_icon: TextureRect
var end_title: Label
var end_reason: Label

var _sel: Array = []
var _refresh_t := 0.0
var _mini_t := 0.0


func _ready() -> void:
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_top_bar()
	_build_toasts()
	_build_army_panel()
	_build_minimap()
	_build_bottom()
	_build_end_overlay()

	Bus.resources_changed.connect(_on_res)
	Bus.war_changed.connect(_on_war)
	Bus.toast.connect(_toast)
	Bus.game_over.connect(_on_game_over)
	Bus.selection_changed.connect(_on_sel)
	Bus.build_rejected.connect(_on_reject)
	Bus.entity_level_changed.connect(_on_level_changed)
	Bus.entity_spawned.connect(func(_n): _refresh_army())
	Bus.entity_removed.connect(func(_i, _r): _refresh_army())
	Bus.player_eliminated.connect(_on_eliminated)
	_on_res(GameState.my_pid)
	_on_war(GameState.war_state, GameState.war_t_left)
	_refresh_army()


# ===================== kurulum =====================

func _pod(content := 5) -> PanelContainer:
	var p := PanelContainer.new()
	UiKit.pod(p, content)
	return p


func _icon_rect(tex: Texture2D, px: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.custom_minimum_size = Vector2(px, px)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _build_top_bar() -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8.0
	top.offset_right = -8.0
	top.offset_top = 6.0
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.panel(top, 0.0, 2.0)
	add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 7)
	top.add_child(bar)

	# kaynak pod'lari: ikon + deger (+gelir)
	for kind in D.RES_KINDS:
		var pod := _pod(4)
		bar.add_child(pod)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		pod.add_child(h)
		h.add_child(_icon_rect(UiKit.icon_tex(StringName(kind)), 22))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		h.add_child(v)
		var val := Label.new()
		UiKit.label(val, 10)
		v.add_child(val)
		res_value_labels[kind] = val
		var inc := Label.new()
		UiKit.label(inc, 6, UiKit.TEXT_DIM)
		v.add_child(inc)
		res_income_labels[kind] = inc

	# nufus pod'u: ikon + sayi + bar
	var ppod := _pod(4)
	bar.add_child(ppod)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 5)
	ppod.add_child(ph)
	ph.add_child(_icon_rect(UiKit.icon_tex(&"pop"), 22))
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 3)
	ph.add_child(pv)
	pop_label = Label.new()
	UiKit.label(pop_label, 9)
	pv.add_child(pop_label)
	pop_bar = UiKit.make_bar(pv, 62, 5, UiKit.ACCENT_BLUE)

	# metropol pod'u: etiket + bar + bina noktalari
	var mpod := _pod(4)
	bar.add_child(mpod)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 3)
	mpod.add_child(mv)
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 8)
	mv.add_child(mh)
	var mtitle := Label.new()
	mtitle.text = "METROPOL"
	UiKit.label(mtitle, 8, UiKit.ACCENT)
	mh.add_child(mtitle)
	metro_pop_label = Label.new()
	UiKit.label(metro_pop_label, 8, UiKit.TEXT_DIM)
	mh.add_child(metro_pop_label)
	var mb := HBoxContainer.new()
	mb.add_theme_constant_override("separation", 6)
	mv.add_child(mb)
	metro_bar = UiKit.make_bar(mb, 96, 6, UiKit.ACCENT)
	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 2)
	mb.add_child(dots)
	for _i in D.metro_types():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(5, 5)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Color(0, 0, 0, 0.45)
		dots.add_child(dot)
		metro_dots.append(dot)

	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(stretch)

	# harita rozeti
	var mappod := _pod(5)
	bar.add_child(mappod)
	var maph := HBoxContainer.new()
	maph.add_theme_constant_override("separation", 6)
	mappod.add_child(maph)
	var mapk := Label.new()
	mapk.text = "HARİTA"
	UiKit.label(mapk, 8, UiKit.TEXT_DIM)
	maph.add_child(mapk)
	map_value = Label.new()
	UiKit.label(map_value, 9)
	var map_keys: Array[StringName] = [&"map_river", &"map_lake", &"map_plains", &"map_snow", &"map_valley"]
	map_value.text = Tr.t(map_keys[GameState.map_type]).to_upper()
	maph.add_child(map_value)

	# savas rozeti
	war_btn = Button.new()
	war_btn.add_theme_font_override("font", FONT)
	war_btn.add_theme_font_size_override("font_size", 9)
	war_btn.pressed.connect(func(): Net.send_declare_war())
	war_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bar.add_child(war_btn)


func _build_toasts() -> void:
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toasts.offset_top = 62.0
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.add_theme_constant_override("separation", 4)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)


func _build_army_panel() -> void:
	var army_panel := PanelContainer.new()
	army_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	army_panel.offset_right = -8.0
	army_panel.offset_left = -158.0
	army_panel.offset_top = -190.0
	army_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	army_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.panel(army_panel, 0.0, 3.0)
	add_child(army_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	army_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var t := Label.new()
	t.text = "ORDU"
	UiKit.label(t, 9, UiKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	army_pop = Label.new()
	UiKit.label(army_pop, 8, UiKit.TEXT_DIM)
	head.add_child(army_pop)
	for tp in ARMY_TYPES:
		var b := Button.new()
		UiKit.button(b, 8)
		b.icon = _unit_icon(tp)
		b.expand_icon = false
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("icon_max_width", 18)
		b.tooltip_text = Tr.t(tp)
		b.pressed.connect(_on_army_pressed.bind(tp))
		army_rows[tp] = b
		box.add_child(b)


func _build_minimap() -> void:
	var mp := PanelContainer.new()
	mp.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mp.offset_left = -158.0
	mp.offset_right = -8.0
	mp.offset_bottom = -132.0
	mp.offset_top = -132.0 - 150.0
	mp.mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.panel(mp, 0.0, 3.0)
	add_child(mp)
	var inner := _pod(3)
	mp.add_child(inner)
	mini_rect = TextureRect.new()
	mini_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mini_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mini_rect.custom_minimum_size = Vector2(112, 112)
	mini_rect.gui_input.connect(_on_mini_input)
	mini_rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	inner.add_child(mini_rect)
	_refresh_minimap()


func _build_bottom() -> void:
	bottom = PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 8.0
	bottom.offset_right = -166.0
	bottom.offset_top = -124.0
	bottom.offset_bottom = -6.0
	bottom.mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.panel(bottom, 0.0, 4.0)
	add_child(bottom)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	bottom.add_child(brow)

	# secim portresi
	var sel_pod := _pod(6)
	sel_pod.custom_minimum_size = Vector2(216, 0)
	brow.add_child(sel_pod)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 9)
	sel_pod.add_child(sh)
	var frame := _pod(3)
	sh.add_child(frame)
	portrait_icon = _icon_rect(null, 48)
	frame.add_child(portrait_icon)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(sv)
	sel_label = Label.new()
	UiKit.label(sel_label, 9)
	sv.add_child(sel_label)
	sel_hp_label = Label.new()
	UiKit.label(sel_hp_label, 8, UiKit.TEXT_DIM)
	sv.add_child(sel_hp_label)
	sel_hp_bar = UiKit.make_bar(sv, 120, 7, UiKit.HP_GREEN)
	form_box = HBoxContainer.new()
	form_box.add_theme_constant_override("separation", 3)
	sv.add_child(form_box)

	# ayirici
	var sep := ColorRect.new()
	sep.color = Color("#141a22")
	sep.custom_minimum_size = Vector2(3, 0)
	brow.add_child(sep)

	# eylem alani: kartlar + kuyruk
	var act_v := VBoxContainer.new()
	act_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act_v.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_child(act_v)
	action_box = HFlowContainer.new()
	action_box.add_theme_constant_override("h_separation", 6)
	action_box.add_theme_constant_override("v_separation", 4)
	act_v.add_child(action_box)
	queue_box = HBoxContainer.new()
	(queue_box as HBoxContainer).add_theme_constant_override("separation", 7)
	act_v.add_child(queue_box)
	queue_label = Label.new()
	UiKit.label(queue_label, 8, UiKit.TEXT_DIM)
	queue_box.add_child(queue_label)
	queue_bar = UiKit.make_bar(queue_box, 150, 8, UiKit.ACCENT)
	queue_pct = Label.new()
	UiKit.label(queue_pct, 8, UiKit.ACCENT)
	queue_box.add_child(queue_pct)
	queue_box.visible = false
	bottom.visible = false


func _build_end_overlay() -> void:
	end_overlay = ColorRect.new()
	(end_overlay as ColorRect).color = Color(0.0, 0.0, 0.0, 0.6)
	end_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_overlay.visible = false
	end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(end_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_overlay.add_child(center)
	var panel := PanelContainer.new()
	UiKit.panel(panel, 0.0, 18.0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	end_icon = _icon_rect(null, 48)
	end_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(end_icon)
	end_title = Label.new()
	UiKit.label(end_title, 24)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(end_title)
	end_reason = Label.new()
	UiKit.label(end_reason, 8, UiKit.TEXT_DIM)
	end_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(end_reason)
	var menu_btn := Button.new()
	menu_btn.text = Tr.t(&"main_menu")
	UiKit.button(menu_btn, 11)
	menu_btn.custom_minimum_size = Vector2(230, 42)
	menu_btn.pressed.connect(_on_main_menu)
	box.add_child(menu_btn)


# ===================== calisma =====================

func _process(dt: float) -> void:
	if GameState.war_state == D.War.COUNTDOWN:
		GameState.war_t_left = maxf(0.0, GameState.war_t_left - dt)
		war_btn.text = Tr.t(&"war_countdown") % int(ceilf(GameState.war_t_left))
	_refresh_t += dt
	if _refresh_t >= 0.25:
		_refresh_t = 0.0
		_refresh_queue()
	_mini_t += dt
	if _mini_t >= 0.4:
		_mini_t = 0.0
		_refresh_minimap()


func _fit_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _unit_icon(def_id: StringName) -> Texture2D:
	var at := AtlasTexture.new()
	at.atlas = load(Bible.unit_sheet(def_id, GameState.my_pid))
	at.region = Rect2(0, 0, Bible.UNIT_FRAME, Bible.UNIT_FRAME)
	return at


func _entity_icon(e: Node) -> Texture2D:
	if e.def.has("size"):
		return TileCatalog.building_preview(e.def_id, e.owner_pid)
	var at := AtlasTexture.new()
	at.atlas = load(Bible.unit_sheet(e.def_id, e.owner_pid))
	at.region = Rect2(0, 0, Bible.UNIT_FRAME, Bible.UNIT_FRAME)
	return at


# === ust bar guncellemeleri ===

func _income_per_s(kind: String) -> float:
	var total := 0.0
	for e in GameState.entities.values():
		if e.owner_pid != GameState.my_pid or not e.def.has("size") or not e.is_complete():
			continue
		var rate: Dictionary = e.def.get("rate", {})
		if rate.has(kind):
			total += rate[kind] * (1.0 + float(e.def.get("up_rate", 0.0)) * float(e.level - 1))
	return total


func _on_res(pid: int) -> void:
	if pid != GameState.my_pid:
		return
	for kind in D.RES_KINDS:
		var v: float = GameState.res[GameState.my_pid][kind]
		res_value_labels[kind].text = str(int(v))
		var inc := _income_per_s(kind)
		res_income_labels[kind].text = "+%.1f/sn" % inc if inc > 0.0 else ""
	var used: int = GameState.pop_used[GameState.my_pid]
	var cap: int = GameState.pop_cap[GameState.my_pid]
	pop_label.text = "%d/%d" % [used, cap]
	UiKit.set_bar(pop_bar, float(used) / maxf(1.0, float(cap)))
	if army_pop != null:
		army_pop.text = "%d/%d" % [used, cap]
	# metropol
	var have := {}
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid and e.def.has("size") and e.is_complete() \
				and not e.def.has("bridge") and not e.def.has("mine") and not e.def.has("cover"):
			have[e.def_id] = true
	metro_pop_label.text = "%d/%d" % [used, D.METROPOLIS_POP]
	UiKit.set_bar(metro_bar, float(used) / float(D.METROPOLIS_POP))
	for i in metro_dots.size():
		metro_dots[i].color = UiKit.ACCENT if i < have.size() else Color(0, 0, 0, 0.45)


func _on_war(state: int, _t_left: float) -> void:
	if _war_tween != null:
		_war_tween.kill()
		_war_tween = null
	war_btn.modulate = Color.WHITE
	match state:
		D.War.PEACE:
			war_btn.text = Tr.t(&"declare_war")
			war_btn.disabled = false
			UiKit.button_state_tex(war_btn, "box_btn.png", Color("#9be08a"))
		D.War.COUNTDOWN:
			war_btn.text = Tr.t(&"war_countdown") % int(ceilf(GameState.war_t_left))
			war_btn.disabled = true
			UiKit.button_state_tex(war_btn, "box_btn_amber.png", Color("#f3c64a"))
		D.War.WAR:
			war_btn.text = Tr.t(&"at_war")
			war_btn.disabled = true
			UiKit.button_state_tex(war_btn, "box_btn_red.png", Color("#ff6a55"))
			_war_tween = create_tween().set_loops()
			_war_tween.tween_property(war_btn, "modulate", Color(1.35, 1.35, 1.35), 0.45)
			_war_tween.tween_property(war_btn, "modulate", Color.WHITE, 0.45)


# === ordu paneli + minimap ===

func _refresh_army() -> void:
	for tp in ARMY_TYPES:
		var n := 0
		for e in GameState.entities.values():
			if e.owner_pid == GameState.my_pid and e.def_id == tp:
				n += 1
		var b: Button = army_rows[tp]
		b.visible = n > 0
		b.text = "%s ×%d" % [Tr.t(tp).to_upper(), n]


func _on_army_pressed(tp: StringName) -> void:
	if input_ctrl != null:
		input_ctrl.select_type(tp)


func _refresh_minimap() -> void:
	if GameState.grid.is_empty():
		return
	var img := Image.create(D.MAP_W, D.MAP_H, false, Image.FORMAT_RGBA8)
	for y in D.MAP_H:
		for x in D.MAP_W:
			img.set_pixel(x, y, MINI_COLORS.get(GameState.grid[y * D.MAP_W + x], Color("#5fb84f")))
	for e in GameState.entities.values():
		if not e.visible:
			continue   # rakip mayini minimap'te de gorunmez
		var c := Vector2i((e.position / float(D.TILE)).floor())
		var col: Color = D.PLAYER_COLORS.get(e.owner_pid, UiKit.ACCENT_RED)
		var sz := 2 if e.def.has("size") else 1
		for dy in sz:
			for dx in sz:
				var px := c + Vector2i(dx, dy)
				if px.x >= 0 and px.y >= 0 and px.x < D.MAP_W and px.y < D.MAP_H:
					img.set_pixel(px.x, px.y, col)
	# kamera cercevesi
	if game != null and game.cam != null:
		var half: Vector2 = get_viewport_rect().size / (2.0 * game.cam.zoom.x * float(D.TILE))
		var cc: Vector2 = game.cam.position / float(D.TILE)
		var tl := Vector2i((cc - half).floor())
		var br := Vector2i((cc + half).ceil())
		for x in range(maxi(0, tl.x), mini(D.MAP_W, br.x)):
			for yy in [tl.y, br.y - 1]:
				if yy >= 0 and yy < D.MAP_H:
					img.set_pixel(x, yy, Color(1, 1, 1, 0.85))
		for y in range(maxi(0, tl.y), mini(D.MAP_H, br.y)):
			for xx in [tl.x, br.x - 1]:
				if xx >= 0 and xx < D.MAP_W:
					img.set_pixel(xx, y, Color(1, 1, 1, 0.85))
	if _mini_tex == null:
		_mini_tex = ImageTexture.create_from_image(img)
		mini_rect.texture = _mini_tex
	else:
		_mini_tex.update(img)


func _on_mini_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if game == null or game.cam == null:
			return
		var local: Vector2 = ev.position
		var rsize: Vector2 = mini_rect.size
		var side := minf(rsize.x, rsize.y)
		var off := (rsize - Vector2(side, side)) / 2.0
		var ratio := ((local - off) / side).clamp(Vector2.ZERO, Vector2.ONE)
		game.cam.position = ratio * float(D.MAP_W * D.TILE)


# === alt panel ===

func _on_level_changed(id: int) -> void:
	if id in _sel:
		_refresh_panel()


func _on_sel(ids: Array) -> void:
	_sel = ids.duplicate()
	_refresh_panel()


func _cost_chip(kind: String, n: int) -> Control:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.3)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", sb)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	chip.add_child(h)
	h.add_child(_icon_rect(UiKit.icon_tex(StringName(kind)), 13))
	var l := Label.new()
	UiKit.label(l, 7, UiKit.TEXT_DIM)
	l.text = str(n)
	h.add_child(l)
	return chip


func _card(icon: Texture2D, title: String, costs: Dictionary, extra := "") -> Button:
	## Tasarimdaki ikon karti: ikon + ad + maliyet cipleri (+istege bagli stat).
	## Uzun adlar SATIR KIRAR, cok maliyetli kartlarda cipler alt satira tasar
	## (yazi/cip kart disinda kalmasin).
	var b := Button.new()
	UiKit.button(b, 7)
	b.custom_minimum_size = Vector2(88, 104 if extra != "" else 96)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 4.0
	v.offset_bottom = -4.0
	v.offset_left = 3.0
	v.offset_right = -3.0
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := _icon_rect(icon, 32)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var nl := Label.new()
	UiKit.label(nl, 7)
	nl.text = title
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(nl)
	if extra != "":
		var ex := Label.new()
		UiKit.label(ex, 6, UiKit.TEXT_DIM)
		ex.text = extra
		ex.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(ex)
	var chips := HFlowContainer.new()
	chips.alignment = FlowContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("h_separation", 3)
	chips.add_theme_constant_override("v_separation", 2)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(chips)
	for kind in costs:
		chips.add_child(_cost_chip(kind, costs[kind]))
	return b


func _stat_chip(k: String, v: String) -> Control:
	var pod := _pod(6)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	pod.add_child(box)
	var kl := Label.new()
	UiKit.label(kl, 7, UiKit.TEXT_DIM)
	kl.text = k
	kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kl)
	var vl := Label.new()
	UiKit.label(vl, 12)
	vl.text = v
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(vl)
	return pod


func _refresh_panel() -> void:
	for c in action_box.get_children():
		c.queue_free()
	for c in form_box.get_children():
		c.queue_free()
	queue_box.visible = false
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

	# portre + can
	portrait_icon.texture = _entity_icon(first)
	if units.size() > 1:
		sel_label.text = (Tr.t(&"n_units") % units.size()).to_upper()
	else:
		var lvl_txt := ""
		if first.def.has("size") and first.level > 1:
			lvl_txt = " L%d" % first.level
		sel_label.text = Tr.t(first.def_id).to_upper() + lvl_txt
	sel_hp_label.text = "%d / %d" % [int(first.hp), int(first.max_hp)]
	UiKit.set_bar(sel_hp_bar, first.hp / maxf(1.0, first.max_hp))

	# dizilis (2+ birim)
	if units.size() > 1:
		var forms: Array = [&"form_free", &"form_line", &"form_wedge", &"form_box"]
		for fi in forms.size():
			var fb := Button.new()
			fb.text = Tr.t(forms[fi])
			UiKit.button(fb, 6, UiKit.ACCENT_BLUE if input_ctrl.formation == fi else Color.TRANSPARENT)
			fb.pressed.connect(_on_formation.bind(fi))
			form_box.add_child(fb)

	# konuslan butonu: en az bir savas birimi/sihhiyeci seciliyse
	var holdable := false
	var all_holding := true
	for e in units:
		if e.def.get("dmg", 0) > 0 or e.def.has("heal_rate"):
			holdable = true
			if (e.flags & D.FLAG_HOLDING) == 0:
				all_holding = false
	if holdable:
		var hb := Button.new()
		hb.text = Tr.t(&"hold")
		UiKit.button(hb, 6, Color("#f3c64a") if all_holding else Color.TRANSPARENT)
		hb.tooltip_text = Tr.t(&"hold_on")
		hb.pressed.connect(func():
			input_ctrl.toggle_hold()
			_refresh_panel())
		form_box.add_child(hb)

	# panel yuksekligi icerige gore: isci insa menusu 2 satir kart,
	# kisla/fabrika tek satir buyuk kart, digerleri kompakt
	if has_worker:
		bottom.offset_top = -236.0
	elif first.def.has("size") and first.owner_pid == GameState.my_pid \
			and first.is_complete() and (first.def.has("trains") or first.def.has("up_cost")):
		bottom.offset_top = -178.0
	else:
		bottom.offset_top = -124.0

	if has_worker:
		for bid in BUILDABLE:
			var bdef := D.building(bid)
			var card := _card(TileCatalog.building_preview(bid, GameState.my_pid), Tr.t(bid), bdef["cost"])
			card.pressed.connect(input_ctrl.start_placement.bind(bid))
			action_box.add_child(card)
	elif units.size() >= 1:
		# savas birimi: stat cipleri (tasarimdaki HASAR/MENZIL/POP)
		var u: Node = units[0]
		action_box.add_child(_stat_chip(Tr.t(&"hp_short").to_upper(), str(int(u.def["hp"]))))
		if u.def.get("dmg", 0) > 0:
			action_box.add_child(_stat_chip(Tr.t(&"dmg_short").to_upper(), str(int(u.def["dmg"]))))
			action_box.add_child(_stat_chip("MENZİL", str(u.def["range_t"])))
		if u.def.has("heal_rate"):
			action_box.add_child(_stat_chip("İYİLEŞT.", "+%d/sn" % int(u.def["heal_rate"])))
		action_box.add_child(_stat_chip("POP", str(int(u.def["pop"]))))
	elif first.def.has("size") and first.owner_pid == GameState.my_pid and first.is_complete():
		if first.def.has("trains"):
			for uid: StringName in first.def["trains"]:
				var udef := D.unit(uid)
				var card := _card(_unit_icon(uid), Tr.t(uid), udef["cost"], _stat_str(udef))
				card.pressed.connect(Net.send_train.bind(first.id, uid))
				action_box.add_child(card)
			var cancel := _card(null, Tr.t(&"cancel"), {})
			cancel.pressed.connect(Net.send_cancel_train.bind(first.id, 0))
			action_box.add_child(cancel)
		if first.def.has("up_cost") and first.level < D.MAX_LEVEL:
			var up_cost := D.scaled_cost(first.def["up_cost"], first.level)
			var up := _card(null, "%s L%d" % [Tr.t(&"upgrade"), first.level + 1], up_cost, _benefit_str(first.def))
			up.modulate = Color(0.88, 1.05, 0.92)
			up.pressed.connect(Net.send_upgrade.bind(first.id))
			action_box.add_child(up)
		if first.def_id != &"city_hall":
			var dem := _card(null, Tr.t(&"demolish"), {})
			dem.modulate = Color(1.05, 0.8, 0.75)
			dem.pressed.connect(Net.send_demolish.bind(first.id))
			action_box.add_child(dem)
		_refresh_queue()


func _on_formation(f: int) -> void:
	input_ctrl.formation = f
	_refresh_panel()


func _stat_str(udef: Dictionary) -> String:
	if udef.has("heal_rate"):
		return "%s %d" % [Tr.t(&"hp_short"), udef["hp"]]
	if udef.get("dmg", 0) <= 0:
		return "%s %d" % [Tr.t(&"hp_short"), udef["hp"]]
	return "%s %d  %s %d" % [Tr.t(&"hp_short"), udef["hp"], Tr.t(&"dmg_short"), udef["dmg"]]


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


func _refresh_queue() -> void:
	if _sel.is_empty():
		return
	var first: Node = GameState.ent(_sel[0])
	if first == null or not first.def.has("size"):
		return
	if not first.is_complete():
		queue_box.visible = true
		queue_label.text = Tr.t(&"under_construction").to_upper()
		var prog: float = first.construction
		UiKit.set_bar(queue_bar, prog)
		queue_pct.text = "%d%%" % int(prog * 100.0)
		return
	if not first.def.has("trains"):
		return
	var q: Array[StringName] = first.queue
	if q.is_empty():
		queue_box.visible = false
		return
	queue_box.visible = true
	queue_label.text = "%s: %s ×%d" % [Tr.t(&"queue").to_upper(), Tr.t(q[0]).to_upper(), q.size()]
	var prog2: float = first.display_progress() if Net.is_host() else first._display_progress_client()
	UiKit.set_bar(queue_bar, prog2)
	queue_pct.text = "%d%%" % int(prog2 * 100.0)


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
		D.Reject.BORDER: key = &"reject_border"
		_: key = &"reject_bad_spot"
	_toast(Tr.t(key))


# === toast / oyun sonu ===

func _toast(msg: String) -> void:
	var chip := PanelContainer.new()
	UiKit.pod(chip, 7)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	UiKit.label(l, 9, Color("#fff6d6"))
	l.text = msg
	chip.add_child(l)
	chip.modulate.a = 0.0
	toasts.add_child(chip)
	var tw := create_tween()
	tw.tween_property(chip, "modulate:a", 1.0, 0.18)
	tw.tween_interval(2.2)
	tw.tween_property(chip, "modulate:a", 0.0, 0.45)
	tw.tween_callback(chip.queue_free)


func _on_eliminated(pid: int) -> void:
	## FFA'da ara eleme: SEN elendiysen mac bitmeden yenilgi ekrani gelir
	## (izlemeye devam edebilirsin; digerleri tek kisi kalana dek oynar).
	if pid != GameState.my_pid or not GameState.result.is_empty():
		return
	end_overlay.visible = true
	end_icon.texture = UiKit.icon_tex(&"skull")
	end_title.text = Tr.t(&"eliminated_title")
	end_title.add_theme_color_override("font_color", Color("#e0564a"))
	end_reason.text = Tr.t(&"reason_destruction")


func _on_game_over(winner: int, reason: int) -> void:
	end_overlay.visible = true
	var won := winner == GameState.my_pid
	end_icon.texture = UiKit.icon_tex(&"crown" if won else &"skull")
	end_title.text = Tr.t(&"victory") if won else Tr.t(&"defeat")
	end_title.add_theme_color_override("font_color",
		Color("#f3c64a") if won else Color("#e0564a"))
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
