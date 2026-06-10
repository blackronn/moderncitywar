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
var pathing = null               # Pathing (RefCounted)
var _screenshot_path := ""


func _ready() -> void:
	# dogrudan acilis / onizleme: seed yoksa sabit seed'le offline kur
	if GameState.seed_v == 0:
		GameState.reset(D.DEFAULT_SEED)

	# iki uc da ayni seed'den ayni haritayi uretir (hash ile dogrulanir)
	var gen := MapGen.generate(GameState.seed_v)
	GameState.grid = gen["grid"]
	GameState.spawns = gen["spawns"]
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

	cam = CameraScript.new()
	cam.name = "Camera"
	add_child(cam)
	var my_spawn: Vector2i = GameState.spawns[GameState.my_pid - 1]
	cam.position = Vector2(my_spawn) * D.TILE + Vector2(D.TILE, D.TILE)

	var input_c: Node = InputScript.new()
	input_c.name = "InputController"
	add_child(input_c)

	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HUD"
	add_child(hud_layer)
	hud = HudScript.new()
	hud.name = "HudRoot"
	hud_layer.add_child(hud)

	pathing = Pathing.new()
	pathing.setup(GameState.grid)

	if Net.is_host():
		var sim: Node = SimScript.new()
		sim.name = "Sim"
		sim.game = self
		sim.pathing = pathing
		add_child(sim)
		Net.sim = sim

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_screenshot_path = arg.get_slice("=", 1)
			if _screenshot_path.is_relative_path():
				_screenshot_path = ProjectSettings.globalize_path("res://") + _screenshot_path

	Net.set_game_ready()

	if _screenshot_path != "":
		_take_screenshot()


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
	entities.add_child(node)
	GameState.entities[id] = node
	Bus.entity_spawned.emit(node)
	return node


func despawn_entity_visual(id: int, reason: int) -> void:
	var node: Node = GameState.entities.get(id)
	if node == null:
		return
	GameState.entities.erase(id)
	Bus.entity_removed.emit(id, reason)
	node.queue_free()


func on_tile_depleted(cell: Vector2i) -> void:
	features.erase_cell(cell)


func show_tracer(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = 1.0
	line.default_color = Color(1.0, 0.95, 0.6, 0.9)
	fx.add_child(line)
	get_tree().create_timer(0.1).timeout.connect(line.queue_free)
