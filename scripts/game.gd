extends Node2D
## Mac sahnesinin koku: haritayi uretir/cizer, entity gorsellerini yonetir,
## host'ta sim.gd'yi kurar. Yapinin tamami kodla kurulur (.tscn ince kabuk).

const D := preload("res://scripts/autoload/defs.gd")
const MapGen := preload("res://scripts/sim/map_gen.gd")
const TileCatalog := preload("res://scripts/sim/tile_catalog.gd")
const Pathing := preload("res://scripts/sim/pathing.gd")
const SimScript := preload("res://scripts/sim/sim.gd")
const CameraScript := preload("res://scripts/camera.gd")
const InputScript := preload("res://scripts/input_controller.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const UnitScript := preload("res://scripts/entities/unit.gd")
const BuildingScript := preload("res://scripts/entities/building.gd")

var terrain: TileMapLayer
var features: TileMapLayer
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
	var gen := MapGen.generate(GameState.seed_v)
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
	pathing.setup(GameState.grid)

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
		pathing.set_rect_solid(node.cell, size, true)
	entities.add_child(node)
	GameState.entities[id] = node
	Bus.entity_spawned.emit(node)
	return node


func despawn_entity_visual(id: int, reason: int) -> void:
	var node: Node = GameState.entities.get(id)
	if node == null:
		return
	if node is BuildingScript:
		pathing.set_rect_solid(node.cell, node.def["size"], false)
	if reason == 1:
		_death_flash(node.position)
	GameState.entities.erase(id)
	Bus.entity_removed.emit(id, reason)
	node.queue_free()


func _death_flash(at: Vector2) -> void:
	var fl := Node2D.new()
	fl.position = at
	var l1 := Line2D.new()
	l1.points = PackedVector2Array([Vector2(-4, -4), Vector2(4, 4)])
	l1.width = 2.0
	l1.default_color = Color(1, 1, 1, 0.9)
	var l2 := Line2D.new()
	l2.points = PackedVector2Array([Vector2(-4, 4), Vector2(4, -4)])
	l2.width = 2.0
	l2.default_color = Color(1, 1, 1, 0.9)
	fl.add_child(l1)
	fl.add_child(l2)
	fx.add_child(fl)
	var tw := create_tween()
	tw.tween_property(fl, "modulate:a", 0.0, 0.35)
	tw.tween_callback(fl.queue_free)


# === insa hayaleti ===

func show_ghost(def_id: StringName) -> void:
	_ghost_def = def_id
	ghost_sprite.texture = TileCatalog.building_texture(def_id, GameState.my_pid)
	ghost_sprite.scale = Vector2(D.building(def_id)["size"] as Vector2i)
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
	var size: Vector2i = bdef["size"]
	for dy in size.y:
		for dx in size.x:
			var c := tl + Vector2i(dx, dy)
			if GameState.grid_at(c) != D.Tile.GRASS:
				return false
			if pathing.is_solid(c):
				return false
	var rect := Rect2i(tl, size)
	for e in GameState.entities.values():
		if e.owner_pid == GameState.my_pid and e.def.has("size"):
			if SimScript._rect_chebyshev(rect, Rect2i(e.cell, e.def["size"])) <= D.BUILD_RADIUS_TILES:
				return true
	return false


func on_tile_depleted(cell: Vector2i) -> void:
	features.erase_cell(cell)


func show_tracer(from: Vector2, to: Vector2, kind := 0) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = 1.0
	# 0 = mermi (sari), 1 = iyilestirme isini (yesil)
	line.default_color = Color(0.45, 1.0, 0.55, 0.9) if kind == 1 else Color(1.0, 0.95, 0.6, 0.9)
	fx.add_child(line)
	get_tree().create_timer(0.18 if kind == 1 else 0.1).timeout.connect(line.queue_free)
