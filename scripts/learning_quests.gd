extends RefCounted
## Host-owned staged adaptations of the reference project's learning events.
const Data = preload("res://scripts/content.gd")
const Training = preload("res://scripts/progression.gd")
const Guide = preload("res://scripts/quest_guide.gd")
var owner: WeakRef
var world:
	get: return owner.get_ref()

func _init(value) -> void:
	owner = weakref(value)

func act(id: int, command: String, arg: String) -> bool:
	var p: Dictionary = world.players[id]
	var parts := arg.split("|", false, 1)
	if parts.is_empty() or not Data.QUESTS.has(parts[0]): return world.reject(id, "沒有這個學藝機緣。")
	var q: Dictionary = Data.QUESTS[parts[0]]
	if command == "任務對話": return choose(id, q, parts[1] if parts.size() > 1 else "")
	if command == "接受任務":
		if p.quests_done.has(q.id) or p.learning_quests.has(q.id): return world.reject(id, "已接受或已完成此機緣。")
		if Guide.support_reason(q) != "": return world.reject(id, Guide.support_reason(q))
		if not q.giver in Data.local_npcs(p.place): return world.reject(id, "請先到任務發起人身邊。")
		var reason := Training.check(p, q.conditions, world.tick)
		if reason != "": return world.reject(id, "機緣需要：" + reason)
		p.learning_quests[q.id] = {"stage": 0, "done": {}, "started": world.tick, "vars": {}, "effects": {}, "dialogue": "", "node": "", "npc": ""}
		for item in q.get("give_items", []): p.inventory[item.item] = int(p.inventory.get(item.item, 0)) + int(item.n)
		world.tell(id, "接受【%s】：%s" % [q.name, q.stages[0].log], "機緣")
		if q.get("dialogues", {}).has("d_offer"): return act(id, "任務緣起", q.id)
		return true
	if not p.learning_quests.has(q.id): return world.reject(id, "請先接受這份學藝機緣。")
	var state: Dictionary = p.learning_quests[q.id]
	if command == "任務緣起":
		if int(state.stage) != 0 or not q.giver in Data.local_npcs(p.place): return world.reject(id, "請到發起人身邊詢問。")
		if not q.get("dialogues", {}).has("d_offer"): return false
		state.dialogue = "d_offer"
		state.node = q.dialogues.d_offer.get("start", "n0")
		state.npc = q.giver
		return present(id, q)
	if command == "任務結局":
		if int(state.stage) < q.stages.size() or parts.size() < 2 or not q.outcomes.has(parts[1]): return false
		var outcome: Dictionary = q.outcomes[parts[1]]
		if str(state.get("outcome", parts[1])) != parts[1]: return world.reject(id, "這不是你在機緣中選定的結局。")
		var rewards: Dictionary = outcome.rewards
		var new_arts := 0
		for skill in rewards.get("learn", {}):
			if int(p.skills.get(skill, 0)) == 0 and not Data.SKILLS.get(skill, {}).get("basic", false) and Data.SKILLS.get(skill, {}).get("category", "SECT") != "SECT": new_arts += 1
		if Training.special_count(p) + new_arts > 16: return world.reject(id, "特殊武功已達十六套，無法領取新的武功。")
		for flag in rewards.get("flags", []): p.flags[flag] = true
		for skill in rewards.get("learn", {}): p.skills[skill] = maxi(int(p.skills.get(skill, 0)), int(rewards.learn[skill]))
		for skill in rewards.get("learn_add", {}): p.skills[skill] = int(p.skills.get(skill, 0)) + int(rewards.learn_add[skill])
		for skill in rewards.get("skill_prof", {}): Training.add_prof(p, skill, int(rewards.skill_prof[skill]), Training.xp_cap(p))
		for pair in [["money", "silver"], ["learn_points", "potential"], ["combat_xp", "combat_xp"], ["fame", "fame"], ["lilian", "lilian"], ["morality", "morality"]]:
			if rewards.has(pair[0]): p[pair[1]] += int(rewards[pair[0]])
		if rewards.has("sect_rank"): p.sect_rank = maxi(int(p.sect_rank), int(rewards.sect_rank))
		for item in rewards.get("items", []): p.inventory[item.item] = int(p.inventory.get(item.item, 0)) + int(item.n)
		p.quests_done[q.id] = parts[1]
		p.learning_quests.erase(q.id)
		world.tell(id, "完成【%s】：%s。" % [q.name, outcome.label], "機緣")
		return true
	if parts.size() < 2 or int(state.stage) >= q.stages.size(): return false
	var stage: Dictionary = q.stages[int(state.stage)]
	var objective: Dictionary = {}
	for o in stage.objectives:
		if o.id == parts[1]: objective = o; break
	if objective.is_empty() or state.done.has(objective.id): return false
	var npc: String = Guide.npc_of(objective)
	if npc != "" and not npc in Data.local_npcs(p.place): return world.reject(id, "請先前往這一步的指定人物身邊。")
	if npc == "" and stage.place != "" and p.place != stage.place: return world.reject(id, "請先前往" + stage.place)
	var reason := Training.check(p, objective.get("requires", []), world.tick)
	if reason != "": return world.reject(id, reason)
	match str(objective.type):
		"TALK":
			if not Data.NPCS.has(npc): return world.reject(id, "這段人物流程尚未開放，不能略過。")
			if q.get("dialogues", {}).has(objective.get("dialogue", "")):
				state.dialogue = objective.dialogue
				state.npc = npc
				state.node = q.dialogues[objective.dialogue].get("start", "n0")
				return present(id, q)
			world.talk(id, npc)
		"STATE":
			if objective.get("requires", []).is_empty(): return world.reject(id, "這段條件流程尚未開放。")
		"WAIT":
			var seconds := ceili(float(objective.get("days", 0)) * 1440)
			if world.tick - int(state.started) < seconds: return world.reject(id, "尚需等待 %d 息。" % (seconds - world.tick + int(state.started)))
		"COLLECT", "DELIVER", "BUY":
			var item: String = objective.get("item", "")
			var count := int(objective.get("count", objective.get("n", 1)))
			if int(p.inventory.get(item, 0)) < count: return world.reject(id, "需要%s × %d，尚未取得。" % [item, count])
			if objective.type == "DELIVER": p.inventory[item] -= count
		"FIGHT":
			for earlier in stage.objectives:
				if earlier.type == "TALK" and not state.done.has(earlier.id): return world.reject(id, "先和考較人物交談。")
			var enemies: Array = objective.get("enemies", []).duplicate()
			if objective.get("target", "").begins_with("m_") and enemies.size() == 1:
				for repeat in maxi(0, int(objective.get("count", 1)) - 1): enemies.append(enemies[0])
			if enemies.is_empty(): return world.reject(id, "這段考較的敵人資料尚未開放，不能略過。")
			var enemy: Dictionary = Data.ENEMIES[enemies[0]].duplicate(true)
			enemy.merge({"name": "機緣考較 · " + str(enemies[0]), "max_hp": enemy.hp, "quest_id": q.id, "quest_objective": objective.id, "quest_any": objective.get("win", "WIN") == "ANY", "quest_enemies": enemies.slice(1), "exp": 0, "combat_xp": 0, "potential": 0, "silver": 0, "drops": []}, true)
			p.quest_restore = {"hp": p.hp, "mp": p.mp, "place": p.place}
			p.enemy = enemy
			p.auto = "停止"
			world.tell(id, "開始【%s】考較。%s" % [q.name, "勝負不拘，可逃跑結束考較。" if enemy.quest_any else "必須勝出。"], "戰鬥")
			return true
		_: return world.reject(id, "這段護送或特殊互動流程尚未開放，不能直接跳過。")
	state.done[objective.id] = true
	advance(id, q.id)
	return true

func advance(id: int, quest: String) -> void:
	var p: Dictionary = world.players[id]
	var state: Dictionary = p.learning_quests[quest]
	var q: Dictionary = Data.QUESTS[quest]
	var stage: Dictionary = q.stages[int(state.stage)]
	for o in stage.objectives:
		if not state.done.has(o.id): return
	if not effects(id, q, stage.get("on_complete", []), "stage-complete"): return
	var next: Variant = stage.get("next", "")
	var destination := ""
	if next is String: destination = next
	elif next is Array:
		for branch in next:
			if Training.check(p, branch.get("if", []), world.tick) == "": destination = branch.get("goto", ""); break
	if destination.begins_with("END"):
		state.outcome = destination.trim_prefix("END:") if destination.begins_with("END:") else "default"
		state.stage = q.stages.size()
	elif destination != "":
		for index in q.stages.size():
			if q.stages[index].id == destination: state.stage = index; break
	else: state.stage += 1
	state.done = {}
	state.started = world.tick
	state.dialogue = ""
	state.node = ""
	state.npc = ""
	world.tell(id, "【%s】%s" % [q.name, q.stages[int(state.stage)].log if int(state.stage) < q.stages.size() else "考較完成，請在機緣頁選擇結局並領取傳授。"], "機緣")

func choose(id: int, q: Dictionary, choice: String) -> bool:
	var p: Dictionary = world.players[id]
	if not p.learning_quests.has(q.id): return false
	var state: Dictionary = p.learning_quests[q.id]
	if not state.get("npc", "") in Data.local_npcs(p.place): return world.reject(id, "請留在交談人物身邊。")
	var dialogue: Dictionary = q.get("dialogues", {}).get(state.get("dialogue", ""), {})
	var node: Dictionary = dialogue.get("nodes", {}).get(state.get("node", ""), {})
	for option in node.get("choices", []):
		if option.id != choice: continue
		var reason := Training.check(p, option.get("requires", []), world.tick)
		if reason != "": return world.reject(id, reason)
		if not effects(id, q, option.get("do", []), str(state.node) + ":" + choice): return false
		if not p.learning_quests.has(q.id): return true
		state.node = option.get("goto", "END")
		return present(id, q)
	return false

func present(id: int, q: Dictionary) -> bool:
	var p: Dictionary = world.players[id]
	var state: Dictionary = p.learning_quests[q.id]
	for iteration in 64:
		if state.node == "" or str(state.node).begins_with("END"):
			state.dialogue = ""
			state.node = ""
			if int(state.stage) < q.stages.size(): advance(id, q.id)
			return true
		var node: Dictionary = q.dialogues.get(state.dialogue, {}).get("nodes", {}).get(state.node, {})
		if node.is_empty(): return world.reject(id, "這段對話資料缺失，沒有跳過此步驟。")
		if not effects(id, q, node.get("do", []), str(state.node)): return false
		if not p.learning_quests.has(q.id): return true
		world.tell(id, str(node.get("text", "")), "機緣")
		if not node.get("choices", []).is_empty(): return true
		state.node = node.get("goto", "END")
	return world.reject(id, "對話循環過長，已停止。")

func effects(id: int, q: Dictionary, actions: Array, context: String) -> bool:
	var p: Dictionary = world.players[id]
	var state: Dictionary = p.learning_quests[q.id]
	if not state.has("effects"): state.effects = {}
	# Check all inventory deductions before applying a dialogue action batch.
	var deductions := {}
	for action in actions:
		if action.get("do", "") == "take": deductions[action.item] = int(deductions.get(action.item, 0)) + int(action.get("n", 1))
	for item in deductions:
		if int(p.inventory.get(item, 0)) < int(deductions[item]): return world.reject(id, "尚缺 " + str(item))
	for index in actions.size():
		var action: Dictionary = actions[index]
		var key := "%d|%s|%s|%d" % [int(state.stage), state.dialogue, context, index]
		if state.effects.has(key): continue
		match str(action.get("do", "")):
			"accept": pass
			"complete": state.done[action.obj] = true
			"var":
				var choices: Array = action.get("random", [])
				state.vars[action.name] = choices[world.rng.randi_range(0, choices.size() - 1)] if not choices.is_empty() else action.get("value")
			"give": p.inventory[action.item] = int(p.inventory.get(action.item, 0)) + int(action.get("n", 1))
			"take": p.inventory[action.item] -= int(action.get("n", 1))
			"learn":
				if not Data.SKILLS.has(action.skill): return world.reject(id, "此技能資料尚未開放。")
				if int(p.skills.get(action.skill, 0)) == 0 and Training.special_count(p) >= 16 and not Data.SKILLS[action.skill].get("basic", false) and Data.SKILLS[action.skill].category != "SECT": return world.reject(id, "特殊武功已達十六套。")
				p.skills[action.skill] = maxi(int(p.skills.get(action.skill, 0)), int(action.get("level", 1)))
			"fight":
				state.effects[key] = true
				return act(id, "任務行動", q.id + "|" + str(action.obj))
			"fail":
				p.learning_quests.erase(q.id)
				world.tell(id, "這次機緣未能完成，可重新接受。", "機緣")
				return true
			"tell": world.tell(id, str(action.get("text", "請依任務線索繼續行動。")), "機緣")
			_: return world.reject(id, "此特殊對話效果尚未開放，沒有跳過。")
		state.effects[key] = true
	return true

func fight_result(id: int, quest: String, objective: String, success: bool) -> void:
	var p: Dictionary = world.players[id]
	if not p.learning_quests.has(quest): return
	if not p.quest_restore.is_empty():
		p.hp = int(p.quest_restore.hp)
		p.mp = int(p.quest_restore.mp)
		p.place = str(p.quest_restore.place)
		p.quest_restore = {}
	if not success: world.tell(id, "考較未通過，可調息後重試。", "機緣"); return
	var state: Dictionary = p.learning_quests[quest]
	state.done[objective] = true
	advance(id, quest)
