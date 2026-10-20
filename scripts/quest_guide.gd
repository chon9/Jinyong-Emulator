extends RefCounted
## Presentation queries; accepting, progressing and rewards stay on the host.
const Data = preload("res://scripts/content.gd")
const Training = preload("res://scripts/progression.gd")
const Market = preload("res://scripts/market.gd")

static func support_reason(q: Dictionary) -> String:
	for stage in q.stages:
		for o in stage.objectives:
			if not o.type in ["TALK", "STATE", "WAIT", "COLLECT", "DELIVER", "BUY", "FIGHT", "KILL"]: return "這條任務的後續內容尚未開放。"
			if o.type == "FIGHT" and o.get("enemies", []).is_empty(): return "這條任務的後續考較尚未開放。"
	return ""

static func status(p: Dictionary, q: Dictionary, tick: int) -> String:
	if p.learning_quests.has(q.id): return "進行中"
	if completion_limit(p, q): return "已完成"
	if cooldown_left(p, q) > 0: return "冷卻中"
	if support_reason(q) != "": return "尚未開放"
	return "可接任務" if Training.check(p, q.conditions, tick) == "" else "條件不足"

static func completion_limit(p: Dictionary, q: Dictionary) -> bool:
	var count := int(p.get("quest_history", {}).get(q.id, {}).get("count", 1 if p.quests_done.has(q.id) else 0))
	var maximum := int(q.get("repeat", {}).get("max", 1))
	return maximum > 0 and count >= maximum

static func cooldown_left(p: Dictionary, q: Dictionary) -> int:
	return maxi(0, int(p.get("quest_history", {}).get(q.id, {}).get("until", 0)) - int(Time.get_unix_time_from_system()))

static func accept_reason(p: Dictionary, q: Dictionary, tick: int) -> String:
	if completion_limit(p, q): return "此任務已完成。"
	var left := cooldown_left(p, q)
	if left > 0: return "再次接取尚需等待 %d 分 %d 秒。" % [left / 60, left % 60]
	var reason := support_reason(q)
	return reason if reason != "" else Training.check(p, q.conditions, tick)

static func npc_of(o: Dictionary) -> String:
	var npc: String = o.get("npc", o.get("target", ""))
	return npc if Data.NPCS.has(npc) else ""

static func place_of(stage: Dictionary, o: Dictionary) -> String:
	return str(o.get("place", Data.NPCS.get(npc_of(o), {}).get("place", stage.get("place", ""))))

static func current_objective(p: Dictionary, q: Dictionary) -> Dictionary:
	var state: Dictionary = p.learning_quests.get(q.id, {})
	if state.is_empty() or int(state.stage) >= q.stages.size(): return {}
	for o in q.stages[int(state.stage)].objectives:
		if not state.done.has(o.id): return o
	return {}

static func at_npc(p: Dictionary, npc: String) -> Array:
	var found: Array = []
	for q in Data.QUESTS.values():
		if completion_limit(p, q): continue
		if q.giver == npc and not p.learning_quests.has(q.id): found.append(q); continue
		var state: Dictionary = p.learning_quests.get(q.id, {})
		if state.is_empty(): continue
		if int(state.stage) >= q.stages.size():
			if q.giver == npc: found.append(q)
			continue
		for o in q.stages[int(state.stage)].objectives:
			if npc_of(o) == npc and not state.done.has(o.id): found.append(q); break
	return found

static func objective_reason(p: Dictionary, stage: Dictionary, o: Dictionary, tick: int, state: Dictionary) -> String:
	if not p.enemy.is_empty() or int(p.fight) != 0: return "交戰中，先結束戰鬥。"
	var destination := place_of(stage, o)
	if destination != "" and destination != p.place: return "請先前往 " + destination
	var reason := Training.check(p, o.get("requires", []), tick)
	if reason != "": return "尚缺：" + reason
	if o.type in ["COLLECT", "DELIVER", "BUY"]:
		var need := int(o.get("count", o.get("n", 1)))
		var have := int(p.inventory.get(o.get("item", ""), 0))
		if have < need: return "需要 %s × %d，目前 %d。" % [o.get("item", ""), need, have]
	if o.type == "WAIT":
		var left := ceili(float(o.get("days", 0)) * 1440) - (tick - int(state.started))
		if left > 0: return "尚需等待 %d 息。" % left
	if o.type == "FIGHT" and o.get("enemies", []).is_empty(): return "這段考較尚未開放。"
	if o.get("hours", []).size() > 0 and Training.check(p, [{"type": "hour_in", "hours": o.hours}], tick) != "": return "時辰尚未到：" + "、".join(o.hours)
	return ""

static func item_sources(start: String, item: String) -> Array:
	var found: Array = []
	for place in Data.PLACES:
		var room: Dictionary = Data.PLACES[place]
		var label := ""
		if item in Market.stock(place): label = "購買 " + item
		elif item in room.get("finds", []): label = "搜查尋找 " + item
		elif not room.safe:
			for enemy in room.get("enemies", []):
				if Data.ENEMIES.get(enemy, {}).get("drops", []).any(func(drop): return drop.get("item", "") == item): label = "擊敗" + enemy + "取得" + item; break
		if label == "": continue
		var route: Array = Data.path_to(start, place)
		if place != start and route.is_empty(): continue
		found.append({"place": place, "steps": route.size(), "label": label})
	found.sort_custom(func(a, b): return a.steps < b.steps if a.steps != b.steps else a.place < b.place)
	return found
