extends Node2D
## Lokal mayin-suphesi isareti (M tusu): kirmizi flama + unlem. Aga gitmez,
## yalnizca koyan oyuncunun ekraninda gorunur.


func _draw() -> void:
	draw_line(Vector2(0, 4), Vector2(0, -10), Color(0.85, 0.85, 0.85), 1.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -10), Vector2(8, -7.5), Vector2(0, -5),
	]), Color(0.86, 0.27, 0.21))
	draw_rect(Rect2(-1.5, 4, 3, 1.5), Color(0.3, 0.3, 0.3))
	# unlem
	draw_rect(Rect2(2.4, -9.3, 1.0, 2.4), Color(1, 1, 1))
	draw_rect(Rect2(2.4, -6.4, 1.0, 1.0), Color(1, 1, 1))
