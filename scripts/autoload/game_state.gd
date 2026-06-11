extends Node
## Mac boyunca yasayan durum. Host'ta sim dogrudan mutasyon yapar;
## istemcide Net'ten gelen snapshot/event'ler gunceller.

const D := preload("res://scripts/autoload/defs.gd")

var my_pid := 1                      # 1 = host, 2..4 = istemciler (katilim sirasi)
var player_count := 2                # bu mactaki oyuncu sayisi (2-4)
var seed_v := 0
var grid := PackedInt32Array()       # guncel harita (tukenmeler islenmis), D.Tile.*
var map_type := 0                    # D.MapType.*
var map_hash := 0
var spawns: Array = []               # belediye sol-ust koseleri (oyuncu sirasiyla)
var res := {}                        # pid -> {"wood": float, ...}
var pop_used := {}
var pop_cap := {}
var war_state := D.War.PEACE
var war_t_left := 0.0
var entities := {}                   # id -> Node (unit.gd / building.gd)
var eliminated := {}                 # pid -> true (belediyesi dusen/ayrilan oyuncular)
var result := {}                     # {"winner": pid, "reason": D.Reason.*}; bos = devam
var match_running := false


func reset(p_seed: int, p_players := 2) -> void:
	my_pid = my_pid  # pid'i Net yonetir; burada dokunma
	player_count = clampi(p_players, 2, D.MAX_PLAYERS)
	seed_v = p_seed
	grid = PackedInt32Array()
	map_type = 0
	map_hash = 0
	spawns = []
	res = {}
	pop_used = {}
	pop_cap = {}
	for pid in player_ids():
		res[pid] = D.START_RES.duplicate(true)
		pop_used[pid] = 0
		pop_cap[pid] = 0
	war_state = D.War.PEACE
	war_t_left = 0.0
	entities = {}
	eliminated = {}
	result = {}
	match_running = false


func player_ids() -> Array:
	var out: Array = []
	for pid in range(1, player_count + 1):
		out.append(pid)
	return out


func alive_ids() -> Array:
	var out: Array = []
	for pid in player_ids():
		if not eliminated.has(pid):
			out.append(pid)
	return out


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
