extends SceneTree
## "Asset Bible.dc.html" (claude.ai/design) canvas cizim motorunun BIREBIR
## GDScript portu. Surekli-zaman animasyonlari sabit araliklarla ornekleyip
## sprite-sheet PNG'lerine pisirir -> assets/generated/bible/.
## Kullanim: tools/godot.ps1 --headless --path . --script res://tools/gen_bible.gd
##
## Cizim yardimcilari JS ile ayni yuvarlama kurallarini kullanir:
##   p():  round(x*S), round(y*S), max(1, ceil(w*S)), max(1, ceil(h*S))
##   disc()/ring(): piksel merkezli daire testi
## Yari saydam renkler canvas gibi alpha-blend edilir.

const Bible := preload("res://scripts/sim/bible.gd")

# ---- paletler (bible birebir) ----
const TEAM := {
	1: {"main": "#3a78d8", "dark": "#27508f", "light": "#7fb0ff", "deep": "#173260"},
	2: {"main": "#dc4636", "dark": "#9c2820", "light": "#ff8473", "deep": "#5e150f"},
}
const SK := "#f1b487"
const SKD := "#cd8a5b"
const BOOT := "#39323a"
const STEELD := "#3c4350"

var _img: Image
var _S := 1.0
var _ox := 0.0
var _oy := 0.0


func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://")
	DirAccess.make_dir_recursive_absolute(root + "assets/generated/bible")
	DirAccess.make_dir_recursive_absolute(root + "assets/generated/ui")
	_bake_units(root)
	_bake_buildings(root)
	_bake_tiles(root)
	_bake_fx(root)
	_bake_ui(root)
	print("GEN_BIBLE_OK")
	quit(0)


# ======================= cizim cekirdegi =======================

func col(hex: String, a := 1.0) -> Color:
	var c := Color(hex)
	c.a = a
	return c


func rgba(r: int, g: int, b: int, a: float) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)


func px_blend(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= _img.get_width() or y >= _img.get_height():
		return
	if c.a >= 0.999:
		_img.set_pixel(x, y, c)
	elif c.a > 0.002:
		_img.set_pixel(x, y, _img.get_pixel(x, y).blend(c))


func p(x: float, y: float, w: float, h: float, c: Color) -> void:
	var rx := roundi((x + _ox) * _S)
	var ry := roundi((y + _oy) * _S)
	var rw := maxi(1, ceili(w * _S))
	var rh := maxi(1, ceili(h * _S))
	for yy in range(ry, ry + rh):
		for xx in range(rx, rx + rw):
			px_blend(xx, yy, c)


func disc(cx: float, cy: float, r: float, c: Color) -> void:
	var r2 := r * r
	for y in range(floori(cy - r), ceili(cy + r) + 1):
		for x in range(floori(cx - r), ceili(cx + r) + 1):
			var dx := x + 0.5 - cx
			var dy := y + 0.5 - cy
			if dx * dx + dy * dy <= r2:
				p(x, y, 1, 1, c)


func ring(cx: float, cy: float, r: float, c: Color, th := 1.0) -> void:
	var ro := r * r
	var ri := (r - th) * (r - th)
	for y in range(floori(cy - r), ceili(cy + r) + 1):
		for x in range(floori(cx - r), ceili(cx + r) + 1):
			var dx := x + 0.5 - cx
			var dy := y + 0.5 - cy
			var d := dx * dx + dy * dy
			if d <= ro and d >= ri:
				p(x, y, 1, 1, c)


func rot_rect(cx: float, cy: float, ang: float, rx: float, ry: float, w: float, h: float, c: Color) -> void:
	## Canvas translate+rotate+fillRect esdegeri: dondurulmus dikdortgeni
	## kucuk adimlarla ornekleyerek boyar.
	var ca := cos(ang)
	var sa := sin(ang)
	var step := 0.35
	var sx := rx
	while sx < rx + w:
		var sy := ry
		while sy < ry + h:
			var wx := cx + sx * ca - sy * sa
			var wy := cy + sx * sa + sy * ca
			p(wx, wy, 0.5, 0.5, c)
			sy += step
		sx += step


func ease_io(x: float) -> float:
	return 2.0 * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 2.0) / 2.0


func blank(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


func blit_rotated(src: Image, dst: Image, pivot: Vector2, ang: float, alpha: float) -> void:
	## Olum animasyonu: govdeyi ayak pivotunda dondurup soldurarak bindirir.
	var ca := cos(ang)
	var sa := sin(ang)
	var old := _img
	_img = dst
	for sy in src.get_height():
		for sx in src.get_width():
			var c := src.get_pixel(sx, sy)
			if c.a <= 0.003:
				continue
			c.a *= alpha
			var dx := sx + 0.5 - pivot.x
			var dy := sy + 0.5 - pivot.y
			var wx := pivot.x + dx * ca - dy * sa
			var wy := pivot.y + dx * sa + dy * ca
			px_blend(roundi(wx - 0.5), roundi(wy - 0.5), c)
	_img = old


func blit_alpha(src: Image, dst: Image, alpha: float) -> void:
	var old := _img
	_img = dst
	for sy in src.get_height():
		for sx in src.get_width():
			var c := src.get_pixel(sx, sy)
			if c.a <= 0.003:
				continue
			c.a *= alpha
			px_blend(sx, sy, c)
	_img = old


# ======================= birimler =======================

func bake_unit_frame(role: StringName, anim: StringName, t: float, pid: int) -> Image:
	var fs := Bible.UNIT_FRAME
	var frame := blank(fs, fs)
	if role == &"tank":
		_tank_frame(frame, anim, t, pid)
	else:
		_humanoid_frame(frame, role, anim, t, pid)
	return frame


func _humanoid_frame(frame: Image, role: StringName, anim: StringName, t: float, pid: int) -> void:
	var T: Dictionary = TEAM[pid]
	var bob := 0.0
	var alpha := 1.0
	var die_p := 0.0
	var walk := 0.0
	var fire := 0.0
	var swing_y := 0.0
	var swing_x := 0.0
	var recoil := 0.0
	match anim:
		&"idle":
			bob = sin(t * 3.0) * 0.4
		&"walk":
			walk = t * 8.0
			bob = -absf(sin(walk)) * 0.7
		&"attack":
			var f := fmod(t, 1.1)
			bob = sin(t * 3.0) * 0.3
			if f < 0.22:
				fire = 1.0 - f / 0.22
				recoil = fire * 1.3
		&"death":
			# oyun icin: dus (0..0.7) -> yat -> sol (1.4..2.1); showcase'teki
			# geri dogrulma kismi (c2>2.1) pisirilmez
			var c2 := fmod(t, 2.6)
			if c2 < 0.7:
				die_p = ease_io(c2 / 0.7)
			else:
				die_p = 1.0
				alpha = clampf(1.0 - (c2 - 1.4) / 0.7, 0.0, 1.0)
		&"gather":
			var f := fmod(t * 1.6, 1.0)
			swing_y = sin(f * PI) * 2.2
			swing_x = sin(f * PI) * 1.4
		&"build", &"heal":
			var f := fmod(t * 2.2, 1.0)
			swing_y = -absf(sin(f * PI)) * 2.4

	# golge: yere sabit (donmez, bob'lanmaz)
	_img = frame
	_S = 1.0
	_ox = 4.0
	_oy = 4.0
	disc(8, 13.6, 2.6, rgba(0, 0, 0, 0.20))

	# govde ayri katmana cizilir; olumde pivot etrafinda dondurulur
	var body := blank(frame.get_width(), frame.get_height())
	_img = body
	_oy = 4.0 + bob
	_body_human(T, role, walk, fire, recoil, swing_x, swing_y, anim, t)
	if die_p > 0.0:
		blit_rotated(body, frame, Vector2(8.0 + 4.0, 14.0 + 4.0), die_p * PI / 2.0 * 0.92, alpha)
	else:
		blit_alpha(body, frame, alpha)
	_img = frame


func _body_human(T: Dictionary, role: StringName, walk: float, fire: float,
		recoil: float, swing_x: float, swing_y: float, anim: StringName, t: float) -> void:
	var sw := sin(walk) if walk != 0.0 else 0.0
	var aw := sin(walk + PI) if walk != 0.0 else 0.0
	var tm := col(T["main"])
	var td := col(T["dark"])
	var tl := col(T["light"])
	var tdeep := col(T["deep"])
	# bacaklar
	var lf := 8.4 + sw * 1.1
	var lb := 6.3 - sw * 1.1
	var lfy := 11.0 - maxf(0.0, sw) * 0.5
	var lby := 11.0 - maxf(0.0, -sw) * 0.5
	p(lb, lby, 1.6, 2.4, td)
	p(lb, lby + 2.2, 1.7, 1, col(BOOT))
	p(lf, lfy, 1.6, 2.4, td)
	p(lf, lfy + 2.2, 1.7, 1, col(BOOT))
	# arka kol
	var back_ay := 7.0 + (aw * 0.6 if walk != 0.0 else 0.0)
	p(5.0, back_ay, 1.4, 3.2, td)
	p(5.0, back_ay + 3, 1.5, 1.1, col(SK))
	# govde
	p(5.3, 6.4, 4.6, 5.2, tm)
	p(5.3, 6.4, 1, 5.2, tdeep)
	p(9.0, 6.6, 0.9, 5.0, td)
	p(5.3, 9.6, 4.6, 0.9, tl)
	p(6.6, 6.4, 0.9, 3, tl)
	# kafa
	p(6.0, 2.6, 4.2, 4.0, col(SK))
	p(6.0, 2.6, 1, 4.0, col(SKD))
	p(9.0, 4.2, 1.1, 1.6, col(SKD))
	p(8.7, 3.9, 0.9, 0.9, col("#2a2230"))
	_headgear(T, role)
	_weapon(T, role, fire, recoil, swing_x, swing_y, anim, t)


func _headgear(T: Dictionary, role: StringName) -> void:
	match role:
		&"worker":
			p(5.6, 1.6, 5, 1.6, col("#f5c542"))
			p(6.2, 0.7, 3.8, 1.1, col("#f5c542"))
			p(5.6, 1.6, 5, 0.5, col("#ffe07a"))
			p(5.6, 2.9, 5, 0.5, col("#caa024"))
		&"rifleman":
			p(5.7, 1.5, 4.9, 1.7, col(T["dark"]))
			p(6.3, 0.7, 3.6, 1, col(T["dark"]))
			p(9.4, 2.0, 1.6, 0.9, col(T["dark"]))
			p(5.7, 1.5, 4.9, 0.5, col(T["light"]))
			p(7.0, 1.0, 0.9, 0.9, col(T["light"]))
		&"sniper":
			p(5.6, 1.7, 5.0, 1.4, col("#3f5a2f"))
			p(9.3, 2.2, 2.0, 0.9, col("#3f5a2f"))
			p(5.6, 1.7, 5, 0.45, col("#56743f"))
			p(6.2, 1.2, 3.4, 0.7, col("#3f5a2f"))
			p(6.0, 5.6, 3.2, 0.9, col("#4d6b34"))   # yesil atki
		&"rpg":
			p(5.7, 1.7, 4.8, 1.4, col("#34302e"))
			p(6.2, 1.1, 3.6, 0.8, col("#34302e"))
			p(5.7, 1.7, 4.8, 0.45, col(T["main"]))
			p(5.9, 5.5, 3.2, 0.9, col(T["dark"]))   # bandana
		&"healer":
			# turetilmis tasarim: beyaz kep + kirmizi hac (bible stiliyle)
			p(5.7, 1.5, 4.9, 1.7, col("#e9e9e3"))
			p(6.3, 0.7, 3.6, 1, col("#e9e9e3"))
			p(5.7, 1.5, 4.9, 0.5, col("#ffffff"))
			p(7.6, 1.4, 0.9, 1.9, col("#d23c30"))
			p(7.1, 1.9, 1.9, 0.9, col("#d23c30"))
			p(6.0, 5.6, 3.2, 0.9, col("#cfd4d8"))   # beyaz yaka
		&"mg":
			# genis celik miğfer + cene bandi (agir piyade)
			p(5.5, 1.4, 5.3, 1.9, col(T["dark"]))
			p(6.1, 0.6, 4.0, 1.1, col(T["dark"]))
			p(5.5, 1.4, 5.3, 0.5, col(T["light"]))
			p(9.6, 1.9, 1.7, 1.0, col(T["dark"]))
			p(6.6, 3.2, 0.6, 2.2, col("#3c4350"))   # cene bandi
		&"commando":
			# takim rengi bere + yuz boyasi (hizli baskin)
			p(5.8, 1.6, 4.6, 1.3, col(T["main"]))
			p(5.8, 1.6, 4.6, 0.45, col(T["light"]))
			p(9.6, 2.2, 1.2, 0.8, col(T["main"]))
			p(6.4, 4.4, 2.8, 0.5, col("#2a2230"))   # yuz boyasi seridi
			p(6.0, 5.6, 3.2, 0.9, col("#34302e"))   # koyu yaka
		&"mortar":
			# kulakli kep + sirt cantasi (topcu)
			p(5.7, 1.6, 4.9, 1.5, col("#5a5648"))
			p(6.3, 0.8, 3.6, 1.0, col("#5a5648"))
			p(5.7, 1.6, 4.9, 0.45, col("#787361"))
			p(4.6, 6.6, 1.3, 3.6, col("#5a5648"))   # sirt cantasi
			p(4.6, 6.6, 1.3, 0.5, col("#787361"))


func _weapon(T: Dictionary, role: StringName, fire: float, recoil: float,
		swing_x: float, swing_y: float, anim: StringName, t: float) -> void:
	var ax := -recoil
	var fy := 7.2 + swing_y
	var fx := swing_x
	match role:
		&"worker":
			p(8.9 + fx, fy, 1.4, 2.6, col(SK))
			var hx := 9.7 + fx
			p(hx, fy + 2.2, 0.9, 2.6, col("#8a6a44"))
			p(hx - 0.6, fy + 4.4, 2.2, 1.2, col("#7d828c"))
			p(hx - 0.6, fy + 4.4, 2.2, 0.45, col("#a8adb8"))
		&"rifleman":
			p(9.0 + ax, 7.0, 1.4, 2.5, col(SK))
			p(9.6 + ax, 7.4, 4.0, 1.0, col(STEELD))
			p(9.4 + ax, 7.0, 1.6, 1.9, col("#43474f"))
			p(10.0 + ax, 8.3, 1.0, 1.3, col("#43474f"))
			p(8.9 + ax, 7.4, 0.9, 1.6, col("#2f333a"))
			if fire > 0.0:
				_muzzle(13.8 + ax, 7.9, fire)
		&"sniper":
			p(9.0 + ax, 7.0, 1.4, 2.5, col(SK))
			p(9.4 + ax, 7.6, 6.0, 0.85, col(STEELD))
			p(9.3 + ax, 7.1, 1.7, 1.7, col("#3c4350"))
			p(10.6 + ax, 6.6, 1.4, 0.8, col("#23262d"))
			p(8.8 + ax, 7.5, 0.9, 1.5, col("#2f333a"))
			p(12.6 + ax, 8.4, 0.8, 1.2, col("#3c4350"))
			if fire > 0.0:
				_muzzle(15.7 + ax, 8.0, fire)
		&"rpg":
			p(8.8 + ax, 6.6, 1.4, 2.6, col(SK))
			p(8.0 + ax, 5.4, 6.4, 1.7, col("#3a4a2e"))
			p(8.0 + ax, 5.4, 6.4, 0.5, col("#536b3c"))
			p(13.9 + ax, 5.0, 1.6, 2.5, col(T["main"]))
			p(14.6 + ax, 4.6, 0.9, 3.3, col(T["light"]))
			p(7.2 + ax, 5.6, 0.9, 1.3, col("#2c2622"))
			if fire > 0.0:
				disc(7.0 + ax, 6.2, 1.4 + fire * 1.4, rgba(255, 170, 60, 0.5 * fire))
				_muzzle(16.2 + ax, 5.9, fire)
		&"healer":
			# on kol + canta; heal aninda yesil '+' isiltisi
			p(8.9 + fx, fy, 1.4, 2.6, col(SK))
			p(9.4, 9.0, 2.4, 2.0, col("#e9e9e3"))
			p(9.4, 9.0, 2.4, 0.5, col("#ffffff"))
			p(10.3, 9.3, 0.7, 1.4, col("#d23c30"))
			p(10.0, 9.7, 1.3, 0.6, col("#d23c30"))
			if anim == &"heal":
				var f := fmod(t * 2.2, 1.0)
				var a := 1.0 - f
				var hy := 4.6 - f * 2.0
				p(11.4, hy, 0.8, 2.4, rgba(110, 230, 140, a))
				p(10.6, hy + 0.8, 2.4, 0.8, rgba(110, 230, 140, a))
		&"mg":
			# agir makineli: kalin namlu + serit kutusu + on bacak (bipod)
			p(9.0 + ax, 7.0, 1.4, 2.5, col(SK))
			p(9.4 + ax, 7.2, 5.2, 1.3, col(STEELD))     # kalin namlu
			p(9.4 + ax, 7.2, 5.2, 0.45, col("#576070"))
			p(9.2 + ax, 6.9, 1.9, 2.1, col("#43474f"))  # govde
			p(10.4 + ax, 8.6, 1.6, 1.5, col("#2f5a35")) # serit kutusu (yesil)
			p(13.5 + ax, 8.4, 0.5, 1.8, col("#3c4350")) # bipod on
			p(14.3 + ax, 8.4, 0.5, 1.8, col("#3c4350"))
			if fire > 0.0:
				_muzzle(15.2 + ax, 7.8, fire)
		&"commando":
			# kisa namlulu SMG + el bicagi silueti
			p(9.0 + ax, 7.0, 1.4, 2.5, col(SK))
			p(9.5 + ax, 7.4, 2.8, 1.0, col("#2f333a"))  # kisa SMG
			p(9.4 + ax, 7.1, 1.5, 1.7, col("#43474f"))
			p(10.4 + ax, 8.3, 0.8, 1.2, col("#2f333a"))
			p(5.2, 9.4, 0.5, 1.6, col("#cdd2d9"))       # belde bicak
			if fire > 0.0:
				_muzzle(12.6 + ax, 7.9, fire)
		&"mortar":
			# yere kurulu havan borusu (yukari acili) + taban plakasi
			p(8.9 + fx, fy, 1.4, 2.6, col(SK))
			p(11.6, 11.6, 3.4, 0.9, col("#3c4350"))     # taban plakasi
			rot_rect(12.2, 11.8, -1.05, 0.0, -0.8, 5.2, 1.5, col("#4a5160"))   # boru
			rot_rect(12.2, 11.8, -1.05, 0.0, -0.8, 5.2, 0.5, col("#6a7282"))
			if fire > 0.0:
				_muzzle(14.4, 6.6, fire)
				disc(14.0, 7.4, 1.0 + fire, rgba(200, 200, 210, 0.4 * fire))


func _muzzle(x: float, y: float, f: float) -> void:
	var r := 1.2 + f * 1.8
	disc(x, y, r, rgba(255, 236, 150, 0.9 * f))
	disc(x, y, r * 0.55, col("#ffffff"))
	p(x - r - 1.2, y - 0.4, r * 1.4, 0.8, rgba(255, 200, 80, 0.8 * f))
	p(x, y - r - 1, 0.8, r * 0.9, rgba(255, 200, 80, 0.6 * f))
	p(x, y + r, 0.8, r * 0.9, rgba(255, 200, 80, 0.6 * f))


func _tank_frame(frame: Image, anim: StringName, t: float, pid: int) -> void:
	var T: Dictionary = TEAM[pid]
	var bob := 0.0
	var alpha := 1.0
	var die_p := 0.0
	var scroll := 0.0
	var recoil := 0.0
	var fire := 0.0
	match anim:
		&"idle":
			bob = sin(t * 2.4) * 0.18
		&"walk":
			scroll = fmod(t * 9.0, 2.0)
			bob = sin(t * 9.0) * 0.18
		&"attack":
			var f := fmod(t, 1.4)
			if f < 0.25:
				fire = 1.0 - f / 0.25
				recoil = fire * 1.6
			bob = sin(t * 2.4) * 0.15
		&"death":
			var c2 := fmod(t, 2.6)
			if c2 < 0.5:
				die_p = ease_io(c2 / 0.5)
			else:
				die_p = 1.0
				alpha = clampf(1.0 - (c2 - 1.1) / 0.7, 0.0, 1.0)

	_img = frame
	_S = 1.0
	_ox = 4.0
	_oy = 4.0
	disc(8, 13.4, 3.4, rgba(0, 0, 0, 0.22))

	var body := blank(frame.get_width(), frame.get_height())
	_img = body
	_oy = 4.0 + bob
	var tm := col(T["main"])
	var td := col(T["dark"])
	var tl := col(T["light"])
	var tdeep := col(T["deep"])
	# paletler
	p(2.2, 11.0, 11.6, 2.6, col("#2c2f36"))
	p(2.2, 11.0, 11.6, 0.6, col("#3d424b"))
	for i in 7:
		var x := 2.6 + fmod(i * 1.7 + scroll, 11.5)
		p(x, 11.5, 0.8, 1.6, col("#15171c"))
	disc(3.2, 12.3, 1.0, col("#3d424b"))
	disc(12.7, 12.3, 1.0, col("#3d424b"))
	# govde
	p(3.0, 8.0, 10.0, 3.4, tm)
	p(3.0, 8.0, 10.0, 0.8, tl)
	p(3.0, 10.4, 10.0, 1.0, tdeep)
	p(11.0, 8.2, 2.0, 3.0, td)
	p(4.0, 8.6, 1.4, 1.4, tl)
	# kule
	var rx := -recoil
	p(5.4, 5.6, 4.6, 3.0, td)
	p(5.4, 5.6, 4.6, 0.7, tl)
	disc(7.6, 6.9, 1.5, tm)
	p(7.0, 6.4, 1.2, 1.0, tl)
	# namlu
	p(9.6 + rx, 6.2, 5.4, 1.2, col("#3c4350"))
	p(9.6 + rx, 6.2, 5.4, 0.4, col("#576070"))
	p(14.4 + rx, 5.9, 1.0, 1.8, col("#2b3038"))
	if fire > 0.0:
		_muzzle(15.4 + rx, 6.8, fire)

	if die_p > 0.0:
		blit_rotated(body, frame, Vector2(8.0 + 4.0, 12.0 + 4.0), die_p * 0.14 * sin(t * 20.0), alpha)
	else:
		blit_alpha(body, frame, alpha)
	_img = frame


func _bake_units(root: String) -> void:
	var fs := Bible.UNIT_FRAME
	for unit_id: StringName in Bible.UNIT_ANIMS:
		var table: Array = Bible.UNIT_ANIMS[unit_id]
		for pid in [1, 2]:
			var sheet := blank(Bible.UNIT_COLS * fs, table.size() * fs)
			for row in table.size():
				var frames: int = table[row][1]
				var dt: float = table[row][2]
				for i in frames:
					var f := bake_unit_frame(unit_id, table[row][0], i * dt, pid)
					sheet.blit_rect(f, Rect2i(0, 0, fs, fs), Vector2i(i * fs, row * fs))
			sheet.save_png(root + "assets/generated/bible/%s_p%d.png" % [unit_id, pid])


# ======================= binalar =======================

func _flag(px_: float, py: float, h: float, T: Dictionary, t: float) -> void:
	p(px_, py, 0.7, h, col("#6b7280"))
	for i in 5:
		var fy := py + 0.4 + sin(t * 5.0 - i * 0.6) * 0.5
		p(px_ + 0.7 + i * 0.9, fy, 1.0, 2.4, col(TEAM_LIGHT_OR_MAIN(T, i)))
	p(px_ - 0.2, py - 0.4, 1.1, 0.8, col("#d9b94a"))


func TEAM_LIGHT_OR_MAIN(T: Dictionary, i: int) -> String:
	return T["light"] if i % 2 == 1 else T["main"]


func _smoke(px_: float, py: float, t: float, rgb: Vector3i, sp := 1.0) -> void:
	for i in 3:
		var ph := fmod(t * sp * 0.5 + i * 0.34, 1.0)
		var yy := py - ph * 6.5
		var xx := px_ + sin(ph * 4.0 + i) * 1.2
		var r := 0.7 + ph * 1.7
		var a := (1.0 - ph) * 0.5
		disc(xx, yy, r, rgba(rgb.x, rgb.y, rgb.z, a))


func bake_building_frame(id: StringName, t: float, pid: int) -> Image:
	var T: Dictionary = TEAM[pid]
	var fpx := Bible.building_frame_px(id)
	var frame := blank(fpx, fpx)
	_img = frame
	_S = 1.0
	_ox = 0.0
	_oy = 0.0
	if id == &"bridge_seg":
		# kopru parcasi: tile boyutunda, altinda akan su + ahsap dosame
		_t_water(t, 0)
		_t_bridge_top()
		return frame
	if id == &"mine":
		_b_mine(t, T)
		return frame
	_S = 1.0 if fpx == 26 else 2.0
	disc(11, 19.5, 8.5, rgba(0, 0, 0, 0.14))
	match id:
		&"city_hall": _b_city_hall(t, T)
		&"house": _b_house(t, T)
		&"greenhouse": _b_greenhouse(t, T)
		&"bank": _b_bank(t, T)
		&"lumber_camp": _b_lumber(t, T)
		&"quarry": _b_quarry(t, T)
		&"barracks": _b_barracks(t, T)
		&"factory": _b_factory(t, T)
		&"turret": _b_turret(t, T)
	return frame


func _b_city_hall(t: float, T: Dictionary) -> void:
	p(3.5, 17.5, 15, 3.0, col("#cfc7b2"))
	p(3.5, 17.5, 15, 0.6, col("#e6dec8"))
	p(4.5, 9.5, 13, 8.2, col("#e8e0cc"))
	p(4.5, 9.5, 13, 0.8, col("#fff7e6"))
	p(4.5, 9.5, 0.9, 8.2, col("#bcb39a"))
	p(16.6, 9.5, 0.9, 8.2, col("#bcb39a"))
	for i in 5:
		var x := 5.6 + i * 2.3
		p(x, 10.6, 1.3, 6.5, col("#f3ecd9"))
		p(x, 10.6, 1.3, 0.5, col("#fffaf0"))
		p(x + 1.0, 10.6, 0.4, 6.5, col("#c9c0aa"))
	for r in 4:
		p(6.5 + r, 8.5 - r, 9 - 2 * r, 1.05, col("#d8cfb8"))
	p(5.4, 9.0, 11.2, 0.7, col("#bcb39a"))
	p(9.6, 3.6, 2.8, 2.2, col("#cdd3da"))
	disc(11, 3.6, 1.5, col("#dfe4ea"))
	disc(11, 3.6, 0.7, col(T["main"]))
	p(10.4, 5.7, 1.2, 1.6, col("#b9bfc7"))
	p(9.4, 13.2, 3.2, 4.3, col("#5b4a3a"))
	p(9.4, 13.2, 3.2, 0.5, col("#7a6450"))
	p(10.2, 12.4, 1.6, 3.2, col(T["main"]))
	p(10.2, 15.0, 1.6, 0.9, col(T["light"]))
	_flag(10.7, 0.4, 2.4, T, t)


func _b_house(t: float, T: Dictionary) -> void:
	p(5.5, 11.5, 11, 6.5, col("#e7c594"))
	p(5.5, 11.5, 11, 0.7, col("#f6d9ac"))
	p(5.5, 11.5, 0.9, 6.5, col("#caa473"))
	for r in 5:
		p(4.0 + r * 0.9, 11.5 - r, 14 - 1.8 * r, 1.15, col(T["dark"]) if r == 0 else col(T["main"]))
	p(4.0, 11.0, 14, 0.6, col(T["light"]))
	p(9.6, 13.6, 2.6, 4.4, col("#7a4a2a"))
	p(9.6, 13.6, 2.6, 0.5, col("#9a6440"))
	p(11.4, 15.6, 0.5, 0.5, col("#f5c542"))
	p(6.6, 13.2, 2.0, 2.0, col("#ffd97a"))
	p(6.6, 13.2, 2.0, 0.5, col("#fff0c0"))
	p(7.55, 13.2, 0.4, 2.0, col("#caa473"))
	p(13.0, 13.2, 2.0, 2.0, col("#ffd97a"))
	p(13.95, 13.2, 0.4, 2.0, col("#caa473"))
	p(13.6, 7.0, 1.6, 3.0, col("#9c5a3a"))
	p(13.4, 6.7, 2.0, 0.7, col("#7a4329"))
	_smoke(14.4, 6.3, t, Vector3i(150, 150, 160), 1.0)


func _b_greenhouse(t: float, _T: Dictionary) -> void:
	p(5.0, 10.5, 12, 7.5, col("#cfeef0"))
	p(5.0, 10.5, 12, 0.8, col("#eafcff"))
	p(5.0, 10.5, 0.8, 7.5, col("#9fc7c2"))
	p(16.2, 10.5, 0.8, 7.5, col("#9fc7c2"))
	for i in range(1, 4):
		p(5.0 + i * 3.0, 10.5, 0.6, 7.5, col("#a9d2cd"))
	p(5.0, 13.8, 12, 0.6, col("#a9d2cd"))
	for r in 4:
		p(5.6 + r * 0.9, 10.5 - r, 10.8 - 1.8 * r, 1.1, col("#d9f4f5"))
	p(5.0, 10.2, 12, 0.5, col("#bfe4e0"))
	var sw := sin(t * 2.0) * 0.4
	for i in 4:
		var x := 6.2 + i * 2.7 + sw * (1.0 if i % 2 == 1 else -1.0)
		p(x, 15.0, 1.0, 2.6, col("#3c9a4a"))
		disc(x + 0.5, 14.6, 1.1, col("#52b95f"))
		p(x + 0.2, 13.9, 0.5, 0.5, col("#ff6b8a"))
	var g := (sin(t * 1.5) + 1.0) / 2.0
	p(6.4, 11.2, 1.4, 3.0, rgba(255, 255, 255, 0.25 + g * 0.4))


func _b_bank(t: float, _T: Dictionary) -> void:
	p(4.6, 17.4, 12.8, 1.4, col("#c8cdd6"))
	p(5.2, 9.8, 11.6, 7.8, col("#dfe3ea"))
	p(5.2, 9.8, 11.6, 0.8, col("#f2f5fa"))
	p(5.2, 9.8, 0.9, 7.8, col("#bcc2cc"))
	for i in 4:
		var x := 6.2 + i * 2.7
		p(x, 11.0, 1.3, 6.2, col("#eef1f6"))
		p(x + 1.0, 11.0, 0.4, 6.2, col("#c2c8d2"))
	for r in 3:
		p(6.4 + r, 9.6 - r, 9.2 - 2 * r, 1.0, col("#cfd4dd"))
	var g := (sin(t * 2.2) + 1.0) / 2.0
	disc(11, 7.2, 1.6, col("#f3c64a"))
	disc(11, 7.2, 1.6 * (0.5 + g * 0.4), col("#ffe07a"))
	p(10.8, 6.2, 0.5, 2.0, col("#7a5a16"))
	p(10.2, 6.6, 1.6, 0.45, col("#7a5a16"))
	p(10.2, 7.6, 1.6, 0.45, col("#7a5a16"))
	p(7.3, 12.0, 1.4, 3.6, rgba(255, 210, 90, 0.55 + g * 0.4))
	p(13.4, 12.0, 1.4, 3.6, rgba(255, 210, 90, 0.55 + g * 0.4))
	p(9.7, 13.0, 2.6, 4.4, col("#5a4a2a"))
	p(9.7, 13.0, 2.6, 0.5, col("#7a6440"))


func _b_lumber(t: float, T: Dictionary) -> void:
	## Kereste Fabrikasi (yeni bible, birebir): kutuk istifi, ahsap atolye,
	## DONEN daire testere, talas pufu, kizakta beslenen kutuk, takim flamasi.
	# kutuk istifi (sol)
	p(2.2, 15.2, 3.4, 2.1, col("#8a5e30"))
	disc(2.4, 16.2, 1.0, col("#a9763f"))
	disc(2.4, 16.2, 0.45, col("#caa069"))
	disc(5.4, 16.2, 1.0, col("#a9763f"))
	disc(5.4, 16.2, 0.45, col("#caa069"))
	p(2.7, 13.3, 2.6, 1.9, col("#946530"))
	disc(2.9, 14.2, 0.9, col("#a9763f"))
	disc(2.9, 14.2, 0.4, col("#caa069"))
	disc(5.1, 14.2, 0.9, col("#a9763f"))
	disc(5.1, 14.2, 0.4, col("#caa069"))
	# atolye (tahta duvar)
	p(6.0, 9.6, 11, 7.9, col("#a9763f"))
	p(6.0, 9.6, 11, 0.7, col("#c08c52"))
	for i in range(1, 5):
		p(6.0, 9.6 + i * 1.55, 11, 0.4, col("#8a5e30"))
	p(6.0, 9.6, 0.9, 7.9, col("#8a5e30"))
	# takim rengi cati
	for r in 5:
		p(5.0 + r * 0.9, 9.6 - r, 13 - 1.8 * r, 1.15, col(T["dark"]) if r == 0 else col(T["main"]))
	p(5.0, 9.1, 13, 0.6, col(T["light"]))
	# kapi
	p(7.0, 13.2, 2.4, 4.3, col("#6e4a2a"))
	p(7.0, 13.2, 2.4, 0.5, col("#8a6038"))
	# buyuk daire testere (on-sag) -- doner
	var scx := 13.2
	var scy := 13.4
	var R := 2.8
	disc(scx, scy, R, col("#c9ced6"))
	disc(scx, scy, R * 0.5, col("#9aa0a9"))
	disc(scx, scy, 0.7, col("#5e636d"))
	var rot := t * 7.0
	for k in 10:
		var a := k * PI / 5.0 + rot
		p(scx + cos(a) * R - 0.35, scy + sin(a) * R - 0.35, 0.7, 0.7, col("#eef1f5"))
	rot_rect(scx, scy, rot, -0.25, -R * 0.5, 0.5, R, col("#aeb4bd"))
	rot_rect(scx, scy, rot, -R * 0.5, -0.25, R, 0.5, col("#aeb4bd"))
	# bicak temasinda talas pufu
	_smoke(scx - 0.6, scy + 1.6, t, Vector3i(214, 194, 150), 1.7)
	# kizakta beslenen kutuk
	p(9.0, 16.3, 4.6, 1.3, col("#a9763f"))
	p(9.0, 16.3, 4.6, 0.4, col("#caa069"))
	disc(9.0, 16.95, 0.65, col("#caa069"))
	# cati flamasi
	_flag(15.2, 6.0, 2.4, T, t)


func _b_quarry(t: float, T: Dictionary) -> void:
	## Tas Ocagi (yeni bible, birebir): terasli kaya cukuru, kesilmis tas
	## bloklari, makarali ahsap vinc (sallanan tas blogu ceker), toz, flama.
	# toprak platform
	p(3.0, 16.0, 16, 3.6, col("#8a6a44"))
	p(3.0, 16.0, 16, 0.7, col("#a07e52"))
	p(3.0, 18.9, 16, 0.7, col("#6e5235"))
	# terasli kaya cukuru (sol, basamak basamak)
	p(3.4, 13.8, 6.6, 2.4, col("#9aa0a9"))
	p(3.4, 13.8, 6.6, 0.6, col("#b3b9c1"))
	p(2.8, 15.9, 5.6, 2.2, col("#868d97"))
	p(2.8, 15.9, 5.6, 0.6, col("#9aa0a9"))
	p(2.4, 17.8, 4.8, 1.6, col("#747983"))
	p(2.4, 17.8, 4.8, 0.5, col("#868d97"))
	for i in 3:
		p(4.0 + i * 1.9, 14.0, 0.35, 2.0, col("#6e747e"))   # kesim izleri
	# istiflenmis kesme taslar (sag)
	p(12.8, 15.4, 3.2, 2.3, col("#b3b9c1"))
	p(12.8, 15.4, 3.2, 0.6, col("#cdd2d9"))
	p(12.8, 15.4, 0.5, 2.3, col("#9aa0a9"))
	p(13.6, 13.1, 2.6, 2.1, col("#aab0b8"))
	p(13.6, 13.1, 2.6, 0.6, col("#c4c9d0"))
	p(14.2, 11.2, 2.0, 1.7, col("#b8bec6"))
	p(14.2, 11.2, 2.0, 0.5, col("#d0d5db"))
	# ahsap A-vinc
	p(7.2, 5.4, 1.0, 9.2, col("#8a5e30"))
	p(11.0, 5.4, 1.0, 9.2, col("#8a5e30"))
	p(7.2, 5.4, 4.8, 1.0, col("#7a4f28"))
	p(7.2, 5.4, 4.8, 0.4, col(T["main"]))   # takim boyali kiris
	p(7.0, 9.0, 5.4, 0.9, col("#7a4f28"))
	p(7.4, 5.6, 0.4, 9.0, col("#9a6c3c"))
	# makara
	disc(9.6, 5.4, 1.1, col("#5e636d"))
	disc(9.6, 5.4, 0.4, col("#cdd2d9"))
	# halat + sallanan tas blogu
	var bob := sin(t * 1.6) * 1.1
	p(9.5, 5.4, 0.3, 4.0 + bob, col("#caa069"))
	p(8.7, 9.2 + bob, 1.8, 1.8, col("#b3b9c1"))
	p(8.7, 9.2 + bob, 1.8, 0.5, col("#cdd2d9"))
	p(8.7, 9.2 + bob, 0.5, 1.8, col("#9aa0a9"))
	# cukurdan yukselen toz
	_smoke(5.2, 15.4, t, Vector3i(170, 150, 120), 1.2)
	_smoke(6.1, 14.9, t + 0.5, Vector3i(155, 135, 105), 1.0)
	# vinc tepesinde takim flamasi
	_flag(7.4, 2.6, 2.8, T, t)
	# kesme blokta parilti
	var g := (sin(t * 2.6) + 1.0) / 2.0
	if g > 0.72:
		p(14.7, 11.6, 0.8, 0.8, rgba(255, 255, 255, g))


func _b_barracks(t: float, T: Dictionary) -> void:
	p(4.4, 17.4, 13.2, 1.3, col("#7c7058"))
	p(5.0, 11.0, 12, 6.6, col("#8a8466"))
	p(5.0, 11.0, 12, 0.7, col("#a8a17e"))
	p(5.0, 11.0, 0.9, 6.6, col("#6f6a50"))
	for r in 4:
		p(4.2 + r * 0.9, 11.0 - r, 13.6 - 1.8 * r, 1.1, col(T["dark"]) if r == 0 else col(T["main"]))
	p(9.6, 13.0, 2.8, 4.6, col("#4a4636"))
	p(9.6, 13.0, 2.8, 0.5, col("#5f5a44"))
	disc(11, 11.9, 1.2, col(T["light"]))
	p(10.6, 11.5, 0.8, 0.8, col("#ffffff"))
	for i in 6:
		disc(5.6 + i * 1.9, 17.6, 0.95, col("#b6a06a"))
	p(6.4, 13.2, 1.6, 1.6, col("#3a4632"))
	p(14.0, 13.2, 1.6, 1.6, col("#3a4632"))
	_flag(15.4, 7.0, 2.2, T, t)


func _b_factory(t: float, T: Dictionary) -> void:
	p(4.6, 11.0, 12.8, 6.8, col("#9aa0a8"))
	p(4.6, 11.0, 12.8, 0.8, col("#b6bcc4"))
	p(4.6, 11.0, 0.9, 6.8, col("#7d828c"))
	for i in 4:
		var x := 5.0 + i * 3.0
		p(x, 9.6, 2.6, 1.6, col("#7d828c"))
		p(x, 9.6, 2.6, 0.5, col(T["main"]))
	p(13.2, 4.2, 2.4, 7.0, col("#7d828c"))
	p(13.0, 3.9, 2.8, 0.8, col("#5e636d"))
	p(13.2, 6.0, 2.4, 0.7, col(T["main"]))
	_smoke(14.4, 3.4, t, Vector3i(120, 124, 132), 1.4)
	_smoke(14.7, 3.4, t + 0.5, Vector3i(140, 144, 152), 1.2)
	disc(8.0, 13.8, 1.7, col("#5e636d"))
	disc(8.0, 13.8, 0.8, col("#9aa0a8"))
	for k in 6:
		var a := k * PI / 3.0
		p(8.0 + cos(a) * 1.9 - 0.35, 13.8 + sin(a) * 1.9 - 0.35, 0.7, 0.7, col("#5e636d"))
	p(10.6, 13.4, 3.4, 4.4, col("#4a4e56"))
	p(10.6, 13.4, 3.4, 0.5, col("#646973"))
	for i in 4:
		p(10.6, 14.0 + i * 1.0, 3.4, 0.4, col("#3a3e46"))


func _b_mine(t: float, T: Dictionary) -> void:
	## Mayin (26px kare, kucuk): toprak tumsek + celik disk + kurma isigi.
	## Rakip ekranda HIC gorunmez; bu gorsel yalnizca sahibine.
	disc(13, 16.5, 4.4, rgba(0, 0, 0, 0.14))
	disc(13, 15.0, 3.6, col("#8a6a44"))
	disc(13, 14.4, 3.0, col("#a07e52"))
	disc(13, 13.8, 2.2, col("#5e636d"))
	disc(13, 13.6, 1.5, col("#747983"))
	p(11.2, 12.2, 0.7, 1.2, col("#9aa0a9"))   # tetik pimleri
	p(12.7, 11.8, 0.7, 1.4, col("#9aa0a9"))
	p(14.2, 12.2, 0.7, 1.2, col("#9aa0a9"))
	p(10.6, 15.6, 0.9, 0.9, col(T["main"]))   # takim pipi
	var blink := fmod(t, 2.0) < 0.25
	if blink:
		p(12.7, 13.2, 0.9, 0.9, col("#ff5a4a"))


func _b_turret(t: float, T: Dictionary) -> void:
	p(6.2, 13.0, 9.6, 5.0, col("#b9bec7"))
	p(6.2, 13.0, 9.6, 0.8, col("#d3d8df"))
	p(6.2, 13.0, 0.9, 5.0, col("#9aa0a9"))
	p(6.2, 15.8, 9.6, 2.2, col(T["dark"]))
	p(6.2, 15.8, 9.6, 0.6, col(T["light"]))
	var ang := sin(t * 1.3) * 0.5
	var fire := 1.0 - fmod(t, 1.6) / 0.18 if fmod(t, 1.6) < 0.18 else 0.0
	var cx := 11.0
	var cy := 11.2
	disc(cx, cy, 2.4, col("#5e636d"))
	disc(cx, cy, 1.5, col(T["main"]))
	p(cx - 0.8, cy - 1.0, 1.0, 1.0, col(T["light"]))
	rot_rect(cx, cy, ang, 0.0, -0.6, 5.4 - fire * 1.4, 1.3, col("#3c4350"))
	rot_rect(cx, cy, ang, 0.0, -0.6, 5.4, 0.4, col("#576070"))
	if fire > 0.0:
		_muzzle(cx + cos(ang) * 5.4, cy + sin(ang) * 5.4, fire)


func _bake_buildings(root: String) -> void:
	for id: StringName in Bible.BUILDING_ANIMS:
		var meta: Array = Bible.BUILDING_ANIMS[id]
		var frames: int = meta[0]
		var dt: float = meta[1]
		var fpx := Bible.building_frame_px(id)
		for pid in [1, 2]:
			var sheet := blank(frames * fpx, fpx)
			for i in frames:
				var f := bake_building_frame(id, i * dt, pid)
				sheet.blit_rect(f, Rect2i(0, 0, fpx, fpx), Vector2i(i * fpx, 0))
			sheet.save_png(root + "assets/generated/bible/b_%s_p%d.png" % [id, pid])


# ======================= zeminler =======================

func bake_tile_frame(kind: StringName, t: float, seed_v: int) -> Image:
	var frame := blank(16, 16)
	_img = frame
	_S = 1.0
	_ox = 0.0
	_oy = 0.0
	match kind:
		&"water", &"bridge":
			_t_water(t, seed_v)
			if kind == &"bridge":
				_t_bridge_top()
		&"grass":
			_t_ground(seed_v, col("#5fb84f"), col("#54a945"), col("#74cf63"))
			var sw := sin(t * 2.0 + seed_v) * 0.5
			p(7.0 + sw, 9, 0.7, 1.6, col("#3f9a37"))
			p(7.0 + sw, 8.5, 0.9, 0.9, col("#ffe14d") if seed_v % 2 == 1 else col("#ff7aa0"))
		&"snow":
			# kar ovasi: soguk beyaz zemin + mavi golgeli dokular + isilti
			_t_ground(seed_v, col("#e6edf3"), col("#cfdbe6"), col("#f7fbff"))
			var g := (sin(t * 2.0 + seed_v) + 1.0) / 2.0
			if g > 0.65:
				p(4.0 + (seed_v * 3) % 8, 5.0 + (seed_v * 5) % 7, 0.9, 0.9, rgba(255, 255, 255, g))
		&"hill":
			# engebe: kayalik sirt — yurunur ama YAVAS (TILE_SPEED)
			_t_ground(seed_v, col("#8d8273"), col("#7a7062"), col("#9c9180"))
			disc(5.5, 6.0, 2.4, col("#6e6557"))
			disc(5.2, 5.4, 1.8, col("#857a6a"))
			disc(11.0, 10.5, 2.8, col("#6e6557"))
			disc(10.6, 9.8, 2.1, col("#857a6a"))
			p(3.0, 12.0, 2.0, 0.8, col("#5e564a"))
			p(12.0, 4.0, 1.6, 0.7, col("#5e564a"))
		# --- ozellik katmani: SEFFAF zemin (cim VEYA kar ustune bindirilir) ---
		&"forest":
			_t_tree(t, seed_v)
		&"stone":
			_t_rock(t, seed_v)
		&"gold":
			_t_gold(t, seed_v)
	return frame


func _t_ground(seed_v: int, base: Color, dark: Color, light: Color) -> void:
	p(0, 0, 16, 16, base)
	for i in 10:
		var bx := _trand(seed_v, i) * 15.0
		var by := _trand(seed_v, i + 40) * 15.0
		p(bx, by, 1, 1, dark if _trand(seed_v, i + 9) > 0.5 else light)


func _t_gold(t: float, seed_v: int) -> void:
	## Tarafsiz bolge altin damari: koyu kaya + parlayan altin yuvalari.
	disc(8, 11, 3.0, rgba(0, 0, 0, 0.12))
	disc(7, 9, 2.6, col("#7a7062"))
	disc(10, 10, 2.0, col("#6e6557"))
	disc(7, 8.2, 2.0, col("#8d8273"))
	disc(6.4, 8.6, 1.0, col("#d4a93c"))
	disc(9.8, 9.6, 0.85, col("#d4a93c"))
	p(8.2, 7.2, 1.0, 1.0, col("#f3c64a"))
	var g := (sin(t * 2.4 + seed_v) + 1.0) / 2.0
	if g > 0.6:
		p(6.2, 7.8, 0.9, 0.9, rgba(255, 240, 170, g))
	if g > 0.8:
		p(9.9, 9.2, 0.8, 0.8, rgba(255, 240, 170, g))


func _trand(seed_v: int, n: int) -> float:
	# JS: fract(sin(seed*97.13 + n*13.7) * 43758.5453)
	var x := sin(seed_v * 97.13 + n * 13.7) * 43758.5453
	return x - floor(x)


func _t_water(t: float, seed_v: int) -> void:
	p(0, 0, 16, 16, col("#2f7fcf"))
	for row in range(0, 16, 2):
		var off := sin(t * 1.6 + row * 0.5 + seed_v) * 3.0 + row
		for k in 2:
			var x := fposmod(off + k * 8.0, 16.0)
			# dalga 3px; tile kenarindan tasani sarmala (kesintisiz doseme)
			for d in 3:
				p(fposmod(x + d, 16.0), row, 1, 1, col("#5aa0e6"))
	var g := (sin(t * 1.2 + seed_v) + 1.0) / 2.0
	p(3, 3, 2, 1, rgba(255, 255, 255, 0.3 + g * 0.3))


func _t_bridge_top() -> void:
	p(0, 4, 16, 8, col("#b07a43"))
	p(0, 4, 16, 1, col("#caa069"))
	p(0, 11, 16, 1, col("#8a5e30"))
	for i in 8:
		p(i * 2, 4, 0.5, 8, col("#8a5e30"))
	p(0, 4, 16, 0.6, col("#5e3f20"))
	p(0, 11.6, 16, 0.6, col("#5e3f20"))


func _t_tree(t: float, seed_v: int) -> void:
	var sw := sin(t * 1.6 + seed_v) * 0.6
	p(7.4, 9, 1.6, 4, col("#6e4a2a"))
	p(7.4, 9, 0.6, 4, col("#5a3a20"))
	disc(8 + sw, 6, 4.0, col("#2f8a3e"))
	disc(8 + sw, 5.4, 3.0, col("#46a851"))
	disc(6.8 + sw, 4.6, 1.2, col("#62c46c"))


func _t_rock(t: float, seed_v: int) -> void:
	disc(8, 11, 3.0, rgba(0, 0, 0, 0.12))
	disc(7, 9, 2.6, col("#9aa0a9"))
	disc(10, 10, 2.0, col("#868d97"))
	disc(7, 8.2, 2.0, col("#b3b9c1"))
	p(5.5, 9.5, 1, 1, col("#747983"))
	var g := (sin(t * 2.4 + seed_v) + 1.0) / 2.0
	if g > 0.7:
		p(6.4, 7.6, 0.9, 0.9, rgba(255, 255, 255, g))


func _bake_tiles(root: String) -> void:
	for kind: StringName in Bible.TILE_ANIMS:
		var meta: Array = Bible.TILE_ANIMS[kind]
		var variants: int = meta[0]
		var frames: int = meta[1]
		var dt: float = meta[2]
		var sheet := blank(frames * 16, variants * 16)
		for v in variants:
			for i in frames:
				var f := bake_tile_frame(kind, i * dt, v)
				sheet.blit_rect(f, Rect2i(0, 0, 16, 16), Vector2i(i * 16, v * 16))
		sheet.save_png(root + "assets/generated/bible/tile_%s.png" % kind)


# ======================= efektler =======================

func bake_fx_frame(id: StringName, t: float) -> Image:
	var frame := blank(16, 16)
	_img = frame
	_S = 1.0
	_ox = 0.0
	_oy = 0.0
	var cx := 8.0
	var cy := 8.0
	match id:
		&"muzzle":
			var f := maxf(0.0, 1.0 - fmod(t * 2.2, 1.0) / 0.5)
			if f > 0.0:
				_muzzle(cx, cy, f)
		&"explosion":
			var ph := fmod(t * 0.9, 1.0)
			var r := 1.0 + ph * 6.5
			var a := 1.0 - ph
			ring(cx, cy, r, rgba(255, 180, 60, a * 0.8), 1.3)
			disc(cx, cy, maxf(0.5, (0.6 - ph) * 7.0), rgba(255, 240, 180, a))
			disc(cx, cy, maxf(0.2, (0.5 - ph) * 9.0), rgba(255, 120, 40, a * 0.9))
			for k in 6:
				var a2 := k * PI / 3.0 + ph
				p(cx + cos(a2) * r, cy + sin(a2) * r, 0.8, 0.8, rgba(80, 70, 70, a))
		&"gather_fx":
			# bible'daki yongalar (kutuk demosuz; oyunda gercek agacin ustunde oynar)
			for k in 4:
				var ph := fmod(t * 1.4 + k * 0.25, 1.0)
				var dx := cos(k * 1.6) * ph * 5.0
				var dy := -ph * 5.0 + ph * ph * 4.0
				p(cx + dx, 7.0 + dy, 0.9, 0.9, rgba(180, 120, 60, 1.0 - ph))
		&"build_fx":
			# toz puflari (yukselen duvar demosu oyunda gercek insaat)
			for k in 5:
				var pp := fmod(t * 1.2 + k * 0.2, 1.0)
				disc(cx - 3.0 + k * 1.6, 13.5, 0.6 + pp * 1.2, rgba(200, 190, 170, (1.0 - pp) * 0.5))
		&"dirt":
			# iska eden merminin carptigi yerden kalkan kucuk toz
			var dp := clampf(t / 0.28, 0.0, 1.0)
			var da := 1.0 - dp
			disc(cx, cy + 1.0 - dp * 2.0, 0.8 + dp * 1.6, rgba(150, 130, 100, da * 0.7))
			p(cx - 1.5 - dp * 2.0, cy + 0.5, 0.8, 0.8, rgba(120, 104, 80, da))
			p(cx + 1.0 + dp * 2.0, cy + 0.2, 0.8, 0.8, rgba(120, 104, 80, da))
	return frame


# ======================= TAS & DEMIR HUD (HUD Redesign.dc.html portu) =======================
# Celik tema paleti (tasarimin --steel degiskenleri birebir)
const UI_PANEL := "#2f3947"
const UI_PANEL2 := "#222a35"
const UI_BEVEL_HI := "#566a7d"
const UI_BEVEL_LO := "#141a22"
const UI_FRAME := "#0c1016"
const UI_RIVET := "#8298ac"
const UI_PLANK_A := "#323d4c"
const UI_PLANK_B := "#2b3540"
const UI_SLOT := "#26303c"


func _poly(pts: Array, c: Color) -> void:
	## Kucuk cokgen doldurma (taç/kafatasi/yaprak icin): even-odd testi.
	var minx := 999.0
	var miny := 999.0
	var maxx := -999.0
	var maxy := -999.0
	for q: Vector2 in pts:
		minx = minf(minx, q.x)
		miny = minf(miny, q.y)
		maxx = maxf(maxx, q.x)
		maxy = maxf(maxy, q.y)
	for y in range(floori(miny), ceili(maxy) + 1):
		for x in range(floori(minx), ceili(maxx) + 1):
			var pt := Vector2(x + 0.5, y + 0.5)
			var inside := false
			var j := pts.size() - 1
			for i in pts.size():
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[j]
				if (a.y > pt.y) != (b.y > pt.y) \
						and pt.x < (b.x - a.x) * (pt.y - a.y) / (b.y - a.y) + a.x:
					inside = not inside
				j = i
			if inside:
				p(x, y, 1, 1, c)


func _bake_box_panel() -> Image:
	## Ana panel (48x48, 9-patch margin 12): celik kalas seritleri + bevel +
	## dis cerceve + kose percinleri. Yatay/dikey TILE ile desensiz uzar.
	var img := blank(48, 48)
	_img = img
	_S = 1.0
	_ox = 0.0
	_oy = 0.0
	# kalas seritleri (dikey, 7px)
	for x in range(0, 48):
		var c := col(UI_PLANK_A) if (x % 14) < 7 else col(UI_PLANK_B)
		p(x, 0, 1, 48, c)
	# bevel (ic kenarlar)
	p(3, 3, 42, 3, col(UI_BEVEL_HI))
	p(3, 3, 3, 42, col(UI_BEVEL_HI))
	p(3, 42, 42, 3, col(UI_BEVEL_LO))
	p(42, 3, 3, 42, col(UI_BEVEL_LO))
	# dis cerceve
	p(0, 0, 48, 3, col(UI_FRAME))
	p(0, 45, 48, 3, col(UI_FRAME))
	p(0, 0, 3, 48, col(UI_FRAME))
	p(45, 0, 3, 48, col(UI_FRAME))
	# percinler
	for corner: Vector2i in [Vector2i(7, 7), Vector2i(36, 7), Vector2i(7, 36), Vector2i(36, 36)]:
		p(corner.x, corner.y, 5, 5, col(UI_RIVET))
		p(corner.x, corner.y, 2, 2, rgba(255, 255, 255, 0.45))
		p(corner.x + 3, corner.y + 3, 2, 2, rgba(0, 0, 0, 0.5))
	return img


func _bake_box_pod() -> Image:
	## Cokuk pod (24x24, margin 6): panel2 zemin + TERS bevel (icine gomulu).
	var img := blank(24, 24)
	_img = img
	p(0, 0, 24, 24, col(UI_PANEL2))
	p(0, 0, 24, 2, col(UI_BEVEL_LO))
	p(0, 0, 2, 24, col(UI_BEVEL_LO))
	p(0, 22, 24, 2, col(UI_BEVEL_HI))
	p(22, 0, 2, 24, col(UI_BEVEL_HI))
	return img


func _bake_box_btn(fill: String, hi: String, lo: String, invert := false) -> Image:
	## Buton/slot (24x24, margin 8): dolgu + bevel + 2px cerceve.
	var img := blank(24, 24)
	_img = img
	p(0, 0, 24, 24, col(UI_FRAME))
	p(2, 2, 20, 20, col(fill))
	var top := col(lo) if invert else col(hi)
	var bot := col(hi) if invert else col(lo)
	p(2, 2, 20, 2, top)
	p(2, 2, 2, 20, top)
	p(2, 20, 20, 2, bot)
	p(20, 2, 2, 20, bot)
	return img


func bake_ui_icon(id: StringName) -> Image:
	## Tasarimin 16px kaynak/UI ikonlari (rWood/rStone/rFood/rMoney/uiPop/
	## uiCrown/uiSkull birebir).
	var img := blank(16, 16)
	_img = img
	_S = 1.0
	_ox = 0.0
	_oy = 0.0
	match id:
		&"wood":
			disc(8, 13, 3, rgba(0, 0, 0, 0.18))
			p(2, 6.5, 12, 3.4, col("#8a5a32"))
			p(2, 6.5, 12, 0.8, col("#a9763f"))
			p(3, 10, 12, 3.3, col("#7a4f2c"))
			p(3, 10, 12, 0.8, col("#9a6a38"))
			disc(3.2, 8.2, 1.8, col("#b9854a"))
			disc(3.2, 8.2, 0.8, col("#6e4528"))
			disc(4.2, 11.6, 1.7, col("#a9763f"))
			disc(4.2, 11.6, 0.7, col("#5e3b22"))
		&"stone":
			disc(8, 12.6, 3.4, rgba(0, 0, 0, 0.18))
			disc(6.4, 9.2, 3.1, col("#9aa0a9"))
			disc(10, 10.6, 2.6, col("#868d97"))
			disc(7, 8, 2.4, col("#b3b9c1"))
			p(5, 9.4, 1, 1, col("#747983"))
			p(6, 6.6, 1.3, 1.3, col("#cdd2d9"))
		&"food":
			disc(8, 13, 3, rgba(0, 0, 0, 0.16))
			disc(8, 9.2, 3.5, col("#d8412f"))
			disc(6.7, 7.9, 1.2, col("#ff8a6a"))
			p(7.7, 4.6, 0.8, 2.2, col("#6e4528"))
			_poly([Vector2(8.4, 5.2), Vector2(10.4, 4.6), Vector2(9.6, 6.2)], col("#4caf50"))
		&"money":
			disc(8, 13, 3, rgba(0, 0, 0, 0.16))
			disc(8, 8.8, 3.7, col("#caa024"))
			disc(8, 8.8, 2.9, col("#f3c64a"))
			p(7.6, 6.3, 0.8, 5, col("#8a6a16"))
			p(6.5, 6.9, 2.7, 0.7, col("#8a6a16"))
			p(6.5, 8.5, 2.7, 0.7, col("#8a6a16"))
			p(6.5, 10, 2.7, 0.7, col("#8a6a16"))
			disc(6.6, 7, 0.8, col("#fff0b0"))
		&"pop":
			for fig: Array in [[6.0, TEAM[1]["main"]], [10.4, TEAM[2]["main"]]]:
				var x: float = fig[0]
				disc(x, 6.4, 1.5, col(SK))
				_poly([Vector2(x - 2, 13.5), Vector2(x - 1.6, 8.8),
					Vector2(x + 1.6, 8.8), Vector2(x + 2, 13.5)], col(fig[1]))
		&"crown":
			disc(8, 13.5, 3.2, rgba(0, 0, 0, 0.2))
			_poly([Vector2(3, 12), Vector2(3, 5), Vector2(5.5, 8), Vector2(8, 4),
				Vector2(10.5, 8), Vector2(13, 5), Vector2(13, 12)], col("#f3c64a"))
			p(3, 11.5, 10, 1.8, col("#d99a1f"))
			disc(3, 5, 0.9, col("#ff7aa0"))
			disc(8, 4, 0.9, col("#7fb0ff"))
			disc(13, 5, 0.9, col("#7be08a"))
			p(5, 12, 1, 1, col("#fff0b0"))
			p(8.5, 12, 1, 1, col("#fff0b0"))
		&"skull":
			disc(8, 7.5, 4, col("#e9e4d6"))
			p(4, 7.5, 8, 4, col("#e9e4d6"))
			p(5, 11.5, 6, 1.4, col("#e9e4d6"))
			disc(6.2, 7.6, 1.2, col("#2b2230"))
			disc(9.8, 7.6, 1.2, col("#2b2230"))
			p(7.4, 9.6, 1.2, 1.4, col("#2b2230"))
			p(5.4, 12.6, 1, 1.4, col("#cfc9ba"))
			p(7.5, 12.6, 1, 1.4, col("#cfc9ba"))
			p(9.6, 12.6, 1, 1.4, col("#cfc9ba"))
	return img


func _bake_ui(root: String) -> void:
	var dir := root + "assets/generated/ui/"
	_bake_box_panel().save_png(dir + "box_panel.png")
	_bake_box_pod().save_png(dir + "box_pod.png")
	_bake_box_btn(UI_SLOT, UI_BEVEL_HI, UI_BEVEL_LO).save_png(dir + "box_btn.png")
	_bake_box_btn("#2c3744", "#6e8499", UI_BEVEL_LO).save_png(dir + "box_btn_hover.png")
	_bake_box_btn("#222b36", UI_BEVEL_HI, UI_BEVEL_LO, true).save_png(dir + "box_btn_pressed.png")
	_bake_box_btn("#3a78d8", "#7fb0ff", "#27508f").save_png(dir + "box_btn_blue.png")
	_bake_box_btn("#4a3a12", "#8a6f2a", "#241c08").save_png(dir + "box_btn_amber.png")
	_bake_box_btn("#4a1410", "#8a3a2a", "#240a06").save_png(dir + "box_btn_red.png")
	for icon: StringName in [&"wood", &"stone", &"food", &"money", &"pop", &"crown", &"skull"]:
		bake_ui_icon(icon).save_png(dir + "icon_%s.png" % icon)


func _bake_fx(root: String) -> void:
	for id: StringName in Bible.FX:
		var meta: Array = Bible.FX[id]
		var frames: int = meta[0]
		var dt: float = meta[1]
		var sheet := blank(frames * 16, 16)
		for i in frames:
			var f := bake_fx_frame(id, i * dt)
			sheet.blit_rect(f, Rect2i(0, 0, 16, 16), Vector2i(i * 16, 0))
		sheet.save_png(root + "assets/generated/bible/fx_%s.png" % id)
