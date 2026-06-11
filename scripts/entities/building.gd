extends Node2D
## Bina node'u (kodla kurulur). position = footprint'in merkez pikseli.
## construction 0..1 (1 = bitmis). Uretim kuyrugu yalnizca host'ta islenir;
## istemci ilerlemeyi snapshot progress baytindan okur.

const D := preload("res://scripts/autoload/defs.gd")
const Bible := preload("res://scripts/sim/bible.gd")

var id := 0
var def_id: StringName
var owner_pid := 1
var def := {}
var hp := 0.0
var max_hp := 0.0
var flags := 0
var construction := 1.0
var level := 1                       # gelistirme seviyesi (1..D.MAX_LEVEL)

# --- sim alanlari (host) ---
var cell := Vector2i(-1, -1)         # footprint sol-ust
var queue: Array[StringName] = []    # uretim kuyrugu
var queue_t := 0.0                   # kuyruk basindaki birimin kalan suresi
var cooldown := 0.0                  # taret atis bekleme

# --- istemci gosterimi ---
var _net_progress := 1.0

# --- animasyon ---
var _anim_frames := 1
var _anim_dt := 0.2
var _anim_t := 0.0

var sprite: Sprite2D
var selected := false:
	set(v):
		selected = v
		queue_redraw()


func setup(p_id: int, p_def_id: StringName, p_owner: int) -> void:
	id = p_id
	def_id = p_def_id
	owner_pid = p_owner
	def = D.building(def_id)
	hp = def["hp"]
	max_hp = def["hp"]
	# Asset Bibliasi: ambient animasyonlu sheet (bayrak/duman/parilti/taret)
	var meta: Array = Bible.BUILDING_ANIMS[def_id]
	_anim_frames = meta[0]
	_anim_dt = meta[1]
	sprite = Sprite2D.new()
	sprite.texture = load(Bible.building_sheet(def_id, owner_pid))
	sprite.hframes = _anim_frames
	sprite.vframes = 1
	add_child(sprite)
	if def.has("bridge"):
		z_index = -1   # kopru ZEMINDIR: birimler ustunde yurur, altinda degil
	elif def.has("mine"):
		z_index = -1   # mayin da yerde; birimler uzerinden gecer
	_anim_t = randf() * _anim_frames * _anim_dt   # binalar senkron oynamasin
	_update_construction_visual()


func _process(dt: float) -> void:
	_anim_t += dt
	sprite.frame = int(_anim_t / _anim_dt) % _anim_frames


func start_construction() -> void:
	construction = 0.0
	hp = max_hp * 0.1
	_update_construction_visual()


func set_construction(v: float) -> void:
	construction = clampf(v, 0.0, 1.0)
	# insaat ilerledikce can da dolar (AoE usulu)
	hp = maxf(hp, max_hp * (0.1 + 0.9 * construction))
	_update_construction_visual()


func is_complete() -> bool:
	return construction >= 1.0


func _update_construction_visual() -> void:
	if is_complete():
		modulate = Color.WHITE
	else:
		modulate = Color(1, 1, 1, 0.55)
	queue_redraw()


func net_update(_pos: Vector2, p_hp: int, p_flags: int, progress: float, _now: float) -> void:
	hp = p_hp
	flags = p_flags
	_net_progress = progress
	if flags & D.FLAG_CONSTRUCTING:
		construction = progress
	else:
		construction = 1.0
	_update_construction_visual()


func snapshot_flags() -> int:
	var f := 0
	if construction < 1.0:
		f |= D.FLAG_CONSTRUCTING
	elif not queue.is_empty():
		f |= D.FLAG_PRODUCING
	return f


func display_progress() -> float:
	if construction < 1.0:
		return construction
	if not queue.is_empty():
		var total: float = D.unit(queue[0]).get("train_s", 1.0)
		return clampf(1.0 - queue_t / maxf(total, 0.01), 0.0, 1.0)
	return 0.0


func footprint_px() -> Rect2:
	var size: Vector2i = def["size"]
	return Rect2(position - Vector2(size) * D.TILE / 2.0, Vector2(size) * D.TILE)


func set_hp(v: float) -> void:
	hp = clampf(v, 0.0, max_hp)
	queue_redraw()


func _draw() -> void:
	var size: Vector2i = def["size"]
	var half := Vector2(size) * D.TILE / 2.0
	if selected:
		draw_rect(Rect2(-half, Vector2(size) * D.TILE), Color(1, 1, 1, 0.85), false, 1.0)
	# gelistirme seviyesi: sol-ust kosede altin pip'ler (L2 = 1, L3 = 2)
	for i in range(level - 1):
		draw_rect(Rect2(-half.x + 1.0 + i * 4.0, -half.y + 1.0, 3.0, 3.0), Color(0.95, 0.82, 0.3))
	# can / ilerleme cubugu
	var frac := hp / max_hp
	var show_bar := frac < 1.0 or not is_complete() or (flags & D.FLAG_PRODUCING) or not queue.is_empty()
	if show_bar:
		var w := half.x * 2.0 - 2.0
		draw_rect(Rect2(-w / 2.0, -half.y - 5.0, w, 2.0), Color(0.1, 0.1, 0.1, 0.8))
		var col := Color(0.3, 0.9, 0.3) if frac > 0.4 else Color(0.95, 0.3, 0.2)
		draw_rect(Rect2(-w / 2.0, -half.y - 5.0, w * clampf(frac, 0.0, 1.0), 2.0), col)
		var prog := display_progress() if Net.is_host() else _display_progress_client()
		if prog > 0.0 and prog < 1.0:
			draw_rect(Rect2(-w / 2.0, -half.y - 2.5, w, 1.5), Color(0.1, 0.1, 0.1, 0.8))
			draw_rect(Rect2(-w / 2.0, -half.y - 2.5, w * prog, 1.5), Color(0.95, 0.85, 0.3))


func _display_progress_client() -> float:
	if construction < 1.0 or (flags & D.FLAG_PRODUCING):
		return _net_progress
	return 0.0
