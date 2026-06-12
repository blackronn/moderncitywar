extends Node2D
## Havan mermisi gorseli: yerdeki golge hedefe dogru kayar, merminin kendisi
## parabolik yayla havadan SUZULEREK gider. Hasar sim'de ucus suresi dolunca
## uygulanir (Ev.SHELL yalnizca gorseldir, Ev.IMPACT patlamayi getirir).

var from := Vector2.ZERO
var to := Vector2.ZERO
var flight := 1.0
var _p := 0.0
var _arc_h := 24.0


func launch(p_from: Vector2, p_to: Vector2, t: float) -> void:
	from = p_from
	to = p_to
	flight = maxf(t, 0.05)
	_arc_h = 14.0 + from.distance_to(to) * 0.18   # uzak atis = yuksek yay
	position = from
	z_index = 10   # mermi her seyin ustunden ucar


func _process(dt: float) -> void:
	_p += dt / flight
	if _p >= 1.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var ground := from.lerp(to, _p)
	var height := sin(_p * PI) * _arc_h
	# yer golgesi (mermi yukseldikce kuculur/soluklasir)
	var sh := 1.0 - height / (_arc_h + 14.0)
	draw_circle(ground - position, 1.6 * maxf(sh, 0.4), Color(0.0, 0.0, 0.0, 0.22 * sh + 0.08))
	# merminin kendisi
	var p := ground - position - Vector2(0.0, height)
	draw_circle(p, 1.8, Color("#2c2f36"))
	draw_circle(p + Vector2(-0.5, -0.5), 0.7, Color("#7a818c"))
