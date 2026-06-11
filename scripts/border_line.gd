extends Node2D
## Baris sinir cizgisi: orta hatta kesikli dikey cizgi. Savas baslayinca kaybolur.

const D := preload("res://scripts/autoload/defs.gd")


func _ready() -> void:
	visible = GameState.war_state != D.War.WAR
	Bus.war_changed.connect(_on_war)


func _on_war(state: int, _t: float) -> void:
	visible = state != D.War.WAR


func _draw() -> void:
	var x := D.MAP_W / 2.0 * D.TILE
	var y := 0.0
	while y < D.MAP_H * D.TILE:
		draw_line(Vector2(x, y), Vector2(x, y + 6.0), Color(1.0, 1.0, 1.0, 0.30), 1.0)
		draw_line(Vector2(x, y), Vector2(x, y + 6.0), Color(0.86, 0.27, 0.21, 0.18), 3.0)
		y += 13.0
