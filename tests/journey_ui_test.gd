extends SceneTree
const Open=preload("res://scripts/journey/open_world.gd")
const Content=preload("res://scripts/journey/open_content.gd")
var ui
var checks:=0
var failures:=[]

func _init() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func press(text: String) -> void:
	await process_frame
	for node in ui.layer.get_children():
		if node is Button and not node.disabled and (node.text==text or node.tooltip_text==text or node.text.begins_with(text)):
			node.pressed.emit()
			await process_frame
			return
	check(false,"Visible enabled action exists: "+text)

func read_lines() -> void:
	for i in 12:
		var next:=false
		for node in ui.layer.get_children():
			if node is Button and node.text=="下一句 →":next=true
		if not next:return
		var before: String=ui.shown_dialogue_text
		await press("下一句 →")
		check(ui.shown_dialogue_text!=before,"Next line advances to new dialogue instead of repeating the premise")

func run() -> void:
	root.size=Vector2i(1440,900)
	var session=root.get_node("Session")
	check(session.save_path.contains("test-results"),"UI reset test is isolated from real saves")
	session.chapter_data={}
	ui=load("res://scenes/journey.tscn").instantiate()
	root.add_child(ui)
	while not ui.boot_ready:await process_frame
	check(Open.current_region(ui.campaign)=="牛家村" and ui.battle==null,"New game starts in a peaceful open-world village")
	await press("交談 · 穆念慈")
	check(ui.dialogue_open and ui.selected_npc=="jy24","Scene portrait opens the correct person's dialogue")
	await read_lines()
	await press("結交條件")
	await read_lines()
	check(not "jy24" in ui.campaign.state.roster and "擂臺之外" in ui.shown_dialogue_text,"Recruitment explains the required personal story")
	await press("回到交談");await read_lines()
	await press("談談 · 穆念慈")
	check(Open.ensure(ui.campaign).quests.friend_jy24.step==1,"Agreeing to help records the opening conversation once")
	for i in 12:
		if Open.ensure(ui.campaign).quests.friend_jy24.status=="done":break
		var step: Dictionary=Content.QUESTS.friend_jy24.steps[int(Open.ensure(ui.campaign).quests.friend_jy24.step)]
		ui.enter_scene(step.region,step.scene);ui.open_quest_dialogue("friend_jy24")
		await read_lines()
		await press(step.options[0] if step.kind=="choice" else step.action)
		if step.kind=="battle":
			check(ui.battle!=null,"Story confrontation enters actual combat")
			for turn in 50:
				if ui.battle.result!="":break
				ui.battle.auto_orders();ui.battle.begin_round()
				while not ui.battle.queue.is_empty() and ui.battle.result=="":ui.battle.next_action()
			check(ui.battle.result=="victory","First companion's story is winnable by a fresh protagonist")
			ui.finish_battle();ui.leave_battle()
	check(Open.ensure(ui.campaign).quests.friend_jy24.status=="done","Full personal story reaches its explicit ending")
	await press("邀請同行")
	check("jy24" in ui.campaign.state.roster and ui.campaign.state.stage==0,"Earned recruitment works without a global main chapter")
	ui.enter_scene("牛家村","村口");ui.open_person("jy24")
	check(ui.shown_dialogue_text==Content.QUESTS.friend_jy24.aftermath.jy24[0].text,"Revisiting a recruited hero opens an authored post-quest conversation")
	await read_lines();await press("聊聊別的")
	check(ui.shown_dialogue_text==Content.PEOPLE.jy24.idle_pages[0].text,"Casual conversation cannot fall back to the old recruitment opening")
	await read_lines();await press("聊聊近況")
	check(ui.shown_dialogue_text==Content.QUESTS.friend_jy24.aftermath.jy24[0].text,"Returning to recent news retains the completed state")
	ui.dialogue_open=false;ui.render()
	check(ui.layer.has_node("JourneyStatus") and ui.layer.has_node("JourneyNotice"),"Resources and event messages have separate opaque panels")
	check(ui.layer.get_node("JourneyStatus").get_rect().end.y<=900 and ui.layer.get_node("JourneyNotice").get_rect().end.y<801,"World status and messages stay above the viewport boundary and companion dock")
	ui.campaign.state.open_world.quests.friend_jy01={"status":"done","step":Content.QUESTS.friend_jy01.steps.size(),"choices":[0],"edition":3}
	ui.campaign.state.open_world.finished.append("friend_jy01")
	ui.enter_scene("襄陽城","城門");ui.open_person("jy01");await read_lines()
	await press("談談 · 死守襄陽")
	check(not ui.campaign.state.open_world.quests.has("flash_17") and ui.shown_dialogue_text==Content.QUESTS.flash_17.steps[0].pages[0].text,"Another quest is explained before acceptance when an NPC is already discussing a finished event")
	await read_lines();await press("先不接這件事")
	check(not ui.campaign.state.open_world.quests.has("flash_17"),"Reading another request does not automatically accept it")
	ui.enter_scene("牛家村","牛家客棧")
	await press("交談 · 黃蓉")
	await read_lines();await press("結交條件");await read_lines()
	check(not "jy02" in ui.campaign.state.party and "鹽碟疑雲" in ui.shown_dialogue_text,"Huang Rong also requires her own story, not another person's clear")
	ui.set_page("行囊")
	var silver: int=ui.campaign.state.silver
	await press("購買 ·")
	check(ui.campaign.state.silver==silver-20,"Buying works at the local village inn")
	await press("出售 ·")
	check(ui.campaign.state.silver==silver-10,"Selling updates actual inventory and money")
	ui.enter_scene("嘉興鎮","演武坪")
	ui.set_page("武學")
	await press("前往師父")
	check(Open.current_region(ui.campaign)=="嘉興鎮" and Open.current_scene(ui.campaign)=="演武坪" and ui.page=="武學","Unjoined characters reach the introductory teacher with learning controls ready")
	await press("拜入華山")
	check(ui.campaign.state.sect=="華山","Visible master action joins a sect")
	await press("前往師父")
	check(Open.current_region(ui.campaign)=="華山派" and Open.current_scene(ui.campaign)=="正氣堂" and ui.page=="武學","Joining Huashan changes the teacher shortcut to the sect, keeping learning open")
	var level: int=ui.campaign.state.levels.hero
	await press("消點進修")
	check(ui.campaign.state.levels.hero==level+1,"Spend-point training changes combat progression")
	await press("自修 ·")
	ui._process(5.1)
	check(ui.campaign.state.levels.hero==level+2,"Self-study completes only after its timed cycle")
	ui.campaign.state.potential=1000
	for teacher in [["華山","華山派","正氣堂"],["武當","武當派","演武場"],["少林","少林派","羅漢堂"],["全真","全真教","重陽宮"],["古墓","全真教","古墓"]]:
		ui.enter_scene("嘉興鎮","演武坪")
		ui.campaign.state.sect="未入門"
		ui.set_page("武學")
		await press("拜入"+teacher[0])
		ui.enter_scene("牛家村","村口")
		ui.set_page("武學")
		await press("前往師父")
		check(ui.campaign.state.sect==teacher[0] and Open.current_region(ui.campaign)==teacher[1] and Open.current_scene(ui.campaign)==teacher[2],"Teacher shortcut reaches the current sect from a distant village: "+teacher[0])
		check(ui.page=="武學" and ui.current_training_place() and ui.campaign.training_place(),"Displayed and actual learning access agree at the destination: "+teacher[0])
		level=ui.campaign.state.levels.hero
		var points: int=ui.campaign.state.potential
		await press("消點進修")
		check(ui.campaign.state.levels.hero==level+1 and ui.campaign.state.potential==points-(12+level*3),"Arriving at the sect teacher permits real spend-point training: "+teacher[0])
		ui.enter_scene("嘉興鎮","藥廬")
		ui.campaign.state.place="演武坪"
		level=ui.campaign.state.levels.hero
		ui.campaign.train("hero")
		check(not ui.current_training_place() and ui.campaign.state.levels.hero==level,"A stale legacy stop cannot enable training after leaving the teacher: "+teacher[0])
	ui.enter_scene("龍門","關隘")
	check(ui.campaign.state.study=="" and ui.battle==null,"Distant scene entry stops study and never starts combat automatically")
	ui.enter_scene(Content.ENEMIES.enemy_001.region,Content.ENEMIES.enemy_001.scene)
	ui.foe_filter="全部";ui.foe_selection="enemy_001";ui.set_page("挑戰")
	await press("接受挑戰")
	check(ui.battle!=null and ui.battle.living(1)[0].sprite=="enemy_001","Challenge UI starts the selected independently illustrated opponent")
	ui.battle=null;ui.stage.battle=null;ui.set_page("設定")
	await press("刪除存檔／重新開始")
	var confirmation=ui.get_children().filter(func(n):return n is ConfirmationDialog)[0]
	check(confirmation.visible and confirmation.get_cancel_button().has_focus(),"Deleting progress opens a confirmation focused on keeping the save")
	confirmation.canceled.emit()
	await process_frame
	check("jy24" in ui.campaign.state.roster,"Cancel preserves earned companions")
	ui.persist()
	DirAccess.copy_absolute(session.save_path,session.save_path+".bak")
	await press("刪除存檔／重新開始")
	confirmation=ui.get_children().filter(func(n):return n is ConfirmationDialog)[0]
	confirmation.confirmed.emit()
	await process_frame
	check(ui.campaign.state.roster==["hero"] and ui.campaign.state.open_world.quests.is_empty(),"Confirmed reset clears recruits and all optional quests")
	check(Open.current_region(ui.campaign)=="牛家村","Reset starts a fresh village exploration")
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(session.save_path))
	check(saved.chapter.roster==["hero"] and saved.chapter.open_world.quests.is_empty(),"Fresh progress replaces the disk save")
	if FileAccess.file_exists(session.save_path+".bak"):
		var backup: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(session.save_path+".bak"))
		check(backup.chapter.roster==["hero"],"Backup cannot resurrect deleted companions")
	print("OPEN WORLD UI TEST: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
