extends SceneTree
const Rules = preload("res://scripts/world.gd")
const Data = preload("res://scripts/content.gd")
var checks := 0
var failures: Array = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func fighter(w, id: int, skill: int = 5) -> Dictionary:
	var p: Dictionary = w.add_player(id)
	p.skills.merge({"搏擊格鬥": skill, "基本內功": skill, "閃躲縱躍": skill, "拆招卸力": skill}, true)
	p.inventory["金創藥"] = 5
	return p

func complete(w, leader: int) -> bool:
	var run: Dictionary = w.dungeons.current(leader)
	var guard := 0
	while run.phase in ["READY", "FIGHT"] and guard < 600:
		if run.phase == "READY":
			for member in run.members:
				if not run.ready.get(member, false): w.act(member, "副本準備")
			if not w.act(leader, "副本開戰"): return false
		w.step()
		guard += 1
	return run.phase == "CLEARED"

func run() -> void:
	for key in Data.DUNGEONS:
		var d: Dictionary = Data.DUNGEONS[key]
		check(Data.PLACES.has(d.entry) and d.stages.size() == 3, key + " has a real entrance and three stages")
		for stage in d.stages:
			for unit in stage.enemies: check(Data.ENEMIES.has(unit.enemy), key + " references real combat data")
		for item in d.rewards.items + d.first_clear.items: check(Data.SHOP.has(item.item), key + " reward item exists")
		var w := Rules.new()
		w.rng.seed = 20261020
		var skill: int = {"blackwind": 5, "bronze": 15, "blood": 25, "gaochang": 40}[key]
		var p := fighter(w, 1, skill)
		p.place = d.entry
		p.combat_xp = int(d.min_xp)
		check(w.act(1, "副本進入", key), key + " enters with stated prerequisites")
		check(not w.act(1, "副本開戰"), key + " cannot start without consent")
		var silver := int(p.silver)
		var points := int(p.potential)
		check(complete(w, 1), key + " completes through real combat at the recommended martial level")
		check(p.silver == silver + int(d.rewards.silver) and p.potential == points + int(d.rewards.points) + int(d.first_clear.points), key + " awards exactly the displayed first-clear totals")
		check(int(p.dungeon_clears.get(key, 0)) == 1 and p.flags.get("yx_dungeon_" + str(key), false), key + " unlocks its linked quest")
		silver = int(p.silver)
		for n in 5: w.step()
		check(p.silver == silver and not w.act(1, "副本開戰"), key + " cannot replay settlement")
		check(w.act(1, "副本離開") and int(p.dungeon) == 0 and int(p.fight) == 0 and p.enemy.is_empty(), key + " leaves cleanly")
		check(not w.act(1, "副本進入", key), key + " enforces persistent clear cooldown")
		p.dungeon_cooldowns[key] = 0
		p.hp = p.max_hp
		p.inventory["金創藥"] = 5
		check(w.act(1, "副本進入", key), key + " can be replayed after cooldown")
		points = int(p.potential)
		check(complete(w, 1) and int(p.potential) == points + int(d.rewards.points), key + " second clear does not duplicate first-clear rewards")
	# Entry checks, group readiness and anti-interference.
	var w := Rules.new()
	var a := fighter(w, 1)
	var b := fighter(w, 2)
	var outsider := fighter(w, 3)
	check(not w.act(1, "副本進入", "blackwind"), "Cannot enter from the wrong location")
	a.place = "黑風林"
	b.place = a.place
	outsider.place = a.place
	check(w.social.join_party(2, 1), "Party fixture forms")
	check(not w.act(2, "副本進入", "blackwind"), "A member cannot force party entry")
	check(w.act(1, "副本進入", "blackwind"), "Leader creates one shared instance")
	check(int(a.dungeon) == int(b.dungeon), "All party members share the same instance")
	check(not w.act(3, "切磋", "2") and not w.act(3, "交易", "2|金創藥|1|0"), "Outside players cannot pull instance members into PvP or trades")
	check(not w.act(2, "前往", "揚州城") and not w.act(2, "離隊"), "Ordinary travel and party mutations cannot escape instance rules")
	w.act(1, "副本準備")
	check(not w.act(1, "副本開戰"), "One ready player cannot start combat for another")
	w.act(2, "副本準備")
	check(w.act(1, "副本開戰"), "All-ready group starts")
	var run: Dictionary = w.dungeons.current(1)
	b.hp = 0
	run.down.append(2)
	run.enemy.hp = 999999
	run.enemy.attack = 0
	var medicine := int(b.inventory["金創藥"])
	w.step()
	check(int(b.hp) == 0 and int(b.inventory["金創藥"]) == medicine, "Auto-heal cannot resurrect downed participants")
	check(not w.act(1, "治療隊友", "2"), "Ordinary medicine cannot revive a downed fighter")
	w.social.disconnect_peer(1)
	check(int(a.dungeon) == 0 and int(run.leader) == 2 and run.phase == "FAILED", "Disconnect removes the leader, transfers control and resolves a downed-only group")
	check(not b.dungeon_clears.has("blackwind") and not b.dungeon_cooldowns.has("blackwind"), "Failure grants no clear or cooldown")
	w.act(2, "副本離開")
	check(int(b.dungeon) == 0 and b.enemy.is_empty(), "Failed group can exit")
	# Two solo instances at the same map entrance remain isolated.
	w = Rules.new()
	w.rng.seed = 20261020
	a = fighter(w, 1, 40)
	b = fighter(w, 2, 1)
	a.place = "黑風林"
	b.place = a.place
	w.act(1, "副本進入", "blackwind")
	w.act(2, "副本進入", "blackwind")
	check(int(a.dungeon) != int(b.dungeon), "Same-location solo players get distinct instances")
	for id in [1, 2]: w.act(id, "副本準備"); w.act(id, "副本開戰")
	w.step()
	check(int(w.dungeons.current(1).wave) == 1 and int(w.dungeons.current(2).wave) == 0, "One instance's kill does not progress another")
	var saved := int(a.silver)
	w.act(1, "副本離開")
	check(int(a.silver) == saved and not a.dungeon_clears.has("blackwind"), "Leaving partway has no partial payout")
	# Five consenting members finish the same encounter and receive one award each.
	w = Rules.new()
	for id in range(1, 6):
		var member := fighter(w, id)
		member.place = "黑風林"
		if id != 1: w.social.join_party(id, 1)
	check(w.act(1, "副本進入", "blackwind"), "Five-person party enters")
	w.players[2].hp = 20
	var used := int(w.players[1].inventory["金創藥"])
	check(w.act(1, "治療隊友", "2") and int(w.players[2].hp) == 90 and int(w.players[1].inventory["金創藥"]) == used - 1, "Party aid consumes one actual potion")
	check(complete(w, 1), "Five players complete all three shared stages")
	for id in range(1, 6): check(int(w.players[id].dungeon_clears.get("blackwind", 0)) == 1 and int(w.players[id].potential) == 230, "Exactly one clear reward for member " + str(id))
	# Beginner balance uses actual combat and the shipped starting potion supply.
	var won := 0
	for seed in 20:
		w = Rules.new()
		w.rng.seed = seed
		a = fighter(w, 1)
		a.place = "黑風林"
		w.act(1, "副本進入", "blackwind")
		if complete(w, 1): won += 1
	check(won == 20, "Beginner dungeon clears across 20 deterministic seeds at recommended level")
	var output := FileAccess.open("res://test-results/dungeons-result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "beginner_clears": won}, "  "))
	output.close()
	print("DUNGEONS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
