extends SceneTree
var session
var is_host := false
var done := false
var failures: Array = []
var checks := 0
var heard_chat := false
var elapsed := 0.0

func _init() -> void:
	is_host = "--host-test" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); push_error(description)

func run() -> void:
	session = root.get_node("Session")
	session.message.connect(_message)
	if is_host:
		session.host_lan()
		session.world.add_player(1, "測試房主")
		print("NET_HOST_READY")
		while not done and elapsed < 25:
			await create_timer(.25).timeout
			elapsed += .25
		check(done, "Client completed the network scenario")
		check(heard_chat, "Host receives client world chat")
		check(not session.guest_saves.is_empty(), "Host owns guest persistence")
	else:
		session.join_lan("127.0.0.1")
		await wait_connected()
		if session.state.is_empty(): finish(); return
		check(session.state.roster.size() == 2, "Both players appear in snapshot")
		session.send("改名", "測試訪客")
		session.send("說", "NET_CHAT")
		session.send("前往", "城郊荒野")
		session.send("掛機", "刷怪")
		while elapsed < 15 and int(session.state.get("player", {}).get("kills", 0)) < 1:
			await create_timer(.25).timeout
			elapsed += .25
		check(int(session.state.player.kills) >= 1, "Server battle produces real client rewards")
		check(session.state.player.name == "測試訪客", "Client rename synchronized")
		session.send("停止")
		await create_timer(.3).timeout
		var kills: int = session.state.player.kills
		session.start_offline()
		await create_timer(.6).timeout
		session.join_lan("127.0.0.1")
		elapsed = 0
		await wait_connected()
		check(not session.state.is_empty() and session.state.player.kills == kills, "Reconnect restores host-owned guest progress")
		check(session.state.player.name == "測試訪客", "Reconnect uses stable identity")
		check(session.state.player.auto == "停止", "Reconnect never restarts unattended automation")
		session.send("說", "NET_DONE")
		await create_timer(.5).timeout
	finish()

func wait_connected() -> void:
	while session.state.is_empty() and elapsed < 8:
		await create_timer(.1).timeout
		elapsed += .1
	check(not session.state.is_empty(), "Connection delivers authoritative snapshot")

func _message(channel: String, text: String) -> void:
	if channel == "世界" and "NET_CHAT" in text: heard_chat = true
	if is_host and channel == "世界" and "NET_DONE" in text: done = true

func finish() -> void:
	var role := "host" if is_host else "client"
	var file := FileAccess.open("res://test-results/net_" + role + "_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	file.close()
	print("NET_", role.to_upper(), ": ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
