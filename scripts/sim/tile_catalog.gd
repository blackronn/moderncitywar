extends RefCounted
## Kenney sheet'lerinden TileSet'i KODLA kurar; entity sprite bolgelerini de
## bilir. Tum atlas koordinatlari tek yerde: gorsel degisiklik = bu dosya.
## Bant mantigi (tiny-battle): bina satirlari gri=0 yesil=1 mavi=2 kirmizi=3
## turuncu=4; arac/asker satirlari gri=5 yesil=6 mavi=7 kirmizi=8 turuncu=9.
## P1 = yesil bant, P2 = kirmizi bant -> takim rengi sheet'ten bedava gelir.

const D := preload("res://scripts/autoload/defs.gd")

const TOWN := "res://assets/kenney/tiny-town/tilemap_packed.png"
const BATTLE := "res://assets/kenney/tiny-battle/tilemap_packed.png"

const SRC_TOWN := 0
const SRC_BATTLE := 1

# --- zemin (town) ---
const GRASS_PLAIN := Vector2i(0, 0)
const GRASS_DOTS := Vector2i(1, 0)    # yesil filizli cim
const GRASS_FLOWERS := Vector2i(2, 0) # turuncu cicekli cim (nadir)
const TREE_A := Vector2i(4, 1)        # yesil govdeli yuvarlak agac (tam, tek tile)
const TREE_B := Vector2i(4, 0)        # yesil selvi (tam, tek tile)

# --- su & kopru & tas (battle) ---
const WATER := Vector2i(0, 4)         # duz derin su
const BRIDGE := Vector2i(4, 7)        # korkuluklu YATAY kopru (oldugu gibi kullanilir)
const ROCK := Vector2i(5, 0)          # toprak/tas yigini (tas yatagi gorseli)

# --- entity bantlari (battle) ---
const BUILDING_BAND := {1: 1, 2: 3}   # pid -> satir
const VEHICLE_BAND := {1: 6, 2: 8}
const BUILDING_COL := {
	&"city_hall": 14,   # buyuk kule (en heybetli yapi)
	&"house": 8,        # ikiz apartman
	&"greenhouse": 9,   # genis cam cepheli bina
	&"bank": 10,        # sutunlu klasik bina
	&"barracks": 13,    # bayrak direkli askeri kule
	&"factory": 11,     # testere catili fabrika
}
const TURRET_VEHICLE_COL := 11        # arac bandindaki sabit top yuvasi
const SOLDIER_RIFLE_COL := 16
const SOLDIER_HEAVY_COL := 17
const TANK_COL := 8
const PEASANT := Vector2i(8, 8)       # town: kapusonlu koylu (isci)


static func build_tileset() -> TileSet:
	var ts := TileSet.new()
	var town_src := _make_source(TOWN, [GRASS_PLAIN, GRASS_DOTS, GRASS_FLOWERS, TREE_A, TREE_B])
	var battle_src := _make_source(BATTLE, [WATER, BRIDGE, ROCK])
	ts.tile_size = Vector2i(D.TILE, D.TILE)
	ts.add_source(town_src, SRC_TOWN)
	ts.add_source(battle_src, SRC_BATTLE)
	return ts


static func _make_source(sheet: String, coords: Array) -> TileSetAtlasSource:
	var src := TileSetAtlasSource.new()
	src.texture = load(sheet)
	src.texture_region_size = Vector2i(D.TILE, D.TILE)
	for c: Vector2i in coords:
		if not src.has_tile(c):
			src.create_tile(c)
	return src


static func paint(terrain: TileMapLayer, features: TileMapLayer, grid: PackedInt32Array) -> void:
	terrain.clear()
	features.clear()
	for y in D.MAP_H:
		for x in D.MAP_W:
			var cell := Vector2i(x, y)
			var t := grid[y * D.MAP_W + x]
			match t:
				D.Tile.WATER:
					terrain.set_cell(cell, SRC_BATTLE, WATER)
				D.Tile.BRIDGE:
					terrain.set_cell(cell, SRC_BATTLE, BRIDGE)
				_:
					terrain.set_cell(cell, SRC_TOWN, _grass_variant(cell))
			if t == D.Tile.FOREST:
				features.set_cell(cell, SRC_TOWN, TREE_A if (x * 7 + y * 13) % 3 != 0 else TREE_B)
			elif t == D.Tile.STONE:
				features.set_cell(cell, SRC_BATTLE, ROCK)


static func _grass_variant(cell: Vector2i) -> Vector2i:
	# deterministik cesitlilik (rng yok: iki ucta ayni gorunum);
	# lineer formul diyagonal cizgi desenine donusuyor, o yuzden tam sayi hash
	var n := cell.x * 374761393 + cell.y * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	n = (n ^ (n >> 16)) & 0x7fffffff
	var v := n % 25
	if v == 0:
		return GRASS_FLOWERS
	if v <= 5:
		return GRASS_DOTS
	return GRASS_PLAIN


# --- entity dokulari ---

static func atlas(sheet: String, coords: Vector2i, size := Vector2i(1, 1)) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = load(sheet)
	at.region = Rect2(coords.x * D.TILE, coords.y * D.TILE, size.x * D.TILE, size.y * D.TILE)
	return at


static func unit_texture(def_id: StringName, pid: int) -> Texture2D:
	match def_id:
		&"worker":
			return atlas(TOWN, PEASANT)
		&"rifleman", &"sniper":
			return atlas(BATTLE, Vector2i(SOLDIER_RIFLE_COL, VEHICLE_BAND[pid]))
		&"rpg":
			return atlas(BATTLE, Vector2i(SOLDIER_HEAVY_COL, VEHICLE_BAND[pid]))
		&"tank":
			return atlas(BATTLE, Vector2i(TANK_COL, VEHICLE_BAND[pid]))
	return atlas(TOWN, PEASANT)


static func building_texture(def_id: StringName, pid: int) -> Texture2D:
	if def_id == &"turret":
		return atlas(BATTLE, Vector2i(TURRET_VEHICLE_COL, VEHICLE_BAND[pid]))
	var col: int = BUILDING_COL.get(def_id, 8)
	return atlas(BATTLE, Vector2i(col, BUILDING_BAND[pid]))
