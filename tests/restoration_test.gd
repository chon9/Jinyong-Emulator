extends SceneTree
const Rules = preload("res://scripts/world.gd")
const Data = preload("res://scripts/content.gd")
const Training = preload("res://scripts/progression.gd")
var checks := 0
var failures: Array = []

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); push_error(description)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var w := Rules.new()
	var p: Dictionary = w.add_player(1)
	check(Training.lesson_gain(p) == 15 and Training.study_gain(p) == 23, "Wit 30: historical point-to-proficiency gains")
	check(Training.energy_cost(p) == 5, "Wit 30: five energy per training action")
	p.skills["讀書識字"] = 100
	check(Training.attrs(p).wit == 40 and Training.lesson_gain(p) == 20 and Training.energy_cost(p) == 1, "Literacy raises wit and changes actual study costs")
	check(Training.needed("華山劍法", 25) == 14061, "2001 level 25-to-26 Huashan example: cubic threshold")
	check(Training.needed("天山折梅手", 29) == 33750, "2002 measured Folding-Plum level 30 threshold")
	p = w.add_player(1)
	check(Training.xp_cap(p) == 5, "No combat experience means a level-five martial ceiling")
	var npc := "n_xx_wushi"
	p.place = Data.NPCS[npc].place
	var skill: String = Data.NPCS[npc].teach[0].skill
	var points: int = p.potential
	check(w.act(1, "消點", npc + "|" + skill), "Local instruction accepted")
	check(p.potential == points - 1 and int(p.skills[skill]) > 0, "Instruction consumes one point for proficiency")
	check(not w.act(1, "消點", npc + "|" + skill) and p.potential == points - 1, "Same-tick requests cannot duplicate instruction")
	p.skills[skill] = 4
	p.skill_xp[skill] = 0
	w.tick += 1
	check(w.act(1, "消點", npc + "|" + skill), "Instruction on a partly mastered art")
	check(p.skills[skill] == 4 and p.skill_xp[skill] == 15, "Instruction gains proficiency rather than granting a whole level")
	p.skills[skill] = 5
	w.tick += 1
	points = p.potential
	check(not w.act(1, "消點", npc + "|" + skill) and p.potential == points, "XP ceiling rejection is resource-neutral")
	p.skills[skill] = 1
	p.skill_xp[skill] = 0
	p.energy = 100
	check(w.act(1, "自修", skill), "Self-study starts")
	points = p.potential
	var mp: int = p.mp
	for i in 4: w.step()
	check(p.potential == points and p.skill_xp[skill] == 0, "Incomplete five-second cycle grants no proficiency and charges nothing")
	w.act(1, "停止")
	w.act(1, "自修", skill)
	for i in 4: w.step()
	check(p.potential == points, "Interrupting and restarting cannot carry a partial cycle")
	w.step()
	check(p.potential == points - 3 and p.energy == 95 and p.mp >= mp, "Full cycle spends three learning points and energy, without arbitrary MP drain")
	p.potential = 2
	var prof: int = p.skill_xp[skill]
	for i in 5: w.step()
	check(p.auto == "停止" and p.potential == 2 and p.skill_xp[skill] == prof, "Insufficient points stop study without partial deductions")
	p.combat_xp = 1000000
	p.skills["基本劍法"] = 20
	check(Training.study_cap(p, "太極劍法") == 30, "Corresponding basic art limits self-study to 1.5 times its level")
	p.skills["基本劍法"] = 140
	check(Training.study_cap(p, "太極劍法") == int(Data.SKILLS["太極劍法"].study_cap), "Basic level 140 removes the proportional ceiling")
	check(Training.check(p, [{"type": "attr_min", "attr": "str", "value": 90}]) != "", "Attribute requirements enforced")
	check(Training.check(p, [{"type": "gender", "value": "F"}]) != "", "Gender requirements enforced")
	check(Training.check(p, [{"type": "morality_min", "value": 50}]) != "", "Morality requirements enforced")
	check(Training.check(p, [{"type": "sect_master", "npc": "n_qz_mayu"}]) != "", "Personal-master requirements enforced")
	check(Training.check(p, [{"type": "quest_flag", "flag": "wd_q_taiji"}]) != "", "Quest unlock requirements enforced")
	check(Training.check(p, [{"type": "unknown_future_requirement"}]) != "", "Unknown condition types fail closed")
	check(not w.act(1, "先天配點", JSON.stringify({"str": 30, "wit": 30, "agi": 30, "con": 30, "cal": 30, "guts": 30, "luck": 30})), "Host rejects attribute budgets above the simulator allowance")
	check(w.act(1, "先天配點", JSON.stringify({"str": 26, "wit": 25, "agi": 25, "con": 28, "cal": 26, "guts": 25, "luck": 25})), "One-time build allocation can meet Wudang attribute requirements")
	check(not w.act(1, "先天配點", JSON.stringify(p.attrs)), "Confirmed attribute allocation cannot be repeated")
	p.skills["基本刀法"] = 0
	check(not w.act(1, "裝備", "基本刀法"), "A partially studied level-zero entry cannot be equipped")
	var old := {"rules_version": 0}
	p.skill_xp["基本劍法"] = 6
	p.skills["基本劍法"] = 2
	p.rules_version = 0
	Training.normalize(p)
	var converted: int = p.skill_xp["基本劍法"]
	check(converted == floori(6.0 / 18 * Training.needed("基本劍法", 2)), "Legacy within-level progress fraction survives curve conversion")
	Training.normalize(p)
	check(p.skill_xp["基本劍法"] == converted, "Save migration is idempotent")
	p = w.add_player(1)
	p.skills["太極拳"] = 61
	p.equipped = "太極拳"
	p.skills["搏擊格鬥"] = 0
	p.skills["基本內功"] = 0
	check(absf(Rules.Combat.attack_power(p, "太極拳") - pow(61, 3) * .395) < .001, "2002 measured Taiji cubic attack example")
	p.skills["太極拳"] = 70
	p.skills["拆招卸力"] = 100
	p.skills["基本內功"] = 100
	p.attrs.con = 15 # Control effective constitution at 25 for the numerical vector.
	p.combat_xp = 23000000
	Data.SHOP["測試鎧甲"] = {"defense": 440}
	p.armor = "測試鎧甲"
	check(absf(Rules.Combat.defense_power(p, "太極拳") - 1232) < 3, "2002 measured Taiji parry example within article rounding")
	p.armor = ""
	Data.SHOP.erase("測試鎧甲")
	var power := Rules.attack(p)
	p.level = 50
	check(Rules.attack(p) == power, "Legacy character level no longer inflates combat power")
	var chance := Rules.Combat.hit_chance(p, p, "太極拳")
	p.skills["閃躲縱躍"] = 200
	check(Rules.Combat.hit_chance(p, p, "太極拳") < chance, "Basic dodge affects hit probability")
	p.skills["太極拳"] = 80
	p.skills["搏擊格鬥"] = 100
	check(w.act(1, "格擋", "搏擊格鬥") and Rules.guard_art(p) == "搏擊格鬥" and p.equipped == "太極拳", "Parry art can be selected independently of attacking art")
	p.skills["太極劍法"] = 100
	p.skills["基本劍法"] = 20
	p.weapon = "木劍"
	p.mp = 1000
	p.energy = 100
	var move := Rules.Combat.choose_move(p, "太極劍法")
	var mana: int = p.mp
	var result := Rules.Combat.roll(p, {"defense": 1, "level": 1}, "太極劍法", "", w.rng)
	check(p.mp == mana - int(move.get("cost_inner", 0)) and p.mp >= 0, "Unlocked affordable move charges its actual inner-power cost")
	p.power = 10
	p.mp = 1
	move = Rules.Combat.choose_move(p, "太極劍法")
	check(move.is_empty() or ceili(int(move.get("cost_inner", 0)) * 2.0) <= 1, "Move affordability includes selected output force before selecting a move")
	# Every suggested destination points to a real room; teacher search is by art.
	var results := Data.destinations("武當心法", "揚州城")
	check(not results.is_empty(), "Search martial-art name to find its teachers")
	for entry in results:
		check(Data.PLACES.has(entry.place), "Search destination exists")
		check(Data.NPCS.values().any(func(n: Dictionary): return n.place == entry.place and n.teach.any(func(l: Dictionary): return l.skill == "武當心法")), "Teacher search sends player to actual teacher room")
	check(Data.path_to("不存在", "揚州城").is_empty() and Data.path_to("揚州城", "不存在").is_empty(), "Invalid route endpoints handled safely")
	p = w.add_player(1)
	var destination: String = Data.NPCS["n_wd_zhangsanfeng"].place
	var route := Data.path_to(p.place, destination)
	check(w.act(1, "尋路", destination), "Server starts a requested route")
	for next in route:
		var before: String = p.place
		w.step()
		check(p.place == next and p.place in Data.PLACES[before].exits, "Travel advances through one adjacent room per tick")
	check(p.place == destination and p.travel_target == "" and p.travel_route.is_empty(), "Travel stops on arrival at the exact destination")
	w.act(1, "尋路", "揚州城")
	w.act(1, "停止")
	var stopped: String = p.place
	w.step()
	check(p.place == stopped and p.travel_target == "", "Cancel stops travel immediately")
	p.enemy = {"name": "測試敵人", "hp": 1}
	check(not w.act(1, "尋路", "揚州城"), "Travel cannot bypass combat")
	p.enemy = {}
	p.follow = true
	check(not w.act(1, "尋路", "揚州城"), "Following and independent travel cannot conflict")
	p.follow = false
	# A real learning event: visiting the giver alone cannot award lightness.
	p = w.add_player(1)
	p.sect = "武當"
	p.skills.merge({"武當身法": 40, "俠義": 40})
	p.place = Data.NPCS[Data.QUESTS["q_wd_yinliu"].giver].place
	check(w.act(1, "接受任務", "q_wd_yinliu"), "Accept verified Yin Liting learning route")
	check(not w.act(1, "任務結局", "q_wd_yinliu|truth") and not p.skills.has("梯雲縱"), "Cannot claim event art before completing its stages")
	check(not w.act(1, "任務行動", "q_wd_yinliu|o_letter"), "Forged objective ID cannot complete a stage")
	check(w.act(1, "任務對話", "q_wd_yinliu|c_what") and w.act(1, "任務對話", "q_wd_yinliu|c_yes"), "Learning event giver conversation supplies the actual letter")
	p.place = Data.NPCS["n_em_jixiaofu"].place
	check(w.act(1, "任務行動", "q_wd_yinliu|o_ji"), "Yin Liting letter delivered to Ji Xiaofu")
	check(w.act(1, "任務對話", "q_wd_yinliu|c_letter") and w.act(1, "任務對話", "q_wd_yinliu|c_take"), "Scripted reply letter received through dialogue choices")
	p.place = Data.NPCS[Data.QUESTS["q_wd_yinliu"].giver].place
	check(w.act(1, "任務行動", "q_wd_yinliu|o_back"), "Return to Yin Liting for the learning event conclusion")
	check(w.act(1, "任務對話", "q_wd_yinliu|c_give") and w.act(1, "任務對話", "q_wd_yinliu|c_truth"), "Return letter consumed and truthful dialogue choice recorded")
	check(not w.act(1, "任務結局", "q_wd_yinliu|comfort"), "Player cannot substitute the opposite quest outcome")
	check(w.act(1, "任務結局", "q_wd_yinliu|truth") and int(p.skills.get("梯雲縱", 0)) == 1 and p.flags.wd_q_yinliu, "Complete verified lightness-learning route awards one actual skill level")
	# Flat letter event validates NPC and item, consumes the actual letter once.
	p = w.add_player(1)
	p.morality = 50
	var q: Dictionary = Data.QUESTS["q_wd_yinjian"]
	p.place = Data.NPCS[q.giver].place
	check(w.act(1, "接受任務", q.id), "Accept Wudang recommendation route")
	check(not w.act(1, "任務行動", q.id + "|o_0"), "Cannot deliver letter remotely")
	var item: String = q.give_items[0].item
	check(p.inventory[item] == 1, "Quest giver grants one actual recommendation letter")
	p.place = Data.NPCS["n_wd_zhangsanfeng"].place
	check(w.act(1, "任務行動", q.id + "|o_0") and p.inventory[item] == 0, "Letter delivered and consumed at the correct NPC")
	check(w.act(1, "任務結局", q.id + "|default") and p.flags.wd_recommended, "Completed event sets recommendation flag")
	check(not w.act(1, "接受任務", q.id), "Quest cannot be replayed to farm rewards")
	# Scripture branch: wrong book fails, and cannot be forced through the client.
	p = w.add_player(1)
	p.sect = "少林"
	p.skills.merge({"讀書識字": 50, "少林心法": 50, "佛法": 70})
	w.tick = 1200
	q = Data.QUESTS["q_sl_riyuebian"]
	p.place = Data.NPCS[q.giver].place
	check(w.act(1, "接受任務", q.id), "Accept night-only scripture event with prerequisites")
	var st: Dictionary = q.stages[0]
	var obj: Dictionary = st.objectives[0]
	p.place = Data.NPCS[obj.npc].place
	check(w.act(1, "任務行動", q.id + "|" + obj.id), "Scripture dialogue opens at the book-giving NPC")
	check(not w.act(1, "任務對話", q.id + "|forged_choice"), "Forged dialogue choices rejected")
	check(w.act(1, "任務對話", q.id + "|c_take"), "Taking scripture follows its actual scripted choice")
	p.learning_quests[q.id].vars.sutra = "jingang" # Host fixture for the wrong-book branch.
	check(w.act(1, "任務對話", q.id + "|c_jingang"), "Scripture name is read before leaving the dialogue")
	p.place = Data.NPCS[q.giver].place
	var return_obj: String = q.stages[1].objectives[0].id
	check(w.act(1, "任務行動", q.id + "|" + return_obj), "Return scripture at the quest giver")
	check(not w.act(1, "任務對話", q.id + "|c_ok") and not p.flags.get("sl_riyuebian_ok", false), "Wrong scripture cannot forge the successful branch")
	check(w.act(1, "任務對話", q.id + "|c_bad") and not p.learning_quests.has(q.id), "Wrong scripture takes the failure branch without unlocking the art")
	print("RESTORATION ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
