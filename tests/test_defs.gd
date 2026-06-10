extends RefCounted
## Tanim tablolari tutarliligi.

const D := preload("res://scripts/autoload/defs.gd")


func run() -> Array:
	var errs: Array = []
	errs.append_array(D.validate())
	if D.defs_hash() != D.defs_hash():
		errs.append("defs_hash kararsiz")
	if D.UNITS.size() != 5:
		errs.append("5 birim bekleniyordu, %d var" % D.UNITS.size())
	if D.BUILDINGS.size() != 7:
		errs.append("7 bina bekleniyordu, %d var" % D.BUILDINGS.size())
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
