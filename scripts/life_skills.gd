extends RefCounted
## Host-owned life work. Only completed timed attempts grant resources; no offline accrual.
const Data = preload("res://scripts/content.gd")
const COMMANDS := ["生活學習", "生活工作"]
const FEATURES := {"FIELD": "農田", "WOOD": "林地", "WATER": "水域", "STOVE": "灶台", "MINE": "礦場", "FORGE": "打鐵爐", "CAST": "鑄劍爐", "LOOM": "織布機", "TANNERY": "烘皮爐", "KILN": "炭窯", "HUNT": "獵場", "": "隨地可做"}
var _owner: WeakRef
var world:
	get: return _owner.get_ref()

func _init(owner) -> void:
	_owner = weakref(owner)

static func recipe(skill: String, key: String) -> Dictionary:
	for r in Data.LIFE.get(skill, {}).get("recipes", []):
		if r.id == key: return r
	return {}

static func feature(row: Dictionary, r: Dictionary) -> String:
	return str(r.get("feature", row.get("feature", "")))

static func tools(row: Dictionary, r: Dictionary) -> Array:
	var result: Array = []
	for item in [row.get("tool", "")] + row.get("tools", []) + r.get("tools", []):
		if item != "" and not item in result: result.append(item)
	return result

static func cost(row: Dictionary, r: Dictionary) -> int:
	return int(r.get("jing_cost", row.get("jing_cost", 5)))

static func chance(level: int) -> float:
	return minf(.95, .5 + level * .005)

static func locations(skill: String, key: String, start: String) -> Array:
	var row: Dictionary = Data.LIFE.get(skill, {})
	var required := feature(row, recipe(skill, key))
	var found: Array = []
	if required == "": return [{"place": start, "steps": 0}]
	for place in Data.FACILITIES:
		if not required in Data.FACILITIES[place].features: continue
		var route := Data.path_to(start, place)
		if route.is_empty() and place != start: continue
		found.append({"place": place, "steps": route.size()})
	found.sort_custom(func(a, b): return a.steps < b.steps or (a.steps == b.steps and a.place < b.place))
	return found

static func reason(p: Dictionary, skill: String, key: String, check_energy: bool = true) -> String:
	if not Data.LIFE.has(skill): return "生活技能不存在。"
	var row: Dictionary = Data.LIFE[skill]
	var r := recipe(skill, key)
	if (key != "" and r.is_empty()) or (key == "" and row.mode == "CRAFT"): return "請先選擇配方。"
	if int(p.get("dungeon", 0)) != 0: return "請先退出副本。"
	if not p.enemy.is_empty() or int(p.fight) != 0: return "請先結束戰鬥。"
	if p.follow: return "請先取消跟隨隊長。"
	if p.travel_target != "": return "正在趕路，到達後再開工。"
	if int(p.hp) <= 0: return "請先療傷。"
	var required := feature(row, r)
	if required != "" and not required in Data.FACILITIES.get(p.place, {}).get("features", []): return "此地沒有%s，請前往工作地點。" % FEATURES[required]
	var lv := int(p.life_levels.get(skill, 0))
	if lv < 1: return "尚未學會，請先向生活師父請教。"
	for item in tools(row, r):
		if int(p.inventory.get(item, 0)) < 1: return "缺少工具：" + str(item)
	if lv < int(r.get("min_level", 1)): return "需要 %s %d 級。" % [row.name, r.min_level]
	if check_energy and int(p.energy) < cost(row, r): return "精力不足，請打坐恢復後重新開工。"
	for item in r.get("inputs", []):
		if int(p.inventory.get(item.item, 0)) < int(item.n): return "材料不足：%s × %d（持有 %d）。" % [item.item, item.n, int(p.inventory.get(item.item, 0))]
	if row.mode == "HUNT" and key == "":
		if Data.FACILITIES.get(p.place, {}).get("hunt_table", []).is_empty(): return "此處沒有可獵的野獸。"
		if int(p.hp) * 4 < int(p.max_hp): return "氣血不足四分之一，請先療傷。"
	return ""

func act(id: int, command: String, arg: String) -> bool:
	var p: Dictionary = world.players[id]
	var parts := arg.split("|", true)
	if command == "生活學習":
		if parts.size() != 2 or not Data.LIFE.has(parts[0]): return world.reject(id, "請選擇生活技能與師父。")
		if world.social.busy(id) or p.travel_target != "": return world.reject(id, "請先停下趕路並結束戰鬥。")
		if int(p.life_levels.get(parts[0], 0)) > 0: return world.reject(id, "已學會此技能，實際工作可增加熟練。")
		for teacher in Data.LIFE[parts[0]].teachers:
			if teacher.npc_id != parts[1]: continue
			if not teacher.npc_id in Data.local_npcs(p.place): return world.reject(id, "請先到生活師父身邊。")
			if int(p.silver) < int(teacher.price): return world.reject(id, "學藝需要 %d 兩。" % int(teacher.price))
			stop(id, "改學生活技藝。")
			p.auto = "停止"
			p.study_ticks = 0
			p.silver -= int(teacher.price)
			p.life_levels[parts[0]] = 1
			p.life_prof[parts[0]] = 2
			var tool: String = teacher.get("tool", "")
			if tool != "" and int(p.inventory.get(tool, 0)) == 0: p.inventory[tool] = 1
			world.tell(id, "向%s學會%s（1級），學費 %d 兩%s。" % [Data.NPCS[teacher.npc_id].name, Data.LIFE[parts[0]].name, teacher.price, "，獲贈" + tool if tool != "" else ""], "生活")
			return true
		return world.reject(id, "這位師父不傳授此生活技藝。")
	if parts.size() not in [3, 4] or not parts[2].is_valid_int(): return world.reject(id, "工作格式：技能|配方|次數|休息或自停，0 表示持續。")
	if parts.size() == 4 and not parts[3] in ["休息", "自停"]: return world.reject(id, "請選擇精力不足時休息或自停。")
	var auto_rest := parts.size() == 4 and parts[3] == "休息"
	var count := parts[2].to_int()
	if count < 0 or count > 999: return world.reject(id, "次數範圍為 0–999。")
	if p.life_work.get("active", false): return world.reject(id, "已有工作進行中，請先停止。")
	if p.travel_target != "": return world.reject(id, "請抵達工作地點後再開工。")
	var why := reason(p, parts[0], parts[1], not auto_rest)
	if why != "": return world.reject(id, why)
	var row: Dictionary = Data.LIFE[parts[0]]
	p.life_work = {"active": true, "skill": parts[0], "recipe": parts[1], "place": p.place, "limit": count, "done": 0, "successes": 0, "gained": {}, "due": world.tick + int(row.cooldown_s), "message": "工作中", "auto_rest": auto_rest, "resting": auto_rest and int(p.energy) < cost(row, recipe(parts[0], parts[1]))}
	p.auto = "生活"
	p.study_ticks = 0
	world.tell(id, "%s開工：%s，每次 %d 息；%s。按停止可取消未完成的一次。" % [row.name, recipe(parts[0], parts[1]).get("name", row.verb), row.cooldown_s, "持續至精力或材料不足" if count == 0 else "完成 %d 次嘗試後停止" % count], "生活")
	return true

func stop(id: int, message: String) -> void:
	var p: Dictionary = world.players[id]
	if not p.life_work.get("active", false): return
	p.life_work.active = false
	p.life_work.message = message
	if p.auto == "生活": p.auto = "停止"
	world.tell(id, "生活掛機停止：%s（已嘗試 %d 次、成功 %d 次）" % [message, p.life_work.done, p.life_work.successes], "生活")

func guard(id: int) -> void:
	var p: Dictionary = world.players[id]
	if not p.life_work.get("active", false): return
	if p.auto != "生活" or p.place != p.life_work.place or p.follow or int(p.fight) != 0 or int(p.dungeon) != 0 or p.travel_target != "" or (not p.enemy.is_empty() and not p.enemy.get("life_hunt", false)):
		stop(id, "行程、戰鬥或其他活動中斷工作。")

func step(id: int) -> void:
	var p: Dictionary = world.players[id]
	var job: Dictionary = p.life_work
	if not job.get("active", false): return
	if job.resting:
		var blocked := reason(p, job.skill, job.recipe, false)
		if blocked != "": stop(id, blocked); return
		p.energy = mini(100, int(p.energy) + 5)
		p.hp = mini(int(p.max_hp), int(p.hp) + 9)
		p.mp = mini(int(p.max_mp), int(p.mp) + 7)
		p.spirit = mini(int(p.max_spirit), int(p.spirit) + 5)
		if int(p.energy) == 100:
			job.resting = false
			job.due = world.tick + int(Data.LIFE[job.skill].cooldown_s)
			world.tell(id, "調息完畢，繼續生活工作；下一次仍須完整工作時間。", "生活")
		return
	if world.tick < int(job.due): return
	var why := reason(p, job.skill, job.recipe)
	if why != "":
		if rest_needed(id, p): return
		stop(id, why)
		return
	var row: Dictionary = Data.LIFE[job.skill]
	var r := recipe(job.skill, job.recipe)
	p.energy -= cost(row, r)
	if row.mode == "HUNT" and job.recipe == "":
		var table: Array = Data.FACILITIES[p.place].hunt_table
		var total := 0
		for e in table: total += int(e.w)
		var roll: int = world.rng.randi_range(1, total)
		var name := ""
		for e in table:
			roll -= int(e.w)
			if roll <= 0: name = e.enemy; break
		var enemy: Dictionary = Data.ENEMIES[name].duplicate(true)
		enemy.merge({"name": name, "max_hp": enemy.hp, "life_hunt": true})
		p.enemy = enemy
		p.life_hunt = {"enemy": name}
		world.tell(id, "打獵遇上%s，開始實戰；勝利才可剝取材料。" % name, "生活")
		return
	var level_before := int(p.life_levels[job.skill])
	var success: bool = world.rng.randf() < chance(level_before)
	practice(p, job.skill, success, int(r.get("prof", 1)) if success else 1)
	if success:
		if not r.is_empty():
			for item in r.inputs: p.inventory[item.item] -= int(item.n)
			give(p, r.output.item, int(r.output.n))
		else: roll_drops(p, row.get("yield", []), job.skill, "", level_before)
	complete(id, success)

static func practice(p: Dictionary, skill: String, success: bool, times: int = 1) -> void:
	var prof := int(p.life_prof.get(skill, 2)) + (5 if success else 2) * times
	var lv := int(p.life_levels[skill])
	while lv < int(Data.LIFE[skill].get("cap", 100)) and 2 * (lv + 1) * (lv + 1) <= prof: lv += 1
	p.life_prof[skill] = prof
	p.life_levels[skill] = lv

func give(p: Dictionary, item: String, count: int) -> void:
	if count <= 0: return
	p.inventory[item] = int(p.inventory.get(item, 0)) + count
	p.life_work.gained[item] = int(p.life_work.gained.get(item, 0)) + count

func roll_drops(p: Dictionary, drops: Array, skill: String, enemy: String = "", level: int = -1) -> void:
	if level < 0: level = int(p.life_levels[skill])
	for item in drops:
		if level < int(item.get("min_level", 1)): continue
		if not item.get("monsters", []).is_empty() and not enemy in item.monsters: continue
		if world.rng.randf() >= float(item.get("chance", 1.0)): continue
		var n: Variant = item.get("n", 1)
		give(p, item.item, world.rng.randi_range(int(n[0]), int(n[1])) if n is Array else int(n))

func complete(id: int, success: bool) -> void:
	var p: Dictionary = world.players[id]
	var job: Dictionary = p.life_work
	job.done += 1
	if success: job.successes += 1
	job.due = world.tick + int(Data.LIFE[job.skill].cooldown_s)
	world.tell(id, "%s第 %d 次：%s，熟練 +%d，目前 %d 級。" % [Data.LIFE[job.skill].name, job.done, "成功" if success else "未成功（保留製作材料）", (5 * int(recipe(job.skill, job.recipe).get("prof", 1))) if success else 2, p.life_levels[job.skill]], "生活")
	if int(job.limit) > 0 and int(job.done) >= int(job.limit): stop(id, "已達指定次數。")
	elif job.get("active", false):
		var why := reason(p, job.skill, job.recipe)
		if why != "" and not rest_needed(id, p): stop(id, why)

func rest_needed(id: int, p: Dictionary) -> bool:
	var job: Dictionary = p.life_work
	if not job.get("auto_rest", false) or int(p.energy) >= cost(Data.LIFE[job.skill], recipe(job.skill, job.recipe)): return false
	if reason(p, job.skill, job.recipe, false) != "": return false
	job.resting = true
	world.tell(id, "精力不足，自動打坐；精力回滿後續作，可隨時停止。", "生活")
	return true

func hunt_result(id: int, won: bool) -> void:
	var p: Dictionary = world.players[id]
	if p.life_hunt.is_empty(): return
	var enemy: String = p.life_hunt.enemy
	p.life_hunt = {}
	practice(p, "life_hunting", won)
	if won: roll_drops(p, Data.LIFE.life_hunting.hunt.drops, "life_hunting", enemy)
	complete(id, won)
	if not won: stop(id, "打獵失敗或撤退，請先療傷。")
