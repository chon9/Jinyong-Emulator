extends RefCounted
## A separate campaign namespace: legacy characters and multiplayer stay intact.
const HEROES := {
	"hero": {"name":"無名少俠", "role":"劍客 · 破綻追擊", "art":"unit_player_m", "hp":430, "atk":72, "def":23, "speed":76, "qi":8, "lane":1, "front":true, "outer":"青山劍訣", "inner":"吐納功", "light":"雁行步", "bio":"你帶著一封無字的舊信來到青溪。信紙裡，藏著父親最後一次押鏢的去向。", "talent":"趁隙：攻擊流血或破甲目標，傷害增加 30%。"},
	"sword": {"name":"顧長風", "role":"快劍 · 越陣點穴", "art":"unit_huashan_m", "hp":350, "atk":75, "def":17, "speed":93, "qi":9, "lane":2, "front":false, "outer":"落英劍法", "inner":"吐納功", "light":"雁行步", "bio":"被鏢局除名的年輕劍客。他嘴上說只為討薪，卻一直守著失鏢者的家人。", "talent":"疾劍：全隊最快的出手，飛燕穿雲可以越過前排。"},
	"healer": {"name":"沈青棠", "role":"醫者 · 清毒續航", "art":"unit_emei_f", "hp":360, "atk":48, "def":18, "speed":81, "qi":11, "lane":1, "front":false, "outer":"回春掌", "inner":"長春功", "light":"踏雪步", "bio":"青溪藥廬的醫者。她在運回的藥箱裡發現暗記，決意親自查明真相。", "talent":"仁心：回春拂穴治療最低氣血的同伴，並解除中毒與流血。"},
	"staff": {"name":"陸衡", "role":"棍衛 · 護陣斷招", "art":"unit_shaolin_m", "hp":620, "atk":57, "def":35, "speed":61, "qi":8, "lane":0, "front":true, "outer":"伏虎棍法", "inner":"金鐘心法", "light":"雁行步", "bio":"在渡口幫工的少林俗家弟子。師父說護住眼前的人，比爭論正邪更難。", "talent":"定海：金剛截脈可打斷蓄力；守勢能替後排承受攻擊。"}
}
const ARTS := {
	"青山劍訣":{"slot":"outer","weapon":"劍","skill":"青山一線","cost":50,"cd":2,"kind":"bleed","power":1.6,"text":"單體 160% 傷害，附加 2 回合流血。主角可接破綻追擊。"},
	"華山劍法":{"slot":"outer","weapon":"劍","skill":"白雲出岫","cost":75,"cd":2,"kind":"cleave","power":1.35,"text":"橫掃同列敵人，各造成 135% 傷害。需華山入門、劍法三重。"},
	"武當綿掌":{"slot":"outer","weapon":"拳掌","skill":"綿勁破甲","cost":50,"cd":2,"kind":"break","power":1.4,"text":"單體 140% 傷害，降低防禦 50%，持續 2 回合。"},
	"落英劍法":{"slot":"outer","weapon":"劍","skill":"飛燕穿雲","cost":50,"cd":2,"kind":"pierce","power":1.75,"text":"可指定敵方後排，造成 175% 傷害。"},
	"回春掌":{"slot":"outer","weapon":"拳掌","skill":"回春拂穴","cost":50,"cd":2,"kind":"heal","power":2.7,"text":"治療氣血比例最低的同伴，清除流血與毒。"},
	"伏虎棍法":{"slot":"outer","weapon":"棍","skill":"金剛截脈","cost":50,"cd":3,"kind":"stun","power":1.1,"text":"單體 110% 傷害，封招 1 次；打斷首領蓄力。"},
	"吐納功":{"slot":"inner","hp":0,"def":0,"qi":0,"text":"均衡運氣，開戰真元 50。"},
	"金鐘心法":{"slot":"inner","hp":100,"def":10,"qi":-2,"text":"氣血 +100、防禦 +10，聚氣 -2。適合前排。"},
	"長春功":{"slot":"inner","hp":35,"def":0,"qi":3,"text":"氣血 +35、聚氣 +3。適合需要頻繁施招的角色。"},
	"雁行步":{"slot":"light","speed":12,"evade":0,"text":"速度 +12，先手布下控制或破綻。"},
	"踏雪步":{"slot":"light","speed":0,"evade":12,"text":"身法 +12，提高閃避。"}
}
const PLACES := {
	"青溪客棧":{"pos":Vector2(285,280),"tag":"客棧","desc":"雨打竹簷，酒香裡混著一絲藥味。顧長風獨坐窗邊，盯著桌上一枚折斷的鏢。","npc":"顧長風","face":"unit_huashan_m","bg":"bg_huayin_road","links":["渡口","藥廬","市集","演武坪"]},
	"渡口":{"pos":Vector2(690,455),"tag":"江岸","desc":"青溪渡口的船都被鑿穿了。泥地上有拖走藥箱的痕跡，幾名黑衣人正逼問船翁。","npc":"老船翁","face":"unit_look_m06","bg":"bg_river_road","links":["青溪客棧","蘆葦蕩","古寺"]},
	"藥廬":{"pos":Vector2(505,155),"tag":"醫館","desc":"白芷和當歸曬滿竹架。沈青棠打開空空的藥櫃：鎮上的退熱藥，已經撐不到明天。","npc":"沈青棠","face":"unit_emei_f","bg":"bg_huayin_road","links":["青溪客棧","市集","蘆葦蕩"]},
	"蘆葦蕩":{"pos":Vector2(920,345),"tag":"野外","desc":"水聲掩著腳步聲。遺落的麻袋上繡著鏢局紋章，旁邊卻躺著一個受傷的山賊。","npc":"受傷的鏢師","face":"unit_m_bandit","bg":"bg_river_road","links":["渡口","藥廬","舊倉"]},
	"古寺":{"pos":Vector2(935,150),"tag":"山寺","desc":"晨鐘過後，陸衡仍在替難民生火。寺中石碑背面，有鏢師留下的半截字跡。","npc":"陸衡","face":"unit_shaolin_m","bg":"bg_huayin_road","links":["渡口","演武坪","舊倉"]},
	"市集":{"pos":Vector2(270,480),"tag":"商貿","desc":"鐵匠的火還亮著。商販願意收購沿河採來的草藥，也留了幾瓶金創藥給出行的人。","npc":"陳掌櫃","face":"unit_gaibang_f","bg":"bg_huayin_road","links":["青溪客棧","藥廬","演武坪"]},
	"演武坪":{"pos":Vector2(520,330),"tag":"師門","desc":"松間一方練武坪。雲遊的師父願以入門武學相授，但學到的招式，還須用在真正的江湖裡。","npc":"雲遊師父","face":"unit_wudang_m","bg":"bg_huayin_road","links":["青溪客棧","古寺","市集"]},
	"舊倉":{"pos":Vector2(1115,490),"tag":"險地","desc":"鏽鎖後藏著失去的藥箱。黑風寨主正在運轉毒功；密信的火漆，卻是鏢局自己的印。","npc":"黑風寨主","face":"unit_xuedao_m","bg":"bg_guiwang","links":["蘆葦蕩","古寺"]}
}
const OBJECTIVES := [
	["雨夜斷鏢","青溪客棧","與顧長風談談失鏢的事。"],
	["渡口風波","渡口","與船翁交談，擋下黑衣人的逼問。"],
	["藥箱暗記","藥廬","把斷鏢上的藥草氣味告訴沈青棠。"],
	["蘆花藏影","蘆葦蕩","救出受傷的鏢師，查明藥箱去向。"],
	["鐘聲有信","古寺","尋找陸衡，辨認鏢師留下的字跡。"],
	["失鏢真相","舊倉","選擇如何處理密信，迎戰黑風寨主。"],
	["燈下歸人","青溪客棧","回到客棧，將密信交給顧長風。"],
	["第一章 · 青溪失鏢","青溪客棧","此間事了。可繼續練武、重戰舊倉，探索同伴故事。"]
]
const SHOP := {"金創藥":{"price":20,"sell":10,"desc":"戰鬥中立即恢復一名同伴 140 氣血；每回合全隊限用一次。"},"草藥":{"price":8,"sell":4,"desc":"江岸採集的藥材。可賣給掌櫃，或交給沈青棠。"}}
var state: Dictionary

func _init(saved: Dictionary = {}) -> void:
	state = {"version":1,"stage":0,"place":"青溪客棧","party":["hero"],"silver":100,"potential":90,"sect":"未入門","levels":{},"loadouts":{},"formation":{},"inventory":{"金創藥":3,"草藥":0},"flags":{},"journal":[],"wins":0,"study":""}
	for id in HEROES:
		state.levels[id] = 1
		state.loadouts[id] = {"outer":HEROES[id].outer,"inner":HEROES[id].inner,"light":HEROES[id].light}
		state.formation[id] = {"lane":HEROES[id].lane,"front":HEROES[id].front}
	if valid_save(saved) and not saved.is_empty():
		for key in state:
			if saved.has(key): state[key] = saved[key]
	state.study = ""

static func valid_save(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.get("version") != 1: return false
	for key in ["stage","silver","potential","wins"]:
		var n: Variant = value.get(key)
		if not (n is int or n is float) or not is_finite(float(n)) or n < 0 or n > 1000000: return false
	if value.stage > 7 or not PLACES.has(value.get("place", "")): return false
	if not value.get("party") is Array or value.party.size() < 1 or value.party.size() > 4 or value.party[0] != "hero": return false
	var seen := {}
	for id in value.party:
		if not HEROES.has(id) or seen.has(id): return false
		seen[id] = true
	for key in ["levels","loadouts","formation","inventory","flags"]:
		if not value.get(key) is Dictionary: return false
	for id in HEROES:
		var level: Variant = value.levels.get(id)
		if not (level is int or level is float) or not is_finite(float(level)) or level < 1 or level > 10: return false
		var build: Variant = value.loadouts.get(id)
		if not build is Dictionary: return false
		for slot in ["outer","inner","light"]:
			if not ARTS.has(build.get(slot, "")) or ARTS[build[slot]].slot != slot: return false
		if id != "hero" and build.outer != HEROES[id].outer: return false
		if id == "hero" and not build.outer in ["青山劍訣","華山劍法","武當綿掌"]: return false
		var f: Variant = value.formation.get(id)
		if not f is Dictionary or not f.get("front") is bool: return false
		if not (f.get("lane") is int or f.get("lane") is float) or not is_finite(float(f.lane)) or float(f.lane) != int(f.lane) or int(f.lane) < 0 or int(f.lane) > 2: return false
	for key in value.inventory:
		var n: Variant = value.inventory[key]
		if not SHOP.has(key) or not (n is int or n is float) or not is_finite(float(n)) or n < 0 or n > 9999: return false
	if not value.get("journal") is Array or value.journal.size() > 80: return false
	for entry in value.journal:
		if not entry is String or entry.length() > 500: return false
	if not value.get("sect", "") in ["未入門","華山","武當","少林"]: return false
	return true

func objective() -> Array:
	return OBJECTIVES[int(state.stage)]

func record(text: String) -> void:
	state.journal.append(text)
	if state.journal.size() > 80: state.journal.pop_front()

func advance(stage: int, text: String) -> void:
	state.stage = stage
	record(text)

func unit(id: String) -> Dictionary:
	var u: Dictionary = HEROES[id].duplicate(true)
	u.id = id
	u.level = int(state.levels[id])
	u.merge(state.loadouts[id], true)
	u.merge(state.formation[id], true)
	u.max_hp = int(u.hp) + (u.level - 1) * 28 + int(ARTS[u.inner].get("hp",0))
	u.hp = u.max_hp
	u.atk += (u.level - 1) * 7
	u.def += int(ARTS[u.inner].get("def",0))
	u.qi += int(ARTS[u.inner].get("qi",0))
	u.speed += int(ARTS[u.light].get("speed",0))
	u.evade = int(ARTS[u.light].get("evade",0))
	u.weapon = ARTS[u.outer].weapon
	return u

func available_outer(id: String) -> Array:
	if id != "hero": return [HEROES[id].outer]
	var result := ["青山劍訣"]
	if state.sect == "武當": result.append("武當綿掌")
	if state.sect == "華山" and state.levels.hero >= 3 and state.flags.get("advanced",false): result.append("華山劍法")
	return result

func equip(id: String, slot: String, art: String) -> String:
	if not id in state.party or not ARTS.has(art) or ARTS[art].slot != slot: return "武學不相容。"
	if slot == "outer" and not art in available_outer(id): return "尚未學會這門外功。"
	state.loadouts[id][slot] = art
	return "已激發「%s」。兵器隨外功切換為相容類型。" % art

func position_hero(id: String, lane: int, front: bool) -> void:
	if not id in state.party or lane < 0 or lane > 2: return
	var old: Dictionary = state.formation[id].duplicate()
	for other in state.party:
		if other != id and int(state.formation[other].lane) == lane and state.formation[other].front == front:
			state.formation[other] = old
			break
	state.formation[id] = {"lane":lane,"front":front}

func train(id: String, self_study: bool = false) -> String:
	if not id in state.party: return "同伴尚未加入。"
	if int(state.levels[id]) >= 10: return "本章修為已達十重。"
	if not self_study and state.place != "演武坪": return "請到演武坪向師父消點。"
	if state.sect == "未入門" and state.levels[id] >= 2: return "先在演武坪選擇師門，再修更深的武學。"
	var cost := (8 if self_study else 12) + int(state.levels[id]) * 3
	if state.potential < cost: return "學點不足，需要 %d 點；完成任務或戰鬥可得。" % cost
	state.potential -= cost
	state.levels[id] = int(state.levels[id]) + 1
	return "%s武學提升至 %d 重，消耗 %d 學點。" % [HEROES[id].name,state.levels[id],cost]

func trade(item: String, buy: bool) -> String:
	if state.place != "市集" or not SHOP.has(item): return "請到市集與掌櫃交易。"
	if buy:
		if state.silver < SHOP[item].price: return "銀兩不足。"
		state.silver -= SHOP[item].price
		state.inventory[item] = int(state.inventory.get(item,0)) + 1
	else:
		if state.inventory.get(item,0) < 1: return "行囊裡沒有此物。"
		state.inventory[item] -= 1
		state.silver += SHOP[item].sell
	return ("買入" if buy else "售出") + item

func talk() -> Dictionary:
	var place: String = state.place
	var stage := int(state.stage)
	var text: String = PLACES[place].desc
	var choices: Array = []
	match place:
		"青溪客棧":
			if stage == 0:
				text = "這枚鏢，是你父親用過的樣式？三日前，鏢隊在渡口失蹤，押送的只是救命藥材。有人說是山賊，可我見過那傷口——那是鏢局自己的劍。你若要查，我陪你走一程。"
				choices = [["一起去渡口查明真相","recruit_sword"]]
			elif stage == 6:
				text = "原來鏢頭為了私吞賑災銀，連自己人都不放過。你沒有把這封信燒掉……謝了。等藥材送到，我便陪你去找信裡提到的那個人。這一次，路由我們自己選。"
				choices = [["讓真相留在江湖","ending"]]
			elif stage >= 7: text = "青溪的燈又亮了。我聽說北邊有位老鏢師見過你父親。下次上路前，先把本事練好；對了，舊倉的武夫還等著與我們切磋。"
			else: text = "斷鏢上的藥味不是巧合。先沿著線索查，不要錯怪了真正押鏢的人。"
		"渡口":
			if stage == 1:
				text = "他們不是來找藥的，是來滅口！我昨夜看見有人把藥箱拖進蘆葦蕩……小心，你身後！"
				choices = [["護住船翁 · 迎戰黑衣人","battle_ferry"]]
			else: text = "老漢這條命是你們救的。河水記得每一個過路的人，偏偏人有時不肯記得自己的來處。"
		"藥廬":
			if stage == 2:
				text = "鏢上的是白芷香。這種熏藥只給運往蘆葦蕩的藥箱用。那些病人等不起了，我與你同去——我的掌法能療傷，但要替我擋住前面的刀。"
				choices = [["邀沈青棠同行","recruit_healer"]]
			else: text = "每一味藥都有用，就像每個人都該有自己的位置。受傷的人回到鎮上，我都會替他們療傷；在戰場上，記得替我留足真元。"
			if not state.flags.get("herbs",false): choices.append(["交付三株草藥 · 救急藥方","give_herbs"])
		"蘆葦蕩":
			if stage == 3:
				text = "別動手……我是替鏢局運貨的。寨裡的人病了，想拿藥救人，鏢頭卻要燒掉所有證據。後面那些人是他派來的！救救我，我把藏信的地方告訴你。"
				choices = [["先救人，再問是非","battle_reeds"]]
			else: text = "蘆花上掛著露珠，舊路邊還有些可以入藥的草。"
			choices.append(["採集草藥 · 每次一株","gather"])
		"古寺":
			if stage == 4:
				text = "碑後寫著『倉底有信，火漆為證』。我曾在少林學過幾年棍法，不能眼看有人借俠義二字害人。算我一個；對方蓄力時，讓我出棍截脈。"
				choices = [["邀陸衡入隊 · 四人同行","recruit_staff"]]
			else: text = "棍可以破敵，也可以攔在同伴面前。把我放在前排，讓青棠安心運氣。"
		"舊倉":
			if stage == 5:
				text = "黑風寨主擋住去路：『我們劫藥是為救人，鏢頭卻要我們替他頂罪。你若信我，就把密信帶出去；若只信手裡的劍，便先打贏我！』"
				choices = [["先救寨中病人 · 全隊初始真元 +25","choose_mercy"],["封存毒砂證物 · 毒砂客攻擊 −15","choose_justice"]]
			elif stage >= 6:
				text = "寨主放下刀：『你們的陣法，我服。往後還可來此切磋，但別忘了那封信。』"
				choices = [["切磋 · 再戰黑風寨主","battle_rematch"]]
			else: text = "倉門從裡面鎖住了。先循著斷鏢、藥箱和古寺的線索調查。"
		"演武坪":
			text = "外功決定招式與兵器，內功決定氣血、聚氣，輕功決定先後手與身法。莫把會的招式都塞上去；先想明白，誰來護、誰來破、誰來收。"
			if state.sect == "未入門": choices = [["拜入華山 · 劍法橫掃","sect_華山"],["拜入武當 · 綿掌破甲","sect_武當"],["拜入少林 · 金鐘護體","sect_少林"]]
			elif state.sect == "華山" and not state.flags.get("advanced",false): choices = [["請教華山劍法 · 需主角三重、勝一戰、20 學點","advanced"]]
	return {"name":PLACES[place].npc,"text":text,"choices":choices}

func choose(key: String) -> String:
	# All campaign transitions recheck both location and stage; stale UI cannot skip chapters.
	var offered := false
	for option in talk().choices:
		if option[1] == key: offered = true
	if not offered: return "這段對話已經有新的進展。"
	match key:
		"recruit_sword":
			state.party.append("sword")
			advance(1,"顧長風加入。斷鏢的主人，曾在渡口出現。")
		"recruit_healer":
			state.party.append("healer")
			advance(3,"沈青棠加入。藥箱的去向指向蘆葦蕩。")
		"recruit_staff":
			state.party.append("staff")
			state.potential += 35
			advance(5,"陸衡加入。密信藏在舊倉，全隊準備迎戰。")
		"ending":
			state.silver += 120
			state.potential += 80
			advance(7,"青溪失鏢結案。你保下藥材與密信，獲得 120 銀、80 學點。" if state.flags.get("choice") == "mercy" else "青溪失鏢結案。你封存證據，使鏢頭無法狡辯，獲得 120 銀、80 學點。")
		"gather":
			if state.inventory.get("草藥",0) >= 20: return "藥簍已滿，先到市集出售或交付草藥。"
			state.inventory["草藥"] = int(state.inventory.get("草藥",0)) + 1
			return "採得草藥一株。可交付藥廬支線或到市集出售。"
		"give_herbs":
			if state.inventory.get("草藥",0) < 3: return "還需要三株草藥，可到蘆葦蕩採集。"
			state.inventory["草藥"] -= 3
			state.inventory["金創藥"] = int(state.inventory.get("金創藥",0)) + 2
			state.potential += 25
			state.flags.herbs = true
			record("支線・救急藥方完成。青棠收下草藥，贈你兩瓶金創藥、25 學點。")
		"advanced":
			if state.levels.hero < 3 or state.wins < 1 or state.potential < 20: return "需要主角三重、至少勝一戰，並消耗 20 學點。"
			state.potential -= 20
			state.flags.advanced = true
			return "習得華山劍法。可在武學頁激發白雲出岫。"
		_:
			if key.begins_with("sect_"):
				state.sect = key.trim_prefix("sect_")
				state.potential += 30
				if state.sect == "武當": state.loadouts.hero.outer = "武當綿掌"
				if state.sect == "少林": state.loadouts.hero.inner = "金鐘心法"
				record("拜入%s，師父授予 30 學點。" % state.sect)
			elif key.begins_with("choose_"):
				state.flags.choice = "mercy" if key == "choose_mercy" else "justice"
	return "江湖記事已更新。"

func win(encounter: String) -> void:
	state.wins += 1
	state.silver += 30
	state.potential += 25
	if encounter == "ferry" and state.stage == 1: advance(2,"船翁獲救，斷鏢上的白芷香指向藥廬。戰利品：30 銀、25 學點。")
	elif encounter == "reeds" and state.stage == 3: advance(4,"鏢師獲救。他說古寺石碑背面留著半封信。戰利品：30 銀、25 學點。")
	elif encounter == "warehouse" and state.stage == 5: advance(6,"黑風寨主認輸，交出藥材與密信。回客棧與顧長風作最後的交談。")
	else: record("切磋獲勝，得到 30 銀、25 學點。")
