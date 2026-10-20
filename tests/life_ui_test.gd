extends "res://tests/ui_flow_test.gd"

func run() -> void:
	var logger := ErrorLog.new()
	OS.add_logger(logger)
	session = root.get_node("Session")
	session.save_path = "res://test-results/life-ui-save.json"
	for timer in session.get_children():
		if timer is Timer: timer.stop()
	var p: Dictionary = session.world.add_player(1, "生活驗證")
	p.silver = 1000
	session.world.rng.seed = 42
	session._publish()
	ui = load("res://scenes/main.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	await click(ui.nav_buttons[9])
	check(ui.tabs.current_tab == 9 and find_button("開始生活掛機").disabled, "Life has a labeled entry and explains the unlearned skill")
	await click_named("尋師 · ")
	await walk()
	check(ui.tabs.current_tab == 9, "Finding a teacher retains the life workflow")
	await click_named("學習釣魚")
	check(int(p.life_levels.get("life_fishing", 0)) == 1 and int(p.inventory.get("魚竿", 0)) == 1 and p.silver == 950, "Actual mouse lesson pays teacher and supplies tool")
	if find_button("開始生活掛機").disabled:
		await click_named("工作地點 · ")
		await walk()
	await click_named("開始生活掛機")
	check(p.life_work.active and int(p.life_work.limit) == 10, "Start button sends the selected batch to host")
	for i in 10:
		session._tick()
		await process_frame
		await process_frame
	check(int(p.life_work.done) == 2 and p.energy == 90, "Two actual timed cycles update UI and consume energy")
	check(ui.life_timer.text == "5 息後嘗試", "Live countdown updates without rebuilding controls every second")
	await click_named("停止生活掛機")
	check(not p.life_work.active, "Dedicated life stop button halts automation")
	await click_named("樵夫\n")
	await click_named("尋師 · ")
	await walk()
	await click_named("學習樵夫")
	if find_button("開始生活掛機").disabled:
		await click_named("工作地點 · ")
		await walk()
	await click_named("開始生活掛機")
	for i in 30:
		session._tick()
		await process_frame
		await process_frame
	await click_named("停止生活掛機")
	check(int(p.inventory.get("木材", 0)) > 0, "Mouse-started woodcutting puts real materials in inventory")
	# A trained crafter fixture exercises the recipe UI and real market, not a reward stub.
	p.life_levels.life_smithing = 20
	p.life_prof.life_smithing = 800
	p.inventory["打鐵鎚"] = 1
	p.inventory["鐵礦石"] = 30
	p.energy = 100
	session._publish()
	await process_frame
	await process_frame
	await click_named("打鐵\n")
	await click_named("工作地點 · ")
	await walk()
	ui.life_count = 10
	await click_named("開始生活掛機")
	for i in 80:
		session._tick()
		await process_frame
		await process_frame
	check(int(p.inventory.get("鐵塊", 0)) > 0 and not p.life_work.active, "Crafting actual recipe produces bars and stops at the selected limit")
	await click_named("出售成品")
	check(ui.tabs.current_tab == 7 and ui.shop_mode == 1 and ui.shop_item == "鐵塊", "Craft output opens its exact sale in the shop")
	if not Market.has_shop(p.place):
		await click_named(Market.shops_near(p.place)[0].place + " ·")
		await walk()
		ui.open_market(true, "鐵塊")
		await process_frame
		await process_frame
	var before := int(p.inventory["鐵塊"])
	var silver := int(p.silver)
	await click_named("出售 1 件")
	check(int(p.inventory["鐵塊"]) == before - 1 and int(p.silver) > silver, "Real crafted product can be sold through the mouse UI")
	OS.remove_logger(logger)
	check(logger.errors.is_empty(), "No runtime errors through life UI: " + str(logger.errors))
	var output := FileAccess.open("res://test-results/life-ui-result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	print("LIFE UI: ", checks, " checks, ", failures.size(), " failures")
	ui.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
