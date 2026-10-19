extends RefCounted
const Data = preload("res://scripts/content.gd")
const Training = preload("res://scripts/progression.gd")
## Historical player-tested cubic power / quadratic parry model. Defaults and
## chance coefficients are reconstructions; see docs/RESTORATION.md.

static func attack_power(p: Dictionary, art: String) -> float:
	var level := int(p.skills.get(art, 1))
	var row: Dictionary = Data.SKILLS.get(art, {})
	var base: String = row.get("base", art)
	var basics := int(p.skills.get(base, 0))
	var coefficient := float(row.get("attack_coefficient", .3))
	var raw := maxf(12, pow(level, 3) * coefficient)
	var equipment := int(Data.SHOP.get(p.weapon, {}).get("attack", 0)) if Data.fits(art, p.weapon) else 0
	var xp := int(p.get("combat_xp", 0)) / 10000000 * 10
	return raw * (1.0 + basics * .002 + int(p.skills.get("基本內功", 0)) * .001) * (1.0 + (equipment + xp) / 100.0) * (1 + (int(Training.attrs(p).str) - 25) * .01)

static func defense_power(p: Dictionary, art: String) -> float:
	var level := int(p.skills.get(art, 1))
	var row: Dictionary = Data.SKILLS.get(art, {})
	var raw := maxf(1, pow(level, 2) * float(row.get("parry_coefficient", .03)))
	var armor := int(Data.SHOP.get(p.armor, {}).get("defense", 0))
	var xp := int(p.get("combat_xp", 0)) / 10000000 * 10
	var basic_bonus := int(p.skills.get("拆招卸力", 0)) * .002 + int(p.skills.get("基本內功", 0)) * .001
	var value := raw * (1 + basic_bonus) * (1 + (armor + xp) / 100.0)
	value *= 1 + (int(Training.attrs(p).con) - 25) * .01
	if p.stance == "防守": value *= 1.5
	return maxf(1, value)

static func hit_chance(p: Dictionary, target: Dictionary, art: String) -> float:
	var level := int(p.skills.get(art, 1))
	var dodge := int(target.get("skills", {}).get("閃躲縱躍", target.get("level", 1)))
	if Data.role(str(target.get("movement", ""))) == "MOVEMENT": dodge += int(target.get("skills", {}).get(target.movement, 0)) / 5
	var agility := int(Training.attrs(target).agi) if target.has("skills") else int(target.get("agility", 25))
	return clampf(.8 + (level - dodge) * .003 + (int(Training.attrs(p).agi) - agility) * .008, .1, .95)

static func choose_move(p: Dictionary, art: String) -> Dictionary:
	var selected: Dictionary = {}
	for move in Data.SKILLS.get(art, {}).get("move_data", []):
		if int(move.get("unlock_level", 1)) > int(p.skills.get(art, 0)): continue
		var mana := ceili(int(move.get("cost_inner", 0)) * clampi(int(p.get("power", 5)), 1, 10) / 5.0)
		if mana > int(p.mp) or int(move.get("cost_jing", 0)) > int(p.energy): continue
		if selected.is_empty() or int(move.get("unlock_level", 1)) >= int(selected.get("unlock_level", 1)): selected = move
	return selected

static func roll(p: Dictionary, target: Dictionary, art: String, target_art: String, rng: RandomNumberGenerator) -> Dictionary:
	var move := choose_move(p, art)
	if move.is_empty() and not Data.SKILLS.get(art, {}).get("move_data", []).is_empty():
		var basic: String = Data.SKILLS[art].get("base", "")
		art = basic if Data.fits(basic, p.weapon) else "搏擊格鬥"
	var cost := int(move.get("cost_inner", 0))
	var energy := int(move.get("cost_jing", 0))
	var power := clampi(int(p.get("power", 5)), 1, 10)
	cost = ceili(cost * power / 5.0)
	if int(p.mp) < cost: cost = 0; energy = 0; move = {}
	p.mp -= cost
	p.energy -= energy
	var result := {"damage": 0, "hit": false, "critical": false, "move": move.get("name", art), "mp_cost": cost}
	if rng.randf() > hit_chance(p, target, art): return result
	var offense := attack_power(p, art)
	if not move.is_empty():
		var original_moves: Array = Data.SKILLS.get(art, {}).get("move_data", [])
		var first := maxi(1, int(original_moves[0].get("power", 1))) if not original_moves.is_empty() else 1
		offense *= maxf(.1, float(move.get("power", first)) / first)
	var denominator := defense_power(target, target_art) if target.has("skills") else maxf(1, float(target.get("defense", 0)) + 1)
	var foundation: String = Data.SKILLS.get(art, {}).get("base", art)
	var force := 1.05 if int(p.skills.get(foundation, 0)) >= 120 else .55 + power * .05
	if Data.SKILLS.get(art, {}).get("basic", false): force = 1.0
	var inner := int(p.skills.get(str(p.get("inner", "")), 0)) if Data.role(str(p.get("inner", ""))) == "INNER" else 0
	var target_inner := int(target.get("skills", {}).get(str(target.get("inner", "")), 0)) if Data.role(str(target.get("inner", ""))) == "INNER" else 0
	var multiplier := 1.0 + rng.randf_range(0, inner / 500.0)
	denominator *= 1 + rng.randf_range(0, target_inner / 500.0)
	var damage := maxi(1, roundi(offense * force * multiplier / denominator * rng.randf_range(.9, 1.1)))
	if p.stance == "重擊" and int(p.mp) >= 6:
		p.mp -= 6
		damage = roundi(damage * 1.3)
	elif p.stance == "防守": damage = maxi(1, roundi(damage * .7))
	var critical := rng.randf() < clampf(.02 + int(Training.attrs(p).guts) * .003, 0, .5)
	if critical: damage = roundi(damage * (1.5 + int(Training.attrs(p).con) * .01))
	result.merge({"damage": damage, "hit": true, "critical": critical}, true)
	return result

static func enemy_roll(enemy: Dictionary, p: Dictionary, art: String, rng: RandomNumberGenerator) -> int:
	var dodge := int(p.skills.get("閃躲縱躍", 0))
	if Data.role(str(p.get("movement", ""))) == "MOVEMENT": dodge += int(p.skills.get(p.movement, 0)) / 5
	var hit := clampf(.8 + (int(enemy.get("level", 1)) - dodge) * .003, .1, .95)
	if rng.randf() > hit: return 0
	return maxi(1, roundi(float(enemy.attack) * rng.randf_range(.9, 1.1) / defense_power(p, art)))
