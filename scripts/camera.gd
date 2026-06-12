extends Camera2D
## RTS kamerasi: WASD/ok tuslari + orta tus surukleme ile pan,
## tekerlekle TAM SAYI zoom adimlari (pixel titremesini onler).
## HUD PAYI: alt bar / sag panel haritanin kenarini kaliciydi kapatiyordu;
## limitler HUD kadar disari tasar ki en alttaki/sagdaki kaynaklar panelin
## USTUNE kaydirilabilsin (yoksa oraya isci gonderilemiyordu).

const D := preload("res://scripts/autoload/defs.gd")
const PAN_SPEED := 420.0
const HUD_BOTTOM_PX := 244.0   # insa panelinin en yuksek hali + kenar payi
const HUD_RIGHT_PX := 142.0    # ordu/minimap sutunu (kompakt)
const HUD_TOP_PX := 48.0       # ust kaynak bari

var zoom_level := 2


func _ready() -> void:
	make_current()
	_apply_zoom()


func _process(dt: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * dt / float(zoom_level)
	position.x = clampf(position.x, 0.0, D.MAP_W * D.TILE + HUD_RIGHT_PX / float(zoom_level))
	position.y = clampf(position.y, -HUD_TOP_PX / float(zoom_level),
		D.MAP_H * D.TILE + HUD_BOTTOM_PX / float(zoom_level))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = clampi(zoom_level + 1, 1, 4)
			_apply_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = clampi(zoom_level - 1, 1, 4)
			_apply_zoom()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		position -= event.relative / float(zoom_level)


func _apply_zoom() -> void:
	zoom = Vector2(zoom_level, zoom_level)
	# limitler zoom'a gore: HUD'un ekranda kapladigi alan dunya olceginde
	# zoom'la kuculur; harita kenari + HUD payi kadar kaydirma serbest
	limit_left = 0
	limit_top = -int(ceilf(HUD_TOP_PX / float(zoom_level)))
	limit_right = D.MAP_W * D.TILE + int(ceilf(HUD_RIGHT_PX / float(zoom_level)))
	limit_bottom = D.MAP_H * D.TILE + int(ceilf(HUD_BOTTOM_PX / float(zoom_level)))
