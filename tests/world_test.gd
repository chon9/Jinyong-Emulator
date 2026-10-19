extends SceneTree
const Rules = preload("res://scripts/world.gd")
const Data = preload("res://scripts/content.gd")
var failures: Array = []
var checks := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var counts := {"places": Data.PLACES.size(), "npcs": Data.NPCS.size(), "items": Data.SHOP.size(), "enemies": Data.ENEMIES.size(), "sects": Data.SECTS.size(), "skills": Data.SKILLS.size(), "stories": Data.STORIES.size()}
	print("CONTENT ", JSON.stringify(counts))
	for key in ["places", "npcs", "items", "enemies"]: check(int(counts[key]) >= 100, "Content floor: " + key)
	check(counts.sects >= 11, "Eleven playable sects")
	var dialogue_set := {}
	var acquisitions := {}
	var commissions := {}
	var taught := {}
	var reachable := {"揚州城": true}
	var queue := ["揚州城"]
	while not queue.is_empty():
		var place: String = queue.pop_front()
		for destination in Data.PLACES[place].exits:
			check(Data.PLACES.has(destination), "Valid exit: " + destination)
			if not reachable.has(destination): reachable[destination] = true; queue.append(destination)
	check(reachable.size() == Data.PLACES.size(), "Every location is reachable")
	for id in Data.NPCS:
		var npc: Dictionary = Data.NPCS[id]
		check(reachable.has(npc.place), "NPC reachable: " + id)
		check(not npc.dialogue.is_empty() and str(npc.dialogue[0]).length() > 10, "NPC independent dialogue: " + id)
		dialogue_set[npc.dialogue[0]] = true
		for lesson in npc.teach:
			taught[lesson.skill] = true
			check(Data.SKILLS.has(lesson.skill), "Teacher skill exists: " + lesson.skill)
			for req in lesson.requires: check(Data.SKILLS.has(req.skill), "Lesson requirement exists: " + req.skill)
		for request in npc.get("requests", []): commissions[request.item] = id
	check(dialogue_set.size() >= 100, "At least 100 distinct NPC conversations")
	var spawned := {}
	for place in Data.PLACES.values():
		for item in place.get("finds", []): acquisitions[item] = true
		for enemy in place.get("enemies", [place.enemy] if place.enemy != "" else []):
			check(Data.ENEMIES.has(enemy), "Valid encounter: " + enemy)
			spawned[enemy] = true
	for name in Data.ENEMIES: check(spawned.has(name), "Enemy has a real spawn: " + name)
	for item in Data.SHOP:
		if not Data.SHOP[item].get("quest", false): acquisitions[item] = true
		check(acquisitions.has(item), "Item can actually be acquired: " + item)
		if Data.SHOP[item].get("quest", false): check(commissions.has(item), "Quest item has a delivery use: " + item)
	for skill in Data.SKILLS:
		var quest_locked := false
		for condition in Data.SKILLS[skill].get("conditions", []):
			if condition.type == "quest_flag": quest_locked = true
		check(taught.has(skill) or quest_locked or Data.SKILLS[skill].get("legacy_only", false), "Skill has a teacher, explicit quest lock or preserved legacy status: " + skill)
	check(dialogue_set.size() == Data.NPCS.size(), "Every NPC has a unique opening dialogue")
	for story in Data.STORIES:
		check(story.npcs.size() == story.scenes.size(), "Complete story scenes: " + story.id)
		for id in story.npcs: check(Data.NPCS.has(id), "Story NPC exists: " + id)
	var world := Rules.new()
	world.rng.seed = 7
	var p: Dictionary = world.add_player(1, "測試少俠")
	check(not world.act(1, "前往", "不存在"), "Invalid destination rejected")
	check(not world.act(1, "拜師", "少林"), "Remote sect join rejected")
	for sect in Data.SECTS:
		p = world.add_player(1)
		p.place = Data.SECTS[sect].place
		p.gender = Data.SECTS[sect].get("gender", ["M"])[0]
		p.morality = -100 if sect in ["星宿", "血刀門"] else 50
		p.skills["基本內功"] = 5
		p.skills["讀書識字"] = 5
		p.flags.merge({"wd_recommended": true, "hs_trial_passed": true})
		check(world.act(1, "拜師", sect), "Can join " + sect)
		check(not p.skills.has(Data.SECTS[sect].basic), "Sect enrollment does not bypass learning requirements: " + sect)
		check(not world.act(1, "拜師", sect), "Cannot repeatedly claim sect rewards")
	p = world.add_player(1)
	var teacher := "n_xx_wushi"
	p.place = Data.NPCS[teacher].place
	var lesson: Dictionary = Data.NPCS[teacher].teach[0]
	var skill: String = lesson.skill
	var points: int = p.potential
	var silver: int = p.silver
	check(world.act(1, "消點", teacher + "|" + skill), "First lesson at local master")
	check(int(p.skills[skill]) >= 1 and p.potential == points - 1 and p.silver <= silver, "Lessons spend one point on proficiency and can unlock skills")
	check(not world.act(1, "消點", teacher + "|" + skill), "One lesson per simulation tick")
	world.step()
	p.place = "揚州城"
	check(not world.act(1, "消點", teacher + "|" + skill), "Remote learning rejected")
	p.place = Data.NPCS[teacher].place
	p.skills[skill] = lesson.cap
	check(not world.act(1, "消點", teacher + "|" + skill), "Teacher cap enforced")
	p.skills[skill] = 1
	points = p.potential
	silver = p.silver
	check(world.act(1, "自修", skill), "Self study starts on known martial art")
	for i in 6: world.step()
	check(int(p.skills[skill]) > 1, "Self study actually raises martial level")
	check(p.potential == points - 3 and p.silver == silver, "One full self-study cycle consumes three points without silver")
	check(p.energy < 100, "Self study consumes energy")
	check(not world.act(1, "自修", "不會的武功"), "Unknown self study rejected")
	p = world.add_player(1)
	p.hp = 10
	p.auto_heal = true
	var bottles: int = p.inventory["金創藥"]
	world.step()
	check(p.hp > 10 and p.inventory["金創藥"] == bottles - 1, "Automatic healing uses real inventory")
	check(world.act(1, "任務"), "Bounty accepted")
	check(world.act(1, "前往", "城郊荒野"), "Can reach beginner combat area")
	check(world.act(1, "掛機", "刷怪"), "Auto hunt starts")
	for i in 60:
		world.step()
		if p.job.count == 3: break
	check(p.kills >= 3 and p.job.count == 3, "Kills progress active bounty")
	check(p.potential > 100, "Combat awards study points")
	world.act(1, "逃跑")
	world.act(1, "停止")
	check(world.act(1, "前往", "揚州城"), "Can return after battle")
	check(world.act(1, "領賞"), "Bounty rewards paid once")
	check(not world.act(1, "領賞"), "Cannot replay reward")
	p.silver = 1000
	check(world.act(1, "購買", "精鋼劍"), "Buy weapon")
	check(not world.act(1, "裝備", "精鋼劍"), "Cannot use sword without learned sword arts")
	p.skills["基本劍法"] = p.skills["搏擊格鬥"]
	var before := Rules.attack(p)
	check(world.act(1, "裝備", "精鋼劍") and Rules.attack(p) > before, "Compatible weapon scales actual martial power")
	check(not world.act(1, "出售", "精鋼劍"), "Cannot sell last equipped weapon")
	var story: Dictionary = Data.STORIES[0]
	for npc_id in story.npcs:
		p.place = Data.NPCS[npc_id].place
		check(world.act(1, "對話", npc_id), "Story dialogue at actual NPC")
	check(p.stories[story.id] == story.npcs.size(), "Story progresses through ordered conversations")
	check(world.act(1, "故事選擇", story.id + "|0"), "Story choice rewards granted")
	points = p.potential
	check(not world.act(1, "故事選擇", story.id + "|1") and p.potential == points, "Cannot repeat or switch story rewards")
	var clone := world.snapshot(1)
	clone.player.silver = 999999
	check(p.silver != 999999, "Snapshots cannot mutate authoritative state")
	for npc_id in Data.NPCS:
		var npc: Dictionary = Data.NPCS[npc_id]
		if npc.get("requests", []).is_empty(): continue
		var request: Dictionary = npc.requests[0]
		p.place = request.place
		check(world.act(1, "搜查"), "Find real quest artifact in location")
		check(int(p.inventory.get(request.item, 0)) > 0, "Artifact enters inventory")
		check(not world.act(1, "搜查"), "Search reward cannot be duplicated")
		p.place = npc.place
		check(world.act(1, "交付", npc_id + "|" + request.item), "Artifact can complete local commission")
		check(not world.act(1, "交付", npc_id + "|" + request.item), "Commission cannot be claimed twice")
		break
	var file := FileAccess.open("res://test-results/world.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "counts": counts, "failures": failures}, "  "))
	file.close()
	print("WORLD TEST: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
