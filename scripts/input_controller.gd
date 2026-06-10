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
	# dusman varligina tiklandiysa: savastaysak saldir, degilsek uyar
	var enemy_id := _pick_enemy(wp)
	if enemy_id != 0:
		if GameState.war_state == D.War.WAR:
			Net.send_attack(unit_ids, enemy_id)
		else:
			Bus.build_rejected.emit(D.Reject.PEACE)
		return
	var cell := Vector2i((wp / float(D.TILE)).floor())
	var t := GameState.grid_at(cell)
	if D.TILE_RES.has(t):
		Net.send_gather(unit_ids, cell)
	else:
		Net.send_move(unit_ids, wp)


func _pick_enemy(wp: Vector2) -> int:
	var best := 0
	var best_d := 10.0
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid:
			continue
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
