extends SceneTree
const Rules = preload("res://scripts/world.gd")
const Data = preload("res://scripts/content.gd")
var failures: Array = []
var checks := 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); push_error(description)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var w := Rules.new()
	var p: Dictionary = w.add_player(1)
	check(Data.SKILLS.has("搏擊格鬥") and not Data.SKILLS.has("基本拳腳"), "Original basic skill name retained")
	check(Data.SKILLS["基本刺術"].category == "STAB" and Data.SKILLS["基本槍法"].category == "SPEAR", "Finger arts distinct from spear foundation")
	check(Data.SKILLS["倚天屠龍筆法"].category == "SPEAR" and Data.SKILLS["倚天屠龍筆法"].base == "基本槍法", "Official spear classification overrides source placeholder STAB")
	check(Data.SKILLS["打狗棒法"].category == "STAFF" and Data.role("混天功") == "INNER", "Beggar staff and inner arts classified separately")
	for sect in Data.SECTS:
		check(Data.role(Data.SECTS[sect].basic) == "EXTERNAL", "Sect beginner is an external art: " + sect)
	for art in Data.SKILLS:
		if Data.role(art) == "EXTERNAL": check(not Data.SKILLS[art].weapon_types.is_empty(), "External art has explicit weapon rule: " + art)
	p.skills.merge({"基本劍法": 1, "太極劍法": 25, "基本刀法": 5, "打狗棒法": 20, "倚天屠龍筆法": 20, "基本刺術": 10, "武當心法": 60, "梯雲縱": 50, "俠義": 90}, true)
	for item in ["木劍", "木刀", "竹棒", "練習長槍", "練習鐵爪"]: p.inventory[item] = 1
	var before := Rules.attack(p)
	check(not w.act(1, "裝備", "太極劍法") and p.equipped == "搏擊格鬥", "Sword art rejected without sword")
	check(w.act(1, "裝備", "木劍") and p.equipped == "太極劍法", "Sword equips with highest learned matching art")
	check(not w.act(1, "裝備", "打狗棒法") and p.equipped == "太極劍法", "Sword cannot use staff art")
	check(not w.act(1, "裝備", "搏擊格鬥"), "Sword cannot supply bonus to brawling")
	check(w.act(1, "裝備", "武當心法") and p.inner == "武當心法" and p.equipped == "太極劍法", "Inner art uses separate slot")
	check(w.act(1, "裝備", "梯雲縱") and p.movement == "梯雲縱" and p.equipped == "太極劍法", "Lightness uses separate slot")
	check(not w.act(1, "裝備", "俠義"), "Sect virtue cannot become attack art")
	var defended := Rules.defense(p)
	w.act(1, "卸下", "movement")
	check(Rules.defense(p) < defended, "Lightness provides defensive benefit")
	check(w.act(1, "裝備", "木刀") and p.equipped == "基本刀法", "Blade switches external art without overwriting inner slot")
	check(p.inner == "武當心法", "Weapon switching preserves inner art")
	check(w.act(1, "裝備", "竹棒") and p.equipped == "打狗棒法", "Staff uses staff art")
	check(w.act(1, "裝備", "練習長槍") and p.equipped == "倚天屠龍筆法", "Pen technique uses spear weapon")
	check(w.act(1, "裝備", "練習鐵爪") and Data.SKILLS[p.equipped].category in ["FIST", "STAB"], "Claw supports brawling and finger arts")
	check(w.act(1, "卸下", "weapon") and p.weapon == "" and Data.fits(p.equipped, ""), "Unequip selects valid unarmed art")
	# Defensive engine checks also cover malformed/old selections during host combat.
	p.equipped = "武當心法"
	p.weapon = "木劍"
	check(Rules.active_art(p) == "太極劍法", "Combat never strikes using internal art")
	p.equipped = "打狗棒法"
	check(Rules.active_art(p) == "太極劍法", "Combat revalidates incompatible selection")
	var sword_attack := Rules.attack(p)
	p.weapon = "青鋒劍"
	check(Rules.attack(p) - sword_attack == 11, "Compatible weapon attack contributes actual item stat")
	p.weapon = "不存在的兵器"
	check(Rules.attack(p) < sword_attack, "Unknown weapon never receives weapon attack or sword skill")
	p.skills["紫霞神功"] = 65
	check(not w.act(1, "自修", "紫霞神功"), "Per-art self-study cap checked immediately")
	p.auto_skill = "紫霞神功"
	p.auto = "自修"
	w.self_study(1)
	check(p.skills["紫霞神功"] == 65 and p.auto == "停止", "Automated study cannot exceed art cap")
	for npc in Data.NPCS.values():
		for lesson in npc.teach:
			if lesson.skill in ["紫霞神功", "峨嵋九陽功", "九陰真經"]: check(int(lesson.cap) == 1, "Self-study art cannot be consumed to level 60: " + lesson.skill)
	p.skills["基本拳腳"] = 34
	p.skill_xp["基本拳腳"] = 19
	p.equipped = "武當心法"
	p.auto_skill = "基本拳腳"
	p.weapon = ""
	Rules.normalize_martial(p)
	check(p.skills["搏擊格鬥"] == 34 and p.skill_xp["搏擊格鬥"] == 19 and not p.skills.has("基本拳腳"), "Legacy fist level and proficiency preserved")
	check(p.inner == "武當心法" and Data.role(p.equipped) == "EXTERNAL" and p.auto_skill == "搏擊格鬥", "Legacy inner attack moved safely into inner slot")
	w.act(1, "卸下", "inner")
	Rules.normalize_martial(p)
	check(p.inner == "", "Intentionally cleared inner slot survives save migration")
	# Identical seed: solo uses the same damage roller as party and PK.
	p.enemy = {"name": "驗證木樁", "hp": 10000, "max_hp": 10000, "defense": 3, "attack": 1}
	p.stance = "普通"
	w.rng.seed = 75
	var expected := w.roll_damage(p, 3)
	w.rng.seed = 75
	w.combat(1)
	check(10000 - int(p.enemy.hp) == expected, "Solo and multiplayer share weapon-aware damage formula")
	check(before > 0, "New character can fight unarmed")
	print("MARTIAL ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
