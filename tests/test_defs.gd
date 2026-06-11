extends RefCounted
## Tanim tablolari tutarliligi.

const D := preload("res://scripts/autoload/defs.gd")


func run() -> Array:
	var errs: Array = []
	errs.append_array(D.validate())
	if D.defs_hash() != D.defs_hash():
		errs.append("defs_hash kararsiz")
	if D.UNITS.size() != 9:
		errs.append("9 birim bekleniyordu, %d var" % D.UNITS.size())
	if D.BUILDINGS.size() != 12:
		errs.append("12 bina bekleniyordu, %d var" % D.BUILDINGS.size())
	if D.COVER_MISS < 0.5 or D.COVER_MISS > 0.8:
		errs.append("COVER_MISS makul aralikta degil")
	if D.PLAYER_COLORS.size() != D.MAX_PLAYERS:
		errs.append("PLAYER_COLORS %d oyuncu icermeli" % D.MAX_PLAYERS)
	if D.metro_types() != 9:
		errs.append("metro_types 9 olmali (kopru+mayin haric), %d" % D.metro_types())
	# iska oranlari mantikli araliklarda
	for uid: StringName in D.UNITS:
		var m: float = D.UNITS[uid].get("miss", 0.0)
		if m < 0.0 or m > 0.5:
			errs.append("unit %s: miss 0..0.5 araliginda olmali" % uid)
	if D.unit(&"mortar").get("arc", false) != true:
		errs.append("havanci arc atisli olmali")
	if D.building(&"mine").get("m_dmg", 0) < 100:
		errs.append("mayin hasari tank avcisi olacak kadar yuksek olmali")
	# gelistirme alanlari tutarli mi
	for bid: StringName in D.BUILDINGS:
		var b: Dictionary = D.BUILDINGS[bid]
		if b.has("up_cost"):
			var has_benefit: bool = b.has("up_pop") or b.has("up_rate") \
				or b.has("up_dmg") or b.has("up_speed")
			if not has_benefit:
				errs.append("building %s: up_cost var ama kazanim alani yok" % bid)
	# healer sagligi
	var healer := D.unit(&"healer")
	if healer.get("heal_rate", 0.0) <= 0.0:
		errs.append("healer heal_rate > 0 olmali")
	if healer.get("dmg", 1) != 0:
		errs.append("healer hasar vermemeli")
	# scaled_cost: L2 = 1x, L3 = 2x
	var sc := D.scaled_cost({"wood": 40, "stone": 20}, 2)
	if sc["wood"] != 80 or sc["stone"] != 40:
		errs.append("scaled_cost x2 yanlis")
	if D.SNIPER_VS_INFANTRY <= 1.0:
		errs.append("SNIPER_VS_INFANTRY > 1 olmali")
	if D.RPG_VS_ARMOR_BUILDING <= 1.0:
		errs.append("RPG_VS_ARMOR_BUILDING > 1 olmali")
	if D.RIFLE_VS_SNIPER_CLOSE <= 1.0:
		errs.append("RIFLE_VS_SNIPER_CLOSE > 1 olmali")
	# acilis dengesi: baslangic kaynagi ilk ev + ilk isciyi karsilamali
	var house_cost: Dictionary = D.building(&"house")["cost"]
	if D.START_RES["wood"] < house_cost.get("wood", 0):
		errs.append("baslangic odunu ilk eve yetmiyor")
	if D.START_RES["food"] < D.unit(&"worker")["cost"].get("food", 0):
		errs.append("baslangic yemegi ilk isciye yetmiyor")
	return errs
