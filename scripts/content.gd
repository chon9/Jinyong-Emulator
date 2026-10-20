extends RefCounted
## 所有數值均為本模擬器原型規則，可在此調校，並非原版已驗證數值。

static var SECTS = {
	"少林": {"place": "少林寺", "master": "玄慈", "basic": "羅漢拳", "advanced": "大力金剛掌", "style": "拳掌剛猛，氣血綿長", "hp": 35, "attack": 2},
	"武當": {"place": "武當山", "master": "宋遠橋", "basic": "武當劍法", "advanced": "太極劍", "style": "以靜制動，劍氣縱橫", "hp": 15, "attack": 5},
	"峨眉": {"place": "峨眉山", "master": "靜玄", "basic": "金頂綿掌", "advanced": "四象掌", "style": "掌意靈巧，內息悠長", "hp": 25, "attack": 3},
	"丐幫": {"place": "丐幫分舵", "master": "魯有腳", "basic": "太祖長拳", "advanced": "降龍十八掌", "style": "行俠四海，後勁無窮", "hp": 20, "attack": 4}
}
static var PLACES = {
	"揚州城": {"desc": "細雨打濕青石路。茶棚裡說書正酣，榜前聚著幾個初入江湖的少年。", "exits": ["城郊荒野", "少林寺", "武當山", "峨眉山", "丐幫分舵"], "safe": true, "level": 0, "enemy": ""},
	"城郊荒野": {"desc": "草叢窸窣，遠處傳來野犬低吼。這是試驗拳腳的好地方。", "exits": ["揚州城", "黑風林"], "safe": false, "level": 1, "enemy": "野犬"},
	"黑風林": {"desc": "林深不見日，刀痕留在樹幹上。山賊常在此攔路劫財。", "exits": ["城郊荒野", "黑風寨"], "safe": false, "level": 4, "enemy": "山賊"},
	"黑風寨": {"desc": "寨門半掩，酒氣混著鐵鏽味。深處那把虎皮交椅，似乎正等著一場惡戰。", "exits": ["黑風林"], "safe": false, "level": 9, "enemy": "黑風精銳"},
	"少林寺": {"desc": "晨鐘穿過松林。知客僧合十相迎，演武場上拳風如雷。", "exits": ["揚州城"], "safe": true, "level": 0, "enemy": ""},
	"武當山": {"desc": "雲海托起金殿。一名青衣道長持劍而立，邀你論一論陰陽。", "exits": ["揚州城"], "safe": true, "level": 0, "enemy": ""},
	"峨眉山": {"desc": "山道盡頭佛燈未熄。竹影輕搖，女俠的掌風卻沉穩有力。", "exits": ["揚州城"], "safe": true, "level": 0, "enemy": ""},
	"丐幫分舵": {"desc": "破廟裡炊煙裊裊。幾個衣衫襤褸的漢子分著熱粥，眼裡卻藏著光。", "exits": ["揚州城"], "safe": true, "level": 0, "enemy": ""}
}
static var ENEMIES = {
	"野犬": {"hp": 48, "attack": 7, "defense": 1, "exp": 26, "potential": 14, "silver": 12},
	"山賊": {"hp": 135, "attack": 17, "defense": 5, "exp": 65, "potential": 30, "silver": 28},
	"黑風精銳": {"hp": 310, "attack": 30, "defense": 12, "exp": 145, "potential": 65, "silver": 60}
}
static var SHOP = {
	"金創藥": {"price": 18, "desc": "恢復 70 氣血"},
	"養氣丹": {"price": 24, "desc": "恢復 45 內力"},
	"精鋼劍": {"price": 180, "desc": "裝備後攻擊 +8"},
	"青布袍": {"price": 120, "desc": "裝備後防禦 +5"}
}
const HELP = "指令：前往 地名｜拜師 門派｜練功 武功名｜裝備 武功或裝備名｜打怪｜打坐｜休息｜使用 金創藥｜購買 物品｜任務｜領賞｜掛機 刷怪／練功／打坐｜停止｜逃跑｜改名 名字｜說 話語。"

static var NPCS: Dictionary = {}
static var SKILLS: Dictionary = {}
static var STORIES: Array = []
static var QUESTS: Dictionary = {}
static var RANKS: Array = []
static var DUNGEONS: Dictionary = {}

static func _static_init() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	PLACES.merge(catalog.places, true)
	ENEMIES.merge(catalog.enemies, true)
	SHOP.merge(catalog.items, true)
	SECTS.erase("峨眉")
	SECTS.merge(catalog.sects, true)
	NPCS = catalog.npcs
	SKILLS = catalog.skills
	RANKS = catalog.get("ranks", [])
	STORIES = JSON.parse_string(FileAccess.get_file_as_string("res://data/stories.json"))
	QUESTS = JSON.parse_string(FileAccess.get_file_as_string("res://data/learning_quests.json"))
	DUNGEONS = JSON.parse_string(FileAccess.get_file_as_string("res://data/dungeons.json"))
	SHOP.merge(JSON.parse_string(FileAccess.get_file_as_string("res://data/quest_support.json")).get("items", {}), true)
	for old in ["少林寺", "武當山", "峨眉山"]:
		PLACES.erase(old)
		PLACES["揚州城"].exits.erase(old)
	PLACES["揚州城"].exits.append(catalog.entry)
	PLACES[catalog.entry].exits.append("揚州城")
	# 初始控制台可直達十一門派山門，山內仍需沿路尋師。
	for sect in SECTS:
		var place: String = SECTS[sect].place
		if not place in PLACES["揚州城"].exits: PLACES["揚州城"].exits.append(place)
		if not "揚州城" in PLACES[place].exits: PLACES[place].exits.append("揚州城")
	for name in ["太祖長拳", "逍遙遊", "混天功", "降龍十八掌", "打狗棒法"]:
		if SKILLS.has(name): continue
		var category: String = "STAFF" if name == "打狗棒法" else ("INNER" if name == "混天功" else "FIST")
		SKILLS[name] = {"name": name, "sect": "丐幫", "category": category, "role": "INNER" if category == "INNER" else "EXTERNAL", "weapon_types": ["STAFF"] if category == "STAFF" else (["UNARMED", "CLAW"] if category == "FIST" else []), "base": "基本棍法" if category == "STAFF" else ("基本內功" if category == "INNER" else "搏擊格鬥"), "desc": "丐幫相傳之學；此分舵的師承與數值為模擬器改編。", "difficulty": 1.2, "cap": 100, "study_cap": 100, "moves": []}
		SKILLS[name]["legacy_only"] = true
	SECTS["丐幫"]["virtue"] = "乞討"
	NPCS["yx_hongqigong"] = {"name": "洪七公", "place": "丐幫分舵", "desc": "九指神丐抱著酒葫蘆，目光炯炯。", "kind": "MASTER", "dialogue": ["洪七公笑道：武功高低倒在其次，若仗著本事欺負窮人，老叫化第一個不饒！", "洪七公拈起一根竹枝：棒是尋常竹，心卻不可偏。看清敵人的退路，才知這一棒該落在哪裡。"], "teach": []}
	NPCS["yx_hongqigong"].dialogue.append("丐幫學藝請前往總舵，向各位長老投師。舊版分舵直接授絕技的入口已取消。")
	PLACES["丐幫分舵"]["npcs"] = ["yx_hongqigong"]
	for name in ["金創藥", "養氣丹", "精鋼劍", "青布袍"]:
		SHOP[name]["type"] = "WEAPON" if name == "精鋼劍" else ("ARMOR" if name == "青布袍" else "OTHER")
		SHOP[name]["attack"] = 8 if name == "精鋼劍" else 0
		SHOP[name]["defense"] = 5 if name == "青布袍" else 0
		SHOP[name]["quest"] = false
		SHOP[name]["sellable"] = true
		SHOP[name]["restore"] = {"hp": 70} if name == "金創藥" else ({"mp": 45} if name == "養氣丹" else {})
	SHOP["精鋼劍"]["weapon_type"] = "SWORD"
	# 補齊原匯入商店缺少的武器類；名稱與數值為本作練習兵器。
	for entry in [["練習長槍", "SPEAR"], ["練習鐵爪", "CLAW"]]:
		SHOP[entry[0]] = {"id": "yx_" + entry[1], "type": "WEAPON", "weapon_type": entry[1], "price": 30, "attack": 5, "defense": 0, "quest": false, "sellable": true, "restore": {}, "desc": "本作練習兵器，僅為相容的外功提供兵器加成。"}
	NPCS["yx_bounty"] = {"id": "yx_bounty", "name": "江湖懸賞使", "place": "揚州城", "kind": "QUEST", "desc": "手持討伐簿的差人，替各地百姓張貼剿匪與試煉委託。", "dialogue": ["懸賞使指著榜文：先看清入口與敵情，備好藥再動身。組隊時，等所有人準備好再開戰。"], "teach": []}
	if not PLACES["揚州城"].has("npcs"): PLACES["揚州城"]["npcs"] = []
	PLACES["揚州城"].npcs.append("yx_bounty")
	for key in DUNGEONS:
		var dungeon: Dictionary = DUNGEONS[key]
		var flag := "yx_dungeon_" + str(key)
		var qid := "q_" + flag
		QUESTS[qid] = {"id": qid, "name": "討伐委託 · " + str(dungeon.name), "giver": "yx_bounty", "conditions": [{"type": "combat_xp_min", "value": dungeon.min_xp}], "give_items": [], "dialogues": {}, "stages": [{"id": "s_clear", "title": "完成副本挑戰", "log": "在副本頁選擇" + str(dungeon.name) + "，通過所有關卡後回任務頁領賞。", "place": dungeon.entry, "objectives": [{"id": "o_clear", "type": "STATE", "dungeon": key, "text": "通關" + str(dungeon.name), "requires": [{"type": "quest_flag", "flag": flag}]}], "next": "END:default"}], "outcomes": {"default": {"label": "領取討伐賞金", "rewards": {"money": int(dungeon.rewards.silver), "learn_points": int(dungeon.rewards.points), "fame": 10}}}, "source_status": "proposal"}

static func role(skill: String) -> String:
	return str(SKILLS.get(skill, {}).get("role", "UTILITY"))

static func flag_name(flag: String) -> String:
	for key in DUNGEONS:
		if flag == "yx_dungeon_" + str(key): return "通關" + str(DUNGEONS[key].name)
	for quest in QUESTS.values():
		for outcome in quest.outcomes.values():
			if flag in outcome.rewards.get("flags", []): return quest.name
	return {"gm_jiuyin_read": "古墓九陰刻文（流程待補）", "sl_tongren_passed": "十八銅人陣（流程待補）", "qz_kongming": "空明拳機緣（流程待補）"}.get(flag, flag + "（流程待補）")

static func category_label(category: String) -> String:
	return str({"FIST": "搏擊拳掌", "STAB": "刺術指法", "BLADE": "刀法", "SWORD": "劍法", "STAFF": "棍杖", "SPEAR": "槍法", "WHIP": "鞭法", "CLAW": "搏擊兵器（爪）", "UNARMED": "徒手", "INNER": "內功", "LIGHTNESS": "輕功", "DODGE": "閃躲", "PARRY": "拆招", "FORMATION": "陣法", "HIDDEN": "暗器", "POISON": "毒術", "MEDIC": "醫術", "SECT": "門派修養"}.get(category, "生活技藝"))

static func weapon_type(weapon: String) -> String:
	return "UNARMED" if weapon == "" else str(SHOP.get(weapon, {}).get("weapon_type", "UNKNOWN"))

static func fits(skill: String, weapon: String) -> bool:
	return role(skill) == "EXTERNAL" and weapon_type(weapon) in SKILLS.get(skill, {}).get("weapon_types", [])

static func requirement_text(skill: String) -> String:
	var art: Dictionary = SKILLS.get(skill, {})
	var types: PackedStringArray = []
	for kind in art.get("weapon_types", []): types.append(category_label(kind))
	return category_label(str(art.get("category", ""))) + (" · 需 " + "／".join(types) if not types.is_empty() else " · 不作外功攻擊")

static func local_npcs(place: String) -> Array:
	return PLACES.get(place, {}).get("npcs", [])

static func path_to(start: String, destination: String) -> Array:
	if not PLACES.has(start) or not PLACES.has(destination): return []
	if start == destination: return []
	var queue: Array = [start]
	var previous := {start: ""}
	var cursor := 0
	while cursor < queue.size():
		var current: String = queue[cursor]
		cursor += 1
		for next in PLACES[current].exits:
			if previous.has(next): continue
			previous[next] = current
			queue.append(next)
			if next == destination:
				var result: Array = [next]
				while previous[result[0]] != start: result.push_front(previous[result[0]])
				return result
	return []

static func destinations(query: String, start: String) -> Array:
	var found: Array = []
	var seen := {}
	var needle := query.strip_edges().to_lower()
	for place in PLACES:
		if needle != "" and not needle in place.to_lower() and not needle in str(PLACES[place].get("region", "")).to_lower(): continue
		found.append({"title": place, "place": place, "kind": "地點", "steps": path_to(start, place).size()})
		seen["地點|" + place] = true
	for npc_id in NPCS:
		var npc: Dictionary = NPCS[npc_id]
		var reasons: PackedStringArray = []
		if needle != "" and needle in str(npc.name).to_lower(): reasons.append(npc.name)
		for lesson in npc.teach:
			if needle != "" and needle in str(lesson.skill).to_lower(): reasons.append("學 " + str(lesson.skill))
		if reasons.is_empty(): continue
		found.append({"title": npc.name + " · " + "、".join(reasons), "place": npc.place, "kind": "師父" if not npc.teach.is_empty() else "人物", "steps": path_to(start, npc.place).size()})
	if needle != "":
		for quest in QUESTS.values():
			var match_quest: bool = needle in str(quest.name).to_lower()
			for outcome in quest.outcomes.values():
				for skill in outcome.rewards.get("learn", {}):
					if needle in str(skill).to_lower(): match_quest = true
				for skill in SKILLS:
					if not needle in str(skill).to_lower(): continue
					for condition in SKILLS[skill].get("conditions", []):
						if condition.get("type", "") == "quest_flag" and condition.flag in outcome.rewards.get("flags", []): match_quest = true
			if match_quest and NPCS.has(quest.giver):
				var npc: Dictionary = NPCS[quest.giver]
				found.append({"title": quest.name + " · " + str(npc.name), "place": npc.place, "kind": "機緣", "steps": path_to(start, npc.place).size()})
	found.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.steps == b.steps: return str(a.title) < str(b.title)
		return int(a.steps) < int(b.steps))
	return found
