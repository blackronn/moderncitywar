extends RefCounted
## Hasar matrisi + counter ucgeni: saf attack_damage uzerinden sayisal kanit.

const D := preload("res://scripts/autoload/defs.gd")
const Sim := preload("res://scripts/sim/sim.gd")


func _dps(att_id: StringName, def_id: StringName, dist: float) -> float:
	var att := D.unit(att_id) if D.is_unit(att_id) else D.building(att_id)
	var dfn := D.unit(def_id) if D.is_unit(def_id) else D.building(def_id)
	return Sim.attack_damage(att_id, att, def_id, dfn, dist) / float(att["cooldown_s"])


func run() -> Array:
	var errs: Array = []
	var rifle := D.unit(&"rifleman")
	var sniper := D.unit(&"sniper")
	var rpg := D.unit(&"rpg")
	var tank := D.unit(&"tank")
	var hall := D.building(&"city_hall")
	var turret := D.building(&"turret")

	# --- carpan dogrulugu ---
	if Sim.attack_damage(&"sniper", sniper, &"rifleman", rifle, 6.0) != sniper["dmg"] * D.SNIPER_VS_INFANTRY:
		errs.append("sniper->piyade carpani yanlis")
	if Sim.attack_damage(&"rpg", rpg, &"tank", tank, 4.0) != rpg["dmg"] * D.RPG_VS_ARMOR_BUILDING:
		errs.append("rpg->tank carpani yanlis")
	if Sim.attack_damage(&"rpg", rpg, &"city_hall", hall, 4.0) != rpg["dmg"] * D.RPG_VS_ARMOR_BUILDING:
		errs.append("rpg->bina carpani yanlis")
	if Sim.attack_damage(&"rifleman", rifle, &"sniper", sniper, 2.0) != rifle["dmg"] * D.RIFLE_VS_SNIPER_CLOSE:
		errs.append("piyade->sniper yakin carpani yanlis")
	if Sim.attack_damage(&"rifleman", rifle, &"sniper", sniper, 5.0) != rifle["dmg"] * 1.0:
		errs.append("piyade->sniper uzak carpan 1.0 olmali")
	if Sim.attack_damage(&"tank", tank, &"rifleman", rifle, 3.0) != tank["dmg"] * 1.5:
		errs.append("tank->piyade carpani yanlis")
	if Sim.attack_damage(&"rifleman", rifle, &"tank", tank, 3.0) != rifle["dmg"] * 0.5:
		errs.append("piyade->tank carpani yanlis")
	if Sim.attack_damage(&"turret", turret, &"rifleman", rifle, 3.0) != float(turret["dmg"]):
		errs.append("taret->piyade carpani 1.0 olmali")
	if Sim.attack_damage(&"turret", turret, &"city_hall", hall, 3.0) != 0.0:
		errs.append("taret binaya hasar vermemeli (matris 0)")

	# --- counter ucgeni (dps/ttk kaniti) ---
	# RPG tanka karsi acik ara en iyi piyade
	if _dps(&"rpg", &"tank", 4.0) < _dps(&"rifleman", &"tank", 3.0) * 3.0:
		errs.append("rpg anti-tank rolu zayif")
	# es-maliyete yakin: 3 rpg tanki, tankin 3 rpg'yi oldurmesinden once eritmeli
	var t_rpg_kills_tank: float = tank["hp"] / (3.0 * _dps(&"rpg", &"tank", 4.0))
	var t_tank_kills_rpgs: float = 3.0 * (rpg["hp"] / _dps(&"tank", &"rpg", 4.0))
	if t_rpg_kills_tank >= t_tank_kills_rpgs:
		errs.append("3 rpg tanka yeniliyor (ttk %0.1f vs %0.1f)" % [t_rpg_kills_tank, t_tank_kills_rpgs])
	# sniper piyadeyi menzil disindan dover
	if sniper["range_t"] <= rifle["range_t"]:
		errs.append("sniper menzili piyadeden uzun olmali")
	# yakin mesafede piyade sniper'i dover (dps karsilastirma)
	if _dps(&"rifleman", &"sniper", 2.0) <= _dps(&"sniper", &"rifleman", 2.0) * float(sniper["hp"]) / float(rifle["hp"]):
		errs.append("yakin mesafede piyade sniper'a ustun gelmiyor")
	return errs
