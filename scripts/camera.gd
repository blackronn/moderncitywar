extends Camera2D
## RTS kamerasi: WASD/ok tuslari + orta tus surukleme ile pan,
## tekerlekle TAM SAYI zoom adimlari (pixel titremesini onler).

const D := preload("res://scripts/autoload/defs.gd")
const PAN_SPEED := 420.0

var zoom_level := 2


func _ready() -> void:
	make_current()
	# gorunum harita disina tasmasin (zoom 1'de harita viewport'tan kucuk
	# kalirsa sol-ust koseye yapisir, kabul)
	limit_left = 0
	limit_top = 0
	limit_right = D.MAP_W * D.TILE
	limit_bottom = D.MAP_H * D.TILE
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
	position.x = clampf(position.x, 0.0, D.MAP_W * D.TILE)
	position.y = clampf(position.y, 0.0, D.MAP_H * D.TILE)


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
