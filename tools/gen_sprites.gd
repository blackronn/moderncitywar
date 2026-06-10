extends SceneTree
## Oyuna ozel pixel sprite ureteci: ASCII sablon + palet -> PNG.
## Kenney'de karsiligi olmayan seyler buradan cikar (simdilik: nisanci).
## Kullanim: tools/godot.ps1 --headless --path . --script res://tools/gen_sprites.gd
## Ciktilar commit'lenir (assets/generated/) -- calisma aninda uretim yok.

# 16x16; karakterler palete bakar, '.' seffaf.
const SNIPER := [
	"................",
	"................",
	".....ooo........",
	"....oHHHo.......",
	"....oHfHo.......",
	"....ooooo.......",
	"...oUUUUUo......",
	"..oUAUUUAUo.....",
	"..oU.UUU.Uorrrrr",
	"..oU.UUU.Uo.....",
	"...oUUUUUo......",
	"...oUU.UUo......",
	"...oU...Uo......",
	"...oB...Bo......",
	"...oo...oo......",
	"................",
]

# Sihhiyeci: beyaz uniforma + kirmizi hac; W=beyaz, C=hac, A=takim kol bandi
const MEDIC := [
	"................",
	"................",
	".....ooo........",
	"....oWCWo.......",
	"....oWfWo.......",
	"....ooooo.......",
	"...oWWWWWo......",
	"..oAWCCCWAo.....",
	"..oW.WCW.Wo.....",
	"..oW.WWW.Wo.....",
	"...oWWWWWo......",
	"...oWW.WWo......",
	"...oW...Wo......",
	"...oB...Bo......",
	"...oo...oo......",
	"................",
]

const PALETTES := {
	1: {
		"o": Color8(26, 32, 26),
		"H": Color8(45, 66, 45),
		"f": Color8(214, 178, 140),
		"U": Color8(72, 108, 66),
		"A": Color8(150, 170, 90),
		"r": Color8(58, 56, 50),
		"B": Color8(40, 46, 40),
		"W": Color8(228, 228, 220),
		"C": Color8(200, 44, 44),
	},
	2: {
		"o": Color8(34, 26, 26),
		"H": Color8(72, 40, 40),
		"f": Color8(214, 178, 140),
		"U": Color8(124, 62, 56),
		"A": Color8(192, 122, 92),
		"r": Color8(58, 56, 50),
		"B": Color8(48, 40, 40),
		"W": Color8(228, 228, 220),
		"C": Color8(200, 44, 44),
	},
}


func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://")
	DirAccess.make_dir_recursive_absolute(root + "assets/generated")
	var jobs := {"sniper": SNIPER, "medic": MEDIC}
	for sprite_name: String in jobs:
		for pid in [1, 2]:
			var img := _render(jobs[sprite_name], PALETTES[pid])
			var err := img.save_png(root + "assets/generated/%s_p%d.png" % [sprite_name, pid])
			if err != OK:
				push_error("%s_p%d.png yazilamadi" % [sprite_name, pid])
				quit(1)
				return
	print("GEN_OK")
	quit(0)


static func _render(rows: Array, pal: Dictionary) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if pal.has(ch):
				img.set_pixel(x, y, pal[ch])
	return img
