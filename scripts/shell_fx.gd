extends Node2D
## Havan mermisi gorseli: dusme noktasinda buyuyen KIRMIZI uyari halkasi,
## yerde kayan golge ve parabolik yayla SUZULEN mermi. Hasar sim'de ucus
## suresi dolunca uygulanir (Ev.SHELL gorseldir, patlama Ev.IMPACT ile gelir).

var from := Vector2.ZERO
var to := Vector2.ZERO
var flight := 1.0
var radius := 25.6           # patlama yaricapi (px) — uyari halkasi boyutu
var _p := 0.0
var _arc_h := 24.0


func launch(p_from: Vector2, p_to: Vector2, t: float, p_radius: float) -> void:
	from = p_from
	to = p_to
	flight = maxf(t, 0.05)
	radius = p_radius
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
	var target := to - position
	# dusme noktasi uyarisi: daralan kirmizi halka (mermi yaklastikca belirgin)
	var warn := Color(0.95, 0.3, 0.2, 0.18 + 0.4 * _p)
	draw_arc(target, radius, 0.0, TAU, 40, warn, 1.0)
	draw_arc(target, radius * (1.0 - _p), 0.0, TAU, 32, Color(0.95, 0.3, 0.2, 0.5 * _p), 1.0)
	draw_circle(target, radius, Color(0.95, 0.3, 0.2, 0.05 + 0.07 * _p))
	# yer golgesi (mermi yukseldikce kuculur/soluklasir)
	var ground := from.lerp(to, _p)
	var height := sin(_p * PI) * _arc_h
	var sh := 1.0 - height / (_arc_h + 14.0)
	draw_circle(ground - position, 1.6 * maxf(sh, 0.4), Color(0.0, 0.0, 0.0, 0.22 * sh + 0.08))
	# merminin kendisi
	var p := ground - position - Vector2(0.0, height)
	draw_circle(p, 1.8, Color("#2c2f36"))
	draw_circle(p + Vector2(-0.5, -0.5), 0.7, Color("#7a818c"))
