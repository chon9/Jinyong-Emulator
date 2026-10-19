extends RefCounted
## 純規則引擎。單機與聯機主機使用同一份規則；客戶端只發出意圖。

signal event(peer_id: int, channel: String, message: String)
const Data = preload("res://scripts/content.gd")
const Social = preload("res://scripts/social.gd")
const Training = preload("res://scripts/progression.gd")
const Combat = preload("res://scripts/combat_rules.gd")
const Quests = preload("res://scripts/learning_quests.gd")
var social
var quests
var players: Dictionary = {}
var tick: int = 0
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()
	social = Social.new(self)
	quests = Quests.new(self)

func add_player(id: int, title: String = "無名少俠") -> Dictionary:
	var p := {
		"name": clean_name(title), "level": 1, "exp": 0, "potential": 100, "silver": 80,
		"hp": 120, "max_hp": 120, "mp": 60, "max_mp": 60, "energy": 100, "spirit": 100, "max_spirit": 100,
		"sect": "江湖散人", "contribution": 0, "place": "揚州城",
		"skills": {"搏擊格鬥": 1, "基本內功": 1}, "equipped": "搏擊格鬥", "inner": "基本內功", "movement": "", "parry": "",
		"inventory": {"金創藥": 5, "養氣丹": 3}, "weapon": "", "armor": "",
		"auto": "停止", "auto_heal": true, "heal_at": 45, "auto_skill": "搏擊格鬥",
		"teacher": "", "skill_xp": {}, "talked": {}, "stories": {}, "story_choices": {}, "visited": {"揚州城": true},
		"searched": {}, "deliveries": {},
		"enemy": {}, "kills": 0, "deaths": 0, "job": {}, "cooldown": -1,
		"stance": "普通", "session_kills": 0, "session_silver": 0
	}
	p.merge({"party": 0, "follow": false, "fight": 0, "pk_enabled": false, "pvp_wins": 0, "pvp_losses": 0})
	p.merge({"travel_target": "", "travel_route": [], "study_ticks": 0, "quest_restore": {}})
	p.merge({"attrs": {"str": 25, "con": 25, "wit": 30, "agi": 25, "cal": 25, "guts": 25, "luck": 25}, "gender": "M", "combat_xp": 0, "morality": 0, "fame": 0, "lilian": 0, "sect_master": "", "sect_rank": 1, "flags": {}, "learning_quests": {}, "quests_done": {}, "power": 5, "rules_version": 4})
	p["attributes_locked"] = false
	players[id] = p
	return p

static func clean_name(value: String) -> String:
	var cleaned := value.strip_edges().replace("\n", "").replace("\r", "").replace("\t", "")
	return cleaned.left(12) if not cleaned.is_empty() else "無名少俠"

static func attack(p: Dictionary) -> int:
	return roundi(Combat.attack_power(p, active_art(p)))

static func slot_level(p: Dictionary, slot: String, expected: String) -> int:
	var skill: String = p.get(slot, "")
	return int(p.skills.get(skill, 0)) if Data.role(skill) == expected else 0

static func compatible_art(p: Dictionary, weapon: String) -> String:
	var best := ""
	for skill in p.skills:
		if int(p.skills[skill]) > 0 and Data.fits(skill, weapon) and (best == "" or int(p.skills[skill]) > int(p.skills[best])): best = skill
	return best

static func active_art(p: Dictionary) -> String:
	var skill: String = p.get("equipped", "")
	if int(p.skills.get(skill, 0)) > 0 and Data.fits(skill, str(p.get("weapon", ""))): return skill
	var fallback := compatible_art(p, str(p.get("weapon", "")))
	return fallback if fallback != "" else "搏擊格鬥"

static func normalize_martial(p: Dictionary) -> void:
	# 舊存檔只遷移名稱與運用欄位，保留已學等級、熟練與物品。
	for field in ["skills", "skill_xp"]:
		if p[field].has("基本拳腳"):
			p[field]["搏擊格鬥"] = maxi(int(p[field].get("搏擊格鬥", 0)), int(p[field]["基本拳腳"]))
			p[field].erase("基本拳腳")
	for field in ["equipped", "auto_skill"]:
		if p[field] == "基本拳腳": p[field] = "搏擊格鬥"
	if not p.skills.has("搏擊格鬥"): p.skills["搏擊格鬥"] = 1
	var old: String = p.equipped
	if Data.role(old) == "INNER": p.inner = old
	elif Data.role(old) == "MOVEMENT": p.movement = old
	for slot in ["inner", "movement"]:
		var expected := "INNER" if slot == "inner" else "MOVEMENT"
		if p.get(slot, "") != "" and slot_level(p, slot, expected) <= 0: p[slot] = "基本內功" if slot == "inner" and p.skills.has("基本內功") else ""
	if p.weapon != "" and (int(p.inventory.get(p.weapon, 0)) < 1 or compatible_art(p, p.weapon) == ""): p.weapon = ""
	p.equipped = active_art(p)

static func defense(p: Dictionary) -> int:
	return roundi(Combat.defense_power(p, guard_art(p)))

static func guard_art(p: Dictionary) -> String:
	var skill: String = p.get("parry", "")
	return skill if int(p.skills.get(skill, 0)) > 0 and Data.fits(skill, str(p.get("weapon", ""))) else active_art(p)

static func exp_needed(p: Dictionary) -> int:
	return int(p.level) * 70

func tell(id: int, message: String, channel: String = "江湖") -> void:
	event.emit(id, channel, message)

func act(id: int, command: String, arg: String = "") -> bool:
	if not players.has(id):
		return false
	var p: Dictionary = players[id]
	if command in ["接受任務", "任務行動", "任務結局", "任務對話", "任務緣起"]:
		if not p.enemy.is_empty() or int(p.fight) != 0: return reject(id, "先結束戰鬥，再處理任務。")
		p.travel_target = ""
		p.travel_route = []
		p.auto = "停止"
		p.study_ticks = 0
		return quests.act(id, command, arg)
	if command == "尋路":
		if not p.enemy.is_empty() or int(p.fight) != 0: return reject(id, "先結束戰鬥，再開始趕路。")
		if p.follow: return reject(id, "請先取消跟隨隊長，再自行尋路。")
		if not Data.PLACES.has(arg): return reject(id, "目的地不存在，請從地圖搜尋結果選擇。")
		p.travel_target = arg
		p.travel_route = Data.path_to(p.place, arg)
		p.auto = "停止"
		p.study_ticks = 0
		if arg == p.place:
			p.travel_target = ""
			tell(id, "已抵達%s。" % arg, "行路")
			return true
		if p.travel_route.is_empty():
			p.travel_target = ""
			return reject(id, "目前找不到可通行的路線。")
		tell(id, "開始前往%s，尚餘 %d 步；每息沿相鄰地點行走，可隨時按停止。" % [arg, p.travel_route.size()], "行路")
		return true
	# 新操作取消行程，聊天及戰鬥姿態不會暗中改變路線。
	if command in ["前往", "停止", "拜師", "裝備", "卸下", "消點", "練功", "自修", "打怪", "打坐", "休息", "掛機", "對話", "接受任務", "任務選項", "任務行動"]:
		p.travel_target = ""
		p.travel_route = []
		if command != "自修": p.study_ticks = 0
		if command in ["前往", "拜師", "裝備", "卸下", "消點", "練功", "打怪", "對話"]: p.auto = "停止"
	if command in Social.COMMANDS: return social.act(id, command, arg)
	if int(p.fight) != 0 and command in ["前往", "拜師", "練功", "消點", "自修", "對話", "故事選擇", "搜查", "交付", "裝備", "卸下", "打怪", "打坐", "休息", "購買", "出售", "掛機"]:
		return reject(id, "先結束戰鬥或逃跑，再執行此操作。")
	match command:
		"先天配點":
			if p.attributes_locked or not p.enemy.is_empty() or int(p.fight) != 0: return reject(id, "先天配置已確認，或正在戰鬥中。")
			var values: Variant = JSON.parse_string(arg)
			if not values is Dictionary or values.size() != 7: return false
			var total := 0
			for key in Training.ATTRS:
				var value: Variant = values.get(key)
				if not (value is int or value is float) or float(value) != floorf(float(value)) or int(value) < 15 or int(value) > 30: return false
				total += int(value)
			if total != 180: return reject(id, "本作先天配置總和須為 180，各項 15–30。")
			p.attrs = values
			p.attributes_locked = true
			tell(id, "已確認本作先天屬性配置。後天基本功與裝備加成另計。", "武學")
		"身世":
			if p.sect != "江湖散人": return reject(id, "入門後不能更換身世。")
			if not arg in ["M", "F"]: return false
			p.gender = arg
			tell(id, "已設定身世：" + ("男性" if arg == "M" else "女性"), "武學")
		"投師":
			if not p.enemy.is_empty() or int(p.fight) != 0: return reject(id, "先結束戰鬥，再投師。")
			if not arg in Data.local_npcs(p.place): return reject(id, "請先到師父身邊。")
			var valid := false
			for lesson in Data.NPCS[arg].teach:
				if Data.SKILLS.get(lesson.skill, {}).get("sect", "") == p.sect: valid = true
			if not valid: return reject(id, "這位師父並非本門授業師父。")
			if p.sect_master != "" and p.sect_master != arg: return reject(id, "已有本門個人師承，不能隨意更換。")
			p.sect_master = arg
			tell(id, "你正式投師%s門下。" % Data.NPCS[arg].name, "武學")
		"晉升":
			for rank in Data.RANKS:
				if rank.sect != p.sect or int(rank.rank) != int(p.sect_rank) + 1: continue
				if p.place != Data.SECTS[p.sect].place: return reject(id, "請回本門山門辦理晉升。")
				var reason := Training.check(p, rank.conditions, tick)
				if reason != "": return reject(id, "晉升需要：" + reason)
				if rank.get("promote", "") == "QUEST": return reject(id, "請先完成「%s」。" % Data.QUESTS.get(rank.get("quest", ""), {}).get("name", "門派晉升機緣"))
				for stat in rank.get("cost", {}):
					if int(p.get(stat, 0)) < int(rank.cost[stat]): return reject(id, "晉升資源不足。")
				for stat in rank.get("cost", {}): p[stat] -= int(rank.cost[stat])
				p.sect_rank = int(rank.rank)
				tell(id, "晉升為" + str(rank.name), "武學")
				return true
			return reject(id, "沒有下一個可用的門派位階。")
		"出力":
			if not arg.is_valid_int() or arg.to_int() < 1 or arg.to_int() > 10: return false
			p.power = arg.to_int()
		"格擋":
			if not p.enemy.is_empty() or int(p.fight) != 0: return reject(id, "先結束戰鬥，再更換格擋。")
			if int(p.skills.get(arg, 0)) <= 0 or not Data.fits(arg, p.weapon): return reject(id, "格擋須使用已學且符合兵器的外功。")
			p.parry = arg
		"前往":
			if not Data.PLACES.has(arg) or not arg in Data.PLACES[p.place].exits:
				return reject(id, "此處無法直達那裡，請沿相鄰地點行走。")
			if not p.enemy.is_empty(): return reject(id, "交戰中無法趕路；可先逃跑。")
			var origin: String = p.place
			p.place = arg
			p.auto = "停止"
			if not p.visited.has(arg):
				p.visited[arg] = true
				p.potential += 2
			tell(id, "你來到%s。%s" % [arg, Data.PLACES[arg].desc])
			social.moved(id, origin)
		"拜師":
			if p.sect != "江湖散人": return reject(id, "你已有師承，先精進本門武學吧。")
			if not Data.SECTS.has(arg): return reject(id, "請選擇少林、武當、峨眉或丐幫。")
			var sect: Dictionary = Data.SECTS[arg]
			if p.place != sect.place: return reject(id, "請先前往%s拜訪師父。" % sect.place)
			var reason := Training.check(p, sect.get("conditions", []), tick)
			if reason != "": return reject(id, "入門需要：" + reason)
			var genders: Array = sect.get("gender", [])
			if not genders.is_empty() and not p.gender in genders: return reject(id, "這個門派不接受你的身世；散人可在武功頁先設定男／女。")
			p.sect = arg
			if arg == "丐幫": p.sect_rank = 0
			p.auto_skill = sect.basic
			if sect.has("virtue"): p.skills[sect.virtue] = 1
			p.max_hp += sect.hp
			p.hp = p.max_hp
			tell(id, "%s引你加入%s。請向授業師父消點學藝；入門不再直接贈送特殊武功。" % [sect.master, arg], "武學")
		"練功", "消點": return learn(id, arg)
		"自修":
			var reason := Training.eligibility(p, arg, true, {}, tick)
			if reason != "": return reject(id, reason)
			if not p.enemy.is_empty(): return reject(id, "交戰中無法自修。")
			p.auto_skill = arg
			p.auto = "自修"
			p.study_ticks = 0
			tell(id, "開始自修%s。每完整 5 息消耗 3 學點與 %d 精，獲得 %d 熟練；中斷不結算。" % [arg, Training.energy_cost(p), Training.study_gain(p)], "修行")
		"對話": return talk(id, arg)
		"故事選擇": return choose_story(id, arg)
		"搜查":
			if not p.enemy.is_empty(): return reject(id, "先結束戰鬥，才能仔細搜查。")
			if p.searched.has(p.place): return reject(id, "你已仔細搜查過此地。")
			if p.energy < 3: return reject(id, "搜查需要 3 精力，請先調息。")
			p.energy -= 3
			p.searched[p.place] = true
			var finds: Array = Data.PLACES[p.place].get("finds", [])
			for item in finds: p.inventory[item] = int(p.inventory.get(item, 0)) + 1
			tell(id, "你仔細搜查四周，" + ("發現了" + "、".join(finds) + "。可尋找相關人物交付委託。" if not finds.is_empty() else "暫無發現。"), "探索")
		"交付":
			var pair := arg.split("|", false, 1)
			if pair.size() != 2 or not pair[0] in Data.local_npcs(p.place): return reject(id, "請到委託人身邊交付。")
			var key := pair[0] + "|" + pair[1]
			if p.deliveries.has(key): return reject(id, "這份委託已經完成。")
			for request in Data.NPCS[pair[0]].get("requests", []):
				if request.item != pair[1]: continue
				if int(p.inventory.get(pair[1], 0)) < 1: return reject(id, "尚未找到%s。可前往%s搜查。" % [pair[1], request.place])
				p.inventory[pair[1]] -= 1
				p.deliveries[key] = true
				p.silver += int(request.silver)
				p.potential += int(request.points)
				p.contribution += 1
				tell(id, "%s接過%s，謝你奔走相助。獲得 %d 兩、%d 學點、1 貢獻。" % [Data.NPCS[pair[0]].name, pair[1], request.silver, request.points], "任務")
				return true
			return false
		"裝備":
			if not p.enemy.is_empty(): return reject(id, "交戰中不能更換武學或裝備。")
			if int(p.skills.get(arg, 0)) > 0:
				match Data.role(arg):
					"EXTERNAL":
						if not Data.fits(arg, p.weapon): return reject(id, "%s：%s。請先更換或卸下兵器。" % [arg, Data.requirement_text(arg)])
						p.equipped = arg
					"INNER": p.inner = arg
					"MOVEMENT": p.movement = arg
					_: return reject(id, "陣法、暗器、毒術與生活修養不作普通外功運用。")
			elif int(p.inventory.get(arg, 0)) > 0 and Data.SHOP.has(arg) and Data.SHOP[arg].type in ["WEAPON", "ARMOR"]:
				if Data.SHOP[arg].type == "WEAPON":
					var art: String = p.equipped if Data.fits(p.equipped, arg) else compatible_art(p, arg)
					if art == "": return reject(id, "尚未學會與%s相容的外功，請先向武師學習%s。" % [arg, Data.category_label(Data.weapon_type(arg))])
					p.weapon = arg
					p.equipped = art
				else: p.armor = arg
			else: return reject(id, "你尚未擁有這項武學或裝備。")
			tell(id, "你已運用%s。外功：%s；內功：%s；輕功：%s。" % [arg, p.equipped, p.inner, p.movement], "武學")
		"卸下":
			if not p.enemy.is_empty(): return reject(id, "交戰中不能卸下裝備。")
			if not arg in ["weapon", "armor", "inner", "movement"]: return false
			p[arg] = ""
			if arg == "weapon": p.equipped = active_art(p)
			tell(id, "已卸下。外功運用：%s。" % p.equipped, "武學")
		"打怪": return hunt(id)
		"打坐", "休息":
			if not p.enemy.is_empty(): return reject(id, "交戰中無法調息。")
			p.auto = "打坐"
			tell(id, "你盤膝調息，氣血、內力與精力逐漸恢復。", "修行")
		"使用": return use_item(id, arg)
		"購買":
			if not Data.SHOP.has(arg): return reject(id, "商店沒有這件物品。")
			if p.place != "揚州城" and not arg in Data.PLACES[p.place].get("shop", []): return reject(id, "當地商店沒有販售這件物品。")
			if Data.SHOP[arg].get("quest", false): return reject(id, "任務信物只能從江湖歷練取得。")
			var price: int = Data.SHOP[arg].price
			if p.silver < price: return reject(id, "銀兩不足。")
			p.silver -= price
			p.inventory[arg] = int(p.inventory.get(arg, 0)) + 1
			tell(id, "花費 %d 兩，購得%s。" % [price, arg], "行囊")
		"出售":
			if p.place != "揚州城" and Data.PLACES[p.place].get("shop", []).is_empty(): return reject(id, "此處沒有收購物品的商人。")
			if int(p.inventory.get(arg, 0)) < 1 or not Data.SHOP.has(arg): return false
			if not Data.SHOP[arg].get("sellable", false) or Data.SHOP[arg].get("quest", false): return reject(id, "此物不可出售。")
			if arg in [p.weapon, p.armor] and int(p.inventory[arg]) == 1: return reject(id, "這是你身上最後一件已裝備的物品。")
			p.inventory[arg] -= 1
			var value := maxi(1, int(Data.SHOP[arg].price) / 3)
			p.silver += value
			tell(id, "售出%s，獲得 %d 兩。" % [arg, value], "行囊")
		"掛機":
			if not arg in ["刷怪", "練功", "消點", "自修", "打坐"]: return reject(id, "掛機可選：刷怪、消點、自修、打坐。")
			if arg == "刷怪" and Data.PLACES[p.place].safe: return reject(id, "城內與門派不能刷怪，先去城郊荒野。")
			if arg != "刷怪" and not p.enemy.is_empty(): return reject(id, "先結束戰鬥，再切換修行。")
			p.auto = arg
			tell(id, "游俠已啟動：自動%s。" % arg, "游俠")
		"停止":
			p.auto = "停止"
			tell(id, "游俠已停止。當前戰鬥仍會繼續，可選擇逃跑。", "游俠")
		"補血設定":
			p.auto_heal = arg == "開啟"
		"修練設定":
			if not p.skills.has(arg): return false
			if p.auto_skill != arg: p.study_ticks = 0
			p.auto_skill = arg
		"招式":
			if not arg in ["普通", "重擊", "防守"]: return false
			p.stance = arg
		"逃跑":
			if int(p.fight) != 0: return social.flee(id)
			if p.enemy.is_empty(): return reject(id, "你並未陷入戰鬥。")
			if p.enemy.has("quest_id"):
				var previous: Dictionary = p.enemy
				p.enemy = {}
				quests.fight_result(id, previous.quest_id, previous.quest_objective, previous.get("quest_any", false))
				return true
			p.enemy = {}
			p.auto = "停止"
			p.hp = maxi(1, int(p.hp) - 12)
			tell(id, "你虛晃一招脫身，損失 12 氣血。", "戰鬥")
		"任務":
			if p.place != "揚州城": return reject(id, "請到揚州城告示榜接取懸賞。")
			if not p.job.is_empty(): return reject(id, "你已有懸賞，完成後回城領賞。")
			p.job = {"name": "城郊除患", "target": "野犬", "count": 0, "need": 3}
			tell(id, "接取懸賞：擊敗 3 隻野犬，回城可領 60 兩、40 潛能與 8 貢獻。", "任務")
		"領賞":
			if p.place != "揚州城": return reject(id, "請回揚州城領賞。")
			if p.job.is_empty() or int(p.job.count) < int(p.job.need): return reject(id, "懸賞尚未完成。")
			p.silver += 60
			p.potential += 40
			p.contribution += 8
			p.morality = mini(1000, int(p.morality) + 50)
			p.job = {}
			tell(id, "懸賞完成！獲得 60 兩、40 學點、8 貢獻、50 善惡。", "任務")
		"改名":
			p.name = clean_name(arg)
			tell(id, "從此江湖人稱你為「%s」。" % p.name)
		_:
			return reject(id, "不認得這個指令。" + Data.HELP)
	return true

func reject(id: int, text: String) -> bool:
	tell(id, text, "提示")
	return false

func local_lessons(p: Dictionary) -> Array:
	var result: Array = []
	for npc_id in Data.local_npcs(p.place):
		for lesson in Data.NPCS[npc_id].teach:
			var skill: String = lesson.skill
			var sect: String = Data.SKILLS.get(skill, {}).get("sect", "")
			if sect != "" and sect != p.sect: continue
			var row: Dictionary = lesson.duplicate(true)
			row["npc"] = npc_id
			result.append(row)
	return result

func learn(id: int, arg: String) -> bool:
	var p: Dictionary = players[id]
	if not p.enemy.is_empty(): return reject(id, "交戰中無法向師父消點。")
	var parts := arg.split("|", false, 1)
	var skill: String = parts[-1] if not parts.is_empty() else str(p.auto_skill)
	var teacher: String = parts[0] if parts.size() == 2 else str(p.teacher)
	var lesson: Dictionary = {}
	for row in local_lessons(p):
		if row.skill == skill and (teacher == "" or row.npc == teacher): lesson = row; break
	if lesson.is_empty(): return reject(id, "請到授業師父身邊消點；可在地圖搜尋武功名稱尋師。")
	var reason := Training.eligibility(p, skill, false, lesson, tick)
	if reason == "": reason = Training.check(p, Data.SECTS.get(p.sect, {}).get("teach_conditions", []), tick)
	if reason != "": return reject(id, "消點需要：" + reason)
	if p.cooldown == tick: return false
	var energy := Training.energy_cost(p)
	var mp := 1 if "neili" in Data.SECTS.get(p.sect, {}).get("train_cost", []) and Data.SKILLS[skill].category == "SECT" else 0
	var spirit := 2 if "shen" in Data.SECTS.get(p.sect, {}).get("train_cost", []) and Data.SKILLS[skill].category == "SECT" else 0
	if int(p.potential) < 1 or int(p.silver) < int(lesson.price) or int(p.energy) < energy or int(p.mp) < mp or int(p.spirit) < spirit:
		return reject(id, "消點需 1 學點、%d 兩、%d 精、%d 內力與 %d 神。" % [lesson.price, energy, mp, spirit])
	p.cooldown = tick
	p.potential -= 1
	p.silver -= int(lesson.price)
	p.energy -= energy
	p.mp -= mp
	p.spirit -= spirit
	var gain := Training.lesson_gain(p)
	var before := int(p.skills.get(skill, 0))
	var level := Training.add_prof(p, skill, gain, mini(int(lesson.cap), Training.xp_cap(p)))
	p.auto_skill = skill
	p.teacher = lesson.npc
	tell(id, "%s指點%s：熟練 +%d，%d → %d 級（%d/%d），消耗 1 學點。" % [Data.NPCS[lesson.npc].name, skill, gain, before, level, p.skill_xp[skill], Training.needed(skill, level)], "消點")
	return true

func self_study(id: int) -> void:
	var p: Dictionary = players[id]
	var skill: String = p.auto_skill
	var reason := Training.eligibility(p, skill, true, {}, tick)
	if reason != "":
		p.auto = "停止"
		p.study_ticks = 0
		tell(id, "自修已停止：" + reason, "修行")
		return
	p.study_ticks += 1
	if int(p.study_ticks) < Training.STUDY_SECONDS: return
	p.study_ticks = 0
	var energy := Training.energy_cost(p)
	if int(p.potential) < Training.STUDY_POINTS or int(p.energy) < energy:
		p.auto = "停止"
		tell(id, "自修已停止：需要 3 學點與 %d 精。" % energy, "修行")
		return
	p.potential -= Training.STUDY_POINTS
	p.energy -= energy
	var gain := Training.study_gain(p)
	var level := Training.add_prof(p, skill, gain, mini(Training.study_cap(p, skill), Training.xp_cap(p)))
	tell(id, "%s自修：熟練 +%d，%d 級（%d/%d），消耗 3 學點。" % [skill, gain, level, p.skill_xp[skill], Training.needed(skill, level)], "自修")

func talk(id: int, npc_id: String) -> bool:
	var p: Dictionary = players[id]
	if not npc_id in Data.local_npcs(p.place): return reject(id, "這位人物不在此地。")
	var npc: Dictionary = Data.NPCS[npc_id]
	var count := int(p.talked.get(npc_id, 0))
	var lines: Array = npc.dialogue
	tell(id, str(lines[count % lines.size()]), "對話")
	p.talked[npc_id] = count + 1
	for story in Data.STORIES:
		var stage := int(p.stories.get(story.id, 0))
		if stage < story.npcs.size() and story.npcs[stage] == npc_id:
			tell(id, "【%s・%d】%s" % [story.title, stage + 1, story.scenes[stage]], "故事")
			p.stories[story.id] = stage + 1
			p.potential += 15
			if stage + 1 == story.npcs.size(): tell(id, "故事走到抉擇之處，請在故事頁作出選擇。", "故事")
	return true

func choose_story(id: int, arg: String) -> bool:
	var p: Dictionary = players[id]
	var parts := arg.split("|", false, 1)
	if parts.size() != 2 or not parts[1].is_valid_int(): return false
	var choice := int(parts[1])
	if choice < 0 or choice > 1: return false
	for story in Data.STORIES:
		if story.id != parts[0]: continue
		if int(p.stories.get(story.id, 0)) < story.npcs.size() or p.story_choices.has(story.id): return reject(id, "尚未完成訪談，或這段故事已作過抉擇。")
		p.story_choices[story.id] = choice
		p.potential += 80 if choice == 0 else 50
		p.silver += 50 if choice == 0 else 90
		p.contribution += 5
		p.morality = clampi(int(p.morality) + (20 if choice == 0 else -20), -1000, 1000)
		tell(id, "【%s】%s（學點與銀兩獎勵已入帳，貢獻 +5）" % [story.title, story.ending[choice]], "故事")
		return true
	return false

func hunt(id: int) -> bool:
	var p: Dictionary = players[id]
	if not p.enemy.is_empty(): return false
	var place: Dictionary = Data.PLACES[p.place]
	if place.safe: return reject(id, "此處平安無事。前往城郊荒野再尋敵。")
	if int(p.hp) * 100 < int(p.max_hp) * 25:
		p.auto = "停止"
		return reject(id, "氣血不足四分之一，游俠已停下，請先療傷。")
	var pool: Array = place.get("enemies", [place.enemy])
	var name: String = pool[rng.randi_range(0, pool.size() - 1)]
	var enemy: Dictionary = Data.ENEMIES[name].duplicate(true)
	enemy.name = name
	enemy.max_hp = enemy.hp
	if social.party_hunt(id, enemy): return true
	p.enemy = enemy
	tell(id, "你遭遇%s，擺開「%s」架勢！" % [enemy.name, p.equipped], "戰鬥")
	return true

func use_item(id: int, item: String) -> bool:
	var p: Dictionary = players[id]
	if not Data.SHOP.has(item) or int(p.inventory.get(item, 0)) <= 0:
		return reject(id, "行囊裡沒有可用的%s。" % item)
	var restores: Dictionary = Data.SHOP[item].get("restore", {})
	if restores.is_empty(): return reject(id, "此物不能直接服用；裝備、出售或收藏在行囊中。")
	var restored := false
	for stat in restores:
		var maximum := 100 if stat == "energy" else int(p["max_" + stat])
		var before: int = p[stat]
		p[stat] = mini(maximum, before + int(restores[stat]))
		if p[stat] > before: restored = true
	if not restored: return false
	p.inventory[item] -= 1
	tell(id, "你服下%s，恢復了精氣。" % item, "行囊")
	return true

func step() -> void:
	tick += 1
	for id in players.keys():
		var p: Dictionary = players[id]
		if p.auto_heal and int(p.hp) * 100 <= int(p.max_hp) * int(p.heal_at) and int(p.inventory.get("金創藥", 0)) > 0:
			use_item(id, "金創藥")
		if int(p.fight) != 0: continue
		if p.travel_target != "":
			travel_step(id)
			continue
		if not p.enemy.is_empty():
			combat(id)
		elif p.auto == "刷怪":
			hunt(id)
		elif p.auto in ["練功", "消點"]:
			if not learn(id, str(p.auto_skill)):
				p.auto = "停止"
				tell(id, "潛能、精力不足或武學已滿級，自動練功已停止。", "游俠")
		elif p.auto == "自修":
			self_study(id)
		elif p.auto == "打坐":
			p.hp = mini(int(p.max_hp), int(p.hp) + 9)
			p.mp = mini(int(p.max_mp), int(p.mp) + 7)
			p.energy = mini(100, int(p.energy) + 5)
			p.spirit = mini(int(p.max_spirit), int(p.spirit) + 5)
			if p.hp == p.max_hp and p.mp == p.max_mp and p.energy == 100 and p.spirit == p.max_spirit:
				p.auto = "停止"
				tell(id, "調息完畢，精氣神已恢復。", "修行")
		elif tick % 4 == 0:
			p.energy = mini(100, int(p.energy) + 1)
			p.mp = mini(int(p.max_mp), int(p.mp) + 1)
	social.step()

func travel_step(id: int) -> void:
	var p: Dictionary = players[id]
	if not p.enemy.is_empty() or int(p.fight) != 0 or p.follow:
		p.travel_target = ""
		p.travel_route = []
		return
	var destination: String = p.travel_target
	var route := Data.path_to(p.place, destination)
	if route.is_empty():
		p.travel_target = ""
		p.travel_route = []
		tell(id, "已抵達%s。" % destination if p.place == destination else "行程中斷：前路不通。", "行路")
		return
	var origin: String = p.place
	p.place = route.pop_front()
	p.travel_route = route
	if not p.visited.has(p.place):
		p.visited[p.place] = true
		p.potential += 2
	social.moved(id, origin)
	if route.is_empty():
		p.travel_target = ""
		tell(id, "已抵達%s。%s" % [destination, Data.PLACES[destination].desc], "行路")
	else: tell(id, "來到%s，前往%s尚餘 %d 步。" % [p.place, destination, route.size()], "行路")

func strike(p: Dictionary, target: Dictionary) -> Dictionary:
	return Combat.roll(p, target, active_art(p), guard_art(target) if target.has("skills") else "", rng)

func roll_damage(p: Dictionary, armor: int) -> int:
	return int(strike(p, {"defense": armor, "level": 1}).damage)

func combat(id: int) -> void:
	var p: Dictionary = players[id]
	var e: Dictionary = p.enemy
	var outcome := strike(p, e)
	var damage := int(outcome.damage)
	var style: String = active_art(p)
	style = str(outcome.move)
	e.hp = maxi(0, int(e.hp) - damage)
	tell(id, "%s，對%s造成 %d 傷害。%s" % [style, e.name, damage, "（%d/%d）" % [e.hp, e.max_hp]], "戰鬥")
	if e.hp <= 0:
		victory(id)
		return
	var received := Combat.enemy_roll(e, p, guard_art(p), rng)
	p.hp = maxi(0, int(p.hp) - received)
	tell(id, "%s反擊，你損失 %d 氣血。" % [e.name, received], "戰鬥")
	if p.hp <= 0:
		defeat(id)

func defeat(id: int) -> void:
	var p: Dictionary = players[id]
	if p.enemy.has("quest_id"):
		var previous: Dictionary = p.enemy
		p.enemy = {}
		quests.fight_result(id, previous.quest_id, previous.quest_objective, previous.get("quest_any", false))
		return
	var lost := int(p.silver * 0.08)
	p.silver -= lost
	p.deaths += 1
	p.enemy = {}
	p.fight = 0
	p.auto = "停止"
	p.place = "揚州城"
	p.hp = maxi(1, int(p.max_hp) / 2)
	tell(id, "你重傷倒地，被路人送回揚州。遺失 %d 兩，游俠已停止。" % lost, "戰鬥")

func victory(id: int, reward: Dictionary = {}, loot: bool = true) -> void:
	var p: Dictionary = players[id]
	var e: Dictionary = p.enemy if reward.is_empty() else reward
	if e.has("quest_id"):
		var remaining: Array = e.get("quest_enemies", [])
		if not remaining.is_empty():
			var next: Dictionary = Data.ENEMIES[remaining[0]].duplicate(true)
			next.merge({"name": "機緣考較 · " + str(remaining[0]), "max_hp": next.hp, "quest_id": e.quest_id, "quest_objective": e.quest_objective, "quest_any": e.quest_any, "quest_enemies": remaining.slice(1), "exp": 0, "combat_xp": 0, "potential": 0, "silver": 0, "drops": []}, true)
			p.enemy = next
			return
		p.enemy = {}
		quests.fight_result(id, e.quest_id, e.quest_objective, true)
		return
	p.exp += e.exp
	p.potential += e.potential
	p.silver += e.silver
	p.session_silver += e.silver
	p.kills += 1
	p.session_kills += 1
	if p.sect != "江湖散人": p.contribution += 1
	if not p.job.is_empty() and p.job.target == e.name:
		p.job.count = mini(int(p.job.need), int(p.job.count) + 1)
	tell(id, "擊敗%s！閱歷 +%d，潛能 +%d，銀兩 +%d。" % [e.name, e.exp, e.potential, e.silver], "收穫")
	if loot and rng.randf() < 0.18:
		p.inventory["金創藥"] = int(p.inventory.get("金創藥", 0)) + 1
		tell(id, "你拾得一瓶金創藥。", "收穫")
	for drop in e.get("drops", []) if loot else []:
		if rng.randf() < float(drop.chance):
			p.inventory[drop.item] = int(p.inventory.get(drop.item, 0)) + 1
			tell(id, "你拾得%s。" % drop.item, "收穫")
	p.enemy = {}
	# Original progression is martial proficiency and lifetime combat XP;
	# retained legacy character level no longer grants attack, HP or healing.
	p.combat_xp += int(e.get("combat_xp", e.exp))
	p.lilian += 1
	if e.has("quest_id"): quests.fight_result(id, str(e.quest_id), str(e.quest_objective), true)

func snapshot(id: int) -> Dictionary:
	if not players.has(id): return {}
	var roster: Array = []
	for peer in players:
		var p: Dictionary = players[peer]
		roster.append({"id": peer, "name": p.name, "sect": p.sect, "level": p.level, "combat_xp": p.combat_xp, "place": p.place, "hp": p.hp, "max_hp": p.max_hp, "party": p.party, "fight": p.fight, "pk_enabled": p.pk_enabled, "pvp_wins": p.pvp_wins})
	return {"player": players[id].duplicate(true), "roster": roster, "tick": tick, "social": social.snapshot(id), "self_id": id}
