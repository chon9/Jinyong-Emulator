extends SceneTree
const Data = preload("res://scripts/content.gd")
var checks := 0
var failures: Array = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	var session = root.get_node("Session")
	session.save_path = "res://test-results/quest-clock-save.json"
	var p: Dictionary = session.world.add_player(1)
	p.sect = "全真"
	p.place = Data.NPCS["n_xx_litaian"].place
	var q: Dictionary = Data.QUESTS.q_qz_wangchuyi
	p.learning_quests[q.id] = {"stage": 1, "done": {}, "started": 910, "vars": {}, "effects": {}, "dialogue": ""}
	session.world.tick = 1000
	check(session.save_game(), "Wait checkpoint saves")
	session.world.players.clear()
	session.world.tick = 0
	session.local_character = {}
	session.local_tick = 0
	session._load()
	session.start_offline()
	p = session.world.players[1]
	check(session.world.tick == 1000 and int(p.learning_quests[q.id].started) == 910, "Restart restores world time and elapsed quest wait")
	session.world.tick += 90
	session.world.quests.settle(1, q.id)
	check(q.stages[int(p.learning_quests[q.id].stage)].id == "s_fetch", "Saved wait finishes after only the remaining duration")
	p.learning_quests[q.id].stage = 1
	p.learning_quests[q.id].started = 1000
	var legacy := FileAccess.open(session.save_path, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"version": 1, "character": p, "guests": {}}))
	legacy.close()
	session.world.players.clear()
	session.world.tick = 0
	session.local_character = {}
	session._load()
	session.start_offline()
	p = session.world.players[1]
	check(session.world.tick == 0 and int(p.learning_quests[q.id].started) <= 0, "Legacy wait checkpoints are normalized into the restored clock")
	var result := FileAccess.open("res://test-results/quest-save-result.json", FileAccess.WRITE)
	result.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	result.close()
	print("QUEST SAVE: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
