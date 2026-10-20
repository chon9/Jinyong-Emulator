extends RefCounted
## Classic point/proficiency model. Exact undocumented coefficients are marked
## reconstruction in docs/RESTORATION.md, rather than claimed server formulas.
const Data = preload("res://scripts/content.gd")
const ATTRS := {"str": "臂力", "wit": "悟性", "agi": "機敏", "con": "根骨", "cal": "定力", "guts": "膽識", "luck": "福緣"}
const STUDY_SECONDS := 5
const STUDY_POINTS := 3

static func attrs(p: Dictionary) -> Dictionary:
	var a: Dictionary = p.get("attrs", {}).duplicate()
	for key in ATTRS: a[key] = int(a.get(key, 25))
	for entry in [["str", "搏擊格鬥", 15], ["con", "基本內功", 14], ["agi", "閃躲縱躍", 14], ["wit", "讀書識字", 10]]:
		a[entry[0]] += mini(int(entry[2]), int(p.skills.get(entry[1], 0)) / 10)
	for item in [p.get("weapon", ""), p.get("armor", "")]:
		for key in Data.SHOP.get(item, {}).get("attr_bonus", {}): a[key] += int(Data.SHOP[item].attr_bonus[key])
	return a

static func lesson_gain(p: Dictionary) -> int:
	return maxi(1, roundi(float(attrs(p).wit) / 2.0))

static func study_gain(p: Dictionary) -> int:
	return maxi(1, roundi(float(attrs(p).wit) * STUDY_POINTS / 4.0))

static func energy_cost(p: Dictionary) -> int:
	var wit := int(attrs(p).wit)
	return maxi(1, roundi(10.0 - (wit - 21) * (5.0 / 9.0) if wit <= 30 else 5.0 - (wit - 30) * .4))

static func needed(skill: String, level: int) -> int:
	var art: Dictionary = Data.SKILLS.get(skill, {})
	var n := float(level + 1)
	if art.get("curve", "") == "LITERACY": return maxi(1, ceili(pow(n + 3, 2) * 10))
	return maxi(1, ceili(pow(n, 3) * float(art.get("difficulty", 1.0)) - .000000001))

static func xp_cap(p: Dictionary) -> int:
	# Only the zero-XP level-5 rule is officially documented. Interpolation is
	# a reconstruction and deliberately separate from the confirmed rule.
	return mini(250, 5 + floori(sqrt(maxi(0, int(p.get("combat_xp", 0))) / 10.0)))

static func special_count(p: Dictionary) -> int:
	var count := 0
	for skill in p.skills:
		if int(p.skills[skill]) > 0 and not Data.SKILLS.get(skill, {}).get("basic", false) and Data.SKILLS.get(skill, {}).get("category", "SECT") != "SECT": count += 1
	return count

static func condition_text(c: Dictionary) -> String:
	var value := int(c.get("value", 0))
	match str(c.get("type", "")):
		"sect": return str(c.sect) + "弟子"
		"no_sect": return "尚未加入門派"
		"not_enemy_of": return "未與" + str(c.get("sect", "此門派")) + "結怨"
		"unmarried": return "尚未婚配"
		"not_flag": return "尚未完成：" + Data.flag_name(str(c.flag))
		"gender": return "男性" if c.value == "M" else "女性"
		"attr_min": return "%s至少 %d" % [ATTRS.get(c.attr, c.attr), value]
		"skill_min": return "%s至少 %d 級" % [c.skill, value]
		"skill_max": return "%s最多 %d 級" % [c.skill, value]
		"sect_master": return "師承 " + str(Data.NPCS.get(c.npc, {}).get("name", c.npc))
		"quest_flag": return "完成機緣：" + Data.flag_name(str(c.flag))
		"quest_done": return "完成任務：" + str(Data.QUESTS.get(c.quest, {}).get("name", c.quest))
		"sect_rank_min": return "門派位階至少 %d" % value
		"combat_xp_min": return "實戰至少 %d" % value
		"combat_xp_max": return "實戰最多 %d" % value
		"morality_min": return "善惡至少 %d" % value
		"morality_max": return "善惡最多 %d" % value
		"lilian_min": return "江湖歷練至少 %d" % value
		"hour_in": return "時辰：" + "／".join(c.hours)
		"has_item": return "持有 " + str(c.get("item", ""))
		"quest_var": return "完成當前任務步驟"
		"any_of": return "滿足任一前置條件"
	return "其他學習條件"

static func check(p: Dictionary, conditions: Array, tick: int = 0) -> String:
	for c in conditions:
		var ok := false
		var value := int(c.get("value", 0))
		match str(c.get("type", "")):
			"sect": ok = p.sect == c.sect
			"no_sect": ok = p.sect == "江湖散人"
			"gender": ok = p.get("gender", "M") == c.value
			"attr_min": ok = int(attrs(p).get(c.attr, 0)) >= value
			"skill_min": ok = int(p.skills.get(c.skill, 0)) >= value
			"skill_max": ok = int(p.skills.get(c.skill, 0)) <= value
			"sect_master": ok = p.get("sect_master", "") == c.npc
			"sect_rank_min": ok = int(p.get("sect_rank", 1)) >= value
			"combat_xp_min": ok = int(p.get("combat_xp", 0)) >= value
			"combat_xp_max": ok = int(p.get("combat_xp", 0)) <= value
			"lilian_min": ok = int(p.get("lilian", 0)) >= value
			"fame_min": ok = int(p.get("fame", 0)) >= value
			"morality_min": ok = int(p.get("morality", 0)) >= value
			"morality_max": ok = int(p.get("morality", 0)) <= value
			"quest_flag": ok = bool(p.get("flags", {}).get(c.flag, false))
			"not_flag": ok = not bool(p.get("flags", {}).get(c.flag, false))
			"quest_done": ok = p.get("quests_done", {}).has(c.quest)
			"quest_var": ok = p.get("learning_quests", {}).get(c.quest, {}).get("vars", {}).get(c.var) == c.get("value")
			"not_enemy_of": ok = true # No betrayal/enemy system exists in this simulator.
			"unmarried": ok = true # Marriage is not implemented; all characters are unmarried.
			"pk_max": ok = int(p.get("pk_value", 0)) <= value
			"killing_intent_max": ok = int(p.get("killing_intent", 0)) <= value
			"killing_intent_min": ok = int(p.get("killing_intent", 0)) >= value
			"hour_in": ok = c.hours.has(["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"][posmod(tick / 120, 12)])
			"has_item": ok = int(p.inventory.get(c.get("item", ""), 0)) >= int(c.get("n", 1))
			"any_of":
				for group in c.options:
					if check(p, group, tick) == "": ok = true; break
		if not ok: return condition_text(c)
	return ""

static func eligibility(p: Dictionary, skill: String, study: bool, lesson: Dictionary = {}, tick: int = 0) -> String:
	if not Data.SKILLS.has(skill): return "此武學沒有可用的規則資料。"
	var art: Dictionary = Data.SKILLS[skill]
	var level := int(p.skills.get(skill, 0))
	if art.get("legacy_only", false): return "此為舊版改編武功，保留舊存檔運用，不再新增傳授或修練。"
	var reason := check(p, art.get("conditions", []), tick)
	if reason != "": return reason
	if level == 0 and not art.get("basic", false) and art.get("category", "") != "SECT" and special_count(p) >= 16: return "特殊武功已達十六套上限。"
	if not study:
		reason = check(p, lesson.get("conditions", []), tick)
		if reason != "": return reason
		for req in lesson.get("requires", []):
			if int(p.skills.get(req.skill, 0)) < int(req.level): return "%s至少 %d 級" % [req.skill, req.level]
		if level < int(art.get("self_study_until", 0)): return "須先自修至 %d 級，師父才繼續授課。" % int(art.self_study_until)
		if level >= int(lesson.get("cap", 0)): return "已達此師父授業上限 %d 級。" % int(lesson.get("cap", 0))
	else:
		if level <= 0 and int(art.get("self_study_until", 0)) <= 0: return "須先學會這門武學。"
		if level >= study_cap(p, skill): return "已達自修上限 %d 級；先提升對應基本功或尋找機緣。" % study_cap(p, skill)
	if level >= xp_cap(p): return "實戰不足：目前武學上限 %d 級。" % xp_cap(p)
	return ""

static func study_cap(p: Dictionary, skill: String) -> int:
	var art: Dictionary = Data.SKILLS.get(skill, {})
	var cap := int(art.get("study_cap", 100))
	var base: String = art.get("base", "")
	if base != "" and int(p.skills.get(base, 0)) < 140: cap = mini(cap, floori(int(p.skills.get(base, 0)) * 1.5))
	if skill == "九陰真經" and int(p.skills.get(skill, 0)) < 62: cap = mini(cap, 60)
	return cap

static func add_prof(p: Dictionary, skill: String, gain: int, cap: int) -> int:
	var before := int(p.skills.get(skill, 0))
	var level := before
	var prof := int(p.skill_xp.get(skill, 0)) + gain
	while level < cap and prof >= needed(skill, level):
		prof -= needed(skill, level)
		level += 1
	p.skills[skill] = level
	# Do not bank proficiency through locked levels and skip later restrictions.
	p.skill_xp[skill] = mini(prof, needed(skill, level) - 1)
	if skill == "基本內功" and level > before:
		p.max_mp += (level - before) * 5
		p.max_hp += (level - before) * 8
	return level

static func normalize(p: Dictionary) -> void:
	if int(p.get("rules_version", 0)) >= 4: return
	for skill in p.skill_xp:
		var level := int(p.skills.get(skill, 0))
		var fraction := clampf(float(p.skill_xp[skill]) / (12 + level * 3), 0, .999999)
		p.skill_xp[skill] = floori(fraction * needed(skill, level))
	p.rules_version = 4
