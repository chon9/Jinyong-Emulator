extends SceneTree
var ui
var checks := 0
var failures: Array = []
var screenshots := false

func _init() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); push_error(text)

func click(at: Vector2) -> void:
	var input := InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.position = at
	input.pressed = true
	root.push_input(input)
	await process_frame
	input = input.duplicate()
	input.pressed = false
	root.push_input(input)
	await process_frame

func shot(name: String) -> void:
	if not screenshots: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/journey-"+name+".png")

func wait_navigation() -> void:
	var deadline := Time.get_ticks_msec()+60000
	while ui.navigating and Time.get_ticks_msec()<deadline: await process_frame
	await process_frame

func run() -> void:
	screenshots = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1440,900)
	root.get_node("Session").chapter_data = {}
	ui=load("res://scenes/journey.tscn").instantiate()
	root.add_child(ui)
	while not ui.boot_ready: await process_frame
	await process_frame
	await shot("world")
	if not ui.dialogue_open: ui.dialogue_open=true; ui.render(); await process_frame
	await click(Vector2(500,756))
	check(ui.campaign.state.stage==1,"Visible dialogue button accepts the main story and recruits the swordsman")
	await click(Vector2(170,305))
	await wait_navigation()
	check(ui.campaign.state.place=="渡口","Pinned next-step button routes to the quest NPC")
	if not ui.dialogue_open: ui.dialogue_open=true; ui.render(); await process_frame
	await click(Vector2(500,756))
	check(ui.battle!=null and ui.battle.living(0).size()==2,"Visible NPC action starts the new party battle")
	await shot("battle")
	await click(Vector2(580,805))
	check(ui.battle.orders.get("sword",{}).get("action")=="skill","Character skill slot queues the actual skill")
	await click(Vector2(1300,40))
	check(not ui.battle.queue.is_empty(),"Round button starts the speed-ordered action queue")
	ui.auto_battle=true
	# Fast-forward model resolution while preserving the production victory/reward path.
	for i in 18:
		if ui.battle.result!="": break
		if ui.battle.queue.is_empty(): ui.battle.auto_orders(); ui.battle.begin_round()
		while not ui.battle.queue.is_empty() and ui.battle.result=="": ui.battle.next_action()
	ui.finish_battle()
	check(ui.campaign.state.stage==2,"Battle victory unlocks the medicine clue in the same campaign")
	ui.leave_battle()
	await process_frame
	ui.campaign.state.place="藥廬"
	ui.render()
	await process_frame
	if not ui.dialogue_open: ui.dialogue_open=true; ui.render(); await process_frame
	await click(Vector2(500,756))
	check("healer" in ui.campaign.state.party,"Healer joins through dialogue UI")
	ui.campaign.state.stage=4
	ui.campaign.state.place="古寺"
	ui.render()
	await process_frame
	if not ui.dialogue_open: ui.dialogue_open=true; ui.render(); await process_frame
	await click(Vector2(500,756))
	check(ui.campaign.state.party.size()==4,"Full party is assembled through the fourth character conversation")
	await click(Vector2(975,840))
	check(ui.page=="同伴","Bottom navigation opens companions directly")
	await shot("party")
	var front: bool = ui.campaign.state.formation.hero.front
	await click(Vector2(140,734))
	check(ui.campaign.state.formation.hero.front!=front,"Formation button changes the actual front/rear combat rank")
	await click(Vector2(1135,840))
	# Use the page label rather than relying on the preceding tab coordinate.
	ui.set_page("行囊")
	await process_frame
	await click(Vector2(220,712))
	await wait_navigation()
	check(ui.campaign.state.place=="市集","Inventory offers direct travel to a working merchant")
	ui.set_page("行囊")
	await process_frame
	var silver: int = ui.campaign.state.silver
	await click(Vector2(1040,313))
	check(ui.campaign.state.silver==silver-20,"Shop purchase works from the visible UI")
	await click(Vector2(1250,313))
	check(ui.campaign.state.silver==silver-10,"Shop sale works from the visible UI")
	ui.campaign.state.place="演武坪"
	ui.campaign.choose("sect_華山")
	ui.set_page("武學")
	await process_frame
	var level: int = ui.campaign.state.levels.hero
	await click(Vector2(640,720))
	check(ui.campaign.state.levels.hero==level+1,"Spend-point training works at the master")
	await click(Vector2(945,720))
	check(ui.campaign.state.study=="hero","Self-study can be started from the martial arts page")
	await create_timer(5.2).timeout
	check(ui.campaign.state.levels.hero==level+2,"Self-study completes a timed training cycle and changes progression")
	ui.campaign.state.study=""
	ui.hero_id="staff"
	ui.render()
	await process_frame
	await shot("martial")
	ui.campaign.position_hero("hero",1,true)
	ui.start_battle("warehouse")
	await process_frame
	await shot("boss")
	if screenshots:
		ui.stage.show_event({"actor":"hero","target":"boss","kind":"attack","amount":64})
		await shot("facing-ally-attack")
		ui.stage.show_event({"actor":"boss","target":"hero","kind":"attack","amount":42})
		await shot("facing-enemy-attack")
		ui.stage.animation = 0
		await process_frame
	await click(ui.stage.position+ui.stage.actor_pos(ui.battle.by_id("boss"))-Vector2(0,85))
	check(ui.selected_enemy=="boss","Enemy sprite remains selectable at its visible position after facing correction")
	await click(ui.stage.position+ui.stage.actor_pos(ui.battle.by_id("hero"))-Vector2(0,85))
	check(ui.selected_ally=="hero","Mirrored ally remains selectable at its visible position")
	ui.persist()
	var session=root.get_node("Session")
	check(session.chapter_data.party.size()==4 and session.chapter_data.stage==5,"Campaign progress is included in normal session saves")
	var saved=JSON.parse_string(FileAccess.get_file_as_string(session.save_path))
	check(saved.has("character") and saved.has("chapter") and saved.chapter.party.size()==4,"Old character and new party coexist in the save file")
	check(session.import_save_text(JSON.stringify(saved)),"Normal browser-compatible import accepts the full campaign save")
	check(ui.battle==null and ui.campaign.state.party.size()==4,"Import exits transient combat while preserving the campaign")
	print("JOURNEY UI TEST: %d checks, %d failures" % [checks,failures.size()])
	ui.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
