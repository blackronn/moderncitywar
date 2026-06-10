extends SceneTree
## Gelistirme araci: verilen tile'lari 8x buyutup tek serit PNG yapar.
## Kullanim: --script res://tools/crop_tiles.gd -- "--tiles=town:3,0;battle:1,4"
## Cikti: assets/downloads/tiles_inspect.png (soldan saga verilen sirayla)


func _initialize() -> void:
	var spec := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tiles="):
			spec = arg.get_slice("=", 1)
	if spec.is_empty():
		print("--tiles=... gerekli")
		quit(1)
		return
	var root := ProjectSettings.globalize_path("res://")
	var sheets := {
		"town": Image.load_from_file(root + "assets/kenney/tiny-town/tilemap_packed.png"),
		"battle": Image.load_from_file(root + "assets/kenney/tiny-battle/tilemap_packed.png"),
	}
	var parts := spec.split(";")
	var s := 16
	var scale_f := 8
	var gap := 4
	var cell := s * scale_f + gap
	var out := Image.create(parts.size() * cell, s * scale_f, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.16, 0.16, 0.2))
	var i := 0
	for part in parts:
		var sheet_name := part.get_slice(":", 0)
		var xy := part.get_slice(":", 1).split(",")
		var src: Image = sheets[sheet_name]
		var tile := Image.create(s, s, false, Image.FORMAT_RGBA8)
		tile.blit_rect(src, Rect2i(int(xy[0]) * s, int(xy[1]) * s, s, s), Vector2i.ZERO)
		tile.resize(s * scale_f, s * scale_f, Image.INTERPOLATE_NEAREST)
		out.blend_rect(tile, Rect2i(0, 0, s * scale_f, s * scale_f), Vector2i(i * cell, 0))
		i += 1
	out.save_png(root + "assets/downloads/tiles_inspect.png")
	print("OK ", parts.size(), " tile")
	quit(0)
