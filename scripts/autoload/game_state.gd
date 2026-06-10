extends Node
## Mac boyunca yasayan durum. Host'ta sim dogrudan mutasyon yapar;
## istemcide Net'ten gelen snapshot/event'ler gunceller.

const D := preload("res://scripts/autoload/defs.gd")

var my_pid := 1                      # 1 = host, 2 = istemci
var seed_v := 0
var grid := PackedInt32Array()       # guncel harita (tukenmeler islenmis), D.Tile.*
var map_hash := 0
var spawns: Array = []               # [Vector2i, Vector2i] belediye sol-ust koseleri
var res := {}                        # pid -> {"wood": float, ...}
var pop_used := {1: 0, 2: 0}
var pop_cap := {1: 0, 2: 0}
var war_state := D.War.PEACE
var war_t_left := 0.0
var entities := {}                   # id -> Node (unit.gd / building.gd)
var result := {}                     # {"winner": pid, "reason": D.Reason.*}; bos = devam
var match_running := false


func reset(p_seed: int) -> void:
	my_pid = my_pid  # pid'i Net yonetir; burada dokunma
	seed_v = p_seed
	grid = PackedInt32Array()
	map_hash = 0
	spawns = []
	res = {1: D.START_RES.duplicate(true), 2: D.START_RES.duplicate(true)}
	pop_used = {1: 0, 2: 0}
	pop_cap = {1: 0, 2: 0}
	war_state = D.War.PEACE
	war_t_left = 0.0
	entities = {}
	result = {}
	match_running = false


func enemy_of(pid: int) -> int:
	return 2 if pid == 1 else 1


func my_res() -> Dictionary:
	return res[my_pid]


func ent(id: int) -> Node:
	return entities.get(id)


func can_afford(pid: int, cost: Dictionary) -> bool:
	for kind in cost:
		if res[pid].get(kind, 0.0) < cost[kind]:
			return false
	return true


func pay(pid: int, cost: Dictionary) -> void:
	for kind in cost:
		res[pid][kind] -= cost[kind]
	Bus.resources_changed.emit(pid)


func refund(pid: int, cost: Dictionary) -> void:
	for kind in cost:
		res[pid][kind] += cost[kind]
	Bus.resources_changed.emit(pid)


func grid_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= D.MAP_W or cell.y >= D.MAP_H:
		return -1
	return grid[cell.y * D.MAP_W + cell.x]


func grid_set(cell: Vector2i, val: int) -> void:
	grid[cell.y * D.MAP_W + cell.x] = val
