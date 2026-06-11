extends RefCounted
## VoxGard UI kiti: yumusak (yuvarlak koseli, hover'li) buton ve panel
## stilleri. Menu, lobi ve HUD ayni dili konussun diye tek yerde.

const FONT := preload("res://assets/fonts/PublicPixel.ttf")

const BG := Color("#0e1118")
const PANEL_BG := Color(0.086, 0.106, 0.149, 0.94)     # #161b26
const BTN_BG := Color("#1a2130")
const BTN_HOVER := Color("#26304a")
const BTN_PRESS := Color("#121826")
const ACCENT_BLUE := Color("#2f6fd6")
const ACCENT_RED := Color("#c43a2e")
const TEXT := Color("#cdd5e2")
const TEXT_DIM := Color("#8b94a7")


static func _box(bg: Color, radius: float, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 9.0
	sb.content_margin_bottom = 9.0
	return sb


static func button(b: Button, font_size := 12, accent: Color = Color.TRANSPARENT) -> void:
	## Yumusak buton: koyu zemin, hover'da aydinlanir, basinca koyulasir.
	var base := BTN_BG if accent == Color.TRANSPARENT else accent.darkened(0.25)
	var hover := BTN_HOVER if accent == Color.TRANSPARENT else accent
	var press := BTN_PRESS if accent == Color.TRANSPARENT else accent.darkened(0.45)
	var border := Color(1, 1, 1, 0.08) if accent == Color.TRANSPARENT else accent.lightened(0.2)
	b.add_theme_stylebox_override("normal", _box(base, 9, border))
	b.add_theme_stylebox_override("hover", _box(hover, 9, border.lightened(0.2)))
	b.add_theme_stylebox_override("pressed", _box(press, 9, border))
	b.add_theme_stylebox_override("focus", _box(hover, 9, border))
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT if accent == Color.TRANSPARENT else Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func panel(p: PanelContainer, radius := 10.0, margin := 10.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(int(radius))
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.content_margin_left = margin + 4.0
	sb.content_margin_right = margin + 4.0
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	p.add_theme_stylebox_override("panel", sb)


static func label(l: Label, font_size: int, color: Color = TEXT) -> void:
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
