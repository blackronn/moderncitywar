extends Node
## Global sinyal hatti: sim/ag katmani UI'dan tamamen kopuk kalir.
## Yayinlayan Bus.<sinyal>.emit(...) cagirir, dinleyen connect eder.

@warning_ignore_start("unused_signal")

signal toast(msg: String)
signal match_started
signal war_changed(state: int, t_left: float)
signal resources_changed(pid: int)
signal selection_changed(ids: Array)
signal entity_spawned(node: Node)
signal entity_removed(id: int, reason: int)
signal game_over(winner_pid: int, reason: int)
signal lobby_status(msg: String)
signal net_error(msg: String)
signal build_rejected(reason: int)

@warning_ignore_restore("unused_signal")
