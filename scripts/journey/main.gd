extends Control
## Character-first Godot campaign UI, shared by desktop and the browser export.
const Chapter = preload("res://scripts/journey/chapter.gd")
const Battle = preload("res://scripts/journey/battle.gd")
const Stage = preload("res://scripts/journey/stage.gd")
const Bank = preload("res://scripts/journey/resources.gd")
const GameSkin = preload("res://scripts/journey/game_skin.gd")
const Sounds = preload("res://scripts/journey/sfx.gd")
const Atlas = preload("res://scripts/journey/atlas.gd")
const Daily = preload("res://scripts/journey/daily.gd")
const Open=preload("res://scripts/journey/open_world.gd")
const OW=preload("res://scripts/journey/open_content.gd")
const INK := Color("30251c")
const PAPER := Color("f0dfb5")
const GOLD := Color("dab66c")
const MUTED := Color("bda787")
var campaign
var battle
var stage
var layer: Control
var page := "江湖"
var hero_id := "hero"
var roster_page := 0
var scene_open:=true
var selected_npc:=""
var npc_page:=0
var dialogue_topic:=false
var quest_dialogue:=""
var dialogue_cursor:=0
var dialogue_override: Array=[]
var dialogue_followup:=""
var shown_dialogue_text:=""
var quest_filter:="當地"
var quest_page:=0
var quest_selection:=""
var foe_filter:="全部"
var foe_page:=0
var foe_selection:="enemy_001"
var inventory_selection := "金創藥"
var swap_out := "sword"
var selected_enemy := ""
var selected_ally := "hero"
var notice := "江湖沒有指定的第一章。選一處地方，認識願意同行的人。"
var auto_battle := false
var action_clock := 0.0
var study_clock := 0.0
var result_applied := false
var reward_summary := "30 銀 · 25 學點"
var dialogue_open := false
var game_skin
var font: Font
var navigating := false
var boot_ready := false
var boot_progress := 0
var bank
var sounds
var world_selection := "嘉興鎮"
var daily_focus := ""
var job_clock := 0.0
var job_day := 0
var job_seconds := 0

func _ready() -> void:
	font = load("res://assets/fonts/LXGWWenKaiTC-Regular.ttf")
	var theme_value := Theme.new()
	theme_value.default_font = font
	theme_value.default_font_size = 19
	theme = theme_value
	campaign = Chapter.new(Session.chapter_data)
	if Session.story_migration_notice!="":notice=Session.story_migration_notice
	Atlas.ensure(campaign)
	Daily.ensure(campaign)
	Open.ensure(campaign)
	if Session.chapter_data.is_empty():
		Atlas.ensure(campaign).region="牛家村"
	Open.enter(campaign,Atlas.ensure(campaign).region,Open.current_scene(campaign))
	bank = Bank.new()
	add_child(bank)
	sounds = Sounds.new()
	sounds.bank = bank
	add_child(sounds)
	stage = Stage.new()
	stage.bank = bank
	stage.sounds = sounds
	stage.clip_contents = true
	stage.campaign = campaign
	add_child(stage)
	stage.place_selected.connect(travel)
	stage.unit_selected.connect(select_unit)
	stage.arrived.connect(_arrived)
	stage.walking.connect(func(): navigating=false; dialogue_open=false; scene_open=false; campaign.state.study=""; notice="沿街探索；點人物可走近交談。"; render())
	Session.chapter_imported.connect(_imported)
	get_tree().root.focus_exited.connect(persist)
	bank.progress.connect(func(done,total):
		boot_progress = int(100.0*done/maxi(1,total))
		if OS.has_feature("web"): JavaScriptBridge.eval("window.youxiaSetPreloadProgress?.("+str(boot_progress)+");",true)
		render())
	render()
	await bank.prepare()
	game_skin = GameSkin.new(bank)
	for key in Bgm.TRACKS:
		Bgm.stream_for(key)
		await get_tree().process_frame
	boot_ready = true
	stage.prepared = true
	if OS.has_feature("web"): JavaScriptBridge.eval("window.youxiaSceneReady = true;",true)
	render()
	persist()

func _exit_tree() -> void:
	persist()
	if is_instance_valid(Bgm): Bgm.set_scene_context("")

func _imported() -> void:
	campaign = Chapter.new(Session.chapter_data)
	stage.campaign = campaign
	stage.cancel_walk()
	navigating = false
	job_clock = 0
	daily_focus = ""
	Atlas.ensure(campaign)
	Daily.ensure(campaign)
	battle = null
	stage.battle = null
	Open.ensure(campaign)
	if Session.chapter_data.is_empty():
		Atlas.ensure(campaign).region="牛家村"
	Open.enter(campaign,Atlas.ensure(campaign).region,Open.current_scene(campaign))
	scene_open=true
	selected_npc=""
	dialogue_open=false
	page = "江湖"
	notice = "已載入江湖進度。未完成的戰鬥與自修已停止。"
	if Session.story_migration_notice!="":notice=Session.story_migration_notice
	render()
	persist()

func persist() -> void:
	if campaign == null: return
	Session.chapter_data = campaign.state.duplicate(true)
	Session.save_game()

func _process(delta: float) -> void:
	if campaign == null or not boot_ready: return
	var today := int(Daily.ensure(campaign).day)
	if job_clock > 0:
		job_clock -= delta
		if today != job_day or campaign.state.place != "藥廬" or battle != null:
			job_clock = 0
			notice = "已停下守爐，沒有扣除草藥。"
			render()
		elif job_clock <= 0:
			if int(campaign.state.inventory.get("草藥",0)) > 0 and Daily.complete(campaign,"work",30,15):
				campaign.state.inventory["草藥"] -= 1
				notice = "藥湯煮好了。獲得 30 銀、15 學點。"
				sounds.play("accept")
			persist()
			render()
		elif int(ceil(job_clock)) != job_seconds:
			job_seconds = int(ceil(job_clock))
			notice = "守著藥爐 · 還需 %d 秒；離開會停止。" % job_seconds
			render()
	if campaign.state.study != "" and battle == null:
		study_clock += delta
		if study_clock >= 5:
			study_clock = 0
			var id: String = campaign.state.study
			var before := int(campaign.state.levels[id])
			notice = campaign.train(id,true)
			if before == int(campaign.state.levels[id]): campaign.state.study = ""
			persist()
			render()
	if battle == null or battle.result != "": return
	action_clock -= delta
	if action_clock > 0: return
	if not battle.queue.is_empty():
		var event: Dictionary = battle.next_action()
		if not event.is_empty() and event.get("text","") != "": notice = event.text
		stage.show_event(event)
		action_clock = .85
		if battle.result != "": finish_battle()
		render()
	elif auto_battle:
		battle.auto_orders()
		battle.begin_round()
		action_clock = .5
		render()

func _unhandled_key_input(input: InputEvent) -> void:
	if not input is InputEventKey or not input.pressed or input.echo: return
	match input.keycode:
		KEY_ESCAPE:
			if battle != null and battle.result == "": auto_battle = false; notice = "將在這輪出招後停下，讓你重新佈置。"; render()
			else: dialogue_open=false; set_page("江湖")
		KEY_SPACE:
			if battle != null: play_round()
		KEY_C: set_page("同伴")
		KEY_K: set_page("武學")
		KEY_I: set_page("行囊")
		KEY_J: set_page("江湖誌")
		KEY_M: set_page("世界")
		KEY_D: set_page("每日")
		KEY_F5: persist(); notice = "進度已保存。"; render()
		KEY_F8: set_page("設定")
		KEY_F9: get_tree().change_scene_to_file("res://scenes/main.tscn")

func at(node: Control, rect: Rect2, parent: Node = null) -> Control:
	(parent if parent != null else layer).add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node

func style(bg: Color = INK, border: Color = Color("82633d"), width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(2)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func panel(rect: Rect2, color: Color = INK, parent: Node = null) -> Panel:
	var box := Panel.new()
	box.add_theme_stylebox_override("panel",style(color,Color("8b7046"),2 if rect.size.x>600 else 1))
	at(box,rect,parent)
	return box

func label(value: String, rect: Rect2, size_value: int = 20, color: Color = PAPER, parent: Node = null) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_color_override("font_color",color)
	node.add_theme_font_size_override("font_size",size_value)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.clip_text=true
	at(node,rect,parent)
	return node

func prose(value: String, rect: Rect2, font_size: int = 20, color: Color = PAPER, parent: Node = null) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.text = value
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.scroll_active=true
	node.add_theme_color_override("default_color",color)
	node.add_theme_font_size_override("normal_font_size",font_size)
	node.add_theme_constant_override("line_separation",5)
	at(node,rect,parent)
	return node

func button(value: String, rect: Rect2, callback: Callable, primary: bool = false, disabled: bool = false, parent: Node = null) -> Button:
	var b := Button.new()
	b.text = value
	b.clip_text=true
	b.add_theme_stylebox_override("normal",game_skin.box(5 if primary else 4,true) if game_skin != null else style(Color("7e5e32") if primary else Color("35271d")))
	b.add_theme_stylebox_override("hover",game_skin.box(5,true) if game_skin != null else style(Color("8c6939")))
	b.add_theme_stylebox_override("pressed",game_skin.box(6,true) if game_skin != null else style(Color("251b15")))
	b.add_theme_stylebox_override("disabled",game_skin.box(7,true) if game_skin != null else style(Color("352e26")))
	b.add_theme_stylebox_override("focus",style(Color(0,0,0,0),GOLD,2))
	b.add_theme_color_override("font_color",PAPER)
	b.add_theme_color_override("font_hover_color",Color.WHITE)
	b.add_theme_color_override("font_shadow_color",Color("21160e"))
	b.add_theme_constant_override("shadow_offset_y",1)
	b.add_theme_constant_override("shadow_offset_x",1)
	b.add_theme_color_override("font_disabled_color",Color("8f806a"))
	b.add_theme_font_size_override("font_size",18)
	b.disabled = disabled
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(callback)
	at(b,rect,parent)
	return b

func image_at(art: String, rect: Rect2, parent: Node = null) -> void:
	at(stage.portrait(art),rect,parent)

func bar(value: float, maximum: float, rect: Rect2, color: Color) -> void:
	var node := ProgressBar.new()
	node.max_value = maximum
	node.value = value
	node.show_percentage = false
	var background := style(Color("211a14"),Color("776343"))
	var fill := style(color,color,0)
	for box in [background,fill]:
		box.content_margin_top = 0
		box.content_margin_bottom = 0
		box.content_margin_left = 0
		box.content_margin_right = 0
	node.add_theme_stylebox_override("background",background)
	node.add_theme_stylebox_override("fill",fill)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(node,rect)

func render() -> void:
	if stage != null and battle == null: stage.sync_location()
	if layer != null:
		layer.hide()
		layer.queue_free()
	if not has_node("Backdrop"):
		var bg := ColorRect.new()
		bg.name = "Backdrop"
		bg.color = Color("15120f")
		bg.size = Vector2(1440,900)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		move_child(bg,0)
	stage.scene_context=Open.current_scene(campaign) if scene_open else ""
	stage.visible = boot_ready
	stage.position = Vector2.ZERO
	stage.size = Vector2(1440,900)
	layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = Vector2(1440,900)
	add_child(layer)
	if battle != null:
		render_battle()
	else:
		if page == "江湖": render_world()
		else:
			var shade := ColorRect.new()
			shade.color = Color(0,0,0,.68)
			at(shade,Rect2(0,0,1440,900))
			panel(Rect2(10,67,1420,731),Color("30241c"))
			if page in ["同伴","武學"]: render_party()
			elif page == "行囊": render_inventory()
			elif page == "江湖誌": render_journal()
			elif page == "設定": render_settings()
			elif page == "世界": render_atlas()
			elif page == "每日": render_daily()
			elif page == "挑戰": render_foes()
			button("返回江湖 ×",Rect2(1285,14,138,40),func(): dialogue_open=false; set_page("江湖"))
		render_dock()
		label(notice,Rect2(440,872,960,22),15,GOLD)
	if not boot_ready:
		var curtain := ColorRect.new()
		curtain.color = Color("191510")
		at(curtain,Rect2(0,0,1440,900))
		label("網 金 游 俠",Rect2(525,250,650,80),46,GOLD)
		label("人物、街巷與招式準備中",Rect2(470,365,800,50),25,PAPER)
		label("%d%%" % boot_progress,Rect2(665,450,250,40),25)
	update_browser_status()

func render_dock() -> void:
	var tabs := [["同伴","隊伍",-1],["武學","武功",9],["行囊","行囊",8],["江湖誌","記事",10],["世界","地圖",11],["設定","選單",-1]]
	for i in tabs.size():
		var x := 940+i*80
		var tab: String = tabs[i][0]
		var b := button("",Rect2(x,812,70,67),func(): set_page(tab),page==tab)
		b.tooltip_text = tabs[i][1]
		if int(tabs[i][2]) >= 0 and game_skin != null:
			var icon := TextureRect.new()
			icon.texture = game_skin.texture(int(tabs[i][2]))
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			at(icon,Rect2(x+13,819,44,40))
		elif tab == "同伴": image_at(Chapter.HEROES.hero.art,Rect2(x+16,817,40,45))
		else: label("☰",Rect2(x+22,820,40,34),26,GOLD)
		label(tabs[i][1],Rect2(x+17,860,60,25),16,GOLD)
	label("銀 %d　學點 %d　%s" % [campaign.state.silver,campaign.state.potential,campaign.state.sect],Rect2(510,820,420,30),18,PAPER)
	if page == "江湖":
		for i in campaign.state.party.size():
			var id: String = campaign.state.party[i]
			var x: int = 18+i*102
			var b := button("",Rect2(x,801,94,85),func(): hero_id=id; set_page("同伴"),false)
			b.tooltip_text = Chapter.HEROES[id].name
			image_at(Chapter.HEROES[id].art,Rect2(x+15,804,65,58))
			label(Chapter.HEROES[id].name,Rect2(x+9,861,90,24),15,PAPER)

func update_browser_status() -> void:
	if not OS.has_feature("web"): return
	var status := {"page":page,"place":campaign.state.place,"stage":int(campaign.state.stage),"party":campaign.state.party.size(),"battle":"" if battle == null else (battle.result if battle.result != "" else "active"),"round":0 if battle == null else battle.round_no,"notice":notice,"region":Atlas.ensure(campaign).region,"navigating":navigating,"daily":Daily.ensure(campaign).counts,"ready":boot_ready,"scene":Open.current_scene(campaign),"roster":campaign.state.roster,"quests":Open.ensure(campaign).quests,"dialogue":selected_npc if dialogue_open else ""}
	status.people=Open.people(campaign).map(func(id):return {"id":id,"name":OW.PEOPLE[id].name,"role":OW.PEOPLE[id].role,"art":OW.PEOPLE[id].art})
	status.dialogue_page=dialogue_cursor
	status.dialogue_text=shown_dialogue_text if dialogue_open else ""
	status.evidence=Open.ensure(campaign).evidence
	status.sounds=sounds.history.duplicate()
	status.sound_settings={"enabled":sounds.enabled,"volume":sounds.volume}
	status.event=stage.event if battle!=null else {}
	status.effects="" if battle==null or stage.event.is_empty() or battle.by_id(stage.event.get("actor","")).is_empty() else preload("res://scripts/journey/combat_style.gd").key_for(battle.by_id(stage.event.actor),stage.event)
	status.units=[] if battle==null else battle.units.map(func(u):return {"id":u.id,"name":u.name,"hp":u.hp,"states":preload("res://scripts/journey/combat_style.gd").states(u)})
	JavaScriptBridge.eval("window.youxiaChapterStatus = Object.freeze("+JSON.stringify(status)+");",true)
	var buttons := []
	collect_buttons(layer,buttons)
	JavaScriptBridge.eval("window.youxiaUI = Object.freeze("+JSON.stringify({"buttons":buttons})+");",true)
	var window := JavaScriptBridge.get_interface("window")
	if window.youxiaSetStatus != null: window.youxiaSetStatus("無名少俠",Open.current_region(campaign)+"／"+Open.current_scene(campaign),page,"自由江湖 · 單機")

func collect_buttons(node: Node, result: Array) -> void:
	if node is Button and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		result.append({"text":node.text if node.text != "" else node.tooltip_text,"disabled":node.disabled,"x":rect.position.x,"y":rect.position.y,"w":rect.size.x,"h":rect.size.y})
	for child in node.get_children(): collect_buttons(child,result)

func set_page(value: String) -> void:
	if battle != null or not boot_ready: return
	page = value
	render()

func render_world() -> void:
	var region: String=Open.current_region(campaign)
	var place: String=Open.current_scene(campaign)
	panel(Rect2(12,12,310,100))
	head_at(Chapter.HEROES.hero.art,Rect2(24,24,65,72))
	label("無名少俠",Rect2(104,29,200,30),24,GOLD)
	label("%s · 修為 %d 重"%[campaign.state.sect,campaign.state.levels.hero],Rect2(104,64,200,25),17)
	panel(Rect2(425,12,745,53),Color("30251ce6"))
	label(region+" · "+(place if scene_open else "青溪街巷"),Rect2(450,19,715,43),28,GOLD)
	button("音樂 "+("開" if Bgm.enabled else "關"),Rect2(1270,17,150,42),func():Bgm.set_enabled(not Bgm.enabled);render())
	var data: Dictionary=Open.ensure(campaign)
	panel(Rect2(17,133,290,194))
	label("行 旅 記",Rect2(35,151,250,30),23,GOLD)
	var tracked: String=data.tracked
	if tracked!="" and data.quests.has(tracked) and data.quests[tracked].status=="active":
		var quest: Dictionary=Open.definition(campaign,tracked)
		var step: Dictionary=quest.steps[int(data.quests[tracked].step)]
		label(quest.name,Rect2(35,190,255,29),18)
		prose(step.region+"／"+step.scene+"\n"+step.text,Rect2(35,225,255,70),17,MUTED)
	else:
		prose("沒有必須完成的主線。\n訪城、交友、修行，由你決定。",Rect2(35,198,250,79),18)
	button("江湖委託 [J]",Rect2(17,340,290,43),func():quest_filter="當地";set_page("江湖誌"))
	button("世界地圖 [M]",Rect2(17,390,290,43),func():set_page("世界"))
	button("人物尋訪",Rect2(17,440,290,43),func():hero_id="hero";set_page("同伴"))
	if scene_open:
		var names: Array=OW.REGIONS[region]
		var width: float=minf(175,1085.0/names.size())
		for i in names.size():
			var location: String=names[i]
			button(location,Rect2(330+i*width,85,width-6,40),func():enter_scene(region,location),location==place)
		var locals: Array=Open.people(campaign)
		npc_page=clampi(npc_page,0,maxi(0,(locals.size()-1)/4))
		var points: Array=[Vector2(425,219),Vector2(830,242),Vector2(610,401),Vector2(1110,383)]
		for i in 4:
			if npc_page*4+i>=locals.size():break
			var id: String=locals[npc_page*4+i]
			var npc: Dictionary=OW.PEOPLE[id]
			var p: Vector2=points[i]
			var b:=button("",Rect2(p,Vector2(107,116)),func():open_person(id))
			b.tooltip_text="交談 · "+npc.name
			head_at(npc.art,Rect2(p+Vector2(7,5),Vector2(93,105)))
			panel(Rect2(p+Vector2(-34,119),Vector2(195,61)),Color("30251cee"))
			label(npc.name,Rect2(p+Vector2(-34,121),Vector2(195,30)),20,GOLD)
			label(("尚待結交" if Open.recruit_reason(campaign,npc.hero)!="" else "可邀同行") if npc.has("hero") and not npc.hero in campaign.state.roster else npc.role,Rect2(p+Vector2(-27,153),Vector2(190,25)),16)
		if locals.size()>4:
			button("其他人物 →",Rect2(1110,530,280,42),func():npc_page=(npc_page+1)%int(ceil(locals.size()/4.0));render())
		button("附近挑戰",Rect2(1120,146,280,43),func():foe_filter=region;foe_page=0;set_page("挑戰"))
		button("當地委託 · %d"%Open.quests_here(campaign).size(),Rect2(1120,198,280,43),func():quest_filter="當地";quest_page=0;set_page("江湖誌"))
		var interactions: Array=Open.interactions_here(campaign)
		for i in mini(3,interactions.size()):
			var qid: String=interactions[i]
			var current: Dictionary=Open.definition(campaign,qid).steps[int(data.quests[qid].step)]
			var action_text: String=current.get("action",current.text)
			var action_button:=button(action_text.left(15),Rect2(1120,251+i*52,280,45),func():open_quest_dialogue(qid),true)
			action_button.tooltip_text=action_text
			if i==0 and current.kind=="search":
				label("現場留下的東西 · 點擊察看",Rect2(559,611,390,30),19,GOLD)
				button("察看 · "+current.item,Rect2(556,646,420,49),func():open_quest_dialogue(qid),true)
		button("返回街巷" if region=="嘉興鎮" else "離開此處 · 世界地圖",Rect2(17,490,290,43),func():
			if region=="嘉興鎮":scene_open=false;dialogue_open=false;render()
			else:set_page("世界"))
	else:
		button("選擇街巷入口",Rect2(1120,250,280,43),func():set_page("世界"))
	label("探索 %d / 100 處　·　相識 %d / 41 位俠客　·　自由行旅"%[data.discoveries.size(),campaign.state.roster.filter(func(id):return OW.HEROES.has(id)).size()],Rect2(340,764,1070,28),17,PAPER)
	if daily_focus!="":button(daily_caption(daily_focus),Rect2(1050,701,350,43),func():daily_action(daily_focus),true,navigating or job_clock>0)
	if navigating:label("沿街尋路中…",Rect2(610,695,400,35),21,GOLD)
	if dialogue_open and selected_npc!="":render_dialogue()

func quest_action() -> void:
	set_page("江湖誌")

func render_dialogue() -> void:
	if not OW.PEOPLE.has(selected_npc):return
	# A dialogue is a modal game interaction. Background scene actions must not
	# intercept a same-named "search" or "fight" confirmation in this panel.
	for child in layer.get_children():
		if child is BaseButton:child.disabled=true
	var shade:=ColorRect.new()
	shade.color=Color(0,0,0,.28)
	shade.mouse_filter=Control.MOUSE_FILTER_STOP
	at(shade,Rect2(0,0,1440,900))
	var npc: Dictionary=OW.PEOPLE[selected_npc]
	var quest_ready: bool=quest_dialogue!="" and Open.step_here(campaign,quest_dialogue,selected_npc)
	var lines: Array=Open.step_pages(campaign,quest_dialogue) if quest_ready else Open.conversation(campaign,selected_npc,dialogue_topic)
	if not dialogue_override.is_empty():lines=dialogue_override
	dialogue_cursor=clampi(dialogue_cursor,0,lines.size()-1)
	var line: Dictionary=lines[dialogue_cursor]
	var speaker: Dictionary=OW.PEOPLE.get(line.get("speaker",""),Chapter.HEROES.hero if line.get("speaker","")=="hero" else {"name":"江湖見聞","art":npc.art})
	panel(Rect2(81,536,1278,277),Color("e4d3ab"))
	if line.get("speaker","")!="":image_at(speaker.art,Rect2(90,487,246,315))
	else:
		label(line.get("caption","眼 前 景 象"),Rect2(105,583,225,36),24,INK)
		var clue_name: String=Open.definition(campaign,quest_dialogue).steps[int(Open.ensure(campaign).quests[quest_dialogue].step)].get("item","留意人物的話與眼前的動靜。") if quest_ready else ""
		prose(clue_name,Rect2(107,637,218,107),22,INK)
	label(speaker.name,Rect2(354,553,780,33),25,INK)
	label("%d / %d"%[dialogue_cursor+1,lines.size()],Rect2(1165,555,125,29),18,INK)
	shown_dialogue_text=line.text
	prose(line.text,Rect2(354,599,943,109),21,INK)
	button("×",Rect2(1303,550,39,36),func():dialogue_open=false;render())
	var choices:=[]
	if dialogue_cursor<lines.size()-1:
		choices.append(["下一句 →",func():dialogue_cursor+=1;render()])
	elif not dialogue_override.is_empty():
		if dialogue_followup!="" and Open.ensure(campaign).quests.get(dialogue_followup,{}).get("status","")=="active":
			choices.append(["前往下一步",func():
				var next: Dictionary=Open.definition(campaign,dialogue_followup).steps[int(Open.ensure(campaign).quests[dialogue_followup].step)]
				enter_scene(next.region,next.scene);open_quest_dialogue(dialogue_followup)])
		elif npc.has("hero") and not npc.hero in campaign.state.roster and Open.recruit_reason(campaign,npc.hero)=="":
			choices.append(["邀請同行",func():notice=Open.invite(campaign,npc.hero);persist();dialogue_override=[{"speaker":selected_npc,"text":notice}];dialogue_followup="";render()])
		choices.append(["回到交談",func():dialogue_override=[];dialogue_cursor=0;render()])
	elif quest_ready:
		var step: Dictionary=Open.definition(campaign,quest_dialogue).steps[int(Open.ensure(campaign).quests[quest_dialogue].step)]
		if step.kind=="choice":
			for i in step.options.size():choices.append([step.options[i],func():quest_progress(quest_dialogue,i)])
		else:choices.append([step.get("action","繼續這件事"),func():quest_progress(quest_dialogue)])
	else:
		if npc.has("hero"):
			var reason: String=Open.recruit_reason(campaign,npc.hero)
			choices.append(["已是同行好友" if npc.hero in campaign.state.roster else ("邀請同行" if reason=="" else "結交條件"),func():
				if Open.recruit_reason(campaign,npc.hero)!="":
					var cleared: bool=Open.ensure(campaign).quests.get(npc.story,{}).get("status","")=="done"
					var spoken: Array=npc.pages.filter(func(entry):return entry.speaker==selected_npc)
					var request: String=npc.reply if cleared or spoken.is_empty() else spoken[0].text
					dialogue_override=[{"speaker":selected_npc,"text":request},{"speaker":"","caption":"同行條件","text":Open.recruit_reason(campaign,npc.hero)}];dialogue_cursor=0
				else:notice=Open.invite(campaign,selected_npc);sounds.play("accept");persist();dialogue_override=[{"speaker":selected_npc,"text":notice}];dialogue_cursor=0
				render()])
		var topic: String=npc.get("story","")
		if OW.QUESTS.has(topic):choices.append(["談談 · "+Open.definition(campaign,topic).name,func():
			var q: Dictionary=Open.definition(campaign,topic)
			if q.giver==selected_npc and Open.current_region(campaign)==q.region and Open.current_scene(campaign)==q.scene:
				if not Open.ensure(campaign).quests.has(topic):notice=Open.accept(campaign,topic,selected_npc);quest_progress(topic)
				elif Open.step_here(campaign,topic,selected_npc):open_quest_dialogue(topic)
				else:quest_selection=topic;quest_filter="全部";set_page("江湖誌")
			else:enter_scene(q.region,q.scene);open_person(q.giver)])
		if npc.has("alternate_pages") or (OW.QUESTS.has(topic) and Open.definition(campaign,topic).giver==selected_npc):
			choices.append(["回到正事" if dialogue_topic else "聊聊別的",func():dialogue_topic=not dialogue_topic;dialogue_cursor=0;render()])
		if Open.is_market(campaign):choices.append(["買賣物品",func():set_page("行囊")])
		elif current_training_place():choices.append(["拜師與學武",func():set_page("武學")])
	var width: float=930.0/maxi(1,choices.size())-8
	for i in choices.size():button(choices[i][0],Rect2(354+i*(width+8),726,width,46),choices[i][1],i==0)

func open_quest_dialogue(id: String) -> void:
	if not Open.step_here(campaign,id):return
	var step: Dictionary=Open.definition(campaign,id).steps[int(Open.ensure(campaign).quests[id].step)]
	selected_npc=step.get("npc",Open.definition(campaign,id).giver)
	dialogue_open=true
	quest_dialogue=id
	dialogue_cursor=0
	dialogue_override=[]
	dialogue_followup=""
	page="江湖"
	render()

func travel(destination: String) -> void:
	if battle!=null or not boot_ready or not Chapter.PLACES.has(destination):return
	if Atlas.ensure(campaign).region!="嘉興鎮":Atlas.visit(campaign,"嘉興鎮");stage.cancel_walk();stage.sync_location()
	if destination==campaign.state.place and stage.is_near_npc():enter_scene("嘉興鎮",destination);return
	scene_open=false
	dialogue_open=false
	selected_npc=""
	page="江湖"
	campaign.state.study=""
	job_clock=0
	navigating=stage.go_to(destination)
	notice="前往%s入口；抵達後可選擇場景中的人物交談。"%destination
	render()

func _arrived(destination: String) -> void:
	campaign.state.place=destination
	navigating=false
	enter_scene("嘉興鎮",destination)

func choose(key: String) -> void:
	if battle != null or navigating or not boot_ready or Atlas.ensure(campaign).region != "嘉興鎮" or not stage.is_near_npc(): return
	# Validate that this choice still belongs to the visible conversation.
	var allowed := false
	for option in campaign.talk().choices:
		if option[1] == key: allowed = true
	if not allowed: return
	if key.begins_with("battle_"):
		start_battle(key.trim_prefix("battle_"))
		return
	notice = campaign.choose(key)
	if key == "gather" and Daily.complete(campaign,"gather",0,3): notice += " 今日採集另得 3 學點。"
	sounds.play("accept")
	if key.begins_with("choose_"): start_battle("warehouse")
	else:
		persist()
		render()

func render_party() -> void:
	label("同行，各有所長" if page == "同伴" else "武道，始於一招一式",Rect2(34,91,700,43),30)
	label("相識 %d 人 · 四人出戰 · 主角留隊" % campaign.state.roster.size(),Rect2(710,99,395,30),17,MUTED)
	button("上一頁",Rect2(1115,94,135,38),func(): roster_page=maxi(0,roster_page-1); render(),false,roster_page==0)
	button("下一頁",Rect2(1260,94,135,38),func(): roster_page=mini(int(ceil(Chapter.HEROES.size()/4.0))-1,roster_page+1); render(),false,roster_page>=int(ceil(Chapter.HEROES.size()/4.0))-1)
	for i in 4:
		var roster: Array = ["hero"]+OW.HEROES.keys()+["sword","healer","staff","blade","palm","doctor","taoist","monk","wanderer"]
		roster.erase("hero")
		roster.push_front("hero")
		if roster_page*4+i >= roster.size(): break
		var id: String = roster[roster_page*4+i]
		var recruited: bool = id in campaign.state.roster
		var x := 26+i*350
		panel(Rect2(x,151,338,182),Color("26443b") if hero_id == id else INK)
		image_at(Chapter.HEROES[id].art,Rect2(x+8,157,106,166))
		label(Chapter.HEROES[id].name,Rect2(x+121,173,207,34),25,GOLD)
		label(Chapter.HEROES[id].role,Rect2(x+121,210,210,30),17,MUTED)
		button("查看 · %d 重" % int(campaign.state.levels[id]) if recruited else "尋訪此人",Rect2(x+121,266,200,45),func():
			if recruited:hero_id=id;render()
			elif OW.HEROES.has(id):enter_scene(OW.HEROES[id].region,OW.HEROES[id].scene);open_person(id),hero_id==id,not recruited and not OW.HEROES.has(id))
	if not hero_id in campaign.state.roster: hero_id = "hero"
	var u: Dictionary = campaign.unit(hero_id)
	panel(Rect2(26,350,435,438))
	label("身 世 與 天 賦",Rect2(48,368,390,34),21,GOLD)
	prose(u.bio,Rect2(48,416,390,90),20)
	prose(u.talent,Rect2(48,524,390,70),19,MUTED)
	label("氣血 %d   攻擊 %d   防禦 %d" % [u.max_hp,u.atk,u.def],Rect2(48,615,390,32),18)
	label("速度 %d   聚氣 %d   兵器 · %s" % [u.speed,u.qi,u.weapon],Rect2(48,653,390,32),18)
	if hero_id in campaign.state.party:
		button("輪換前／後排",Rect2(48,714,190,46),func(): campaign.position_hero(hero_id,int(u.lane),not u.front); persist(); render())
		button("換上／中／下路",Rect2(249,714,190,46),func(): campaign.position_hero(hero_id,(int(u.lane)+1)%3,u.front); persist(); render())
	else:
		var swap := OptionButton.new()
		var candidates: Array = campaign.state.party.filter(func(id): return id != "hero")
		for id in candidates: swap.add_item("換下 · "+Chapter.HEROES[id].name)
		at(swap,Rect2(48,714,220,46))
		button("加入出戰",Rect2(280,714,160,46),func(): notice=campaign.swap_companion(hero_id,candidates[swap.selected] if not candidates.is_empty() else ""); persist(); render(),true)
	panel(Rect2(478,350,938,438))
	if page == "同伴":
		render_formation(u)
		return
	var rows := [["outer","外功",campaign.available_outer(hero_id)],["inner","內功",["吐納功","金鐘心法","長春功"]],["light","輕功",["雁行步","踏雪步"]]]
	for i in rows.size():
		var slot: String = rows[i][0]
		var y := 368+i*90
		label(rows[i][1]+" · "+u[slot],Rect2(498,y,375,30),22,GOLD)
		var arts: Array = rows[i][2]
		var chosen := OptionButton.new()
		for art in arts: chosen.add_item(art)
		chosen.select(maxi(0,arts.find(u[slot])))
		chosen.item_selected.connect(func(index): notice=campaign.equip(hero_id,slot,arts[index]); persist(); render())
		at(chosen,Rect2(1110,y,280,34))
		var description: String = Chapter.ARTS[u[slot]].text
		if slot == "outer": description = Chapter.ARTS[u.outer].skill+" · "+description
		prose(description,Rect2(498,y+37,885,48),17,MUTED)
	if campaign.state.sect=="未入門":
		for i in 5:
			var sect: String=["華山","武當","少林","全真","古墓"][i]
			button("拜入"+sect,Rect2(498+i*179,647,169,38),func():notice=campaign.join_sect(sect);persist();render(),false,not current_training_place())
	else:label("師承 · "+campaign.state.sect+"　同行傳承可在外功選單激發",Rect2(498,647,860,30),18)
	var cost := 12+int(campaign.state.levels[hero_id])*3
	button("消點進修 · %d 學點" % cost,Rect2(498,698,290,43),func(): notice=campaign.train(hero_id); persist(); render(),false,not current_training_place())
	button("停止自修" if campaign.state.study != "" else "自修 · 每 5 秒一重",Rect2(803,698,290,43),toggle_study,true)
	button("前往師父",Rect2(1108,698,280,43),func(): travel("演武坪"))
	label("自修耗 8＋重數×3 學點，消點耗 12＋重數×3；兩者均提升戰鬥屬性，上限三十重。",Rect2(498,752,887,25),16,MUTED)

func render_formation(u: Dictionary) -> void:
	label("隊 伍 陣 型",Rect2(503,368,850,36),25,GOLD)
	label("選定 %s，點陣位換位；已有同伴的位置會互換。" % u.name,Rect2(503,410,875,30),18,MUTED)
	label("後排 · 支援／越陣",Rect2(586,457,350,30),19)
	label("前排 · 承傷／護陣",Rect2(1000,457,360,30),19)
	for lane in 3:
		label(["上路","中路","下路"][lane],Rect2(505,511+lane*65,75,45),18,GOLD)
		for rank in 2:
			var front: bool = rank == 1
			var occupant := ""
			for id in campaign.state.party:
				if int(campaign.state.formation[id].lane)==lane and campaign.state.formation[id].front==front: occupant=id
			button(Chapter.HEROES[occupant].name if occupant!="" else "空位",Rect2(584+rank*412,505+lane*65,380,51),func(): campaign.position_hero(hero_id,lane,front); persist(); render(),occupant==hero_id)
	prose("近戰須先突破前排；不同路會影響自動索敵。守勢中的前排可攔下後排攻勢，越陣武學則能直接選後排。",Rect2(503,711,600,62),17,MUTED)
	button("搭配武學 →",Rect2(1130,712,255,47),func(): set_page("武學"),true)

func toggle_study() -> void:
	if campaign.state.study == "":
		campaign.state.study = hero_id
		study_clock = 0
		notice = "開始自修，每完成 5 秒才扣學點並提升一重；切換地點、開戰或離開會停止。"
	else:
		campaign.state.study = ""
		notice = "已停止自修。"
	persist()
	render()

func item_image(index: int, rect: Rect2) -> void:
	var source: Texture2D = bank.get_asset("res://assets/ui/items.png")
	if source == null: return
	var icon := AtlasTexture.new()
	icon.atlas = source
	var cell := source.get_size()/Vector2(4,2)
	icon.region = Rect2(Vector2(index%4,index/4)*cell,cell)
	icon.filter_clip = true
	var node := TextureRect.new()
	node.texture = icon
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(node,rect)

func render_inventory() -> void:
	label("行 囊",Rect2(46,94,720,43),30,GOLD)
	label("銀兩 %d　·　點物品查看用途" % campaign.state.silver,Rect2(930,104,470,30),19,PAPER)
	panel(Rect2(28,163,846,498))
	var items: Array = Chapter.SHOP.keys()
	for slot in 40:
		var x := 54+(slot%8)*99
		var y := 189+(slot/8)*89
		var item: String = items[slot] if slot<items.size() else ""
		var cell := button("",Rect2(x,y,85,78),func(): inventory_selection=item; render(),item==inventory_selection,item=="")
		cell.tooltip_text = item if item!="" else "空行囊格"
		if item!="":
			item_image(slot,Rect2(x+10,y+4,65,57))
			label("×"+str(int(campaign.state.inventory.get(item,0))),Rect2(x+46,y+50,38,25),16,PAPER)
	label("隨身物品　%d / 40 格" % items.size(),Rect2(59,626,755,25),17,MUTED)
	var evidence: Array=[]
	for clue in Open.ensure(campaign).evidence.values():evidence.append(clue.name)
	if not evidence.is_empty():
		prose("隨身物件（任務所用，不可出售）\n"+"、".join(evidence),Rect2(54,374,788,224),19,GOLD)
	panel(Rect2(895,163,520,498))
	item_image(items.find(inventory_selection),Rect2(929,191,92,92))
	label(inventory_selection,Rect2(1033,208,340,42),29,GOLD)
	var data: Dictionary = Chapter.SHOP[inventory_selection]
	prose(data.desc,Rect2(932,369,433,90),22,PAPER)
	label("持有 %d　·　買入 %d 銀／售出 %d 銀" % [int(campaign.state.inventory.get(inventory_selection,0)),int(data.price),int(data.sell)],Rect2(932,475,445,30),18,MUTED)
	button("購買 · %d 銀" % int(data.price),Rect2(930,289,211,47),func(): notice=campaign.trade(inventory_selection,true); persist(); render(),true,not Open.is_market(campaign))
	button("出售 · %d 銀" % int(data.sell),Rect2(1160,289,220,47),func(): notice=campaign.trade(inventory_selection,false); persist(); render(),false,not Open.is_market(campaign) or campaign.state.inventory.get(inventory_selection,0)<1)
	prose("戰鬥中每回合全隊限用一次藥。\n抵達市集後，掌櫃會按標價買賣。",Rect2(932,544,435,70),18,MUTED)
	button("前往市集 · 與掌櫃交易",Rect2(33,688,430,50),func():enter_scene(Open.current_region(campaign),Open.market_scene(Open.current_region(campaign))),true)
	button("前往蘆葦蕩 · 採藥",Rect2(487,688,430,50),func(): travel("蘆葦蕩"))
	button("前往藥廬 · 交付草藥",Rect2(944,688,465,50),func(): travel("藥廬"))

func render_journal() -> void:
	label("江 湖 委 託",Rect2(38,91,530,43),30,GOLD)
	var data: Dictionary=Open.ensure(campaign)
	var ids:=[]
	for id in OW.QUESTS:
		var quest: Dictionary=Open.definition(campaign,id)
		if quest_filter=="當地" and (quest.region!=Open.current_region(campaign) or quest.scene!=Open.current_scene(campaign)):continue
		if quest_filter=="進行中" and (not data.quests.has(id) or data.quests[id].status!="active"):continue
		ids.append(id)
	for i in 3:
		var filter: String=["當地","進行中","全部"][i]
		button(filter,Rect2(860+i*177,94,165,40),func():quest_filter=filter;quest_page=0;render(),quest_filter==filter)
	panel(Rect2(28,155,505,624))
	quest_page=clampi(quest_page,0,maxi(0,(ids.size()-1)/10))
	if not ids.is_empty() and not quest_selection in ids:quest_selection=ids[0]
	for i in 10:
		if quest_page*10+i>=ids.size():break
		var id: String=ids[quest_page*10+i]
		var status: String=data.quests.get(id,{}).get("status","")
		button(("✓ " if status=="done" else ("◆ " if status=="active" else ""))+Open.definition(campaign,id).name,Rect2(44,176+i*49,473,43),func():quest_selection=id;render(),quest_selection==id)
	button("上一頁",Rect2(45,706,145,42),func():quest_page-=1;render(),false,quest_page==0)
	label("%d / %d"%[quest_page+1,maxi(1,int(ceil(ids.size()/10.0)))],Rect2(209,713,150,25),18)
	button("下一頁",Rect2(369,706,145,42),func():quest_page+=1;render(),false,(quest_page+1)*10>=ids.size())
	panel(Rect2(553,155,860,624))
	if ids.is_empty():
		prose("這裡暫無待辦。點選「全部」查看各地委託，或繼續與場景中的人物交談。",Rect2(585,199,790,130),23)
		return
	var q: Dictionary=Open.definition(campaign,quest_selection)
	label(q.name,Rect2(581,178,800,45),29,GOLD)
	label(q.region+"／"+q.scene+" · "+OW.PEOPLE[q.giver].name,Rect2(583,231,788,32),18,MUTED)
	prose(q.text,Rect2(584,282,788,136),22)
	var status: Dictionary=data.quests.get(quest_selection,{})
	if status.is_empty():
		prose("自由支線 · 可與其他委託同時進行，沒有主線期限。",Rect2(584,443,788,80),20,MUTED)
		button("接下委託" if q.region==Open.current_region(campaign) and q.scene==Open.current_scene(campaign) else "尋訪委託人",Rect2(584,615,788,51),func():
			if q.region!=Open.current_region(campaign) or q.scene!=Open.current_scene(campaign):enter_scene(q.region,q.scene);open_person(q.giver)
			else:notice=Open.accept(campaign,quest_selection,q.giver);quest_filter="進行中";persist();render(),true)
	elif status.status=="done":
		label("已結案 · 報酬已領取",Rect2(584,443,788,40),26,GOLD)
		var choice: int=0 if status.choices.is_empty() else int(status.choices.back())
		prose(q.get("endings",[q.text,q.text])[choice],Rect2(584,504,788,112),20)
	else:
		var step: Dictionary=q.steps[int(status.step)]
		label("步驟 %d / %d"%[int(status.step)+1,q.steps.size()],Rect2(584,435,788,35),23,GOLD)
		prose(step.region+"／"+step.scene+"\n"+step.text,Rect2(584,480,788,89),22)
		button("追蹤此委託",Rect2(584,608,220,47),func():data.tracked=quest_selection;persist();notice="已追蹤這份支線。";render())
		button("前往目標",Rect2(819,608,250,47),func():enter_scene(step.region,step.scene);open_quest_dialogue(quest_selection),true)
		if step.region==Open.current_region(campaign) and step.scene==Open.current_scene(campaign):
			button("交談辦理" if step.has("npc") else ("察看線索" if step.kind=="search" else "查看現場"),Rect2(1084,608,288,47),func():open_quest_dialogue(quest_selection),true)
		var clues: Array=[]
		for clue in data.evidence.values():
			if clue.quest==quest_selection:clues.append(clue.name)
		if not clues.is_empty():label("隨身物件："+"、".join(clues),Rect2(584,677,788,32),18,GOLD)
	label("報酬：%d 銀 · %d 學點"%[q.reward.silver,q.reward.potential],Rect2(584,734,788,27),18,GOLD)

func render_atlas() -> void:
	label("山 河 行 旅 · 自由探索",Rect2(35,88,700,43),29,GOLD)
	button("江湖群雄 · 100 種對手",Rect2(824,91,340,43),func():foe_filter="全部";foe_page=0;set_page("挑戰"))
	button("武林論劍",Rect2(1180,91,230,43),challenge_supremacy,true)
	var map_rect:=Rect2(28,158,820,615)
	var background:=TextureRect.new()
	background.texture=bank.get_asset("res://assets/town/world.png")
	background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	at(background,map_rect)
	for name in Atlas.REGIONS:
		var r: Dictionary=Atlas.REGIONS[name]
		var p: Vector2=map_rect.position+r.point*map_rect.size/Vector2(640,480)
		var b:=button("◆" if world_selection==name else "",Rect2(p-Vector2(18,18),Vector2(36,36)),func():world_selection=name;render(),world_selection==name)
		b.tooltip_text="選擇 · "+name
		for state_name in ["normal","hover","pressed","focus"]:
			var ring:=StyleBoxFlat.new()
			ring.bg_color=Color(1,.85,.4,.35) if world_selection==name else Color(0,0,0,0)
			ring.set_corner_radius_all(18)
			b.add_theme_stylebox_override(state_name,ring)
	panel(Rect2(873,158,540,615))
	label(world_selection,Rect2(900,182,485,44),30,GOLD)
	label("所有道路開放 · 目前在 "+Open.current_region(campaign),Rect2(901,236,483,28),17,MUTED)
	prose("可尋訪："+"、".join(OW.REGIONS[world_selection])+"。\n先與當地人物交談，選擇你願意參與的支線。",Rect2(901,286,480,110),21)
	var scenes: Array=OW.REGIONS[world_selection]
	for i in scenes.size():
		var place: String=scenes[i]
		button(place,Rect2(901+(i%2)*245,416+(i/2)*53,231,44),func():
			if world_selection=="嘉興鎮" and Chapter.PLACES.has(place):travel(place)
			else:enter_scene(world_selection,place))
	button("進入 · "+world_selection,Rect2(901,715,480,45),func():journey_to(world_selection),true)

func challenge_supremacy() -> void:
	start_battle("supremacy")

func journey_to(region: String) -> void:
	if not OW.REGIONS.has(region):return
	enter_scene(region,OW.REGIONS[region][0])

func render_daily() -> void:
	label("今 日 江 湖",Rect2(32,87,500,43),30,GOLD)
	label("每日凌晨零時更新（UTC+8） · 進度自動保存",Rect2(370,98,600,30),18,MUTED)
	button("世界地圖",Rect2(1080,87,160,42),func(): set_page("世界"))
	button("返回江湖",Rect2(1252,87,160,42),func(): set_page("江湖"))
	var i := 0
	for key in Daily.TASKS:
		var task: Dictionary = Daily.TASKS[key]
		var x := 28+(i%2)*700
		var y := 153+(i/2)*192
		var done := Daily.count(campaign,key)
		panel(Rect2(x,y,684,179),Color("1b382f"))
		label(task.name,Rect2(x+20,y+12,340,36),25,GOLD)
		label("%d / %d" % [done,task.limit],Rect2(x+545,y+15,120,30),22)
		prose(task.desc,Rect2(x+20,y+56,642,48),18)
		label(task.reward,Rect2(x+20,y+116,452,29),16,MUTED)
		var locked: bool = key == "sect" and campaign.state.sect == "未入門"
		var title: String = "今日完成" if done >= task.limit else ("先拜師" if locked else ("前往 · "+Daily.target(campaign,key)))
		button(title,Rect2(x+472,y+116,190,43),func(): daily_action(key),true,done >= task.limit)
		i += 1
	var contribution := int(campaign.state.flags.get("contribution",0))
	label("師門貢獻 %d · 30 貢獻換 40 學點（演武坪）" % contribution,Rect2(42,744,1030,35),20,GOLD)
	button("兌換修行資糧",Rect2(1100,736,286,47),func():
		if campaign.state.place != "演武坪" or Atlas.ensure(campaign).region != "嘉興鎮": travel("演武坪"); return
		if int(campaign.state.flags.get("contribution",0)) < 30: return
		campaign.state.flags.contribution = int(campaign.state.flags.contribution)-30
		campaign.state.potential += 40
		notice = "以 30 師門貢獻兌得 40 學點。"
		persist()
		render(),false,contribution < 30)

func daily_caption(key: String) -> String:
	if not Daily.available(campaign,key): return "今日次數已完成"
	if job_clock > 0: return "守爐中 · %d 秒" % int(ceil(job_clock))
	var target := Daily.target(campaign,key)
	if campaign.state.place != target or not stage.is_near_npc(): return "前往 · "+target
	var data := Daily.ensure(campaign)
	if key == "sect": return "領取師門信" if data.errand == "" else "交付師門信"
	if key == "escort": return ["接取藥材鏢","驗收鏢貨","護住鏢貨 · 迎戰"][int(data.escort)]
	return {"work":"開始煮藥 · 草藥一株","gather":"採集一株草藥","training":"接受武館指點","dungeon":"挑戰黑風寨主"}[key]

func daily_action(key: String) -> void:
	if not boot_ready or battle != null or navigating or job_clock > 0 or not Daily.available(campaign,key): return
	daily_focus = key
	if key == "sect" and campaign.state.sect == "未入門": travel("演武坪"); notice="先與師父交談拜師，再領師門信。"; render(); return

	var target := Daily.target(campaign,key)
	if campaign.state.place != target or Atlas.ensure(campaign).region != "嘉興鎮" or not stage.is_near_npc(): travel(target); return
	page = "江湖"
	var data := Daily.ensure(campaign)
	match key:
		"sect":
			if data.errand == "":
				data.errand = ["青溪客棧","藥廬","古寺"][Daily.count(campaign,key)]
				notice = "師父交給你一封問安信，請親手送到%s。" % data.errand
			else:
				Daily.complete(campaign,key,15,12)
				campaign.state.flags.contribution = mini(1000000,int(campaign.state.flags.get("contribution",0))+10)
				data.errand = ""
				notice = "信已送達。獲得 15 銀、12 學點、10 師門貢獻。"
		"work":
			if int(campaign.state.inventory.get("草藥",0)) < 1: notice="需要一株草藥。可到蘆葦蕩採集，或到市集購買。"
			else:
				job_clock = 6
				job_day = int(data.day)
				notice = "開始守爐；藥成後才扣除草藥並發放工錢。"
		"escort":
			if data.escort == 0:
				data.escort = 1
				notice = "接下藥材鏢。先到演武坪與師父驗貨，再運到渡口。"
			elif data.escort == 1:
				data.escort = 2
				notice = "封箱完好，沿街前往渡口；留意劫道的人。"
			else: start_battle("escort"); return
		"training": start_battle("training"); return
		"dungeon": start_battle("rematch"); return
		"gather": choose("gather"); return
	sounds.play("accept")
	persist()
	render()

func render_settings() -> void:
	label("讓江湖合你的步調",Rect2(34,93,950,43),30)
	panel(Rect2(28,151,675,632))
	label("聲音與進度",Rect2(54,175,620,40),27,GOLD)
	button("關閉音樂" if Bgm.enabled else "開啟音樂",Rect2(54,244,610,47),func(): Bgm.set_enabled(not Bgm.enabled); render(),true)
	label("音量",Rect2(54,322,120,32),22)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = Bgm.volume*100
	slider.value_changed.connect(func(value): Bgm.set_volume(value/100.0))
	at(slider,Rect2(180,322,480,34))
	var tracks := OptionButton.new()
	tracks.add_item("隨場景切換")
	var keys: Array = [""]+Bgm.TRACKS.keys()
	for key in Bgm.TRACKS: tracks.add_item(Bgm.TRACKS[key].title)
	tracks.select(maxi(0,keys.find(Bgm.override_track)))
	tracks.item_selected.connect(func(index): Bgm.set_override(keys[index]))
	at(tracks,Rect2(54,395,610,48))
	var effects_button := button("音效 · "+("開" if sounds.audible() else "關"),Rect2(54,458,290,43),func(): sounds.toggle(); render())
	button("刪除存檔／重新開始",Rect2(366,458,298,43),request_reset_save,false,Session.mode!="單機")
	label("音效音量",Rect2(54,523,180,30),20)
	var fx_slider := HSlider.new()
	fx_slider.min_value=0
	fx_slider.max_value=100
	fx_slider.value=sounds.volume*100
	fx_slider.value_changed.connect(func(value):
		sounds.set_volume(value/100.0)
		effects_button.text="音效 · "+("開" if sounds.audible() else "關")
		update_browser_status())
	at(fx_slider,Rect2(220,523,440,30))
	button("試聽刀劍音效",Rect2(54,700,290,43),func(): sounds.preview(); render())
	button("匯出重寫前舊檔",Rect2(366,700,298,43),func():Session.export_story_backup(),false,Session.story_backups().is_empty())
	prose("進度自動保存。右上 ☰ 可匯出／匯入存檔。新版首次載入舊進度會先完整備份，再重新開局；舊檔可由下方匯出。手動刪檔也會清除這些備份。",Rect2(54,569,610,120),20,MUTED)
	panel(Rect2(723,151,689,632))
	label("戰鬥怎麼玩",Rect2(750,175,630,40),27,GOLD)
	prose("一、戰前在同伴頁調整前後排、上中下路與三門武學。\n\n二、每輪先替同伴選擇普攻、施招或守勢，再按「進行回合」。按速度先後出手。\n\n三、任一方普攻，全體存活者聚氣。25 真元為一格，施招需足夠真元與調息完成。\n\n四、近戰先打前排，飛燕穿雲能越陣。寨主蓄力時用陸衡封招；沈青棠療傷解毒；主角追擊流血與破甲。",Rect2(750,238,632,355),21)
	prose("自由江湖目前為單機隊伍。原有 Steam／區網與生活技能仍可由舊版江湖進入。",Rect2(750,611,632,73),18,MUTED)
	button("進入舊版江湖 · F9",Rect2(750,710,630,47),func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))

func start_battle(kind: String) -> void:
	if not boot_ready or battle != null or job_clock > 0: return

	if kind.begins_with("road_"):
		var region := kind.trim_prefix("road_")
		if Atlas.ensure(campaign).region != region or not Atlas.REGIONS.has(region): return
	if (kind.begins_with("quest:") or kind.begins_with("wild:")) and Open.battle_roster(campaign,kind).is_empty():return
	campaign.state.study = ""
	stage.cancel_walk()
	navigating = false
	battle = Battle.new(campaign,kind)
	stage.battle = battle
	selected_enemy = battle.living(1)[0].id
	selected_ally = "hero"
	stage.selected = selected_enemy
	auto_battle = false
	result_applied = false
	reward_summary = "30 銀 · 25 學點"
	notice = "先觀察敵方意圖。選敵人後替各同伴下令，再進行回合；未下令的同伴會普攻。"
	Bgm.set_scene_context("boss" if kind in ["warehouse","rematch"] else "battle")
	persist()
	render()

func select_unit(id: String) -> void:
	if battle == null: return
	var u: Dictionary = battle.by_id(id)
	if u.side == 1: selected_enemy = id
	else: selected_ally = id
	stage.selected = id
	notice = "%s · 氣血 %d/%d · %s" % [u.name,u.hp,u.max_hp,u.intent if u.side == 1 else Chapter.HEROES[u.id].talent]
	render()

func queue_order(id: String, action: String) -> void:
	if battle.order(id,action,selected_enemy):
		notice = "%s已準備%s。" % [Chapter.HEROES[id].name,{"skill":"施招","guard":"守勢","attack":"普攻"}[action]]
		if action == "skill": notice += Chapter.ARTS[battle.by_id(id).outer].text
	else: notice = "這一輪正在出招，下一輪可調整。"
	render()

func play_round() -> void:
	if battle == null or battle.result != "" or not battle.queue.is_empty(): return
	battle.begin_round()
	action_clock = .15
	render()

func finish_battle() -> void:
	if result_applied: return
	result_applied = true
	auto_battle = false
	if battle.result == "victory":
		var before_silver := int(campaign.state.silver)
		var before_potential := int(campaign.state.potential)
		var before_medicine := int(campaign.state.inventory.get("金創藥",0))
		campaign.win(battle.encounter)
		Open.battle_won(campaign,battle.encounter)
		notice = "此戰告捷 · 30 銀、25 學點。回鎮後全隊療傷。"
		if battle.encounter.begins_with("road_"): notice = Atlas.resolve(campaign)
		elif battle.encounter == "supremacy":
			if not campaign.state.flags.get("supremacy",false):
				campaign.state.silver += 500
				campaign.state.potential += 600
				campaign.state.flags.supremacy = true
				campaign.record("武林論劍勝出。你與同伴擊敗三位宗師，獲推為武林盟主。")
			notice = "武林論劍告捷 · 武林盟主！江湖仍有未相識的人、未走完的路。"
		elif battle.encounter == "training" and Daily.complete(campaign,"training",0,15): notice += " 指點另得 15 學點。"
		elif battle.encounter == "escort" and Daily.ensure(campaign).escort == 2 and Daily.complete(campaign,"escort",50,20):
			Daily.ensure(campaign).escort = 0
			notice += " 運鏢完成，另得 50 銀、20 學點。"
		elif battle.encounter == "rematch" and Daily.complete(campaign,"dungeon",20,20): notice += " 今日試煉另得 20 銀、20 學點。"
		reward_summary = "%d 銀 · %d 學點" % [int(campaign.state.silver)-before_silver,int(campaign.state.potential)-before_potential]
		var extra_medicine := int(campaign.state.inventory.get("金創藥",0))-before_medicine
		if extra_medicine > 0: reward_summary += " · 金創藥 ×%d" % extra_medicine
	else: notice = "暫且退回鎮上。試著調整前排、配金鐘心法，或留真元打斷首領。沒有扣除銀兩與修為。"
	persist()

func leave_battle() -> void:
	if battle == null: return
	var defeated: bool = battle.result != "victory"
	var story: String=battle.encounter.split(":")[1] if battle.encounter.begins_with("quest:") else ""
	battle = null
	stage.battle = null
	stage.selected = ""
	page = "江湖"
	if defeated:
		campaign.state.place = "青溪客棧"
		Atlas.ensure(campaign).region = "嘉興鎮"
		Open.enter(campaign,"嘉興鎮","青溪客棧")
	stage.cancel_walk()
	Bgm.set_scene_context("town")
	persist()
	if not defeated and story!="" and Open.step_here(campaign,story):open_quest_dialogue(story)
	else:render()

func use_medicine() -> void:
	var event: Dictionary = battle.medicine(selected_ally,campaign.state.inventory)
	if event.is_empty(): notice = "先選一位受傷的同伴；僅能在回合準備時用藥，每回合全隊限一次。"
	else:
		notice = event.text
		stage.show_event(event)
		persist()
	render()

func render_battle() -> void:
	stage.position = Vector2.ZERO
	stage.size = Vector2(1440,710)
	var ready: bool = battle.queue.is_empty() and battle.result == ""
	if battle.by_id(selected_enemy).get("hp",0) <= 0 and not battle.living(1).is_empty(): selected_enemy = battle.living(1)[0].id
	panel(Rect2(14,12,288,65))
	label("第 %02d 回合" % battle.round_no,Rect2(36,23,250,42),28,GOLD)
	label("準備施招 · 點敵人選定目標" if ready else "交鋒中 · 依身法出手",Rect2(405,24,650,37),22,PAPER)
	button("委託 · 開" if auto_battle else "委託 · 關",Rect2(1035,17,150,46),func(): auto_battle=not auto_battle; render(),auto_battle)
	button("進行回合 [空白]",Rect2(1193,17,230,46),play_round,true,not ready)
	var target: Dictionary = battle.by_id(selected_enemy)
	var target_text: String = target.name+" · "+target.intent if not target.is_empty() else "點敵人選目標"
	panel(Rect2(17,88,800,53))
	label(target_text,Rect2(35,96,768,36),18,GOLD)
	button("音效 " + ("開" if sounds.audible() else "關"),Rect2(826,90,128,43),func(): sounds.toggle(); render())
	button("音樂 " + ("開" if Bgm.enabled else "關"),Rect2(960,90,128,43),func(): Bgm.set_enabled(not Bgm.enabled); render())
	button("金創藥 ×%d" % int(campaign.state.inventory.get("金創藥",0)),Rect2(1097,90,174,43),use_medicine,false,not ready or battle.medicine_used)
	button("繼續故事" if battle.result=="victory" else ("回鎮療傷" if battle.result!="" else "撤退"),Rect2(1280,90,142,43),leave_battle,battle.result!="",not battle.queue.is_empty() and battle.result=="")
	for i in campaign.state.party.size():
		var id: String = campaign.state.party[i]
		var u: Dictionary = battle.by_id(id)
		var x: int = 12+i*357
		panel(Rect2(x,718,345,160))
		var portrait_button := button("",Rect2(x+7,731,78,115),func(): select_unit(id),selected_ally==id,u.hp<=0)
		portrait_button.tooltip_text = "選定 · "+u.name
		image_at(Chapter.HEROES[id].art,Rect2(x+10,732,74,112))
		label(u.name,Rect2(x+96,729,151,30),21,GOLD)
		label("%d/%d" % [u.hp,u.max_hp],Rect2(x+243,734,96,25),15)
		bar(u.hp,u.max_hp,Rect2(x+96,760,230,7),Color("9ebd8a"))
		bar(u.energy,100,Rect2(x+96,774,230,6),Color("739ba7"))
		var art: Dictionary = Chapter.ARTS[u.outer]
		var reason: String = battle.cast_reason(id)
		var command: Dictionary = battle.orders.get(id,{"action":"attack","target":""})
		var skill := button(art.skill+" · %d 格" % (int(art.cost)/25),Rect2(x+96,788,230,35),func(): queue_order(id,"skill"),command.action=="skill",not ready or reason!="")
		skill.tooltip_text = art.text+"\n消耗 %d 真元，調息 %d 回合。" % [art.cost,art.cd]
		button("普攻",Rect2(x+96,830,108,35),func(): queue_order(id,"attack"),command.action=="attack",not ready or u.hp<=0)
		button("守勢",Rect2(x+213,830,113,35),func(): queue_order(id,"guard"),command.action=="guard",not ready or u.hp<=0)
		label("真元 %d" % u.energy,Rect2(x+14,850,83,24),14,MUTED)
	label(notice,Rect2(22,879,1390,21),15,GOLD)
	if battle.result != "":
		panel(Rect2(470,265,500,198))
		label("此 戰 告 捷" if battle.result=="victory" else "勝 敗 乃 兵 家 常 事",Rect2(505,282,430,45),31,GOLD)
		label(reward_summary if battle.result=="victory" else "調整武學與陣型，再戰江湖。",Rect2(505,342,430,34),18)
		button("繼續故事" if battle.result=="victory" else "回鎮療傷",Rect2(504,398,432,43),leave_battle,true)

func head_at(art: String,rect: Rect2) -> void:
	at(stage.portrait(art,true),rect)

func enter_scene(region: String,location: String) -> void:
	if battle!=null:return
	stage.cancel_walk()
	navigating=false
	Open.enter(campaign,region,location)
	scene_open=true
	dialogue_open=false
	selected_npc=""
	npc_page=0
	page="江湖"
	job_clock=0
	campaign.state.study=""
	if region=="嘉興鎮" and Chapter.PLACES.has(location):campaign.state.place=location
	Bgm.set_scene_context("town")
	notice="抵達%s／%s。點人物頭像交談，接委託或邀請同行。"%[region,location]
	persist()
	render()

func open_person(id: String) -> void:
	if not Open.meet(campaign,id):return
	page="江湖"
	selected_npc=id
	dialogue_open=true
	dialogue_topic=false
	quest_dialogue=""
	dialogue_cursor=0
	dialogue_override=[]
	dialogue_followup=""
	var active: Array=Open.active_for(campaign,id)
	if not active.is_empty():quest_dialogue=active[0]
	render()

func current_training_place() -> bool:
	return Open.current_region(campaign) in ["華山派","武當派","少林派","全真教","峨嵋派"] or Open.current_scene(campaign) in ["演武坪","古墓"]

func quest_progress(id: String,choice: int=-1) -> void:
	var result: Dictionary=Open.action(campaign,id,selected_npc,choice)
	notice=result.text
	if result.has("battle"):dialogue_open=false;start_battle(result.battle)
	else:
		persist()
		dialogue_cursor=0
		quest_dialogue=""
		dialogue_followup=id
		dialogue_override=[{"speaker":"","caption":"行旅進展","text":result.text}]
		if Open.step_here(campaign,id,selected_npc):dialogue_override=[];quest_dialogue=id
		render()

func render_foes() -> void:
	label("江 湖 群 雄",Rect2(38,90,610,45),30,GOLD)
	label("100 種獨立外觀 · 自由挑戰 · 出手前可退",Rect2(600,101,790,29),18,MUTED)
	var ids:=[]
	for id in OW.ENEMIES:
		if foe_filter=="全部" or OW.ENEMIES[id].region==foe_filter:ids.append(id)
	foe_page=clampi(foe_page,0,maxi(0,(ids.size()-1)/8))
	if not foe_selection in ids and not ids.is_empty():foe_selection=ids[0]
	panel(Rect2(29,156,600,620))
	for i in 8:
		if foe_page*8+i>=ids.size():break
		var id: String=ids[foe_page*8+i]
		var enemy: Dictionary=OW.ENEMIES[id]
		button(enemy.name+" · "+str(enemy.level)+" 重",Rect2(48,176+i*61,563,52),func():foe_selection=id;render(),foe_selection==id)
	button("上一頁",Rect2(48,697,150,43),func():foe_page-=1;render(),false,foe_page==0)
	button("全部對手",Rect2(211,697,215,43),func():foe_filter="全部";foe_page=0;render())
	button("下一頁",Rect2(439,697,171,43),func():foe_page+=1;render(),false,(foe_page+1)*8>=ids.size())
	if ids.is_empty():return
	var e: Dictionary=OW.ENEMIES[foe_selection]
	panel(Rect2(651,156,762,620))
	image_at("actor_"+e.sprite,Rect2(677,211,260,402))
	label(e.name,Rect2(959,187,420,43),29,GOLD)
	prose("%s／%s\n氣血 %d　攻擊 %d\n防禦 %d　身法 %d\n%s\n\n%s"%[e.region,e.scene,e.hp,e.atk,e.def,e.speed,e.skill,e.text],Rect2(958,253,420,285),21)
	button("前往對手所在地",Rect2(681,636,690,47),func():enter_scene(e.region,e.scene);foe_filter=e.region;set_page("挑戰"))
	button("接受挑戰",Rect2(681,699,690,47),func():start_battle("wild:"+foe_selection),true,Open.current_region(campaign)!=e.region or Open.current_scene(campaign)!=e.scene)

func request_reset_save() -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.title="刪除存檔並重新開始"
	dialog.dialog_text="這會清除本機角色、同行名冊、物品和支線進度。\n自動備份也會一併清除，避免舊進度復原。\n需要保留時，請先匯出存檔。確定重新開始？"
	dialog.ok_button_text="刪除並重新開始"
	dialog.cancel_button_text="保留存檔"
	dialog.confirmed.connect(func():
		if Session.reset_local_progress():notice="舊進度已清除，重新展開自由江湖。";render()
		else:notice=Session.status;render()
		dialog.queue_free())
	dialog.canceled.connect(func():dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(610,235))
	dialog.get_cancel_button().grab_focus()
