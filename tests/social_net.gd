extends SceneTree
var session
var host := false
var complete := false
var private_received := false
var failures: Array = []
var checks := 0

func _init() -> void:
	host = "--host-test" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description); push_error(description)

func wait_until(predicate: Callable, description: String, timeout: float = 8.0) -> bool:
	var elapsed := 0.0
	while not predicate.call() and elapsed < timeout:
		await create_timer(.1).timeout
		elapsed += .1
	var ok: bool = predicate.call()
	check(ok, description)
	return ok

func tx(command: String, arg: String = "") -> void:
	session.send(command, arg)
	await create_timer(.2).timeout

func invitation(kind: String) -> int:
	for r in session.state.get("social", {}).get("requests", []):
		if r.kind == kind: return int(r.id)
	return 0

func run() -> void:
	session = root.get_node("Session")
	session.message.connect(_message)
	if host:
		session.host_lan()
		session.guest_saves.clear()
		session.world.add_player(1, "聯機隊長")
		session.world.players[1].auto_heal = false
		await wait_until(func(): return complete, "Remote interaction scenario completes", 55)
		check(private_received, "Host receives directed private chat")
		check(session.world.social.battles.is_empty(), "No orphan multiplayer battles")
	else:
		session.join_lan("127.0.0.1")
		if not await wait_until(func(): return not session.state.is_empty(), "Client connected"): finish(); return
		await tx("說", "SYNC_MARTIAL")
		await wait_until(func(): return session.state.player.skills.has("基本劍法"), "Martial fixture replicated from host")
		await tx("裝備", "木劍")
		check(session.state.player.weapon == "木劍" and session.state.player.equipped == "基本劍法", "Host selects compatible sword art over RPC")
		await tx("裝備", "打狗棒法")
		check(session.state.player.equipped == "基本劍法", "Host rejects remote sword and staff mismatch")
		await tx("裝備", "基本內功")
		check(session.state.player.inner == "基本內功" and session.state.player.equipped == "基本劍法", "Remote inner slot does not replace external art")
		await tx("卸下", "weapon")
		check(session.state.player.weapon == "" and session.state.player.equipped == "搏擊格鬥", "Host applies remote weapon removal")
		await tx("尋路", session.world.Data.NPCS["n_wd_zhangsanfeng"].place)
		await wait_until(func(): return session.state.player.place == session.world.Data.NPCS["n_wd_zhangsanfeng"].place, "Remote navigation reaches the exact NPC room", 15)
		check(session.state.player.travel_target == "", "Remote travel clears automatically on arrival")
		await tx("說", "SYNC_LEARNING")
		await wait_until(func(): return session.state.player.place == session.world.Data.NPCS["n_xx_wushi"].place, "Host learning fixture synchronized")
		await tx("消點", "n_xx_wushi|基本劍法")
		check(int(session.state.player.potential) == 99 and int(session.state.player.skills["基本劍法"]) == 4 and int(session.state.player.skill_xp["基本劍法"]) == 15, "Remote instruction spends one point for proficiency instead of a level")
		await tx("自修", "基本劍法")
		await wait_until(func(): return int(session.state.player.potential) <= 96, "Host completes remote five-second self-study cycle", 8)
		await tx("停止")
		check(int(session.state.player.potential) == 96, "Remote self-study consumes exactly three points per cycle")
		await tx("說", "SYNC_PARTY")
		if not await wait_until(func(): return invitation("組隊") > 0, "Host invitation replicated"): finish(); return
		await tx("接受邀請", str(invitation("組隊")))
		await wait_until(func(): return int(session.state.player.party) != 0, "Party acceptance synchronized")
		check(session.state.social.party.members.size() == 2, "Both peers listed in party")
		await tx("跟隨", "開啟")
		await tx("說", "SYNC_TRAVEL")
		await wait_until(func(): return session.state.player.place == "城郊荒野", "Following crosses network")
		await wait_until(func(): return int(session.state.player.kills) >= 1, "Shared party victory reaches client")
		check(int(session.state.player.exp) == 13, "Client receives divided encounter experience")
		await tx("說", "SYNC_TRADE")
		if not await wait_until(func(): return invitation("交易") > 0, "Trade offer replicated"): finish(); return
		var money: int = session.state.player.silver
		var items: int = session.state.player.inventory["金創藥"]
		await tx("接受邀請", str(invitation("交易")))
		await wait_until(func(): return int(session.state.player.silver) == money - 10, "Trade currency synchronized")
		check(int(session.state.player.inventory["金創藥"]) == items + 2, "Trade item quantity synchronized")
		await tx("說", "SYNC_DUEL")
		if not await wait_until(func(): return invitation("切磋") > 0, "Duel invitation replicated"): finish(); return
		await tx("接受邀請", str(invitation("切磋")))
		await wait_until(func(): return int(session.state.player.fight) != 0, "Consensual duel starts remotely")
		await tx("認輸")
		await wait_until(func(): return int(session.state.player.fight) == 0, "Duel surrender clears client battle")
		check(int(session.state.player.pvp_losses) == 1, "Duel result synchronized")
		await tx("說", "SYNC_PK")
		await tx("前往", "城郊荒野")
		await tx("PK設定", "開啟")
		await tx("說", "SYNC_PK_READY")
		await wait_until(func(): return int(session.state.player.fight) != 0, "Wilderness PK starts remotely")
		await tx("認輸")
		await wait_until(func(): return session.state.player.place == "揚州城", "PK defeat moves remote client to town")
		check(not session.state.player.pk_enabled and int(session.state.player.fight) == 0, "Remote PK state resets after loss")
		await tx("私聊", "1|SOCIAL_PRIVATE")
		await tx("說", "SOCIAL_DONE")
	finish()

func _message(channel: String, text: String) -> void:
	if not host: return
	if channel == "私聊" and "SOCIAL_PRIVATE" in text: private_received = true
	if channel != "世界": return
	var target := 0
	for id in session.world.players:
		if id != 1: target = id
	if target == 0: return
	if "SYNC_MARTIAL" in text:
		var p: Dictionary = session.world.players[target]
		p.skills.merge({"基本劍法": 1, "打狗棒法": 1}, true)
		p.inventory["木劍"] = 1
		session._publish()
	elif "SYNC_LEARNING" in text:
		var p: Dictionary = session.world.players[target]
		p.place = session.world.Data.NPCS["n_xx_wushi"].place
		p.skills["基本劍法"] = 4
		p.skill_xp["基本劍法"] = 0
		p.potential = 100
		p.energy = 100
		p.silver = 1000
		p.combat_xp = 10000
		session._publish()
	elif "SYNC_PARTY" in text:
		session.world.players[target].place = "揚州城"
		session.world.players[target].auto_heal = false
		session.send("組隊邀請", str(target))
	elif "SYNC_TRAVEL" in text:
		session.send("前往", "城郊荒野")
		session.send("打怪")
	elif "SYNC_TRADE" in text:
		session.send("前往", "揚州城")
		session.send("交易", str(target) + "|金創藥|2|10")
	elif "SYNC_DUEL" in text: session.send("切磋", str(target))
	elif "SYNC_PK_READY" in text:
		session.send("PK設定", "開啟")
		session.send("PK", str(target))
	elif "SYNC_PK" in text:
		session.send("離隊")
		session.send("前往", "城郊荒野")
	elif "SOCIAL_DONE" in text: complete = true

func finish() -> void:
	var role := "host" if host else "client"
	var file := FileAccess.open("res://test-results/social_net_" + role + "_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	file.close()
	print("SOCIAL NET ", role, ": ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
