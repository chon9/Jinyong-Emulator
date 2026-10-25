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
	await press("邀請同行")
	check("jy24" in ui.campaign.state.roster and ui.campaign.state.stage==0,"Companion invitation has no chapter gate")
	await press("委託與故事")
	check(ui.page=="江湖誌" and ui.quest_selection=="friend_jy24","Conversation opens this person's actual optional story")
	await press("接下委託")
	check(Open.ensure(ui.campaign).quests.friend_jy24.status=="active","Accept button creates real quest progress")
	await press("交談辦理")
	await press("處理委託")
	check(Open.ensure(ui.campaign).quests.friend_jy24.step==1,"Dialogue action advances the quest")
	ui.enter_scene("牛家村","牛家客棧")
	await press("交談 · 黃蓉")
	await press("邀請同行")
	check("jy02" in ui.campaign.state.party,"Second visited hero can join the active party")
	ui.set_page("行囊")
	var silver: int=ui.campaign.state.silver
	await press("購買 ·")
	check(ui.campaign.state.silver==silver-20,"Buying works at the local village inn")
	await press("出售 ·")
	check(ui.campaign.state.silver==silver-10,"Selling updates actual inventory and money")
	ui.enter_scene("嘉興鎮","演武坪")
	ui.set_page("武學")
	await press("拜入華山")
	check(ui.campaign.state.sect=="華山","Visible master action joins a sect")
	var level: int=ui.campaign.state.levels.hero
	await press("消點進修")
	check(ui.campaign.state.levels.hero==level+1,"Spend-point training changes combat progression")
	await press("自修 ·")
	ui._process(5.1)
	check(ui.campaign.state.levels.hero==level+2,"Self-study completes only after its timed cycle")
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
	check("jy02" in ui.campaign.state.roster,"Cancel preserves recruited companions")
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
