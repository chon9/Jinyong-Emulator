extends SceneTree
const Rules = preload("res://scripts/world.gd")
const Data = preload("res://scripts/content.gd")
const Life = preload("res://scripts/life_skills.gd")
var checks := 0
var failures: Array = []

func _init() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description); push_error(description)

func advance(w, seconds: int) -> void:
	for i in seconds: w.step()

func run() -> void:
	var w = Rules.new()
	w.rng.seed = 42
	var p: Dictionary = w.add_player(1)
	check(Data.LIFE.size() == 11 and Data.FACILITIES.size() == 62, "Reference life skills and workplaces imported")
	var recipes := 0
	for skill in Data.LIFE:
		var row: Dictionary = Data.LIFE[skill]
		for teacher in row.teachers:
			p.silver = 500
			p.place = "揚州城"
			p.life_levels.erase(skill)
			check(not w.act(1, "生活學習", skill + "|" + teacher.npc_id), "Distant teacher cannot teach: " + skill)
			p.place = Data.NPCS[teacher.npc_id].place
			check(w.act(1, "生活學習", skill + "|" + teacher.npc_id), "Local source teacher grants initial lesson: " + skill)
			check(p.silver == 500 - int(teacher.price) and int(p.life_levels[skill]) == 1 and int(p.life_prof[skill]) == 2, "Exact lesson payment and initial proficiency")
			if teacher.tool != "": check(int(p.inventory.get(teacher.tool, 0)) > 0, "Initial tool supplied")
			check(not w.act(1, "生活學習", skill + "|" + teacher.npc_id), "Repeated lesson cannot mint tools")
		p.life_levels[skill] = 100
		p.life_prof[skill] = 20000
		for r in row.get("recipes", []):
			recipes += 1
			var places := Life.locations(skill, r.id, "揚州城")
			check(not places.is_empty(), "Reachable workstation: " + str(r.name))
			p.place = places[0].place
			p.inventory = {}
			for tool in Life.tools(row, r):
				check(Data.SHOP.has(tool), "Tool has runtime item definition")
				p.inventory[tool] = 1
			for item in r.inputs:
				check(Data.SHOP.has(item.item), "Ingredient has runtime item definition")
				p.inventory[item.item] = int(p.inventory.get(item.item, 0)) + int(item.n)
			check(Data.SHOP.has(r.output.item), "Craft output has runtime item definition")
			var output_before := int(p.inventory.get(r.output.item, 0))
			var attempts := 0
			while int(p.inventory.get(r.output.item, 0)) == output_before and attempts < 8:
				p.energy = 100
				var before: Dictionary = p.inventory.duplicate(true)
				check(w.act(1, "生活工作", "%s|%s|1" % [skill, r.id]), "Source recipe can start: " + str(r.name))
				advance(w, int(row.cooldown_s) - 1)
				check(p.inventory == before and p.energy == 100, "Incomplete work cannot consume materials or grant output")
				w.step()
				check(not p.life_work.active and int(p.life_work.done) == 1 and int(p.energy) == 100 - Life.cost(row, r), "A full cycle pays energy once and respects the one-attempt limit")
				if int(p.life_work.successes) == 0: check(p.inventory == before, "Failed craft retains all materials")
				else:
					for item in r.inputs: check(int(p.inventory[item.item]) == int(before[item.item]) - int(item.n), "Successful craft consumes the exact input")
				attempts += 1
			check(int(p.inventory.get(r.output.item, 0)) == output_before + int(r.output.n), "Source recipe produces exactly the declared result")
	check(recipes == 38, "All 38 source recipes executed")
	p.place = Life.locations("life_fishing", "", "揚州城")[0].place
	p.inventory = {Data.LIFE.life_fishing.tool: 1}
	p.energy = 100
	w.act(1, "生活工作", "life_fishing||10")
	advance(w, 4)
	check(not w.act(1, "生活工作", "life_fishing||1"), "Spamming start cannot shorten a pending cycle")
	w.act(1, "停止")
	advance(w, 8)
	check(int(p.inventory.get("魚", 0)) == 0 and p.energy == 100 and int(p.life_work.done) == 0, "Stopping an incomplete cycle grants no product and charges no energy")
	p.energy = 5
	w.act(1, "生活工作", "life_fishing||0")
	advance(w, 5)
	check(not p.life_work.active and p.energy == 0 and int(p.life_work.done) == 1, "Continuous mode stops automatically at insufficient energy")
	p.energy = 0
	check(w.act(1, "生活工作", "life_fishing||2|休息"), "Optional rest mode may start exhausted")
	advance(w, 19)
	check(p.life_work.active and p.life_work.resting and int(p.life_work.done) == 0 and p.energy == 95, "Automatic meditation recovers energy without producing resources")
	w.step()
	check(not p.life_work.resting and p.energy == 100, "Automatic rest ends at full energy")
	advance(w, 4)
	check(int(p.life_work.done) == 0, "Resumed work still waits a full cycle")
	advance(w, 6)
	check(int(p.life_work.done) == 2 and not p.life_work.active and int(p.energy) == 90, "Rest and resume retain the exact remaining batch limit")
	p.energy = 100
	w.act(1, "生活工作", "life_fishing||10")
	p.inventory.erase(Data.LIFE.life_fishing.tool)
	advance(w, 5)
	check(not p.life_work.active and int(p.life_work.done) == 0 and p.energy == 100, "Selling or trading the required tool invalidates pending work without partial charge")
	p.inventory[Data.LIFE.life_fishing.tool] = 1
	w.act(1, "生活工作", "life_fishing||10")
	w.act(1, "尋路", "揚州城")
	check(not p.life_work.active and p.auto == "停止", "Travel cancels pending life work immediately")
	p.travel_target = ""
	p.travel_route = []
	p.place = Life.locations("life_hunting", "", "揚州城")[0].place
	p.energy = 100
	p.hp = p.max_hp
	w.act(1, "生活工作", "life_hunting||1")
	advance(w, 10)
	check(not p.enemy.is_empty() and p.enemy.life_hunt and p.energy == 90 and int(p.life_work.done) == 0, "Hunting spends energy and starts actual combat before yielding hides")
	var prof := int(p.life_prof.life_hunting)
	w.act(1, "逃跑")
	check(p.life_hunt.is_empty() and not p.life_work.active and int(p.life_prof.life_hunting) == prof + 2 and p.life_work.gained.is_empty(), "Retreat gives failure proficiency but no hunting materials")
	p.hp = p.max_hp
	p.energy = 100
	w.act(1, "生活工作", "life_hunting||1")
	advance(w, 10)
	p.enemy.hp = 1
	w.step()
	check(p.enemy.is_empty() and p.life_hunt.is_empty() and int(p.life_work.successes) == 1 and not p.life_work.active, "Winning actual hunt settles one completed attempt")
	# Save migration is tested through the real Session loader, including a pending job.
	var session = root.get_node("Session")
	session.save_path = "res://test-results/life-save.json"
	session.world.players[1] = p
	p.enemy = {}
	p.energy = 100
	p.place = Life.locations("life_fishing", "", "揚州城")[0].place
	session.world.act(1, "生活工作", "life_fishing||10")
	session.save_game()
	session._load()
	session._restore(1, session.local_character)
	var restored: Dictionary = session.world.players[1]
	for field in ["life_levels", "life_prof", "inventory"]:
		for key in p[field]: check(int(restored[field].get(key, -1)) == int(p[field][key]), "Save retains %s/%s" % [field, key])
	check(restored.life_work.is_empty() and restored.life_hunt.is_empty() and restored.auto == "停止", "Loading cannot resume pending work or invent offline products")
	session._restore(1, {"name": "舊角色"})
	check(session.world.players[1].life_levels.is_empty(), "Pre-life saves get safe empty defaults")
	var output := FileAccess.open("res://test-results/life-result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	print("LIFE: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
