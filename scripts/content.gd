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

static func _static_init() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	PLACES.merge(catalog.places, true)
	ENEMIES.merge(catalog.enemies, true)
	SHOP.merge(catalog.items, true)
	SECTS.erase("峨眉")
	SECTS.merge(catalog.sects, true)
	NPCS = catalog.npcs
	SKILLS = catalog.skills
	STORIES = JSON.parse_string(FileAccess.get_file_as_string("res://data/stories.json"))
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
		var category: String = "STAFF" if name == "打狗棒法" else ("INNER" if name == "混天功" else "FIST")
		SKILLS[name] = {"name": name, "sect": "丐幫", "category": category, "role": "INNER" if category == "INNER" else "EXTERNAL", "weapon_types": ["STAFF"] if category == "STAFF" else (["UNARMED", "CLAW"] if category == "FIST" else []), "base": "基本棍法" if category == "STAFF" else ("基本內功" if category == "INNER" else "搏擊格鬥"), "desc": "丐幫相傳之學；此分舵的師承與數值為模擬器改編。", "difficulty": 1.2, "cap": 100, "study_cap": 100, "moves": []}
	SKILLS["乞討"] = {"name": "乞討", "sect": "丐幫", "category": "SECT", "base": "", "desc": "知人情冷暖，行江湖正道。", "difficulty": 1.0, "cap": 100, "moves": []}
	SECTS["丐幫"]["virtue"] = "乞討"
	NPCS["yx_hongqigong"] = {"name": "洪七公", "place": "丐幫分舵", "desc": "九指神丐抱著酒葫蘆，目光炯炯。", "kind": "MASTER", "dialogue": ["洪七公笑道：武功高低倒在其次，若仗著本事欺負窮人，老叫化第一個不饒！", "洪七公拈起一根竹枝：棒是尋常竹，心卻不可偏。看清敵人的退路，才知這一棒該落在哪裡。"], "teach": []}
	for name in ["太祖長拳", "逍遙遊", "混天功", "乞討", "降龍十八掌", "打狗棒法"]:
		NPCS["yx_hongqigong"].teach.append({"skill": name, "cap": 80 if name in ["降龍十八掌", "打狗棒法"] else 60, "price": 2, "requires": [{"skill": "太祖長拳", "level": 30}, {"skill": "乞討", "level": 20}] if name in ["降龍十八掌", "打狗棒法"] else []})
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

static func role(skill: String) -> String:
	return str(SKILLS.get(skill, {}).get("role", "UTILITY"))

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
