extends RefCounted
## Deterministic, presentation-independent party combat. One call resolves one action.
const Chapter = preload("res://scripts/journey/chapter.gd")
const Open=preload("res://scripts/journey/open_world.gd")
const MAX_QI := 100
var units: Array = []
var round_no := 1
var orders := {}
var queue: Array = []
var cursor := 0
var result := ""
var encounter := ""
var medicine_used := false
var rng := RandomNumberGenerator.new()
var history: Array = []

func _init(campaign, kind: String, seed_value: int = 0) -> void:
	encounter = kind
	if seed_value == 0: rng.randomize()
	else: rng.seed = seed_value
	for id in campaign.state.party:
		var u: Dictionary = campaign.unit(id)
		u.side = 0
		_prepare(u)
		if kind == "warehouse" and campaign.state.flags.get("choice","") == "mercy": u.energy += 25
		units.append(u)
	var enemies: Array
	match kind:
		"training": enemies = [["dummy","演武教頭","unit_shaolin_m",260,28,18,48,1,true,"blade"]]
		"escort": enemies = [["guard1","劫道刀客","unit_m_bandit",280,47,16,65,1,true,"blade"],["archer","劫鏢暗哨","unit_xingxiu_m",210,37,10,71,1,false,"poison"]]
		"ferry": enemies = [["guard1","黑衣刀客","unit_m_bandit",240,44,14,65,0,true,"blade"],["archer","暗哨","unit_xingxiu_m",190,38,9,72,0,false,"poison"]]
		"reeds": enemies = [["guard1","截鏢刀手","unit_m_bandit",340,54,19,69,1,true,"blade"],["guard2","埋伏刀手","unit_m_bandit",280,49,16,62,2,true,"blade"],["poison","毒砂客","unit_xingxiu_m",250,42,12,85,1,false,"poison"]]
		_: enemies = [["boss","黑風寨主","unit_xuedao_m",1150,92,29,70,1,true,"boss"],["guard1","護寨刀手","unit_m_bandit",380,60,22,58,0,true,"blade"],["poison","毒砂客","unit_xingxiu_m",300,48,15,88,1,false,"poison"]]
	for entry in enemies:
		var u := {"id":entry[0],"name":entry[1],"art":entry[2],"hp":entry[3],"max_hp":entry[3],"atk":entry[4],"def":entry[5],"speed":entry[6],"lane":entry[7],"front":entry[8],"ai":entry[9],"side":1,"qi":7,"evade":0,"weapon":"刀"}
		_prepare(u)
		if kind == "warehouse" and campaign.state.flags.get("choice","") == "justice" and u.ai == "poison": u.atk -= 15
		units.append(u)
	if kind.begins_with("road_"):
		var region: String = kind.trim_prefix("road_")
		var region_data: Dictionary = preload("res://scripts/journey/atlas.gd").REGIONS.get(region,{"tier":0})
		var tier := int(region_data.tier)
		var level: int = preload("res://scripts/journey/atlas.gd").POWER.get(region,1)
		# Early journeys use two opponents; later ones test the complete party.
		for i in range(units.size()-1,-1,-1):
			var u: Dictionary = units[i]
			if u.side == 0: continue
			if tier == 0 and u.ai == "boss": units.remove_at(i); continue
			u.name = ("守關教頭" if "派" in region or region == "全真教" else "截路首領") if u.ai == "boss" else ("快刀護衛" if u.ai == "blade" else "毒砂伏兵")
			var names: Array = preload("res://scripts/journey/atlas.gd").FOES.get(region,[])
			if names.size() == 3: u.name = names[0 if u.ai == "boss" else (1 if u.ai == "blade" else 2)]
			if region in ["少林派","全真教"]:
				u.art = "actor_staff" if u.ai != "poison" else "actor_taoist"
				u.sprite = "staff" if u.ai != "poison" else "taoist"
				u.weapon = "棍" if u.ai != "poison" else "劍"
			if region in ["武當派","華山派","峨嵋派"]:
				u.sprite = "taoist" if region == "武當派" else "companion"
				u.weapon = "劍"
			u.hp = int(u.hp * ([.62,.76,1.0][tier]) * (1+(level-1)*.14))
			u.max_hp = u.hp
			u.atk = int(u.atk * ([.65,.8,1.0][tier]) * (1+(level-1)*.06))
			u.def += (level-1)*2
	if kind == "supremacy":
		for u in units:
			if u.side == 0: continue
			u.name = {"boss":"天外刀尊","guard1":"鐵壁宗師","poison":"千機客"}[u.id]
			u.hp *= 4
			u.max_hp = u.hp
			u.atk = int(u.atk*2.3)
			u.def += 45
	if kind.begins_with("wild:") or kind.begins_with("quest:"):
		for i in range(units.size()-1,-1,-1):
			if units[i].side==1:units.remove_at(i)
		for u in Open.battle_roster(campaign,kind):
			_prepare(u)
			units.append(u)
	plan_intents()

func _prepare(u: Dictionary) -> void:
	u.energy = 50
	u.cd = 0
	u.bleed = 0
	u.poison = 0
	u.broken = 0
	u.stun = 0
	u.guarding = false
	u.charging = false
	u.intent = ""

func by_id(id: String) -> Dictionary:
	for u in units:
		if u.id == id: return u
	return {}

func living(side: int) -> Array:
	return units.filter(func(u): return u.side == side and u.hp > 0)

func target_for(actor: Dictionary, requested: String = "", bypass: bool = false) -> Dictionary:
	var foes := living(1 - int(actor.side))
	if foes.is_empty(): return {}
	if bypass:
		for foe in foes:
			if foe.id == requested: return foe
		foes.sort_custom(func(a,b): return a.hp < b.hp)
		return foes[0]
	# Every melee target must be in the front rank while any front rank survives.
	var fronts := foes.filter(func(u): return u.front)
	var eligible := fronts if not fronts.is_empty() else foes
	for foe in eligible:
		if foe.id == requested: return foe
	eligible.sort_custom(func(a,b): return absi(int(a.lane)-int(actor.lane)) < absi(int(b.lane)-int(actor.lane)))
	return eligible[0]

func cast_reason(id: String) -> String:
	var actor := by_id(id)
	if actor.is_empty() or actor.hp <= 0: return "已倒地"
	if not actor.has("outer"): return "沒有外功"
	if actor.stun > 0: return "被封招"
	var art: Dictionary = Chapter.ARTS[actor.outer]
	if actor.cd > 0: return "調息 %d 回合" % int(actor.cd)
	if actor.energy < art.cost: return "真元 %d／%d" % [actor.energy, art.cost]
	return ""

func order(id: String, action: String, target: String = "") -> bool:
	var actor := by_id(id)
	if actor.is_empty() or actor.side != 0 or actor.hp <= 0 or not queue.is_empty() or result != "": return false
	if not action in ["attack","skill","guard"]: return false
	if action == "skill" and cast_reason(id) != "": return false
	orders[id] = {"action":action,"target":target}
	return true

func auto_orders() -> void:
	for u in living(0):
		if orders.has(u.id): continue
		var action := "attack"
		var kind: String = Chapter.ARTS[u.outer].kind
		if cast_reason(u.id) == "":
			if kind == "heal":
				for ally in living(0):
					if ally.hp < ally.max_hp * .75 or ally.poison > 0: action = "skill"
			elif kind == "stun":
				for enemy in living(1):
					if enemy.charging: action = "skill"
			else: action = "skill"
		var target := "boss" if kind == "stun" else ""
		if kind == "pierce":
			for enemy in living(1):
				if not enemy.front: target = enemy.id
		order(u.id,action,target)

func plan_intents() -> void:
	for u in living(1):
		if u.has("kind"):
			u.intent=u.skill+" · "+{"fighter":"隔輪施招","healer":"先救低血同伴","sentinel":"護陣後反擊","assassin":"越陣搶攻","venom":"持續毒傷","breaker":"破甲截脈","berserker":"蓄勢重擊"}.get(u.ai,"進攻")
		elif u.ai == "boss": u.intent = "蓄力斬 · 下一回合橫掃前排" if not u.charging else "⚠ 斷江斬 · 橫掃前排，可封招打斷"
		elif u.ai == "poison": u.intent = "毒砂 · 越陣攻擊後排" if round_no % 2 == 1 else "短刀 · 攻擊前排"
		else: u.intent = "重斬 · 攻擊前排" if round_no % 3 == 0 else "刀擊 · 攻擊前排"

func begin_round() -> void:
	if not queue.is_empty() or result != "": return
	medicine_used = false
	queue = living(0) + living(1)
	queue.sort_custom(func(a,b): return a.speed > b.speed)
	cursor = 0
	for u in units: u.guarding = false

func next_action() -> Dictionary:
	if queue.is_empty() or result != "": return {}
	if cursor >= queue.size():
		queue.clear()
		orders.clear()
		round_no += 1
		if round_no > 40: result = "defeat"
		plan_intents()
		return {"kind":"round","text":"第 %d 回合 · 重新觀察敵方招式，調整施招。" % round_no}
	var u: Dictionary = queue[cursor]
	cursor += 1
	if u.hp <= 0: return {"kind":"skip","text":""}
	if u.cd > 0: u.cd -= 1
	var dot := 0
	if u.bleed > 0:
		dot += 20
		u.bleed -= 1
	if u.poison > 0:
		dot += 25
		u.poison -= 1
	if dot > 0:
		u.hp = maxi(0,int(u.hp)-dot)
		if u.hp == 0:
			_check_end()
			return _event(u,u,"dot",dot,"%s傷勢發作，倒地。" % u.name)
	if u.stun > 0:
		u.stun -= 1
		u.charging = false
		return _event(u,u,"stun",0,"%s被封招，蓄力中斷，本次無法行動。" % u.name)
	var action := "attack"
	var target := ""
	if u.side == 0:
		action = orders.get(u.id,{}).get("action","attack")
		target = orders.get(u.id,{}).get("target","")
		if action == "skill" and cast_reason(u.id) != "": action = "attack"
	else:
		if u.has("kind"):
			if u.ai=="healer" and living(1).any(func(ally):return ally.hp<ally.max_hp*.6):action="heal"
			elif u.ai=="sentinel" and round_no%3==1:action="guard"
			elif u.ai=="assassin":action="pierce"
			elif u.ai=="venom" and round_no%2==1:action="poison"
			elif u.ai=="breaker" and round_no%2==0:action="break"
			elif u.ai=="berserker":action="boss_hit" if u.charging else "charge"
			elif round_no%2==0:action=u.kind
		elif u.ai == "boss": action = "boss_hit" if u.charging else "charge"
		elif u.ai == "poison" and round_no % 2 == 1: action = "poison"
		elif round_no % 3 == 0: action = "heavy"
	var event := _resolve(u,action,target)
	if dot > 0: event.text = "[傷勢 -%d] " % dot + event.text
	if u.broken > 0: u.broken -= 1
	_check_end()
	return event

func _resolve(u: Dictionary, action: String, requested: String) -> Dictionary:
	if action == "guard":
		u.guarding = true
		u.energy = mini(MAX_QI,int(u.energy)+12)
		return _event(u,u,"guard",0,"%s架勢護陣，減傷 60%%，並援護後排同伴。" % u.name)
	if action == "charge":
		u.charging = true
		return _event(u,u,"charge",0,"%s開始蓄力！下回合將橫掃前排，用陸衡封招或提前守勢。" % u.name)
	var kind := action
	var power := 2.2 if action=="heal" else 1.0
	var title: String=u.get("skill","普攻") if u.side==1 and action!="attack" else "普攻"
	if action == "skill":
		var art: Dictionary = Chapter.ARTS[u.outer]
		u.energy -= int(art.cost)
		u.cd = int(art.cd)
		kind = art.kind
		power = art.power
		title = art.skill
	if kind == "heal":
		var allies := living(int(u.side))
		allies.sort_custom(func(a,b): return float(a.hp)/a.max_hp < float(b.hp)/b.max_hp)
		var t: Dictionary = allies[0]
		var amount := mini(int(t.max_hp)-int(t.hp),int(u.atk * power)+60)
		t.hp += amount
		t.poison = 0
		t.bleed = 0
		return _event(u,t,"heal",amount,"%s使出%s，%s回復 %d 氣血，毒與流血盡除。" % [u.name,title,t.name,amount])
	var t := target_for(u,requested,kind in ["pierce","poison"])
	if t.is_empty(): return {}
	if kind == "poison":
		var backs := living(1-int(u.side)).filter(func(a): return not a.front)
		if not backs.is_empty(): t = backs[0]
		power = .8
		title = "毒砂"
	if kind == "heavy":
		power = 1.6
		title = "重斬"
	if kind == "boss_hit":
		u.charging = false
		power = 2.2
		title = "斷江斬"
	var targets := [t]
	if kind == "cleave": targets = living(1-int(u.side)).filter(func(a): return a.lane == t.lane)
	if kind == "boss_hit":
		targets = living(0).filter(func(a): return a.front)
		if targets.is_empty(): targets = living(0)
	var hits: Array = []
	var total := 0
	for original in targets:
		var victim: Dictionary = original
		if not victim.front:
			for guard in living(int(victim.side)):
				if guard.front and guard.guarding:
					victim = guard
					break
		var damage := maxi(8,int(float(u.atk)*power)-int(float(victim.def)*(1.0 if victim.broken == 0 else .5)))
		var combo: bool = u.id == "hero" and (victim.bleed > 0 or victim.broken > 0)
		if combo: damage = int(damage * 1.3)
		if victim.guarding: damage = int(damage * .4)
		var dodged := rng.randf() < float(victim.evade) / 180.0
		if dodged: damage = 0
		victim.hp = maxi(0,int(victim.hp)-damage)
		if damage > 0:
			if kind == "bleed": victim.bleed = 2
			if kind == "break": victim.broken = 3
			if kind == "poison": victim.poison = 2
			if kind == "stun":
				victim.stun = 1
				victim.charging = false
		var hit := {"id":victim.id,"amount":damage,"combo":combo,"dodge":dodged}
		hits.append(hit)
		total += damage
	if action == "attack":
		# A normal attack by either side gives every living unit one 聚氣 pulse.
		for fighter in units:
			if fighter.hp > 0: fighter.energy = mini(MAX_QI,int(fighter.energy)+int(fighter.qi))
	var effect := ""
	if kind == "stun": effect = " · 封招／打斷"
	elif kind == "bleed": effect = " · 流血兩回合"
	elif kind == "break": effect = " · 破甲"
	elif kind == "poison": effect = " · 中毒兩回合"
	var event := _event(u,t,kind,total,"%s · %s → %s，造成 %d 傷害%s。" % [u.name,title,t.name,total,effect])
	event.hits = hits
	return event

func medicine(id: String, inventory: Dictionary) -> Dictionary:
	var target := by_id(id)
	if result != "" or not queue.is_empty() or medicine_used or inventory.get("金創藥",0) < 1 or target.is_empty() or target.side != 0 or target.hp <= 0 or target.hp == target.max_hp: return {}
	inventory["金創藥"] -= 1
	medicine_used = true
	var amount := mini(140,int(target.max_hp)-int(target.hp))
	target.hp += amount
	return _event(target,target,"heal",amount,"為%s使用金創藥，回復 %d 氣血。" % [target.name,amount])

func _event(actor: Dictionary, target: Dictionary, kind: String, amount: int, text: String) -> Dictionary:
	var e := {"actor":actor.id,"target":target.id,"kind":kind,"amount":amount,"text":text}
	history.append(e)
	return e

func _check_end() -> void:
	if living(1).is_empty(): result = "victory"
	elif living(0).is_empty(): result = "defeat"
