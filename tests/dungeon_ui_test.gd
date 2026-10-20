extends "res://tests/ui_flow_test.gd"

func run() -> void:
	var logger := ErrorLog.new()
	OS.add_logger(logger)
	session = root.get_node("Session")
	session.save_path = "res://test-results/dungeon-ui-save.json"
	for timer in session.get_children():
		if timer is Timer: timer.stop()
	var p: Dictionary = session.world.add_player(1, "副本驗證")
	p.skills.merge({"搏擊格鬥": 5, "基本內功": 5, "閃躲縱躍": 5, "拆招卸力": 5}, true)
	session.world.rng.seed = 7
	session._publish()
	ui = load("res://scenes/main.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	await click_named("接任務 · 討伐委託 · 黑風寨剿匪")
	check(p.learning_quests.has("q_yx_dungeon_blackwind"), "Beginner can accept the linked dungeon quest beside the hub NPC")
	await click_named("開啟副本 ·")
	check(ui.tabs.current_tab == 8, "Quest points directly to the relevant dungeon page")
	await click_named("前往副本入口")
	await walk()
	await click(ui.nav_buttons[8])
	await click_named("進入副本")
	check(not session.state.dungeon.is_empty() and find_button("開始這一關").disabled, "Instance shows readiness before starting")
	var guard := 0
	while session.state.dungeon.phase in ["READY", "FIGHT"] and guard < 200:
		if session.state.dungeon.phase == "READY":
			await click_named("我已準備")
			await click_named("開始這一關")
		session._tick()
		guard += 1
		await process_frame
		await process_frame
	check(session.state.dungeon.phase == "CLEARED" and int(p.dungeon_clears.get("blackwind", 0)) == 1, "Mouse-driven instance clears all three stages through actual combat")
	await click_named("返回江湖")
	check(int(p.dungeon) == 0, "Return button exits the instance")
	await click(ui.nav_buttons[3])
	await click_named("領取獎勵")
	check(p.quests_done.has("q_yx_dungeon_blackwind"), "Dungeon clear unlocks the linked quest reward")
	session.save_game()
	session.local_character = {}
	session._load()
	session._restore(1, session.local_character)
	p = session.world.players[1]
	check(int(p.dungeon) == 0 and int(p.dungeon_clears.get("blackwind", 0)) == 1 and p.dungeon_cooldowns.has("blackwind"), "Save keeps awarded clears and cooldowns while dropping live-instance state")
	OS.remove_logger(logger)
	check(logger.errors.is_empty(), "No script errors during the real dungeon UI flow: " + str(logger.errors))
	var output := FileAccess.open("res://test-results/dungeon-ui-result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	output.close()
	print("DUNGEON UI: ", checks, " checks, ", failures.size(), " failures")
	ui.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
