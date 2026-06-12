extends Node2D
## Oyuncu girdisi: sol tik sec / surukle kutu-secim, sag tik baglamsal komut
## (yuru / topla), insa yerlestirme modu (hayalet game.gd'de cizilir).
## Secim yalnizca kendi varliklarindan olur.

const D := preload("res://scripts/autoload/defs.gd")

var game: Node2D = null
var selected: Array[int] = []
var dragging := false
var drag_start := Vector2.ZERO
var drag_cur := Vector2.ZERO
var placing := false
var place_def: StringName
var formation := 0    # 0 serbest, 1 saf, 2 kama, 3 kutu — bozulana kadar korunur


func _ready() -> void:
	Bus.entity_removed.connect(_on_entity_removed)


func _on_entity_removed(id: int, _reason: int) -> void:
	if id in selected:
		selected.erase(id)
		Bus.selection_changed.emit(selected)


func start_placement(def_id: StringName) -> void:
	placing = true
	place_def = def_id
	game.show_ghost(def_id)


func cancel_placement() -> void:
	placing = false
	game.hide_ghost()


func _unhandled_input(event: InputEvent) -> void:
	if GameState.result.size() > 0:
		return   # oyun bitti
	if event is InputEventMouseButton:
		var wp := get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if placing:
					_try_place(wp)
				else:
					dragging = true
					drag_start = wp
					drag_cur = wp
					queue_redraw()
			elif dragging:
				dragging = false
				_finish_select()
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if placing:
				cancel_placement()
			else:
				_command(wp)
	elif event is InputEventMouseMotion:
		if dragging:
			drag_cur = get_global_mouse_position()
			queue_redraw()
		elif placing:
			game.update_ghost(get_global_mouse_position())
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if placing:
			cancel_placement()
		else:
			_set_selection([])
	elif event is InputEventKey and event.pressed and event.keycode == KEY_M:
		# mayin suphesi isareti (lokal)
		var cell := Vector2i((get_global_mouse_position() / float(D.TILE)).floor())
		game.toggle_marker(cell)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_H:
		toggle_hold()


func toggle_hold() -> void:
	## H: secili askerleri KONUSLANDIR / konuslanmayi kaldir.
	## Konuslu birim yerinden kimildamaz; menziline gireni vurur ama kovalamaz.
	var ids := PackedInt32Array()
	var any_free := false
	for id in selected:
		var e: Node = GameState.ent(id)
		if e == null or not e.def.has("speed_t"):
			continue
		if e.def.get("dmg", 0) <= 0 and not e.def.has("heal_rate"):
			continue
		ids.append(id)
		if (e.flags & D.FLAG_HOLDING) == 0:
			any_free = true
	if ids.is_empty():
		return
	Net.send_hold(ids, any_free)   # karisik secimde once HEPSINI konuslandir
	Bus.toast.emit(Tr.t(&"hold_on" if any_free else &"hold_off"))


func _try_place(wp: Vector2) -> void:
	var bdef := D.building(place_def)
	var tl := ghost_tl(wp, bdef["size"])
	var workers := PackedInt32Array()
	for id in selected:
		var e: Node = GameState.ent(id)
		if e != null and e.def_id == &"worker":
			workers.append(id)
	Net.send_build(place_def, tl, workers)
	cancel_placement()


static func ghost_tl(wp: Vector2, size: Vector2i) -> Vector2i:
	var c := Vector2i((wp / float(D.TILE)).floor())
	return c - size / 2


func _finish_select() -> void:
	var rect := Rect2(drag_start, drag_cur - drag_start).abs()
	var ids: Array[int] = []
	if rect.size.length() < 6.0:
		var pick := _pick(drag_cur)
		if pick != 0:
			ids = [pick]
	else:
		for e in GameState.entities.values():
			if e.owner_pid == GameState.my_pid and e.def.has("speed_t") and rect.has_point(e.position):
				ids.append(e.id)
	_set_selection(ids)


func _pick(wp: Vector2) -> int:
	# once birim (yaricap), sonra bina (footprint); yalnizca kendi
	var best := 0
	var best_d := 10.0
	for e in GameState.entities.values():
		if e.owner_pid != GameState.my_pid or not e.def.has("speed_t"):
			continue
		var d := wp.distance_to(e.position)
		if d < best_d:
			best_d = d
			best = e.id
	if best != 0:
		return best
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid and e.def.has("size") and e.footprint_px().has_point(wp):
			return e.id
	return 0


func _set_selection(ids: Array[int]) -> void:
	for id in selected:
		var e: Node = GameState.ent(id)
		if e != null:
			e.selected = false
	selected = ids
	for id in selected:
		var e: Node = GameState.ent(id)
		if e != null:
			e.selected = true
	Bus.selection_changed.emit(selected)


func _command(wp: Vector2) -> void:
	var unit_ids := PackedInt32Array()
	for id in selected:
		var e: Node = GameState.ent(id)
		if e != null and e.owner_pid == GameState.my_pid and e.def.has("speed_t"):
			unit_ids.append(id)
	if unit_ids.is_empty():
		return
	# dusman varligina tiklandiysa: saldir (savas ilani yok, her an serbest)
	var enemy_id := _pick_enemy(wp)
	if enemy_id != 0:
		if GameState.war_state == D.War.WAR:
			Net.send_attack(unit_ids, enemy_id)
		else:
			Bus.build_rejected.emit(D.Reject.PEACE)
		return
	# kendi yarim insaatina tiklandiysa: secili iscileri insaata ata (devam et)
	var own_b := _pick_own_building(wp)
	if own_b != null and not own_b.is_complete():
		var workers := PackedInt32Array()
		for id in unit_ids:
			var e: Node = GameState.ent(id)
			if e != null and e.def_id == &"worker":
				workers.append(id)
		if not workers.is_empty():
			Net.send_assign_build(workers, own_b.id)
			return
	var cell := Vector2i((wp / float(D.TILE)).floor())
	var t := GameState.grid_at(cell)
	if D.TILE_RES.has(t):
		Net.send_gather(unit_ids, cell)
		return
	# dizilis: secili grup hedef noktada secili duzene gore konuslanir
	if formation > 0 and unit_ids.size() > 1:
		_move_in_formation(unit_ids, wp)
	else:
		Net.send_move(unit_ids, wp)


func _move_in_formation(unit_ids: PackedInt32Array, wp: Vector2) -> void:
	## Her birime dizilisteki yuvasinin hedefi gonderilir; grup o duzende
	## durur ve duzen bozulana (yeni emir/kovalamaca) kadar oyle savasir.
	var centroid := Vector2.ZERO
	var nodes: Array = []
	for id in unit_ids:
		var e: Node = GameState.ent(id)
		if e != null:
			nodes.append(e)
			centroid += e.position
	if nodes.is_empty():
		return
	centroid /= nodes.size()
	var dir := (wp - centroid).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var slots := _formation_slots(formation, nodes.size(), dir)
	# yakin birim yakin yuvaya: basit aciyla sirala
	nodes.sort_custom(func(a, b): return a.position.x < b.position.x)
	for i in nodes.size():
		Net.send_move(PackedInt32Array([nodes[i].id]), wp + slots[i])


func _formation_slots(kind: int, n: int, dir: Vector2) -> Array:
	var perp := Vector2(-dir.y, dir.x)
	var out: Array = []
	match kind:
		1:   # SAF: yan yana siralar (8'lik)
			for i in n:
				var row := i / 8
				var col := i % 8
				var row_n: int = mini(8, n - row * 8)
				out.append(perp * (col - (row_n - 1) / 2.0) * 14.0 - dir * row * 16.0)
		2:   # KAMA: V ucu ileride
			out.append(Vector2.ZERO)
			for i in range(1, n):
				var side := 1.0 if i % 2 == 1 else -1.0
				var k := ceili(i / 2.0)
				out.append(-dir * k * 13.0 + perp * side * k * 11.0)
		3:   # KUTU: kare blok
			var cols := ceili(sqrt(float(n)))
			for i in n:
				var row := i / cols
				var col := i % cols
				out.append(perp * (col - (cols - 1) / 2.0) * 14.0 - dir * row * 14.0)
		_:
			for i in n:
				out.append(Vector2.ZERO)
	return out


func select_type(def_id: StringName) -> void:
	## Ordu panelinden: bu turdeki TUM kendi birimlerini sec.
	var ids: Array[int] = []
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid and e.def_id == def_id and e.def.has("speed_t"):
			ids.append(e.id)
	_set_selection(ids)


func _pick_own_building(wp: Vector2) -> Node:
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid and e.def.has("size") and e.footprint_px().has_point(wp):
			return e
	return null


func _pick_enemy(wp: Vector2) -> int:
	var best := 0
	var best_d := 10.0
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid:
			continue
		if not e.visible:
			continue   # rakibin gizli mayini: tiklanamaz/hedeflenemez
		if e.def.has("speed_t"):
			var d := wp.distance_to(e.position)
			if d < best_d:
				best_d = d
				best = e.id
		elif e.footprint_px().has_point(wp):
			return e.id
	return best


func _draw() -> void:
	if dragging:
		var r := Rect2(drag_start, drag_cur - drag_start).abs()
		draw_rect(r, Color(1, 1, 1, 0.08), true)
		draw_rect(r, Color(1, 1, 1, 0.7), false, 1.0)
