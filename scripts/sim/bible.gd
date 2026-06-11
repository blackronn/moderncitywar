extends RefCounted
## Asset Bibliasi meta verisi — tools/gen_bible.gd uretir, oyun calisma aninda
## okur. Kaynak: claude.ai/design "Asset Bible.dc.html" (WorldBox tarzi,
## P1 mavi / P2 kirmizi). Frame sayilari ve sureler oradaki surekli-zaman
## animasyonlarin orneklenmis halidir.

const D := preload("res://scripts/autoload/defs.gd")
const DIR := "res://assets/generated/bible/"

# --- birimler ---
# frame karesi 24x24 (16'lik mantiksal izgara +4 ofset; olum devrilmesi tassin diye)
const UNIT_FRAME := 24
const UNIT_COLS := 10                     # sheet sutun sayisi (en uzun anim = olum, 10 kare)

# def_id -> [[anim, kare, kare_suresi, dongu], ...]  (satir sirasi = sheet satiri)
const UNIT_ANIMS := {
	&"worker": [
		[&"idle", 6, 0.349, true], [&"walk", 6, 0.131, true],
		[&"gather", 6, 0.104, true], [&"build", 6, 0.076, true],
		[&"death", 10, 0.21, false],
	],
	&"rifleman": [
		[&"idle", 6, 0.349, true], [&"walk", 6, 0.131, true],
		[&"attack", 8, 0.1375, true], [&"death", 10, 0.21, false],
	],
	&"sniper": [
		[&"idle", 6, 0.349, true], [&"walk", 6, 0.131, true],
		[&"attack", 8, 0.1375, true], [&"death", 10, 0.21, false],
	],
	&"rpg": [
		[&"idle", 6, 0.349, true], [&"walk", 6, 0.131, true],
		[&"attack", 8, 0.1375, true], [&"death", 10, 0.21, false],
	],
	&"healer": [
		[&"idle", 6, 0.349, true], [&"walk", 6, 0.131, true],
		[&"heal", 6, 0.104, true], [&"death", 10, 0.21, false],
	],
	&"mg": [
		[&"idle", 6, 0.349, true], [&"walk", 6, 0.131, true],
		[&"attack", 8, 0.1375, true], [&"death", 10, 0.21, false],
	],
	&"commando": [
		[&"idle", 6, 0.349, true], [&"walk", 6, 0.131, true],
		[&"attack", 8, 0.1375, true], [&"death", 10, 0.21, false],
	],
	&"mortar": [
		[&"idle", 6, 0.349, true], [&"walk", 6, 0.131, true],
		[&"attack", 8, 0.1375, true], [&"death", 10, 0.21, false],
	],
	&"tank": [
		[&"idle", 6, 0.436, true], [&"walk", 6, 0.116, true],
		[&"attack", 8, 0.175, true], [&"death", 10, 0.21, false],
	],
}

# --- binalar ---
# 1x1 -> 26 px kare (S=1), 2x2 -> 52 px kare (S=2); tek satir dongu animasyonu
# def_id -> [kare, kare_suresi]
const BUILDING_ANIMS := {
	&"city_hall": [16, 0.0785],   # bayrak dalgasi (1.257 sn)
	&"house": [12, 0.1667],       # baca dumani (2.0 sn)
	&"greenhouse": [12, 0.5236],  # bitki salinimi (2pi sn)
	&"bank": [12, 0.238],         # $ parilti (2.856 sn)
	&"lumber_camp": [12, 0.0748], # donen daire testere (0.9 sn tam tur)
	&"quarry": [16, 0.0785],      # vinc + bayrak (1.257 sn)
	&"barracks": [16, 0.0785],    # bayrak
	&"factory": [12, 0.119],      # kalin duman (1.43 sn)
	&"turret": [24, 0.2],         # tarama + ates dongusu (4.8 sn)
	&"bridge_seg": [8, 0.4909],   # altindaki su akar
	&"mine": [8, 0.25],           # kurulum isigi yanip soner (sadece sahibi gorur)
}

# --- zeminler ---
# kind -> [varyant, kare, kare_suresi]; sheet: satir=varyant, sutun=kare (16x16)
const TILE_ANIMS := {
	&"grass": [3, 6, 0.5236],
	&"water": [3, 8, 0.4909],
	&"bridge": [3, 8, 0.4909],
	&"forest": [3, 8, 0.4909],   # seffaf zemin: cim/kar uzerine bindirilir
	&"stone": [3, 6, 0.4363],    # seffaf zemin
	&"gold": [3, 6, 0.4363],     # seffaf zemin: tarafsiz bolge altini
	&"snow": [3, 6, 0.5236],
	&"hill": [3, 4, 0.6],
}

# --- efektler ---
# id -> [kare, kare_suresi, dongu]; 16x16
const FX := {
	&"muzzle": [5, 0.045, false],
	&"explosion": [9, 0.123, false],
	&"gather_fx": [6, 0.119, true],
	&"build_fx": [6, 0.139, true],
	&"dirt": [4, 0.07, false],   # iska eden merminin dustugu yerde toz
}


static func unit_sheet(def_id: StringName, pid: int) -> String:
	return DIR + "%s_p%d.png" % [def_id, pid]


static func building_sheet(def_id: StringName, pid: int) -> String:
	return DIR + "b_%s_p%d.png" % [def_id, pid]


static func tile_sheet(kind: StringName) -> String:
	return DIR + "tile_%s.png" % kind


static func fx_sheet(fx_id: StringName) -> String:
	return DIR + "fx_%s.png" % fx_id


static func building_frame_px(def_id: StringName) -> int:
	if D.building(def_id).has("bridge"):
		return 16   # kopru parcasi tile boyutunda
	var size: Vector2i = D.building(def_id)["size"]
	return 26 if size.x == 1 else 52


static func unit_anim_row(def_id: StringName, anim: StringName) -> int:
	var table: Array = UNIT_ANIMS[def_id]
	for i in table.size():
		if table[i][0] == anim:
			return i
	return 0
