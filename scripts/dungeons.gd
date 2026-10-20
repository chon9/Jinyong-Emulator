extends RefCounted
## Host-owned instances. Only clears, cooldowns and awarded items persist.
const Data = preload("res://scripts/content.gd")
var owner: WeakRef
var world:
	get: return owner.get_ref()
var runs: Dictionary = {}
var sequence := 0
const COMMANDS := ["副本進入", "副本準備", "副本開戰", "副本離開"]

func _init(value) -> void:
	owner = weakref(value)

func reset() -> void:
	runs.clear()

func current(id: int) -> Dictionary:
	return runs.get(int(world.players.get(id, {}).get("dungeon", 0)), {})

func entry_reason(id: int, definition: Dictionary) -> String:
	var p: Dictionary = world.players[id]
	if int(p.get("dungeon", 0)) != 0: return "請先退出目前的副本。"
	if world.social.busy(id) or int(p.hp) <= 0: return "先結束戰鬥並療傷。"
	if p.place != definition.entry: return "請先到入口：" + str(definition.entry)
	if int(p.combat_xp) < int(definition.min_xp): return "實戰至少 %d，目前 %d。" % [definition.min_xp, p.combat_xp]
	var left := int(p.dungeon_cooldowns.get(definition.id, 0)) - int(Time.get_unix_time_from_system())
	if left > 0: return "通關冷卻尚餘 %d 分 %d 秒。" % [left / 60, left % 60]
	return ""

func act(id: int, command: String, arg: String) -> bool:
	var p: Dictionary = world.players[id]
	if command == "副本進入":
		if not Data.DUNGEONS.has(arg): return world.reject(id, "找不到這個副本。")
		var definition: Dictionary = Data.DUNGEONS[arg]
		var allies: Array = world.social.members(id).duplicate() if int(p.party) != 0 else [id]
		if int(p.party) != 0 and int(world.social.parties[int(p.party)].leader) != id: return world.reject(id, "請由隊長建立副本。")
		for member in allies:
			var reason := entry_reason(member, definition)
			if reason != "": return world.reject(id, "%s：%s" % [world.players[member].name, reason])
		sequence += 1
		var run := {"id": sequence, "definition": arg, "leader": id, "members": allies, "ready": {}, "stage": 0, "wave": 0, "cleared": 0, "phase": "READY", "enemy": {}, "down": [], "log": [], "awarded": false}
		runs[sequence] = run
		for member in allies:
			var player: Dictionary = world.players[member]
			player.dungeon = sequence
			player.auto = "停止"
			player.travel_target = ""
			player.travel_route = []
			player.study_ticks = 0
			run.ready[member] = false
		announce(run, "進入【%s】。每人按準備後，由隊長開戰；可隨時退出。" % definition.name)
		return true
	var run := current(id)
	if run.is_empty(): return world.reject(id, "你目前不在副本中。")
	match command:
		"副本離開": leave(id); return true
		"副本準備":
			if run.phase != "READY": return world.reject(id, "等目前關卡結束，才能準備下一關。")
			run.ready[id] = not bool(run.ready.get(id, false))
			p.auto = "停止"
			announce(run, "%s%s。" % [p.name, "已準備" if run.ready[id] else "取消準備"])
			return true
		"副本開戰":
			if int(run.leader) != id: return world.reject(id, "只有隊長能開始關卡。")
			if run.phase != "READY": return world.reject(id, "目前不能開始下一關。")
			for member in run.members:
				if not run.ready.get(member, false) or int(world.players[member].hp) <= 0: return world.reject(id, "所有隊員需先準備並保持氣血。")
			run.phase = "FIGHT"
			run["rounds"] = 0
			run.down = []
			spawn(run)
			return true
	return false

func announce(run: Dictionary, message: String) -> void:
	run.log.append(message)
	if run.log.size() > 18: run.log.pop_front()
	world.social.notify(run.members, message, "副本")

func spawn(run: Dictionary) -> void:
	var definition: Dictionary = Data.DUNGEONS[run.definition]
	var stage: Dictionary = definition.stages[int(run.stage)]
	var unit: Dictionary = stage.enemies[int(run.wave)]
	var enemy: Dictionary = Data.ENEMIES[unit.enemy].duplicate(true)
	for field in ["hp", "attack", "defense", "level"]: enemy[field] = int(unit.get(field, enemy.get(field, 1)))
	enemy.hp = ceili(int(enemy.hp) * (1.0 + .5 * (run.members.size() - 1)))
	enemy.max_hp = enemy.hp
	enemy.name = unit.enemy
	run.enemy = enemy
	for member in run.members:
		var p: Dictionary = world.players[member]
		p.fight = -int(run.id)
		p.enemy = enemy
		p.auto = "停止"
	announce(run, "第 %d/%d 關【%s】：%s（%d/%d）！" % [int(run.stage) + 1, definition.stages.size(), stage.name, enemy.name, int(run.wave) + 1, stage.enemies.size()])

func step() -> void:
	for key in runs.keys():
		if not runs.has(key): continue
		var run: Dictionary = runs[key]
		if run.phase != "FIGHT": continue
		run.rounds += 1
		if int(run.rounds) > 600: failed(run); continue
		var enemy: Dictionary = run.enemy
		for member in run.members:
			if member in run.down: continue
			var hit: Dictionary = world.strike(world.players[member], enemy)
			enemy.hp = maxi(0, int(enemy.hp) - int(hit.damage))
			announce(run, "%s以%s造成 %d 傷害，%s氣血 %d/%d。" % [world.players[member].name, hit.move, hit.damage, enemy.name, enemy.hp, enemy.max_hp])
			if int(enemy.hp) <= 0: won_enemy(run); break
		if run.phase != "FIGHT" or int(enemy.hp) <= 0: continue
		var alive: Array = run.members.filter(func(member): return not member in run.down)
		if alive.is_empty(): failed(run); continue
		var target: int = alive[world.rng.randi_range(0, alive.size() - 1)]
		var player: Dictionary = world.players[target]
		var hurt: int = world.Combat.enemy_roll(enemy, player, world.guard_art(player), world.rng)
		player.hp = maxi(0, int(player.hp) - hurt)
		announce(run, "%s反擊%s，造成 %d 傷害。" % [enemy.name, player.name, hurt])
		if int(player.hp) == 0:
			run.down.append(target)
			announce(run, "%s暫時失去戰力；隊友過關後可重新療傷。" % player.name)
			if run.down.size() == run.members.size(): failed(run)

func won_enemy(run: Dictionary) -> void:
	var definition: Dictionary = Data.DUNGEONS[run.definition]
	run.wave += 1
	if int(run.wave) < definition.stages[int(run.stage)].enemies.size(): spawn(run); return
	run.cleared += 1
	for member in run.members:
		world.players[member].fight = 0
		world.players[member].enemy = {}
		world.players[member].hp = maxi(1, int(world.players[member].hp))
		run.ready[member] = false
	if int(run.cleared) == definition.stages.size():
		run.phase = "CLEARED"
		if not run.awarded:
			run.awarded = true
			for member in run.members:
				var p: Dictionary = world.players[member]
				var first := int(p.dungeon_clears.get(definition.id, 0)) == 0
				for pair in [["silver", "silver"], ["points", "potential"], ["xp", "combat_xp"]]: p[pair[1]] += int(definition.rewards.get(pair[0], 0))
				for item in definition.rewards.get("items", []): p.inventory[item.item] = int(p.inventory.get(item.item, 0)) + int(item.n)
				if first:
					p.potential += int(definition.first_clear.points)
					for item in definition.first_clear.get("items", []): p.inventory[item.item] = int(p.inventory.get(item.item, 0)) + int(item.n)
				p.dungeon_clears[definition.id] = int(p.dungeon_clears.get(definition.id, 0)) + 1
				p.dungeon_cooldowns[definition.id] = int(Time.get_unix_time_from_system()) + int(definition.cooldown)
				p.flags["yx_dungeon_" + str(definition.id)] = true
				world.tell(member, "通關【%s】：銀兩 +%d、學點 +%d、實戰 +%d。%s獎勵已自動入帳。" % [definition.name, definition.rewards.silver, int(definition.rewards.points) + (int(definition.first_clear.points) if first else 0), definition.rewards.xp, "另獲首通道具，" if first else ""], "副本")
		announce(run, "全員通關！可退出副本返回江湖。")
	else:
		run.stage += 1
		run.wave = 0
		run.phase = "READY"
		announce(run, "本關完成。可打坐、用藥；所有人重新準備後開始下一關。")
	run.down = []
	run.enemy = {}

func failed(run: Dictionary) -> void:
	run.phase = "FAILED"
	run.enemy = {}
	for member in run.members:
		world.players[member].enemy = {}
		world.players[member].fight = 0
		world.players[member].auto = "停止"
		world.players[member].hp = maxi(1, int(world.players[member].hp))
	announce(run, "挑戰失敗，沒有發放通關獎勵。消耗的藥品不退回；退出療傷後可重新挑戰。")

func leave(id: int) -> void:
	var run := current(id)
	if run.is_empty(): return
	var p: Dictionary = world.players[id]
	world.tell(id, "已退出【%s】。%s" % [Data.DUNGEONS[run.definition].name, "通關獎勵已保留。" if run.phase == "CLEARED" else "本次未完成的進度不保留。"], "副本")
	p.dungeon = 0
	p.fight = 0
	p.enemy = {}
	p.auto = "停止"
	p.hp = maxi(1, int(p.hp))
	run.members.erase(id)
	run.ready.erase(id)
	run.down.erase(id)
	if run.members.is_empty(): runs.erase(int(run.id)); return
	if int(run.leader) == id: run.leader = run.members[0]
	announce(run, "%s退出副本；隊長為%s。" % [p.name, world.players[int(run.leader)].name])
	if run.phase == "FIGHT" and run.members.size() == run.down.size(): failed(run)

func snapshot(id: int) -> Dictionary:
	var run := current(id)
	if run.is_empty(): return {}
	var result: Dictionary = run.duplicate(true)
	result["roster"] = []
	for member in run.members:
		var p: Dictionary = world.players[member]
		result.roster.append({"id": member, "name": p.name, "hp": p.hp, "max_hp": p.max_hp, "ready": run.ready.get(member, false), "down": member in run.down})
	return result
