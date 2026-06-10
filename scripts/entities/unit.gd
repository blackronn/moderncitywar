extends Node2D
## Birim node'u. Gorseller Asset Bibliasi sheet'lerinden kare kare oynar:
## bayraklara gore idle / yuru / ates / topla / insa / iyilestir. Olum
## animasyonunu game.gd despawn'da ayri bir "ceset" node'u oynatir.
## Host'ta sim alanlarini sim.gd kullanir; istemcide pozisyon/hp/bayraklar
## snapshot'tan gelir ve iki snapshot arasi interpolasyonla cizilir.

const D := preload("res://scripts/autoload/defs.gd")
const Bible := preload("res://scripts/sim/bible.gd")

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
var task := {}              # {"kind": &"idle"/&"move"/&"gather"/&"build"/&"attack"/&"heal", ...}
var cooldown := 0.0
var repath_block := 0       # tekrar yol arama frenleyici (tick)

# --- istemci interpolasyonu ---
var _has_snap := false
var _pa := Vector2.ZERO
var _ta := 0.0
var _pb := Vector2.ZERO
var _tb := 0.0

# --- animasyon ---
var sprite: Sprite2D
var _anim_table: Array = []
var _anim := &"idle"
var _anim_t := 0.0
var _prev_x := 0.0
var _fx_t := 0.0

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
	_anim_table = Bible.UNIT_ANIMS[def_id]
	sprite = Sprite2D.new()
	sprite.texture = load(Bible.unit_sheet(def_id, owner_pid))
	sprite.hframes = Bible.UNIT_COLS
	sprite.vframes = _anim_table.size()
	sprite.offset = Vector2(0, 1)    # 24px karede ayaklar tile tabanina otursun
	sprite.flip_h = owner_pid == 2   # P2 sola bakar; hareketle guncellenir
	add_child(sprite)
	_anim_t = randf() * 2.0          # ayni anda dogan birimler senkron sallanmasin


func _process(dt: float) -> void:
	# istemci: snapshot interpolasyonu
	if not Net.is_host() and _has_snap:
		var rt := Time.get_ticks_msec() / 1000.0 - D.INTERP_DELAY_S
		if _tb > _ta:
			var f := clampf((rt - _ta) / (_tb - _ta), 0.0, 1.25)
			position = _pa.lerp(_pb, f)
		else:
			position = _pb
	_advance_anim(dt)
	_emit_work_fx(dt)


func _advance_anim(dt: float) -> void:
	var want := _pick_anim()
	if want != _anim:
		_anim = want
		_anim_t = 0.0
	_anim_t += dt
	var row := Bible.unit_anim_row(def_id, _anim)
	var spec: Array = _anim_table[row]
	var fi := int(_anim_t / float(spec[2])) % int(spec[1])
	sprite.frame = row * Bible.UNIT_COLS + fi
	# yon: hareket ettigi tarafa bak
	var dx := position.x - _prev_x
	if absf(dx) > 0.08:
		sprite.flip_h = dx < 0.0
	_prev_x = position.x


func _pick_anim() -> StringName:
	var want: StringName = &"idle"
	if flags & D.FLAG_ATTACKING:
		want = &"attack"
	elif flags & D.FLAG_HEALING:
		want = &"heal"
	elif flags & D.FLAG_GATHERING:
		want = &"gather"
	elif flags & D.FLAG_CONSTRUCTING:
		want = &"build"
	elif flags & D.FLAG_MOVING:
		want = &"walk"
	for row in _anim_table:
		if row[0] == want:
			return want
	return &"idle"


func _emit_work_fx(dt: float) -> void:
	## Toplarken yonga, insa ederken toz (iki ucta da yalnizca gorsel).
	var working := flags & (D.FLAG_GATHERING | D.FLAG_CONSTRUCTING)
	if working == 0:
		_fx_t = 0.3
		return
	_fx_t -= dt
	if _fx_t > 0.0:
		return
	_fx_t = 0.55
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("spawn_fx"):
		return
	var front := Vector2(-7.0 if sprite.flip_h else 7.0, -1.0)
	if flags & D.FLAG_GATHERING:
		scene.spawn_fx(&"gather_fx", position + front, 1.0, 0.7)
	else:
		scene.spawn_fx(&"build_fx", position + front, 1.0, 0.7)


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
		var c := Color(0.3, 0.9, 0.3) if frac > 0.4 else Color(0.95, 0.3, 0.2)
		draw_rect(Rect2(-w / 2.0, -12.0, w * frac, 2.0), c)
