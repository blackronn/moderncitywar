extends Node2D
## Baris sinir cizgileri: 2 oyunculu macta dikey orta hat; 3-4 oyunculu
## macta dikey + yatay hac. Savas baslayinca kaybolur.

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
	if GameState.player_count > 2:
		var hy := D.MAP_H / 2.0 * D.TILE
		var hx := 0.0
		while hx < D.MAP_W * D.TILE:
			draw_line(Vector2(hx, hy), Vector2(hx + 6.0, hy), Color(1.0, 1.0, 1.0, 0.30), 1.0)
			draw_line(Vector2(hx, hy), Vector2(hx + 6.0, hy), Color(0.86, 0.27, 0.21, 0.18), 3.0)
			hx += 13.0
