extends RefCounted
## Free exploration, optional multi-step commissions and persistent relationships.
const Content = preload("res://scripts/journey/open_content.gd")

static func ensure(campaign) -> Dictionary:
	if not campaign.state.has("open_world"):
		campaign.state.open_world={"version":1,"scene":"","quests":{},"tracked":"","affinity":{},"met":[],"defeated":[],"discoveries":[],"honor":0}
	return campaign.state.open_world

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
		var step: Dictionary=Content.QUESTS[id].steps[int(state.step)]
		if step.kind=="visit" and step.region==region and step.scene==scene: _advance(campaign,id)

static func people(campaign) -> Array:
	var result:=[]
	for id in Content.PEOPLE:
		var npc: Dictionary=Content.PEOPLE[id]
		if npc.region==current_region(campaign) and npc.scene==current_scene(campaign): result.append(id)
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
	campaign.recruit(hero)
	campaign.record(Content.PEOPLE[id].name+"應邀同行；江湖不問先後，支線可日後再辦。")
	return Content.PEOPLE[id].name+"加入同行名冊。"+("已加入出戰隊伍。" if hero in campaign.state.party else "四人出戰已滿，可在隊伍視窗輪換。")

static func quests_here(campaign, npc: String="") -> Array:
	var result:=[]
	for id in Content.QUESTS:
		var quest: Dictionary=Content.QUESTS[id]
		if quest.region==current_region(campaign) and quest.scene==current_scene(campaign) and (npc=="" or quest.giver==npc):result.append(id)
	return result

static func active_for(campaign,npc: String) -> Array:
	var result:=[]
	var data:=ensure(campaign)
	for id in data.quests:
		var state: Dictionary=data.quests[id]
		if state.status!="active":continue
		var step: Dictionary=Content.QUESTS[id].steps[int(state.step)]
		if step.get("npc",npc)==npc and step.region==current_region(campaign) and step.scene==current_scene(campaign):result.append(id)
	return result

static func accept(campaign,id: String,npc: String="") -> String:
	if not Content.QUESTS.has(id):return "找不到這份委託。"
	var quest: Dictionary=Content.QUESTS[id]
	if quest.region!=current_region(campaign) or quest.scene!=current_scene(campaign):return "先到委託人所在的場景。"
	if npc!="" and npc!=quest.giver:return "請向委託人親自接洽。"
	var data:=ensure(campaign)
	if data.quests.has(id):data.tracked=id;return "已追蹤這份委託，可查看當前步驟。"
	data.quests[id]={"status":"active","step":0,"choices":[]}
	data.tracked=id
	campaign.record("接下支線・"+quest.name+"。")
	return "已接下「"+quest.name+"」。可隨時探索別處，沒有主線期限。"

static func action(campaign,id: String,npc: String="",choice: int=-1) -> Dictionary:
	var data:=ensure(campaign)
	if not data.quests.has(id) or data.quests[id].status!="active":return {"text":"這份委託目前沒有待辦步驟。"}
	var state: Dictionary=data.quests[id]
	var step: Dictionary=Content.QUESTS[id].steps[int(state.step)]
	if step.region!=current_region(campaign) or step.scene!=current_scene(campaign):return {"text":"請先前往"+step.region+"／"+step.scene+"。"}
	if step.has("npc") and step.npc!=npc:return {"text":"請與"+Content.PEOPLE[step.npc].name+"交談。"}
	match step.kind:
		"battle":return {"text":step.text,"battle":"quest:"+id+":"+str(int(state.step))}
		"deliver":
			if int(campaign.state.inventory.get(step.item,0))<int(step.count):return {"text":"需要 %d 份%s；可採集或購買後再回來。"%[step.count,step.item]}
			campaign.state.inventory[step.item]-=int(step.count)
		"choice":
			if choice<0 or choice>=step.options.size():return {"text":"先選擇你願意採取的做法。"}
			state.choices.append(choice)
			if choice==0:data.honor+=2
			else:campaign.state.potential+=8
	_advance(campaign,id)
	return {"text":"委託完成，報酬與情義已記入。" if state.status=="done" else "已完成這一步；可繼續查看下一個目標。"}

static func _advance(campaign,id: String) -> void:
	var state: Dictionary=ensure(campaign).quests[id]
	if state.status!="active":return
	state.step=int(state.step)+1
	var quest: Dictionary=Content.QUESTS[id]
	if state.step<quest.steps.size():return
	state.status="done"
	var reward: Dictionary=quest.reward
	campaign.state.silver+=int(reward.silver)
	campaign.state.potential+=int(reward.potential)
	if reward.has("hero"):
		var data:=ensure(campaign)
		data.affinity[reward.hero]=mini(100,int(data.affinity.get(reward.hero,0))+int(reward.affinity))
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
		var step: Dictionary=Content.QUESTS[parts[1]].steps[int(parts[2])]
		if step.kind!="battle" or step.region!=current_region(campaign) or step.scene!=current_scene(campaign):return []
		ids=step.enemies
	var result:=[]
	for id in ids:
		if not Content.ENEMIES.has(id):return []
		var source: Dictionary=Content.ENEMIES[id]
		var u: Dictionary=source.duplicate(true)
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
	if not value is Dictionary or value.get("version")!=1:return false
	for key in ["quests","affinity"]:
		if not value.get(key) is Dictionary:return false
	if value.quests.size()>Content.QUESTS.size():return false
	for id in value.quests:
		if not Content.QUESTS.has(id):return false
		var state: Variant=value.quests[id]
		if not state is Dictionary or not state.get("status") in ["active","done"]:return false
		var step: Variant=state.get("step")
		if not (step is int or step is float) or not is_finite(float(step)) or float(step)!=int(step) or step<0:return false
		var maximum: int=Content.QUESTS[id].steps.size()
		if (state.status=="done" and step!=maximum) or (state.status=="active" and step>=maximum):return false
		if not state.get("choices") is Array or state.choices.size()>maximum:return false
		for choice in state.choices:
			if not (choice is int or choice is float) or not is_finite(float(choice)) or float(choice)!=int(choice) or choice<0 or choice>1:return false
	for id in value.affinity:
		var n: Variant=value.affinity[id]
		if not Content.HEROES.has(id) or not (n is int or n is float) or not is_finite(float(n)) or n<0 or n>100:return false
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
