extends Sprite2D
## Sheet tabanli mini efekt/animasyon oynatici (Asset Bibliasi kareleri).
## one_shot: animasyon bitince kendini siler. ttl > 0: dongulu efektin omru.

var frames := 1
var frame_dt := 0.1
var one_shot := true
var ttl := 0.0
var row := 0

var _t := 0.0
var _life := 0.0


func _process(delta: float) -> void:
	_t += delta
	_life += delta
	var fi := int(_t / frame_dt)
	if one_shot and fi >= frames:
		queue_free()
		return
	frame = row * hframes + (fi % frames)
	if ttl > 0.0 and _life >= ttl:
		queue_free()
