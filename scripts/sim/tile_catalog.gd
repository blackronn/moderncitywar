extends RefCounted
## Asset Bibliasi zemin seti: ANIMASYONLU TileSet'i kodla kurar (su akar,
## cicekler/agaclar salinir, kaya parlar) + insa hayaleti icin bina onizlemesi.
## Sheet'ler tools/gen_bible.gd tarafindan uretilir.

const D := preload("res://scripts/autoload/defs.gd")
const Bible := preload("res://scripts/sim/bible.gd")

# kind -> atlas source id
const SRC_IDS := {
	D.Tile.GRASS: 0,
	D.Tile.WATER: 1,
	D.Tile.BRIDGE: 2,
	D.Tile.FOREST: 3,
	D.Tile.STONE: 4,
	D.Tile.GOLD: 5,
	D.Tile.SNOW: 6,
	D.Tile.HILL: 7,
}
const KIND_NAMES := {
	D.Tile.GRASS: &"grass",
	D.Tile.WATER: &"water",
	D.Tile.BRIDGE: &"bridge",
	D.Tile.FOREST: &"forest",
	D.Tile.STONE: &"stone",
	D.Tile.GOLD: &"gold",
	D.Tile.SNOW: &"snow",
	D.Tile.HILL: &"hill",
}


static func build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(D.TILE, D.TILE)
	for kind: int in SRC_IDS:
		var kname: StringName = KIND_NAMES[kind]
		var meta: Array = Bible.TILE_ANIMS[kname]
		var variants: int = meta[0]
		var frames: int = meta[1]
		var dt: float = meta[2]
		var src := TileSetAtlasSource.new()
		src.texture = load(Bible.tile_sheet(kname))
		src.texture_region_size = Vector2i(D.TILE, D.TILE)
		for v in variants:
			var coords := Vector2i(0, v)
			src.create_tile(coords)
			src.set_tile_animation_frames_count(coords, frames)
			for f in frames:
				src.set_tile_animation_frame_duration(coords, f, dt)
		ts.add_source(src, SRC_IDS[kind])
	return ts


static func paint(terrain: TileMapLayer, features: TileMapLayer, grid: PackedInt32Array) -> void:
	terrain.clear()
	features.clear()
	# kar haritasinda zemin kar; ozellikler (orman/tas/altin) seffaf bindirme
	var snow_map: bool = GameState.map_type == D.MapType.SNOW
	var ground_kind: int = D.Tile.SNOW if snow_map else D.Tile.GRASS
	var ground_name: StringName = &"snow" if snow_map else &"grass"
	for y in D.MAP_H:
		for x in D.MAP_W:
			var cell := Vector2i(x, y)
			var t := grid[y * D.MAP_W + x]
			match t:
				D.Tile.WATER:
					terrain.set_cell(cell, SRC_IDS[D.Tile.WATER], Vector2i(0, _variant(cell, &"water")))
				D.Tile.BRIDGE:
					terrain.set_cell(cell, SRC_IDS[D.Tile.BRIDGE], Vector2i(0, _variant(cell, &"bridge")))
				D.Tile.HILL:
					terrain.set_cell(cell, SRC_IDS[D.Tile.HILL], Vector2i(0, _variant(cell, &"hill")))
				D.Tile.SNOW:
					terrain.set_cell(cell, SRC_IDS[D.Tile.SNOW], Vector2i(0, _variant(cell, &"snow")))
				_:
					terrain.set_cell(cell, SRC_IDS[ground_kind], Vector2i(0, _variant(cell, ground_name)))
			if t == D.Tile.FOREST:
				features.set_cell(cell, SRC_IDS[D.Tile.FOREST], Vector2i(0, _variant(cell, &"forest")))
			elif t == D.Tile.STONE:
				features.set_cell(cell, SRC_IDS[D.Tile.STONE], Vector2i(0, _variant(cell, &"stone")))
			elif t == D.Tile.GOLD:
				features.set_cell(cell, SRC_IDS[D.Tile.GOLD], Vector2i(0, _variant(cell, &"gold")))


static func _variant(cell: Vector2i, kname: StringName) -> int:
	# deterministik varyant secimi (iki ucta ayni gorunum; rng yok)
	var variants: int = Bible.TILE_ANIMS[kname][0]
	var n := cell.x * 374761393 + cell.y * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	n = (n ^ (n >> 16)) & 0x7fffffff
	return n % variants


static func building_preview(def_id: StringName, pid: int) -> Texture2D:
	## Insa hayaleti: bina sheet'inin ilk karesi.
	var at := AtlasTexture.new()
	at.atlas = load(Bible.building_sheet(def_id, pid))
	var fpx := Bible.building_frame_px(def_id)
	at.region = Rect2(0, 0, fpx, fpx)
	return at
