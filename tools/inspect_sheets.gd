extends SceneTree
## Gelistirme araci: Kenney sheet'lerini 4x nearest buyutup assets/downloads/
## altina kaydeder ki tile koordinatlari gozle secilebilsin.
## Kullanim: tools/godot.ps1 --headless --path . --script res://tools/inspect_sheets.gd


func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://")
	for pack: String in ["tiny-town", "tiny-battle"]:
		var src := root + "assets/kenney/" + pack + "/tilemap_packed.png"
		var img := Image.load_from_file(src)
		if img == null:
			push_error("Yuklenemedi: " + src)
			quit(1)
			return
		print(pack, ": ", img.get_width(), "x", img.get_height(), " (",
			img.get_width() / 16, "x", img.get_height() / 16, " tile)")
		img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
		img.save_png(root + "assets/downloads/preview_" + pack + ".png")
	print("OK")
	quit(0)
