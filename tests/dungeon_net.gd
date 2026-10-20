extends SceneTree
var session
var host := false
var complete := false
var checks := 0
var failures: Array = []

func _init() -> void:
	host = "--host-test" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok: failures.append(description); push_error(description)
	return ok

func until(predicate: Callable, description: String, seconds: float = 15) -> bool:
	var start := Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec() - start < seconds * 1000:
		await create_timer(.1).timeout
	return check(predicate.call(), description)

func tx(command: String, arg: String = "") -> void:
	session.send(command, arg)
	await create_timer(.2).timeout

func setup(p: Dictionary) -> void:
	p.place = "黑風林"
	p.skills.merge({"搏擊格鬥": 5, "基本內功": 5, "閃躲縱躍": 5, "拆招卸力": 5}, true)
	p.inventory["金創藥"] = 5

func run() -> void:
	session = root.get_node("Session")
	session.message.connect(message)
	if host:
		session.host_lan()
		session.guest_saves.clear()
		setup(session.world.add_player(1, "副本隊長"))
		await until(func(): return complete, "Remote dungeon scenario completes", 45)
		check(session.world.dungeons.runs.is_empty(), "No orphan instance remains after both players leave")
	else:
		session.join_lan("127.0.0.1")
		if not await until(func(): return not session.state.is_empty(), "Client receives initial snapshot"): finish(); return
		await tx("說", "DUNGEON_SETUP")
		if not await until(func(): return not session.state.get("social", {}).get("requests", []).is_empty(), "Party invitation crosses network"): finish(); return
		await tx("接受邀請", str(session.state.social.requests[0].id))
		await tx("說", "DUNGEON_ENTER")
		if not await until(func(): return not session.state.get("dungeon", {}).is_empty(), "Client receives shared instance state"): finish(); return
		check(session.state.dungeon.roster.size() == 2 and session.state.dungeon.phase == "READY", "Client sees both participants and preparation state")
		await tx("副本開戰")
		check(session.state.dungeon.phase == "READY", "Remote nonleader cannot force combat")
		var guard := 0
		while session.state.dungeon.phase in ["READY", "FIGHT"] and guard < 350:
			if session.state.dungeon.phase == "READY" and not session.state.dungeon.ready.get(session.state.self_id, false):
				await tx("副本準備")
				await tx("說", "DUNGEON_START")
			await create_timer(.1).timeout
			guard += 1
		check(session.state.dungeon.phase == "CLEARED", "All three encounter stages settle across the real connection")
		check(int(session.state.player.dungeon_clears.get("blackwind", 0)) == 1 and int(session.state.player.inventory.get("木劍", 0)) == 1, "Client receives one persistent clear and first-clear item")
		check(int(session.state.player.potential) == 230, "Remote first-clear learning points match the displayed total")
		await tx("副本離開")
		check(int(session.state.player.dungeon) == 0 and session.state.dungeon.is_empty(), "Remote leave clears replicated instance state")
		await tx("說", "DUNGEON_DONE")
	finish()

func message(channel: String, text: String) -> void:
	if not host or channel != "世界": return
	var guest := 0
	for id in session.world.players:
		if id != 1: guest = id
	if guest == 0: return
	if "DUNGEON_SETUP" in text:
		setup(session.world.players[guest])
		session.send("組隊邀請", str(guest))
	elif "DUNGEON_ENTER" in text:
		session.send("副本進入", "blackwind")
		session.send("副本準備")
	elif "DUNGEON_START" in text:
		var current: Dictionary = session.world.dungeons.current(1)
		if not current.ready.get(1, false): session.send("副本準備")
		session.send("副本開戰")
	elif "DUNGEON_DONE" in text:
		check(int(session.world.players[guest].dungeon_clears.get("blackwind", 0)) == 1, "Host owns guest clear progression")
		session.send("副本離開")
		complete = true

func finish() -> void:
	var role := "host" if host else "client"
	var output := FileAccess.open("res://test-results/dungeon-net-" + role + ".json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	output.close()
	print("DUNGEON NET ", role, ": ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
