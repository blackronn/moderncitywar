extends Node
## Oyunun veri omurgasi: tum denge sabitleri, birim/bina tanimlari, hasar matrisi.
## Saf veri + statik yardimcilar; node bagimliligi YOK -- testler bu script'i
## preload edip dogrudan kullanir. Sim dosyalari da autoload yerine
## `const D := preload(...)` ile erisir.

const VERSION := "0.7.3"

# --- gelismis baslangic kiti (lobi/menu anahtari; host sim'i kurar) ---
# offsetler belediye sol-ustune gore, eksen basina YON carpanli (harita
# merkezine dogru acilir; her oyuncuda simetrik)
const ADV_KIT: Array = [
	[&"house", Vector2i(4, 0)], [&"house", Vector2i(4, 2)],
	[&"greenhouse", Vector2i(4, 4)], [&"bank", Vector2i(6, 1)],
	[&"barracks", Vector2i(0, 4)],
]
const ADV_WORKERS := 3
const ADV_RES := {"wood": 150, "stone": 100, "food": 100, "money": 120}

# --- oyuncular ---
const MAX_PLAYERS := 4
# takim renkleri (gen_bible TEAM paletlerinin "main" degerleriyle birebir)
const PLAYER_COLORS := {
	1: Color("#3a78d8"), 2: Color("#dc4636"),
	3: Color("#3fa650"), 4: Color("#9b59d0"),
}

# --- zaman / ag ---
const TICK_RATE := 30
const SNAPSHOT_EVERY_TICKS := 3      # 10 Hz
const SNAP_MAX_ENTS := 110           # 10 B/entity -> paket ~1100 B < 1200 B (ENet MTU guvenligi)
const WAR_COUNTDOWN_S := 30.0
const INTERP_DELAY_S := 0.15         # istemci render gecikmesi (snapshot araliginin ~1.5 kati)

# --- harita ---
const MAP_W := 48
const MAP_H := 48
const TILE := 16
const BUILD_RADIUS_TILES := 10       # yeni bina, mevcut kendi binandan en fazla bu kadar uzakta
const SPAWN_CLEAR_RADIUS := 5        # baslangic bolgesi temiz cim yaricapi
const NEUTRAL_HALF_W := 4            # tarafsiz bolge: orta hattan iki yana bu kadar (altin burada)

# --- zafer ---
const METROPOLIS_POP := 200

# --- ekonomi ---
const START_RES := {"wood": 150, "stone": 80, "food": 80, "money": 80}
const RES_KINDS: Array[String] = ["wood", "stone", "food", "money"]
const FOREST_WOOD := 80.0            # bir orman tile'indaki toplam odun
const STONE_AMOUNT := 250.0          # bir tas yatagindaki toplam tas
const GATHER_RETARGET_T := 6         # kaynak tukenince bu yaricapta yenisi aranir (tile)
const MAX_BUILDERS := 3              # ayni insaata en fazla isci
const TRAIN_QUEUE_MAX := 5

enum Tile { GRASS, WATER, BRIDGE, FOREST, STONE, GOLD, SNOW, HILL, MOUNTAIN }
enum Klass { INFANTRY, ARMOR, BUILDING }
enum War { PEACE, COUNTDOWN, WAR }
enum MapType { RIVER, LAKE, PLAINS, SNOW, VALLEY }
enum Ev { MATCH_STARTED, WAR_STATE, DEPLETED, BUILD_REJECTED, TRACER, TOAST_KEY, LEVEL, IMPACT, MISS_FX, ELIMINATED, SHELL }
enum Reason { DESTRUCTION, METROPOLIS, OPPONENT_LEFT }
enum Reject { NO_RES, BAD_SPOT, TOO_FAR, POP_FULL, BLOCKED, QUEUE_FULL, PEACE, INVALID, MAX_LEVEL, BORDER }

# bina gelistirme
const MAX_LEVEL := 3

# snapshot bayraklari
const FLAG_MOVING := 1
const FLAG_ATTACKING := 2
const FLAG_GATHERING := 4
const FLAG_CONSTRUCTING := 8
const FLAG_PRODUCING := 16
const FLAG_HEALING := 32
const FLAG_HOLDING := 64     # konuslanmis: yerinden kimildamaz, kovalamaz

# hangi tile hangi kaynagi verir + saniyelik toplama hizi
# (x2 tempo: oyunun 20-25 dk'da bitmesi hedefi — kaynak cok yavas geliyordu)
const TILE_RES := {Tile.FOREST: "wood", Tile.STONE: "stone", Tile.GOLD: "money"}
const GATHER_RATES := {Tile.FOREST: 2.0, Tile.STONE: 1.5, Tile.GOLD: 1.2}
const GOLD_AMOUNT := 200.0           # sinir altin rezervi (hucre basina)

# arazi hiz carpani: engebeye gore hareket kabiliyeti
const TILE_SPEED := {
	Tile.GRASS: 1.0, Tile.BRIDGE: 1.0, Tile.FOREST: 0.85, Tile.STONE: 0.8,
	Tile.GOLD: 0.85, Tile.SNOW: 0.75, Tile.HILL: 0.55, Tile.WATER: 1.0,
}
const BUILDABLE_TILES := [Tile.GRASS, Tile.SNOW]
const MISS_SPREAD_T := 1.3           # iska eden merminin sapma yaricapi (tile)
const COVER_MISS := 0.67             # siperdeki birime direkt atislarin iskalanma orani (3'te 1 isabet)

# --- birimler ---
# speed_t: tile/sn, range_t/aggro_t: tile, cooldown_s: atislar arasi sn, train_s: uretim sn
const UNITS := {
	&"worker": {
		"cost": {"food": 30}, "hp": 60, "dmg": 0, "range_t": 0.0, "cooldown_s": 0.0,
		"speed_t": 2.9, "pop": 1, "klass": Klass.INFANTRY, "train_s": 6.0, "aggro_t": 0.0,
	},
	&"rifleman": {
		"cost": {"food": 40, "money": 20}, "hp": 90, "dmg": 8, "range_t": 3.0, "cooldown_s": 1.0,
		"speed_t": 2.2, "pop": 1, "klass": Klass.INFANTRY, "train_s": 7.0, "aggro_t": 5.0,
		"miss": 0.15,
	},
	&"sniper": {
		"cost": {"food": 50, "money": 50}, "hp": 55, "dmg": 22, "range_t": 6.0, "cooldown_s": 2.5,
		"speed_t": 2.0, "pop": 1, "klass": Klass.INFANTRY, "train_s": 9.0, "aggro_t": 6.0,
		"miss": 0.08,
	},
	&"rpg": {
		"cost": {"food": 60, "money": 60}, "hp": 70, "dmg": 30, "range_t": 4.0, "cooldown_s": 3.0,
		"speed_t": 1.8, "pop": 1, "klass": Klass.INFANTRY, "train_s": 10.0, "aggro_t": 5.0,
		"splash_t": 1.2, "miss": 0.2,   # alan hasari yaricapi (tile); cevredekilere %50
	},
	&"mg": {
		"cost": {"food": 70, "money": 40}, "hp": 100, "dmg": 5, "range_t": 3.5, "cooldown_s": 0.25,
		"speed_t": 1.9, "pop": 2, "klass": Klass.INFANTRY, "train_s": 10.0, "aggro_t": 5.0,
		"miss": 0.25,   # yayilim atesi: cok mermi, cok iska
	},
	&"commando": {
		"cost": {"food": 80, "money": 60}, "hp": 120, "dmg": 14, "range_t": 1.5, "cooldown_s": 0.8,
		"speed_t": 3.0, "pop": 2, "klass": Klass.INFANTRY, "train_s": 12.0, "aggro_t": 5.0,
		"miss": 0.1,    # hizli yakin baskin birimi
	},
	&"mortar": {
		# KUSATMA birimi (spam nerf'i): pahali, 3 pop, yavas uretim; durunca
		# 2 sn KURULUM ister; mermisi havadan SUZULEREK gider (kacilabilir) —
		# sabit hedef/binalara olumcul, kosan orduya karsi zayif
		"cost": {"food": 90, "money": 130}, "hp": 60, "dmg": 35, "range_t": 7.5, "cooldown_s": 4.5,
		"speed_t": 1.6, "pop": 3, "klass": Klass.INFANTRY, "train_s": 18.0, "aggro_t": 7.0,
		"splash_t": 1.6, "arc": true, "scatter_t": 0.9, "setup_s": 2.0,
	},
	&"tank": {
		"cost": {"money": 150, "stone": 80}, "hp": 450, "dmg": 24, "range_t": 4.0, "cooldown_s": 2.0,
		"speed_t": 1.4, "pop": 3, "klass": Klass.ARMOR, "train_s": 14.0, "aggro_t": 5.0,
		"splash_t": 1.0, "miss": 0.15,
	},
	&"healer": {
		"cost": {"food": 50, "money": 30}, "hp": 70, "dmg": 0, "range_t": 2.5, "cooldown_s": 0.0,
		"speed_t": 2.3, "pop": 1, "klass": Klass.INFANTRY, "train_s": 9.0, "aggro_t": 6.0,
		"heal_rate": 4.0,   # hp/sn; hasarli dost birim/binalari kendiliginden iyilestirir
	},
}

# havan mermisi ucusu (px/sn) — uzaga atis = uzun ucus.
# DODGE DENGESI (birim hizina gore): patlama yaricapi 1.6t = 25.6 px;
# komando (48 px/sn) hemen her atistan, piyade/sihhiyeci (35+) uzun
# atislardan TETIKTEYSE kacar; nisanci/mg/rpg ancak max menzilde;
# havanci (26) ve TANK (22) pratikte KACAMAZ (karda/engebede hic).
const SHELL_SPEED := 95.0
const SHELL_MIN_T := 0.7
const SHELL_MAX_T := 1.6
const SHELL_FALLOFF_T := 0.6         # ic cember orani: disinda hasar x0.6

# --- binalar ---
# size: tile cinsinden footprint, build_s: 1 isciyle insaat suresi, rate: pasif uretim/sn
# gelistirme alanlari: up_cost (L2 maliyeti; L3 = 2x), up_pop (+nufus/seviye),
# up_rate (uretim carpani +%/seviye), up_dmg (+hasar/seviye), up_speed (egitim hizi +%/seviye)
const BUILDINGS := {
	&"city_hall": {
		"cost": {}, "hp": 1500, "size": Vector2i(2, 2), "pop_cap": 5, "build_s": 0.0,
		"trains": [&"worker"],
	},
	&"house": {
		"cost": {"wood": 50}, "hp": 300, "size": Vector2i(1, 1), "pop_cap": 4, "build_s": 12.0,
		"up_cost": {"wood": 40, "stone": 20}, "up_pop": 2,
	},
	&"greenhouse": {
		"cost": {"wood": 60}, "hp": 250, "size": Vector2i(1, 1), "build_s": 12.0,
		"rate": {"food": 1.0},
		"up_cost": {"wood": 50, "money": 20}, "up_rate": 0.5,
	},
	&"bank": {
		"cost": {"wood": 80, "stone": 40}, "hp": 400, "size": Vector2i(1, 1), "build_s": 16.0,
		"rate": {"money": 0.8},
		"up_cost": {"wood": 60, "stone": 30}, "up_rate": 0.5,
	},
	&"lumber_camp": {
		"cost": {"wood": 80, "money": 30}, "hp": 650, "size": Vector2i(2, 2), "build_s": 18.0,
		"rate": {"wood": 0.8},
		"up_cost": {"money": 40}, "up_rate": 0.5,
	},
	&"quarry": {
		"cost": {"wood": 90, "money": 30}, "hp": 700, "size": Vector2i(2, 2), "build_s": 20.0,
		"rate": {"stone": 0.6},
		"up_cost": {"money": 50}, "up_rate": 0.5,
	},
	&"barracks": {
		"cost": {"wood": 100, "stone": 50}, "hp": 600, "size": Vector2i(2, 2), "build_s": 20.0,
		"trains": [&"rifleman", &"sniper", &"rpg", &"mg", &"commando", &"healer"],
		"up_cost": {"wood": 80, "stone": 40}, "up_speed": 0.15,
	},
	&"factory": {
		"cost": {"wood": 120, "stone": 100, "money": 100}, "hp": 800, "size": Vector2i(2, 2), "build_s": 28.0,
		"trains": [&"tank", &"mortar"],
		"up_cost": {"wood": 100, "stone": 60}, "up_speed": 0.15,
	},
	&"turret": {
		"cost": {"stone": 60, "money": 40}, "hp": 500, "size": Vector2i(1, 1), "build_s": 16.0,
		"dmg": 15, "range_t": 5.0, "cooldown_s": 1.2, "miss": 0.1,
		"up_cost": {"stone": 50, "money": 30}, "up_dmg": 5,
	},
	&"bridge_seg": {
		# adim adim kurulan kopru parcasi: su hucresine insa edilir, bitince
		# hucre yurunebilir olur; saldirilabilir/yikilabilir (yikilirsa su geri gelir)
		"cost": {"wood": 30, "stone": 10}, "hp": 250, "size": Vector2i(1, 1), "build_s": 8.0,
		"bridge": true,
	},
	&"mine": {
		# gorunmez mayin: rakip GORMEZ; savastayken ustune basan dusmana genis
		# alan hasari (zirhliya x1.5 - tank avcisi). Tarafsiz bolgeye de kurulur.
		"cost": {"money": 40, "stone": 20}, "hp": 80, "size": Vector2i(1, 1), "build_s": 4.0,
		"mine": true, "m_dmg": 120, "m_trigger_t": 0.8, "m_splash_t": 1.5,
	},
	&"sandbags": {
		# kum torbasi siperi: yaninda duran dost birimlere direkt atislarin
		# COVER_MISS kadari iskalanir (3'te 1 isabet); havan/alan hasari DELER.
		# Yurunebilir (uzerinde/arkasinda durulur), tarafsiz bolgeye kurulabilir.
		"cost": {"wood": 25, "stone": 15}, "hp": 200, "size": Vector2i(1, 1), "build_s": 6.0,
		"cover": true, "cover_t": 0.9,
	},
}


static func in_zone(pid: int, c: Vector2i, players: int) -> bool:
	## Baris bolgesi: KENDI yari/ceyregi — gorunen sinir cizgisi KESINDIR,
	## baristayken hicbir birim cizgiyi gecemez (altin damarlari zaten her
	## yakaya aynali). pid yerlesimi: 1 sol-ust, 2 sag-ust, 3 sol-alt, 4 sag-alt.
	var mid := MAP_W / 2
	if players <= 2:
		return c.x < mid if pid == 1 else c.x >= mid
	var midy := MAP_H / 2
	var okx: bool = (c.x < mid) if (pid == 1 or pid == 3) else (c.x >= mid)
	var oky: bool = (c.y < midy) if (pid == 1 or pid == 2) else (c.y >= midy)
	return okx and oky


static func in_home(pid: int, c: Vector2i, players: int) -> bool:
	## On cephe seridi (NEUTRAL_HALF_W) HARIC ic bolge: normal binalar
	## baristayken buraya; mayin/kopru/siper cizgiye kadar (in_zone) kurulur.
	var mid := MAP_W / 2
	if players <= 2:
		return c.x < mid - NEUTRAL_HALF_W if pid == 1 else c.x >= mid + NEUTRAL_HALF_W
	var midy := MAP_H / 2
	var okx: bool = (c.x < mid - NEUTRAL_HALF_W) if (pid == 1 or pid == 3) \
		else (c.x >= mid + NEUTRAL_HALF_W)
	var oky: bool = (c.y < midy - NEUTRAL_HALF_W) if (pid == 1 or pid == 2) \
		else (c.y >= midy + NEUTRAL_HALF_W)
	return okx and oky


static func zone_clamp(pid: int, c: Vector2i, players: int) -> Vector2i:
	## Hedef hucreyi oyuncunun baris bolgesinin icine ceker (kesin sinir).
	var mid := MAP_W / 2
	var out := c
	if players <= 2:
		if pid == 1 and c.x >= mid:
			out.x = mid - 1
		elif pid == 2 and c.x < mid:
			out.x = mid
		return out
	if pid == 1 or pid == 3:
		if out.x >= mid:
			out.x = mid - 1
	elif out.x < mid:
		out.x = mid
	var midy := MAP_H / 2
	if pid == 1 or pid == 2:
		if out.y >= midy:
			out.y = midy - 1
	elif out.y < midy:
		out.y = midy
	return out


static func metro_types() -> int:
	## Metropol hedefi icin gereken bina turu sayisi (kopru/mayin/siper haric).
	var n := 0
	for id: StringName in BUILDINGS:
		var b: Dictionary = BUILDINGS[id]
		if not b.has("bridge") and not b.has("mine") and not b.has("cover"):
			n += 1
	return n

# hasar carpani: [saldiran klass][hedef klass]
const DMG_MATRIX := {
	Klass.INFANTRY: {Klass.INFANTRY: 1.0, Klass.ARMOR: 0.5, Klass.BUILDING: 0.5},
	Klass.ARMOR: {Klass.INFANTRY: 1.5, Klass.ARMOR: 1.0, Klass.BUILDING: 1.0},
	Klass.BUILDING: {Klass.INFANTRY: 1.0, Klass.ARMOR: 1.0, Klass.BUILDING: 0.0},
}
const MORTAR_VS_BUILDING := 1.5          # havanci -> bina

# matrisi ezen ozel kurallar (combat.gd uygular) -- counter ucgeninin keskin kenarlari
const SNIPER_VS_INFANTRY := 2.0          # niscanci -> piyade sinifi
const RPG_VS_ARMOR_BUILDING := 2.5       # rpg -> zirh/bina
const RIFLE_VS_SNIPER_CLOSE := 2.0       # piyade -> niscanci, yakin mesafede
const RIFLE_VS_SNIPER_RANGE_T := 3.0

const DEFAULT_SEED := 1337               # offline onizleme/screenshot icin sabit seed


static func unit(id: StringName) -> Dictionary:
	return UNITS.get(id, {})


static func building(id: StringName) -> Dictionary:
	return BUILDINGS.get(id, {})


static func is_unit(id: StringName) -> bool:
	return UNITS.has(id)


static func is_building(id: StringName) -> bool:
	return BUILDINGS.has(id)


static func defs_hash() -> int:
	## Iki uctaki build'lerin ayni dengeyle calistigini dogrulamak icin.
	return hash([VERSION, UNITS, BUILDINGS, DMG_MATRIX, START_RES])


static func scaled_cost(cost: Dictionary, mult: int) -> Dictionary:
	## Gelistirme maliyeti: L2 = up_cost, L3 = 2x up_cost (mult = mevcut seviye).
	var out := {}
	for kind in cost:
		out[kind] = int(cost[kind]) * mult
	return out


static func validate() -> Array:
	## Tanim tablolarinin ic tutarliligi; testler bos dizi bekler.
	var problems: Array = []
	for id: StringName in UNITS:
		var u: Dictionary = UNITS[id]
		for field in ["cost", "hp", "dmg", "range_t", "cooldown_s", "speed_t", "pop", "klass", "train_s", "aggro_t"]:
			if not u.has(field):
				problems.append("unit %s: '%s' alani eksik" % [id, field])
		if u.get("hp", 0) <= 0:
			problems.append("unit %s: hp > 0 olmali" % id)
		if u.get("speed_t", 0.0) <= 0.0:
			problems.append("unit %s: speed_t > 0 olmali" % id)
		for res_kind in u.get("cost", {}):
			if res_kind not in RES_KINDS:
				problems.append("unit %s: bilinmeyen kaynak '%s'" % [id, res_kind])
	for id: StringName in BUILDINGS:
		var b: Dictionary = BUILDINGS[id]
		if b.get("hp", 0) <= 0:
			problems.append("building %s: hp > 0 olmali" % id)
		var size: Vector2i = b.get("size", Vector2i.ZERO)
		if size.x < 1 or size.y < 1:
			problems.append("building %s: size en az 1x1 olmali" % id)
		for res_kind in b.get("cost", {}):
			if res_kind not in RES_KINDS:
				problems.append("building %s: bilinmeyen kaynak '%s'" % [id, res_kind])
		for trained: StringName in b.get("trains", []):
			if not UNITS.has(trained):
				problems.append("building %s: tanimsiz birim uretir '%s'" % [id, trained])
	for atk in [Klass.INFANTRY, Klass.ARMOR, Klass.BUILDING]:
		for dfn in [Klass.INFANTRY, Klass.ARMOR, Klass.BUILDING]:
			if not DMG_MATRIX.get(atk, {}).has(dfn):
				problems.append("DMG_MATRIX[%d][%d] eksik" % [atk, dfn])
	for res_kind in START_RES:
		if res_kind not in RES_KINDS:
			problems.append("START_RES: bilinmeyen kaynak '%s'" % res_kind)
	return problems
