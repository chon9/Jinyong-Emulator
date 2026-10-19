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
		SKILLS[name] = {"name": name, "sect": "丐幫", "category": "FIST", "base": "基本拳腳", "desc": "丐幫相傳之學，以扶危濟困為立身根本。", "difficulty": 1.2, "cap": 100, "moves": []}
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
