extends RefCounted
## 純規則引擎。單機與聯機主機使用同一份規則；客戶端只發出意圖。

signal event(peer_id: int, channel: String, message: String)
const Data = preload("res://scripts/content.gd")
const Social = preload("res://scripts/social.gd")
var social
var players: Dictionary = {}
var tick: int = 0
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()
	social = Social.new(self)

func add_player(id: int, title: String = "無名少俠") -> Dictionary:
	var p := {
		"name": clean_name(title), "level": 1, "exp": 0, "potential": 100, "silver": 80,
		"hp": 120, "max_hp": 120, "mp": 60, "max_mp": 60, "energy": 100,
		"sect": "江湖散人", "contribution": 0, "place": "揚州城",
		"skills": {"基本拳腳": 1, "基本內功": 1}, "equipped": "基本拳腳",
		"inventory": {"金創藥": 5, "養氣丹": 3}, "weapon": "", "armor": "",
		"auto": "停止", "auto_heal": true, "heal_at": 45, "auto_skill": "基本拳腳",
		"teacher": "", "skill_xp": {}, "talked": {}, "stories": {}, "story_choices": {}, "visited": {"揚州城": true},
		"searched": {}, "deliveries": {},
		"enemy": {}, "kills": 0, "deaths": 0, "job": {}, "cooldown": -1,
		"stance": "普通", "session_kills": 0, "session_silver": 0
	}
	p.merge({"party": 0, "follow": false, "fight": 0, "pk_enabled": false, "pvp_wins": 0, "pvp_losses": 0})
	players[id] = p
	return p

static func clean_name(value: String) -> String:
	var cleaned := value.strip_edges().replace("\n", "").replace("\r", "").replace("\t", "")
	return cleaned.left(12) if not cleaned.is_empty() else "無名少俠"

static func attack(p: Dictionary) -> int:
	var skill := int(p.skills.get(p.equipped, 1))
	var bonus := 0 if not Data.SECTS.has(p.sect) else int(Data.SECTS[p.sect].attack)
	var advanced: bool = Data.SECTS.has(p.sect) and p.equipped == Data.SECTS[p.sect].advanced
	return 12 + int(p.level) * 3 + skill * 2 + bonus + int(Data.SHOP.get(p.weapon, {}).get("attack", 0)) + (skill if advanced else 0)

static func defense(p: Dictionary) -> int:
	return 2 + int(p.level) + int(p.skills.get("基本內功", 1)) / 3 + int(Data.SHOP.get(p.armor, {}).get("defense", 0))

static func exp_needed(p: Dictionary) -> int:
	return int(p.level) * 70

func tell(id: int, message: String, channel: String = "江湖") -> void:
	event.emit(id, channel, message)

func act(id: int, command: String, arg: String = "") -> bool:
	if not players.has(id):
		return false
	var p: Dictionary = players[id]
	if command in Social.COMMANDS: return social.act(id, command, arg)
	if int(p.fight) != 0 and command in ["前往", "拜師", "練功", "消點", "自修", "對話", "故事選擇", "搜查", "交付", "裝備", "打怪", "打坐", "休息", "購買", "出售", "掛機"]:
		return reject(id, "先結束戰鬥或逃跑，再執行此操作。")
	match command:
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
			p.sect = arg
			p.skills[sect.basic] = 1
			p.equipped = sect.basic
			p.auto_skill = sect.basic
			if sect.has("virtue"): p.skills[sect.virtue] = 1
			p.max_hp += sect.hp
			p.hp = p.max_hp
			tell(id, "%s收你為%s弟子，傳授%s。你的江湖，自此有了師承。" % [sect.master, arg, sect.basic], "武學")
		"練功", "消點": return learn(id, arg)
		"自修":
			if not p.skills.has(arg): return reject(id, "先向師父學會這門武功，才能自修。")
			if not p.enemy.is_empty(): return reject(id, "交戰中無法自修。")
			p.auto_skill = arg
			p.auto = "自修"
			tell(id, "開始自修%s。每息消耗 2 精力與 1 內力，累積熟練後升級，不消耗學點與銀兩。" % arg, "修行")
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
			if p.skills.has(arg) and arg != "基本內功":
				p.equipped = arg
			elif int(p.inventory.get(arg, 0)) > 0 and Data.SHOP.has(arg) and Data.SHOP[arg].type in ["WEAPON", "ARMOR"]:
				p["weapon" if Data.SHOP[arg].type == "WEAPON" else "armor"] = arg
			else: return reject(id, "你尚未擁有這項武學或裝備。")
			tell(id, "你已裝備%s。" % arg, "武學")
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
			p.auto_skill = arg
		"招式":
			if not arg in ["普通", "重擊", "防守"]: return false
			p.stance = arg
		"逃跑":
			if int(p.fight) != 0: return social.flee(id)
			if p.enemy.is_empty(): return reject(id, "你並未陷入戰鬥。")
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
			p.job = {}
			tell(id, "懸賞完成！獲得 60 兩、40 潛能、8 貢獻。", "任務")
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
		if row.skill == skill and (teacher == "" or row.npc == teacher):
			lesson = row
			break
	if lesson.is_empty(): return reject(id, "請到授業師父身邊消點；可在武學頁查看師承與路線。")
	for req in lesson.requires:
		if int(p.skills.get(req.skill, 0)) < int(req.level): return reject(id, "學習%s需要%s %d 級。" % [skill, req.skill, req.level])
	var level := int(p.skills.get(skill, 0))
	if level >= int(lesson.cap): return reject(id, "已達這位師父的授業上限 %d 級；可尋訪高師或自修突破。" % lesson.cap)
	if p.cooldown == tick: return false
	var cost := 5 + level * 2
	if int(p.potential) < cost or int(p.silver) < int(lesson.price) or int(p.energy) < 3:
		return reject(id, "消點需 %d 學點、%d 兩與 3 精力。刷怪賺學點，打坐回復精力。" % [cost, lesson.price])
	p.cooldown = tick
	p.potential -= cost
	p.silver -= int(lesson.price)
	p.energy -= 3
	p.skills[skill] = level + 1
	p.auto_skill = skill
	p.teacher = lesson.npc
	if skill == "基本內功": p.max_mp += 3
	tell(id, "%s指點%s：%d → %d 級，消耗 %d 學點與 %d 兩。" % [Data.NPCS[lesson.npc].name, skill, level, level + 1, cost, lesson.price], "消點")
	return true

func self_study(id: int) -> void:
	var p: Dictionary = players[id]
	var skill: String = p.auto_skill
	var level := int(p.skills.get(skill, 0))
	if level <= 0 or level >= 100 or p.energy < 2 or p.mp < 1:
		p.auto = "停止"
		tell(id, "自修已停止：需要已學武功、精力及內力，等級上限 100。", "修行")
		return
	p.energy -= 2
	p.mp -= 1
	var difficulty := float(Data.SKILLS.get(skill, {}).get("difficulty", 1.0))
	var gain := maxi(1, int(6.0 / maxf(0.5, difficulty)))
	var needed := 12 + level * 3
	p.skill_xp[skill] = int(p.skill_xp.get(skill, 0)) + gain
	if int(p.skill_xp[skill]) >= needed:
		p.skill_xp[skill] -= needed
		p.skills[skill] = level + 1
		if skill == "基本內功": p.max_mp += 3
		tell(id, "你反覆推敲招意，%s自修至 %d 級。" % [skill, level + 1], "自修")

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
			if p.hp == p.max_hp and p.mp == p.max_mp and p.energy == 100:
				p.auto = "停止"
				tell(id, "調息完畢，精氣神已恢復。", "修行")
		elif tick % 4 == 0:
			p.energy = mini(100, int(p.energy) + 1)
			p.mp = mini(int(p.max_mp), int(p.mp) + 1)
	social.step()

func roll_damage(p: Dictionary, armor: int) -> int:
	var damage := maxi(1, attack(p) - armor + rng.randi_range(-3, 3))
	if p.stance == "重擊" and int(p.mp) >= 6:
		p.mp -= 6
		damage = int(damage * 1.65)
	elif p.stance == "防守": damage = maxi(1, int(damage * .7))
	if rng.randf() < .1: damage = int(damage * 1.5)
	return damage

func combat(id: int) -> void:
	var p: Dictionary = players[id]
	var e: Dictionary = p.enemy
	var damage := maxi(1, attack(p) - int(e.defense) + rng.randi_range(-3, 3))
	var style: String = p.equipped
	var moves: Array = Data.SKILLS.get(p.equipped, {}).get("moves", [])
	if not moves.is_empty(): style = str(moves[mini(moves.size() - 1, int(p.skills.get(p.equipped, 1)) / 30)])
	if p.stance == "重擊" and p.mp >= 6:
		p.mp -= 6
		damage = int(damage * 1.65)
		style += "・重擊"
	elif p.stance == "防守":
		damage = maxi(1, int(damage * 0.7))
	var critical := rng.randf() < 0.1
	if critical: damage = int(damage * 1.5)
	e.hp = maxi(0, int(e.hp) - damage)
	tell(id, "%s%s，對%s造成 %d 傷害。%s" % ["會心！" if critical else "", style, e.name, damage, "（%d/%d）" % [e.hp, e.max_hp]], "戰鬥")
	if e.hp <= 0:
		victory(id)
		return
	var received := maxi(1, int(e.attack) - defense(p) + rng.randi_range(-2, 2))
	if p.stance == "防守": received = maxi(1, int(received * 0.45))
	p.hp = maxi(0, int(p.hp) - received)
	tell(id, "%s反擊，你損失 %d 氣血。" % [e.name, received], "戰鬥")
	if p.hp <= 0:
		defeat(id)

func defeat(id: int) -> void:
	var p: Dictionary = players[id]
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
	while p.exp >= exp_needed(p) and p.level < 50:
		p.exp -= exp_needed(p)
		p.level += 1
		p.max_hp += 18
		p.max_mp += 6
		p.hp = p.max_hp
		p.mp = p.max_mp
		tell(id, "江湖境界提升至 %d 級，氣血與內力恢復！" % p.level, "成長")

func snapshot(id: int) -> Dictionary:
	if not players.has(id): return {}
	var roster: Array = []
	for peer in players:
		var p: Dictionary = players[peer]
		roster.append({"id": peer, "name": p.name, "sect": p.sect, "level": p.level, "place": p.place, "hp": p.hp, "max_hp": p.max_hp, "party": p.party, "fight": p.fight, "pk_enabled": p.pk_enabled, "pvp_wins": p.pvp_wins})
	return {"player": players[id].duplicate(true), "roster": roster, "tick": tick, "social": social.snapshot(id), "self_id": id}
