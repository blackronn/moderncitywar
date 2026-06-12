extends Node2D
## Mac sahnesinin koku: haritayi uretir/cizer, entity gorsellerini yonetir,
## host'ta sim.gd'yi kurar. Yapinin tamami kodla kurulur (.tscn ince kabuk).

const D := preload("res://scripts/autoload/defs.gd")
const MapGen := preload("res://scripts/sim/map_gen.gd")
const TileCatalog := preload("res://scripts/sim/tile_catalog.gd")
const Bible := preload("res://scripts/sim/bible.gd")
const FxScript := preload("res://scripts/fx_sprite.gd")
const Pathing := preload("res://scripts/sim/pathing.gd")
const SimScript := preload("res://scripts/sim/sim.gd")
const CameraScript := preload("res://scripts/camera.gd")
const InputScript := preload("res://scripts/input_controller.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const UnitScript := preload("res://scripts/entities/unit.gd")
const BuildingScript := preload("res://scripts/entities/building.gd")

var terrain: TileMapLayer
var features: TileMapLayer
var ground: Node2D
var entities: Node2D
var fx: Node2D
var cam: Camera2D
var hud: Control
var ghost: Node2D
var ghost_sprite: Sprite2D
var pathing = null               # Pathing (RefCounted)
var _ghost_def: StringName
var _screenshot_path := ""


func _ready() -> void:
	# dogrudan acilis / onizleme: seed yoksa sabit seed'le offline kur
	if GameState.seed_v == 0:
		GameState.reset(D.DEFAULT_SEED)

	# iki uc da ayni seed'den ayni haritayi uretir (hash ile dogrulanir)
	var gen := MapGen.generate(GameState.seed_v, GameState.player_count)
	GameState.grid = gen["grid"]
	GameState.spawns = gen["spawns"]
	GameState.map_type = gen["map_type"]
	GameState.map_hash = gen["hash"]

	var ts := TileCatalog.build_tileset()
	terrain = TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = ts
	add_child(terrain)
	features = TileMapLayer.new()
	features.name = "TerrainFeatures"
	features.tile_set = ts
	add_child(features)
	TileCatalog.paint(terrain, features, GameState.grid)

	var border: Node2D = preload("res://scripts/border_line.gd").new()
	border.name = "BorderLine"
	add_child(border)

	# zemin dekorlari (kopru/mayin): araziden SONRA, birimlerden ONCE cizilir;
	# y-sort'a girmez — birimler her zaman ustunden yurur
	ground = Node2D.new()
	ground.name = "GroundDecals"
	add_child(ground)

	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)

	fx = Node2D.new()
	fx.name = "FX"
	add_child(fx)

	ghost = Node2D.new()
	ghost.name = "PlacementGhost"
	ghost.visible = false
	add_child(ghost)
	ghost_sprite = Sprite2D.new()
	ghost.add_child(ghost_sprite)

	cam = CameraScript.new()
	cam.name = "Camera"
	add_child(cam)
	var my_spawn: Vector2i = GameState.spawns[GameState.my_pid - 1]
	cam.position = Vector2(my_spawn) * D.TILE + Vector2(D.TILE, D.TILE)

	pathing = Pathing.new()
	# oyuncu sayisi SART: 3-4 oyuncuda baris bolge grid'leri (astar_half[3/4])
	# ancak boyle kurulur — eksikti ve P3/P4 hareket emrinde host cokuyordu
	pathing.setup(GameState.grid, GameState.player_count)

	var input_c: Node2D = InputScript.new()
	input_c.name = "InputController"
	input_c.game = self
	add_child(input_c)

	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HUD"
	add_child(hud_layer)
	hud = HudScript.new()
	hud.name = "HudRoot"
	hud.game = self
	hud.input_ctrl = input_c
	hud_layer.add_child(hud)

	if Net.is_host():
		var sim: Node = SimScript.new()
		sim.name = "Sim"
		sim.game = self
		sim.pathing = pathing
		add_child(sim)
		Net.sim = sim

	var show_end := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_screenshot_path = arg.get_slice("=", 1)
			if _screenshot_path.is_relative_path():
				_screenshot_path = ProjectSettings.globalize_path("res://") + _screenshot_path
		elif arg == "--end":
			show_end = true   # son ekran onizlemesi (screenshot icin)

	Net.set_game_ready()

	if show_end:
		_preview_end_overlay()
	if _screenshot_path != "":
		_take_screenshot()


func _preview_end_overlay() -> void:
	for _i in 10:
		await get_tree().process_frame
	Net._apply_game_over(1, D.Reason.METROPOLIS)


func _take_screenshot() -> void:
	# render + mac baslangici otursun
	for _i in 45:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_screenshot_path)
	print("SCREENSHOT_SAVED " if err == OK else "SCREENSHOT_FAILED ", _screenshot_path)
	get_tree().quit(0 if err == OK else 1)


# === entity gorselleri: host'ta sim cagirir, istemcide Net (sv_spawn) ===

func spawn_entity_visual(id: int, def_id: StringName, owner_pid: int, pos: Vector2) -> Node:
	var node: Node2D
	if D.is_unit(def_id):
		node = UnitScript.new()
	else:
		node = BuildingScript.new()
	node.setup(id, def_id, owner_pid)
	node.position = pos
	node.name = "E%d" % id
	if node is BuildingScript:
		# footprint sol-ustu pozisyondan turetilir; iki ucta ortak yol
		var size: Vector2i = node.def["size"]
		node.cell = Vector2i(((pos - Vector2(size) * D.TILE / 2.0) / D.TILE).round())
		# kopru/mayin/siper yuruyusu ENGELLEMEZ (gecis, gizli, arkasinda durma)
		if not node.def.has("bridge") and not node.def.has("mine") and not node.def.has("cover"):
			pathing.set_rect_solid(node.cell, size, true)
		# rakibin mayini bu ekranda gorunmez (host herkesi sim'ler)
		if node.def.has("mine") and owner_pid != GameState.my_pid:
			node.visible = false
	if node is BuildingScript and (node.def.has("bridge") or node.def.has("mine")):
		ground.add_child(node)   # zemin dekoru: birimlerin ALTINDA kalir
	else:
		entities.add_child(node)
	GameState.entities[id] = node
	Bus.entity_spawned.emit(node)
	return node


func despawn_entity_visual(id: int, reason: int) -> void:
	var node: Node = GameState.entities.get(id)
	if node == null:
		return
	if node is BuildingScript and not node.def.has("bridge") and not node.def.has("mine") \
			and not node.def.has("cover"):
		pathing.set_rect_solid(node.cell, node.def["size"], false)
	if reason == 1:
		_death_visual(node)
	GameState.entities.erase(id)
	Bus.entity_removed.emit(id, reason)
	node.queue_free()


func _death_visual(node: Node) -> void:
	## Bible olum sahnesi: birim kendi olum animasyonunu oynar (devril+sol),
	## bina patlama efektiyle gider.
	if node is UnitScript:
		var table: Array = Bible.UNIT_ANIMS[node.def_id]
		var row := Bible.unit_anim_row(node.def_id, &"death")
		var corpse: Sprite2D = FxScript.new()
		corpse.texture = load(Bible.unit_sheet(node.def_id, node.owner_pid))
		corpse.hframes = Bible.UNIT_COLS
		corpse.vframes = table.size()
		corpse.row = row
		corpse.frames = table[row][1]
		corpse.frame_dt = table[row][2]
		corpse.one_shot = true
		corpse.offset = Vector2(0, 1)
		corpse.flip_h = node.sprite.flip_h
		corpse.position = node.position
		fx.add_child(corpse)
	else:
		var size: Vector2i = node.def["size"]
		spawn_fx(&"explosion", node.position, 1.2 * size.x)


func spawn_shell(from: Vector2, to: Vector2, flight: float) -> void:
	## Havan mermisi: yay cizerek suzulur; patlama IMPACT event'iyle ayri gelir.
	var s: Node2D = preload("res://scripts/shell_fx.gd").new()
	fx.add_child(s)
	s.launch(from, to, flight)


func spawn_fx(fx_id: StringName, at: Vector2, fx_scale := 1.0, ttl := 0.0) -> void:
	var meta: Array = Bible.FX[fx_id]
	var s: Sprite2D = FxScript.new()
	s.texture = load(Bible.fx_sheet(fx_id))
	s.hframes = meta[0]
	s.vframes = 1
	s.frames = meta[0]
	s.frame_dt = meta[1]
	s.one_shot = not meta[2]
	s.ttl = ttl
	s.position = at
	s.scale = Vector2(fx_scale, fx_scale)
	fx.add_child(s)


# === insa hayaleti ===

func show_ghost(def_id: StringName) -> void:
	_ghost_def = def_id
	ghost_sprite.texture = TileCatalog.building_preview(def_id, GameState.my_pid)
	ghost_sprite.scale = Vector2.ONE   # bible sheet'leri footprint olcusunde pisirilir
	ghost.visible = true
	update_ghost(get_global_mouse_position())


func hide_ghost() -> void:
	ghost.visible = false


func update_ghost(wp: Vector2) -> void:
	if not ghost.visible:
		return
	var bdef := D.building(_ghost_def)
	var size: Vector2i = bdef["size"]
	var tl: Vector2i = InputScript.ghost_tl(wp, size)
	ghost.position = (Vector2(tl) + Vector2(size) / 2.0) * D.TILE
	var ok := _ghost_valid(tl, bdef)
	ghost.modulate = Color(0.45, 1.0, 0.45, 0.65) if ok else Color(1.0, 0.35, 0.35, 0.65)


func _ghost_valid(tl: Vector2i, bdef: Dictionary) -> bool:
	# istemci tarafi ON-kontrol (renk icin); asil dogrulama host'ta
	if not GameState.can_afford(GameState.my_pid, bdef["cost"]):
		return false
	if bdef.has("bridge"):
		# kopru: su hucresi + yurunebilir komsu
		if GameState.grid_at(tl) != D.Tile.WATER:
			return false
		for off in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var t := GameState.grid_at(tl + off)
			if (t != -1 and t != D.Tile.WATER and t != D.Tile.HILL) \
					or not pathing.is_solid(tl + off):
				return true
		return false
	var size: Vector2i = bdef["size"]
	for dy in size.y:
		for dx in size.x:
			var c := tl + Vector2i(dx, dy)
			if not D.BUILDABLE_TILES.has(GameState.grid_at(c)):
				return false
			if pathing.is_solid(c):
				return false
	if bdef.has("mine"):
		return true   # mayinda sehir yaricapi kurali yok
	var rect := Rect2i(tl, size)
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid and e.def.has("size"):
			if SimScript._rect_chebyshev(rect, Rect2i(e.cell, e.def["size"])) <= D.BUILD_RADIUS_TILES:
				return true
	return false


# === mayin suphesi isaretleri (tamamen lokal) ===

var _markers := {}


func toggle_marker(cell: Vector2i) -> void:
	if _markers.has(cell):
		_markers[cell].queue_free()
		_markers.erase(cell)
		return
	var m: Node2D = preload("res://scripts/marker.gd").new()
	m.position = Vector2(cell) * D.TILE + Vector2(D.TILE, D.TILE) / 2.0
	fx.add_child(m)
	_markers[cell] = m


func on_tile_depleted(cell: Vector2i) -> void:
	features.erase_cell(cell)


static var _tracer_tex: Texture2D = null


func show_tracer(from: Vector2, to: Vector2, kind := 0) -> void:
	if kind == 1:
		# iyilestirme isini: yesil cizgi (bible'da heal fx yok; mevcut stil)
		var line := Line2D.new()
		line.points = PackedVector2Array([from, to])
		line.width = 1.0
		line.default_color = Color(0.45, 1.0, 0.55, 0.9)
		fx.add_child(line)
		get_tree().create_timer(0.18).timeout.connect(line.queue_free)
		return
	# bible mermi izi: namlu parlama + soluk iz + ucan parlak mermi basi
	spawn_fx(&"muzzle", from)
	var trail := Line2D.new()
	trail.points = PackedVector2Array([from, to])
	trail.width = 1.0
	trail.default_color = Color(1.0, 0.823, 0.47, 0.35)
	fx.add_child(trail)
	var tw_trail := create_tween()
	tw_trail.tween_property(trail, "modulate:a", 0.0, 0.18)
	tw_trail.tween_callback(trail.queue_free)
	if _tracer_tex == null:
		var img := Image.create(4, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color("#ffd070"))
		img.set_pixel(1, 0, Color("#ffd070"))
		img.set_pixel(2, 0, Color("#fff3b0"))
		img.set_pixel(3, 0, Color("#fff3b0"))
		_tracer_tex = ImageTexture.create_from_image(img)
	var head := Sprite2D.new()
	head.texture = _tracer_tex
	head.position = from
	head.rotation = from.angle_to_point(to)
	fx.add_child(head)
	var tw := create_tween()
	tw.tween_property(head, "position", to, clampf(from.distance_to(to) / 420.0, 0.05, 0.18))
	tw.tween_callback(head.queue_free)
