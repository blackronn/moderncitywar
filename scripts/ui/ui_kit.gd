extends RefCounted
## TAS & DEMIR UI kiti (HUD Redesign.dc.html'in celik stili, birebir palet).
## 9-patch dokulari gen_bible._bake_ui uretir: kalas desenli bevel'li panel
## (kose percinli), cokuk pod, kabarik slot butonlar (hover/pressed/renkli).

const FONT := preload("res://assets/fonts/PublicPixel.ttf")
const DIR := "res://assets/generated/ui/"

# celik palet (tasarimin --steel degiskenleri)
const BG := Color("#0e1117")
const INK := Color("#e9eef6")
const TEXT := Color("#e9eef6")
const TEXT_DIM := Color("#94a2b6")
const ACCENT := Color("#5ec8e6")
const ACCENT2 := Color("#3aa0c0")
const ACCENT_BLUE := Color("#3a78d8")
const ACCENT_RED := Color("#dc4636")
const GOLD := Color("#f3c64a")
const BAR_BG := Color(0, 0, 0, 0.45)
const HP_GREEN := Color("#5fc457")
const POD_BG := Color("#222a35")


static func _tex_box(tex_name: String, margin: int, content := -1) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(DIR + tex_name)
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	if content >= 0:
		sb.content_margin_left = content
		sb.content_margin_right = content
		sb.content_margin_top = content
		sb.content_margin_bottom = content
	return sb


static func panel(p: Control, _radius := 10.0, margin := 6.0) -> void:
	## Ana panel: celik kalaslar + bevel + percin (9-patch).
	p.add_theme_stylebox_override("panel", _tex_box("box_panel.png", 12, int(margin) + 6))


static func pod(p: Control, content := 5) -> void:
	## Cokuk ic kutu (kaynak yuvalari, portre kutusu).
	p.add_theme_stylebox_override("panel", _tex_box("box_pod.png", 6, content))


static func button(b: Button, font_size := 12, accent := Color.TRANSPARENT) -> void:
	var normal_tex := "box_btn.png"
	if accent == ACCENT_BLUE:
		normal_tex = "box_btn_blue.png"
	elif accent == ACCENT_RED:
		normal_tex = "box_btn_red.png"
	var hover_tex := "box_btn_hover.png" if accent == Color.TRANSPARENT else normal_tex
	b.add_theme_stylebox_override("normal", _tex_box(normal_tex, 8, 8))
	b.add_theme_stylebox_override("hover", _tex_box(hover_tex, 8, 8))
	b.add_theme_stylebox_override("pressed", _tex_box("box_btn_pressed.png", 8, 8))
	b.add_theme_stylebox_override("focus", _tex_box(normal_tex, 8, 8))
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", font_size)
	var ink := Color.WHITE if accent != Color.TRANSPARENT else INK
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", TEXT_DIM)
	b.add_theme_color_override("font_focus_color", ink)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func button_state_tex(b: Button, tex_name: String, font_col: Color) -> void:
	## Durum bazli rozet butonlar (savas: slot yesil / amber sayim / kizil savas).
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, _tex_box(tex_name, 8, 8))
	b.add_theme_color_override("font_color", font_col)
	b.add_theme_color_override("font_hover_color", font_col.lightened(0.2))
	b.add_theme_color_override("font_pressed_color", font_col)
	b.add_theme_color_override("font_focus_color", font_col)
	b.add_theme_color_override("font_disabled_color", font_col)


static func label(l: Label, font_size: int, color: Color = INK) -> void:
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)


static func icon_tex(icon: StringName) -> Texture2D:
	return load(DIR + "icon_%s.png" % icon)


static func make_bar(parent: Control, w: float, h: float, fill_col: Color) -> Dictionary:
	## Cokuk ilerleme cubugu: koyu zemin + dolgu. {"bg", "fill", "w", "h"}
	var bg := ColorRect.new()
	bg.color = BAR_BG
	bg.custom_minimum_size = Vector2(w, h)
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color = fill_col
	fill.position = Vector2.ZERO
	fill.size = Vector2(0, h)
	bg.add_child(fill)
	return {"bg": bg, "fill": fill, "w": w, "h": h}


static func set_bar(bar: Dictionary, pct: float) -> void:
	(bar["fill"] as ColorRect).size = Vector2(bar["w"] * clampf(pct, 0.0, 1.0), bar["h"])
