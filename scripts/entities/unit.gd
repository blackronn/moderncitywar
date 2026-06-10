extends Node2D
## Birim node'u (kodla kurulur, .tscn yok). Host'ta sim alanlarini sim.gd
## kullanir; istemcide pozisyon/hp/bayraklar snapshot'tan gelir ve iki
## snapshot arasi interpolasyonla cizilir.

const D := preload("res://scripts/autoload/defs.gd")
const TileCatalog := preload("res://scripts/sim/tile_catalog.gd")

var id := 0
var def_id: StringName
var owner_pid := 1
var def := {}
var hp := 0.0
var max_hp := 0.0
var flags := 0

# --- sim alanlari (yalnizca host) ---
var path: Array[Vector2i] = []
var path_i := 0
var task := {}              # {"kind": &"idle"/&"move"/&"gather"/&"build"/&"attack", ...}
var cooldown := 0.0
var repath_block := 0       # tekrar yol arama frenleyici (tick)

# --- istemci interpolasyonu ---
var _has_snap := false
var _pa := Vector2.ZERO
var _ta := 0.0
var _pb := Vector2.ZERO
var _tb := 0.0

var sprite: Sprite2D
var selected := false:
	set(v):
		selected = v
		queue_redraw()


func setup(p_id: int, p_def_id: StringName, p_owner: int) -> void:
	id = p_id
	def_id = p_def_id
	owner_pid = p_owner
	def = D.unit(def_id)
	hp = def["hp"]
	max_hp = def["hp"]
	task = {"kind": &"idle"}
	sprite = Sprite2D.new()
	sprite.texture = TileCatalog.unit_texture(def_id, owner_pid)
	sprite.flip_h = owner_pid == 2   # P2 sola baksin
	add_child(sprite)
	if def_id == &"worker":
		# tek koylu sprite'i var; sahibi belli olsun diye hafif takim tonu
		sprite.modulate = Color(0.85, 1.0, 0.85) if owner_pid == 1 else Color(1.0, 0.85, 0.85)


func _process(_dt: float) -> void:
	if Net.is_host() or not _has_snap:
		return
	var rt := Time.get_ticks_msec() / 1000.0 - D.INTERP_DELAY_S
	if _tb > _ta:
		var f := clampf((rt - _ta) / (_tb - _ta), 0.0, 1.25)
		position = _pa.lerp(_pb, f)
	else:
		position = _pb


func net_update(pos: Vector2, p_hp: int, p_flags: int, _progress: float, now: float) -> void:
	if not _has_snap:
		position = pos
		_pb = pos
		_tb = now - 0.05
	_has_snap = true
	_pa = _pb
	_ta = _tb
	_pb = pos
	_tb = now
	if p_hp != int(hp) or p_flags != flags:
		hp = p_hp
		flags = p_flags
		queue_redraw()


func snapshot_flags() -> int:
	return flags


func display_progress() -> float:
	return 0.0


func cell() -> Vector2i:
	return Vector2i(position / float(D.TILE))


func set_hp(v: float) -> void:
	hp = clampf(v, 0.0, max_hp)
	queue_redraw()


func _draw() -> void:
	if selected:
		draw_arc(Vector2(0, 4), 8.0, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 1.0)
	if hp < max_hp and hp > 0.0:
		var w := 12.0
		var frac := hp / max_hp
		draw_rect(Rect2(-w / 2.0, -12.0, w, 2.0), Color(0.1, 0.1, 0.1, 0.8))
		var col := Color(0.3, 0.9, 0.3) if frac > 0.4 else Color(0.95, 0.3, 0.2)
		draw_rect(Rect2(-w / 2.0, -12.0, w * frac, 2.0), col)
