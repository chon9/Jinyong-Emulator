extends SceneTree
var ui
var checks := 0
var failures := []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func arrive() -> void:
	var deadline := Time.get_ticks_msec()+20000
	while ui.navigating and Time.get_ticks_msec()<deadline: await process_frame
	check(not ui.navigating,"Activity navigation reaches its NPC")

func click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await process_frame

func _init() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440,900)
	root.get_node("Session").chapter_data = {}
	ui = load("res://scenes/journey.tscn").instantiate()
	root.add_child(ui)
	while not ui.boot_ready: await process_frame
	ui.campaign.state.stage = 7
	ui.campaign.state.sect = "華山"
	for id in ["sword","healer","staff"]: ui.campaign.recruit(id)
	ui.set_page("每日")
	await process_frame
	await click(Vector2(590,675))
	await arrive()
	check(ui.campaign.state.place == "蘆葦蕩","Daily gathering card routes into the walkable town")
	await click(Vector2(1240,566))
	check(ui.campaign.state.inventory["草藥"] == 1 and ui.campaign.state.daily.counts.gather == 1,"Arrival action actually gathers herbs and records today's progress")
	ui.set_page("每日")
	await process_frame
	await click(Vector2(1280,290))
	await arrive()
	var silver: int = ui.campaign.state.silver
	await click(Vector2(1240,566))
	check(ui.job_clock > 0 and ui.campaign.state.silver == silver,"Starting a medicine job does not grant instant rewards")
	ui._process(6.1)
	check(ui.campaign.state.silver == silver+30 and ui.campaign.state.inventory["草藥"] == 0 and ui.campaign.state.daily.counts.work == 1,"Finished job consumes the real ingredient and pays its displayed reward")
	ui.set_page("每日")
	await process_frame
	await click(Vector2(590,290))
	await arrive()
	await click(Vector2(1240,566))
	check(ui.campaign.state.daily.errand == "青溪客棧","Master gives a concrete delivery destination")
	await click(Vector2(1240,566))
	await arrive()
	await click(Vector2(1240,566))
	check(ui.campaign.state.daily.counts.sect == 1 and ui.campaign.state.flags.contribution == 10,"Delivery completes only at the recipient and grants sect contribution")
	ui.set_page("每日")
	await process_frame
	await click(Vector2(590,480))
	check(ui.campaign.state.daily.escort == 1,"Escort quest begins with an actual shipment")
	await click(Vector2(1240,566))
	await arrive()
	await click(Vector2(1240,566))
	check(ui.campaign.state.daily.escort == 2,"Escort requires checking the goods at the intermediate destination")
	await click(Vector2(1240,566))
	await arrive()
	await click(Vector2(1240,566))
	check(ui.battle != null and ui.battle.encounter == "escort","Final delivery triggers the actual bandit encounter")
	for i in 40:
		if ui.battle.result != "": break
		ui.battle.auto_orders()
		if ui.battle.queue.is_empty(): ui.battle.begin_round()
		while not ui.battle.queue.is_empty() and ui.battle.result == "": ui.battle.next_action()
	ui.finish_battle()
	check(ui.battle.result == "victory" and ui.campaign.state.daily.counts.escort == 1 and ui.campaign.state.daily.escort == 0,"Escort payout requires victory, records one run, and clears the shipment")
	print("ACTIVITIES UI TEST: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
