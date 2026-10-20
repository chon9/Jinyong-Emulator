extends SceneTree
const Data = preload("res://scripts/content.gd")
const Rules = preload("res://scripts/world.gd")
const Training = preload("res://scripts/progression.gd")
var checks := 0
var failures: Array = []
var cases: Dictionary
var results: Array = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok: failures.append(description); push_error(description)
	return ok

func travel(w, p: Dictionary, destination: String) -> bool:
	if p.place != destination and Data.path_to(p.place, destination).is_empty(): return false
	for place in Data.path_to(p.place, destination):
		if not w.act(1, "前往", place): return false
	return p.place == destination

func play(w, p: Dictionary, qid: String) -> bool:
	var q: Dictionary = Data.QUESTS[qid]
	var test: Dictionary = cases[qid]
	for condition in q.conditions:
		if condition.type == "quest_done" and not p.quests_done.has(condition.quest):
			if not cases.has(condition.quest) or not play(w, p, condition.quest): return false
	var setup: Dictionary = test.setup
	p.sect = setup.sect
	for name in ["morality", "fame", "lilian", "combat_xp", "sect_rank", "gender"]:
		if setup.has(name): p[name] = setup[name]
	for key in setup.get("attrs", {}): p.attrs[key] = setup.attrs[key]
	for skill in setup.get("skills", {}): p.skills[skill] = int(setup.skills[skill])
	for item in setup.items: p.inventory[item] = int(setup.items[item])
	for req in q.conditions:
		if req.type == "skill_min": p.skills[req.skill] = maxi(int(p.skills.get(req.skill, 0)), int(req.value))
		if req.type == "quest_flag": p.flags[req.flag] = true
		if req.type == "combat_xp_max": p.combat_xp = mini(int(p.combat_xp), int(req.value))
	var initial: Dictionary = p.inventory.duplicate(true)
	var messages: Array = []
	w.event.connect(func(_id, _channel, text): messages.append(text))
	for instruction in test.path:
		var ok := true
		if instruction.begins_with("walk@"):
			ok = travel(w, p, instruction.trim_prefix("walk@"))
		elif instruction.begins_with("accept@"):
			ok = w.act(1, "接受任務", qid)
		elif instruction.begins_with("reopen@"):
			ok = w.act(1, "任務緣起", qid)
		elif instruction.begins_with("choose@"):
			var tokens: PackedStringArray = instruction.trim_prefix("choose@").split(":")
			var state: Dictionary = p.learning_quests.get(qid, {})
			ok = state.get("node", "") == tokens[1] and w.act(1, "任務對話", qid + "|" + tokens[2])
		elif instruction.begins_with("talk@"):
			var npc: String = instruction.trim_prefix("talk@")
			var state: Dictionary = p.learning_quests.get(qid, {})
			ok = false
			if not state.is_empty() and int(state.stage) < q.stages.size():
				for o in q.stages[int(state.stage)].objectives:
					if Rules.Quests.Guide.npc_of(o) == npc and not state.done.has(o.id):
						ok = w.act(1, "任務行動", qid + "|" + o.id)
						break
		elif instruction.begins_with("act@"):
			ok = w.act(1, "任務場景", instruction.trim_prefix("act@").replace(":", "|"))
		elif instruction.begins_with("wait:hour="):
			var hour: String = instruction.trim_prefix("wait:hour=")
			var offset: int = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"].find(hour) * 120
			w.tick = int(w.tick / 1440) * 1440 + offset
		elif instruction.begins_with("wait:days="):
			w.tick += ceili(float(instruction.trim_prefix("wait:days=")) * 1440)
		elif instruction.begins_with("expect_stage:"):
			ok = q.stages[int(p.learning_quests[qid].stage)].id == instruction.trim_prefix("expect_stage:")
		elif instruction.begins_with("fight:"):
			ok = not p.enemy.is_empty()
			if ok and instruction == "fight:FLEE": ok = w.act(1, "逃跑")
			elif ok:
				if instruction == "fight:DEFEAT": p.hp = 1; p.enemy.hp = 100000000; p.enemy.attack = 100000000
				var rounds := 0
				while not p.enemy.is_empty() and rounds < 2048:
					w.combat(1)
					rounds += 1
				ok = p.enemy.is_empty()
		else: ok = false
		if not check(ok, qid + " :: " + instruction + " :: " + str(messages.back() if not messages.is_empty() else "")): return false
		w.quests.settle(1, qid)
	var state: Dictionary = p.learning_quests.get(qid, {})
	if not check(not state.is_empty() and int(state.stage) >= q.stages.size(), qid + " reaches its real ending"): return false
	if not check(w.act(1, "任務結局", qid + "|" + test.outcome), qid + " awards the scripted outcome"): return false
	for item in test.expect_items:
		var n := int(test.expect_items[item])
		var expected := int(initial.get(item, 0)) + n if n < 0 else n
		check(int(p.inventory.get(item, 0)) == expected, "%s item %s: expected %d, got %d" % [qid, item, expected, int(p.inventory.get(item, 0))])
	for flag in test.expect_flags: check(p.flags.get(flag, false), qid + " unlock flag " + flag)
	check(p.quests_done.get(qid, "") == test.outcome, qid + " completion persists")
	if test.repeat_cooldown:
		travel(w, p, Data.NPCS[q.giver].place)
		check(not w.act(1, "接受任務", qid) and Rules.Quests.Guide.cooldown_left(p, q) > 0, qid + " repeat cooldown prevents duplicate payouts")
	return true

func run() -> void:
	cases = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/quest_paths.json"))
	for qid in cases:
		var w := Rules.new()
		w.rng.seed = 20261020
		var p: Dictionary = w.add_player(1)
		p.inventory = {}
		p.attrs = {"str": 150, "wit": 150, "con": 150, "agi": 150, "cal": 150, "guts": 150, "luck": 150}
		p.skills.merge({"搏擊格鬥": 120, "基本內功": 120, "閃躲縱躍": 120, "拆招卸力": 120}, true)
		p.combat_xp = 1000000
		p.fame = 10000
		p.lilian = 10000
		p.max_hp = 1000000
		p.hp = p.max_hp
		p.max_mp = 1000000
		p.mp = p.max_mp
		var before := failures.size()
		var completed := play(w, p, qid)
		if completed and cases[qid].repeat_cooldown:
			p.quest_history[qid].until = 0
			check(Rules.Quests.Guide.status(p, Data.QUESTS[qid], w.tick) == "可接任務", qid + " becomes available again after cooldown")
			completed = play(w, p, qid)
			check(int(p.quest_history.get(qid, {}).get("count", 0)) == 2, qid + " records two real completions")
		results.append({"quest": qid, "completed": completed, "failures": failures.size() - before})
		print("QUEST PATH ", qid, " ", "PASS" if completed and before == failures.size() else "FAIL")
	var out := FileAccess.open("res://test-results/quest-paths-result.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": results}, "  "))
	out.close()
	print("QUEST PATHS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
