extends RefCounted
## Free exploration, optional multi-step commissions and persistent relationships.
const Content = preload("res://scripts/journey/open_content.gd")

static func ensure(campaign) -> Dictionary:
	if not campaign.state.has("open_world"):
		campaign.state.open_world={"version":2,"story_edition":3,"scene":"","quests":{},"tracked":"","affinity":{},"met":[],"defeated":[],"discoveries":[],"honor":0,"evidence":{}}
	var world: Dictionary=campaign.state.open_world
	if world.version==1:
		# Preserve the exact old script, step, choices and earned rewards. New
		# commissions opt into edition 3 at acceptance; no old progress is reset.
		for id in world.quests:
			world.quests[id].edition=1
		world.version=2
		if not world.has("evidence"):world.evidence={}
	return campaign.state.open_world

static func definition(campaign,id: String) -> Dictionary:
	var world: Dictionary=campaign.state.get("open_world",{})
	var progress: Dictionary=world.get("quests",{}).get(id,{})
	var edition: int=int(progress.get("edition",1 if world.get("version",2)==1 else 2)) if not progress.is_empty() else 3
	return Content.QUESTS[id] if edition==3 else Content.LEGACY_QUESTS[str(edition)][id]

static func current_region(campaign) -> String:
	return campaign.state.get("atlas",{}).get("region","嘉興鎮")

static func current_scene(campaign) -> String:
	var data:=ensure(campaign)
	var region:=current_region(campaign)
	return data.scene if data.scene in Content.REGIONS[region] else Content.REGIONS[region][0]

static func enter(campaign, region: String, scene: String) -> void:
	if not Content.REGIONS.has(region) or not scene in Content.REGIONS[region]: return
	var data:=ensure(campaign)
	campaign.state.atlas.region=region
	data.scene=scene
	var place:=region+"／"+scene
	if not place in data.discoveries: data.discoveries.append(place)
	for id in data.quests:
		var state: Dictionary=data.quests[id]
		if state.status!="active":continue
		var step: Dictionary=definition(campaign,id).steps[int(state.step)]
		if step.kind=="visit" and step.region==region and step.scene==scene: _advance(campaign,id)

static func people(campaign) -> Array:
	var result:=[]
	var visiting: Dictionary={}
	for qid in ensure(campaign).quests:
		var progress: Dictionary=ensure(campaign).quests[qid]
		if progress.status!="active":continue
		var step: Dictionary=definition(campaign,qid).steps[int(progress.step)]
		if step.has("visiting"):visiting[step.visiting]=step.region+"／"+step.scene
	for id in Content.PEOPLE:
		var npc: Dictionary=Content.PEOPLE[id]
		if visiting.has(id):
			if visiting[id]==current_region(campaign)+"／"+current_scene(campaign):result.append(id)
			continue
		if npc.region!=current_region(campaign) or npc.scene!=current_scene(campaign):continue
		if npc.get("event_only",false):
			var present:=false
			for qid in npc.get("stories",[]):
				var progress: Dictionary=ensure(campaign).quests.get(qid,{})
				if progress.get("status","")!="active":continue
				var step: Dictionary=definition(campaign,qid).steps[int(progress.step)]
				if step.region!=npc.region or step.scene!=npc.scene:continue
				if step.get("npc","")==id or step.get("pages",[]).any(func(line):return line.speaker==id):present=true
			if not present:continue
		result.append(id)
	result.sort_custom(func(a,b):return Content.PEOPLE[a].has("hero") and not Content.PEOPLE[b].has("hero"))
	return result

static func is_market(campaign) -> bool:
	if not campaign.state.has("open_world"):return campaign.state.place=="市集" and current_region(campaign)=="嘉興鎮"
	var scene:=current_scene(campaign)
	return scene==market_scene(current_region(campaign)) or scene in ["市集","青溪客棧","牛家客棧","藥王莊","蝴蝶谷","馮家鐵鋪"]

static func market_scene(region: String) -> String:
	for scene in Content.REGIONS[region]:
		for word in ["市","商","客棧","客舍","茶","村口","山門"]:
			if word in scene:return scene
	return Content.REGIONS[region][0]

static func meet(campaign, id: String) -> bool:
	if not id in people(campaign):return false
	var data:=ensure(campaign)
	if not id in data.met:data.met.append(id)
	return true

static func invite(campaign, id: String) -> String:
	if not meet(campaign,id) or not Content.PEOPLE[id].has("hero"):return "請先在當地與這位人物交談。"
	var hero: String=Content.PEOPLE[id].hero
	if hero in campaign.state.roster:return "已是同行好友，可在隊伍視窗安排出戰。"
	var reason:=recruit_reason(campaign,id)
	if reason!="":return reason
	campaign.recruit(hero)
	campaign.record(Content.PEOPLE[id].name+"在個人往事了結後，應邀同行。")
	return Content.HEROES[hero].get("join",Content.PEOPLE[id].name+"加入同行名冊。")

static func recruit_reason(campaign,id: String) -> String:
	if not Content.HEROES.has(id):return "此人沒有同行的打算。"
	if id in campaign.state.roster:return ""
	var rule: Dictionary=Content.HEROES[id].recruit
	var data:=ensure(campaign)
	var missing: Array[String]=[]
	if data.quests.get(rule.quest,{}).get("status","")!="done":missing.append("先了結「"+definition(campaign,rule.quest).name+"」")
	if int(data.affinity.get(id,0))<int(rule.affinity):missing.append("交情 %d／%d"%[data.affinity.get(id,0),rule.affinity])
	if int(campaign.state.levels.hero)<int(rule.level):missing.append("主角修為 %d／%d 重"%[campaign.state.levels.hero,rule.level])
	return "；".join(missing)

static func step_here(campaign,id: String,npc: String="") -> bool:
	var data:=ensure(campaign)
	if not data.quests.has(id) or data.quests[id].status!="active":return false
	var step: Dictionary=definition(campaign,id).steps[int(data.quests[id].step)]
	return step.region==current_region(campaign) and step.scene==current_scene(campaign) and (npc=="" or step.get("npc",npc)==npc)

static func step_pages(campaign,id: String) -> Array:
	var data:=ensure(campaign)
	var state: Dictionary=data.quests[id]
	var step: Dictionary=definition(campaign,id).steps[int(state.step)]
	if step.has("ending_pages") and not state.choices.is_empty():return step.ending_pages[clampi(int(state.choices.back()),0,step.ending_pages.size()-1)]
	return step.get("pages",[{"speaker":step.get("npc",""),"text":step.text}])

static func conversation(campaign,id: String,alternate: bool=false) -> Array:
	var npc: Dictionary=Content.PEOPLE[id]
	var data:=ensure(campaign)
	var own: Array=npc.get("pages",[{"speaker":id,"text":npc.text}])
	if alternate:return npc.get("alternate_pages",own)
	var qid: String=npc.get("story","")
	if not Content.QUESTS.has(qid):return own
	var quest: Dictionary=definition(campaign,qid)
	var progress: Dictionary=data.quests.get(qid,{})
	if progress.get("status","")=="done":
		if npc.has("hero"):return [{"speaker":id,"text":npc.reply},{"speaker":id,"text":npc.join}]
		if quest.giver!=id:return own
		var endings: Array=quest.get("endings",[quest.get("conclusion",npc.reply)])
		var choice: int=clampi(0 if progress.choices.is_empty() else int(progress.choices.back()),0,endings.size()-1)
		return [{"speaker":id,"text":endings[choice]},{"speaker":id,"text":npc.reply}]
	if progress.get("status","")=="active":
		var step: Dictionary=quest.steps[int(progress.step)]
		if step_here(campaign,qid,id):return step_pages(campaign,qid)
		return own+[{"speaker":"","caption":"目前安排","text":step.text+"\n地點："+step.region+"／"+step.scene}]
	if quest.giver==id:return quest.steps[0].get("pages",[{"speaker":id,"text":quest.text}])
	return own

static func interactions_here(campaign) -> Array:
	var result:=[]
	for id in ensure(campaign).quests:
		if step_here(campaign,id) and not definition(campaign,id).steps[int(ensure(campaign).quests[id].step)].has("npc"):result.append(id)
	return result

static func quests_here(campaign, npc: String="") -> Array:
	var result:=[]
	for id in Content.QUESTS:
		var quest: Dictionary=definition(campaign,id)
		if quest.region==current_region(campaign) and quest.scene==current_scene(campaign) and (npc=="" or quest.giver==npc):result.append(id)
	return result

static func active_for(campaign,npc: String) -> Array:
	var result:=[]
	var data:=ensure(campaign)
	for id in data.quests:
		var state: Dictionary=data.quests[id]
		if state.status!="active":continue
		var step: Dictionary=definition(campaign,id).steps[int(state.step)]
		if step.get("npc","")==npc and step.region==current_region(campaign) and step.scene==current_scene(campaign):result.append(id)
	return result

static func accept(campaign,id: String,npc: String="") -> String:
	if not Content.QUESTS.has(id):return "找不到這份委託。"
	var quest: Dictionary=definition(campaign,id)
	if quest.region!=current_region(campaign) or quest.scene!=current_scene(campaign):return "先到委託人所在的場景。"
	if npc!="" and npc!=quest.giver:return "請向委託人親自接洽。"
	var data:=ensure(campaign)
	if data.quests.has(id):data.tracked=id;return "已追蹤這份委託，可查看當前步驟。"
	data.quests[id]={"status":"active","step":0,"choices":[],"edition":3}
	data.tracked=id
	campaign.record("接下支線・"+quest.name+"。")
	return "已接下「"+quest.name+"」。可隨時探索別處，沒有主線期限。"

static func action(campaign,id: String,npc: String="",choice: int=-1) -> Dictionary:
	var data:=ensure(campaign)
	if not data.quests.has(id) or data.quests[id].status!="active":return {"text":"這份委託目前沒有待辦步驟。"}
	var state: Dictionary=data.quests[id]
	var step: Dictionary=definition(campaign,id).steps[int(state.step)]
	if step.region!=current_region(campaign) or step.scene!=current_scene(campaign):return {"text":"請先前往"+step.region+"／"+step.scene+"。"}
	if step.has("npc") and step.npc!=npc:return {"text":"請與"+Content.PEOPLE[step.npc].name+"交談。"}
	if step.has("requires") and not data.evidence.has(step.requires):return {"text":"還沒有找到這件事的證物。"}
	match step.kind:
		"battle":return {"text":step.text,"battle":"quest:"+id+":"+str(int(state.step))}
		"search":data.evidence[step.evidence]={"quest":id,"name":step.item}
		"deliver":
			if int(campaign.state.inventory.get(step.item,0))<int(step.count):return {"text":"需要 %d 份%s；可採集或購買後再回來。"%[step.count,step.item]}
			campaign.state.inventory[step.item]-=int(step.count)
		"choice":
			if choice<0 or choice>=step.options.size():return {"text":"先選擇你願意採取的做法。"}
			state.choices.append(choice)
			if choice==0:data.honor+=2
			else:campaign.state.potential+=8
	if step.has("consume"):
		if not data.evidence.has(step.consume):return {"text":"請先找回並帶著證物，再向當事人交代。"}
		data.evidence.erase(step.consume)
	var feedback: String=step.get("result",step.get("outcomes",[step.text,step.text])[maxi(0,choice)])
	_advance(campaign,id)
	var current: Dictionary=definition(campaign,id)
	if state.status=="done":feedback="完成「"+current.name+"」。\n報酬：%d 銀、%d 學點。"%[current.reward.silver,current.reward.potential]
	else:
		var next: Dictionary=current.steps[int(state.step)]
		feedback=next.text+"\n地點："+next.region+"／"+next.scene
	return {"text":feedback,"done":state.status=="done"}

static func _advance(campaign,id: String) -> void:
	var state: Dictionary=ensure(campaign).quests[id]
	if state.status!="active":return
	var quest: Dictionary=definition(campaign,id)
	var previous: Dictionary=quest.steps[int(state.step)]
	state.step=int(previous.next_by_choice[int(state.choices.back())]) if previous.has("next_by_choice") else int(state.step)+1
	if state.step<quest.steps.size():return
	state.status="done"
	# Only edition-3 objects are consumed here; old scripts keep their original
	# explicit handover rules. Never touch another active quest's belongings.
	if int(state.get("edition",2))==3:
		for key in ensure(campaign).evidence.keys():
			if ensure(campaign).evidence[key].quest==id:ensure(campaign).evidence.erase(key)
	var reward: Dictionary=quest.reward
	campaign.state.silver+=int(reward.silver)
	campaign.state.potential+=int(reward.potential)
	if reward.has("hero"):
		var data:=ensure(campaign)
		var amount: int=int(reward.affinity)
		if reward.has("affinity_by_choice") and not state.choices.is_empty():amount=int(reward.affinity_by_choice[int(state.choices.back())])
		data.affinity[reward.hero]=mini(100,int(data.affinity.get(reward.hero,0))+amount)
	campaign.record("支線結案・%s。%d 銀、%d 學點。"%[quest.name,reward.silver,reward.potential])

static func battle_roster(campaign,encounter: String) -> Array:
	var ids:=[]
	if encounter.begins_with("wild:"):
		ids=Array(encounter.trim_prefix("wild:").split(","))
	elif encounter.begins_with("quest:"):
		var parts:=encounter.split(":")
		if parts.size()!=3:return []
		var data:=ensure(campaign)
		if not data.quests.has(parts[1]) or data.quests[parts[1]].status!="active" or int(data.quests[parts[1]].step)!=int(parts[2]):return []
		var step: Dictionary=definition(campaign,parts[1]).steps[int(parts[2])]
		if step.kind!="battle" or step.region!=current_region(campaign) or step.scene!=current_scene(campaign):return []
		ids=step.enemies
	var result:=[]
	for id in ids:
		if not Content.ENEMIES.has(id):return []
		var source: Dictionary=Content.ENEMIES[id]
		var u: Dictionary=source.duplicate(true)
		if encounter.begins_with("quest:"):
			var quest_step: Dictionary=definition(campaign,encounter.split(":")[1]).steps[int(encounter.split(":")[2])]
			var rank: int=int(quest_step.get("story_rank",source.level))
			var names: Array=quest_step.get("foe_names",[])
			if result.size()<names.size():u.name=names[result.size()]
			u.kind="poison" if "毒" in u.name else ("heavy" if "錘" in u.name else "break")
			u.skill=u.name+" · "+{"poison":"淬毒逼退","heavy":"蓄勢重擊","break":"截脈破防"}[u.kind]
			u.hp=175+rank*48
			u.atk=24+rank*6
			u.def=8+rank*2
			u.speed=48+rank*2
			u.ai="fighter" if rank<4 else ("venom" if u.kind=="poison" else ("berserker" if u.kind=="heavy" else "breaker"))
			if quest_step.has("opponent_hero"):
				var opponent: Dictionary=Content.HEROES[quest_step.opponent_hero]
				u.sprite=quest_step.opponent_hero
				u.weapon=Content.ARTS[opponent.outer].weapon
				u.kind=Content.ARTS[opponent.outer].kind
				u.skill=opponent.outer
		u.id=id
		u.side=1
		u.max_hp=u.hp
		u.art="actor_"+u.sprite
		u.lane=result.size()%3
		u.front=result.size()!=1
		result.append(u)
	return result

static func battle_won(campaign,encounter: String) -> void:
	var data:=ensure(campaign)
	var opponents:=battle_roster(campaign,encounter)
	if opponents.is_empty():return
	for enemy in opponents:
		if not enemy.id in data.defeated:data.defeated.append(enemy.id)
	if encounter.begins_with("quest:"):
		var parts:=encounter.split(":")
		if parts.size()==3 and data.quests.has(parts[1]) and data.quests[parts[1]].status=="active" and int(data.quests[parts[1]].step)==int(parts[2]):_advance(campaign,parts[1])

static func valid_save(value: Variant) -> bool:
	if not value is Dictionary or (value.get("version")!=1 and value.get("version")!=2):return false
	for key in ["quests","affinity"]:
		if not value.get(key) is Dictionary:return false
	if value.quests.size()>Content.QUESTS.size():return false
	for id in value.quests:
		if not Content.QUESTS.has(id):return false
		if value.version==1 and not Content.LEGACY_STEPS.has(id):return false
		var state: Variant=value.quests[id]
		if not state is Dictionary or not state.get("status") in ["active","done"]:return false
		var step: Variant=state.get("step")
		if not (step is int or step is float) or not is_finite(float(step)) or float(step)!=int(step) or step<0:return false
		var edition: Variant=state.get("edition",1 if value.version==1 else 2)
		if not (edition is int or edition is float) or not is_finite(float(edition)) or float(edition)!=int(edition) or not int(edition) in [1,2,3]:return false
		var script: Dictionary=Content.QUESTS[id] if edition==3 else Content.LEGACY_QUESTS[str(int(edition))].get(id,{})
		if script.is_empty():return false
		var maximum: int=script.steps.size()
		if (state.status=="done" and step!=maximum) or (state.status=="active" and step>=maximum):return false
		if not state.get("choices") is Array or state.choices.size()>maximum:return false
		for choice in state.choices:
			if not (choice is int or choice is float) or not is_finite(float(choice)) or float(choice)!=int(choice) or choice<0 or choice>1:return false
	for id in value.affinity:
		var n: Variant=value.affinity[id]
		if not Content.HEROES.has(id) or not (n is int or n is float) or not is_finite(float(n)) or n<0 or n>100:return false
	if value.version==2:
		if not value.get("evidence") is Dictionary or value.evidence.size()>Content.QUESTS.size():return false
		for key in value.evidence:
			var clue: Variant=value.evidence[key]
			if not clue is Dictionary or not Content.QUESTS.has(clue.get("quest","")) or not clue.get("name") is String:return false
			if not value.quests.has(clue.quest):return false
			var edition: int=int(value.quests[clue.quest].get("edition",2))
			var script: Dictionary=Content.QUESTS[clue.quest] if edition==3 else Content.LEGACY_QUESTS[str(edition)].get(clue.quest,{})
			var found:=false
			for step in script.steps:
				if step.get("evidence","")==key and step.get("item","")==clue.name:found=true
			if not found:return false
	for key in ["met","defeated","discoveries"]:
		if not value.get(key) is Array or value[key].size()>500:return false
		var seen: Dictionary={}
		for id in value[key]:
			if not id is String or seen.has(id):return false
			seen[id]=true
			if key=="met" and not Content.PEOPLE.has(id):return false
			if key=="defeated" and not Content.ENEMIES.has(id):return false
			if key=="discoveries":
				var parts: PackedStringArray=id.split("／")
				if parts.size()!=2 or not Content.REGIONS.has(parts[0]) or not parts[1] in Content.REGIONS[parts[0]]:return false
	if not value.get("scene","") is String or value.scene.length()>50:return false
	if value.get("tracked","")!="" and not Content.QUESTS.has(value.tracked):return false
	var honor: Variant=value.get("honor",0)
	return (honor is int or honor is float) and is_finite(float(honor)) and honor>=0 and honor<=1000000
