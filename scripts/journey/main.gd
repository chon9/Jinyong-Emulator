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
var inventory_selection := "金創藥"
var swap_out := "sword"
var selected_enemy := ""
var selected_ally := "hero"
var notice := "雨停之前，先向窗邊的顧長風打聽失鏢。"
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
	Atlas.ensure(campaign)
	Daily.ensure(campaign)
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
	stage.walking.connect(func(): navigating=false; dialogue_open=false; campaign.state.study=""; notice="沿街探索；點人物可走近交談。"; render())
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
	page = "江湖"
	notice = "已載入存檔。青溪故事與舊版角色分別保留；未完成的戰鬥與自修已停止。"
	render()

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
	box.add_theme_stylebox_override("panel",game_skin.box(1 if color.get_luminance() > .5 else (0 if rect.size.x > 600 and rect.size.y > 400 else 2)) if game_skin != null else style(color))
	at(box,rect,parent)
	return box

func label(value: String, rect: Rect2, size_value: int = 20, color: Color = PAPER, parent: Node = null) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_color_override("font_color",color)
	node.add_theme_font_size_override("font_size",size_value)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(node,rect,parent)
	return node

func prose(value: String, rect: Rect2, font_size: int = 20, color: Color = PAPER, parent: Node = null) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.text = value
	node.add_theme_color_override("default_color",color)
	node.add_theme_font_size_override("normal_font_size",font_size)
	node.add_theme_constant_override("line_separation",5)
	at(node,rect,parent)
	return node

func button(value: String, rect: Rect2, callback: Callable, primary: bool = false, disabled: bool = false, parent: Node = null) -> Button:
	var b := Button.new()
	b.text = value
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
	var node := TextureRect.new()
	node.texture = stage.portrait(art)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(node,rect,parent)

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
	var status := {"page":page,"place":campaign.state.place,"stage":int(campaign.state.stage),"party":campaign.state.party.size(),"battle":"" if battle == null else (battle.result if battle.result != "" else "active"),"round":0 if battle == null else battle.round_no,"notice":notice,"region":Atlas.ensure(campaign).region,"navigating":navigating,"daily":Daily.ensure(campaign).counts,"ready":boot_ready}
	JavaScriptBridge.eval("window.youxiaChapterStatus = Object.freeze("+JSON.stringify(status)+");",true)
	var buttons := []
	collect_buttons(layer,buttons)
	JavaScriptBridge.eval("window.youxiaUI = Object.freeze("+JSON.stringify({"buttons":buttons})+");",true)
	var window := JavaScriptBridge.get_interface("window")
	if window.youxiaSetStatus != null: window.youxiaSetStatus("無名少俠",campaign.state.place,page,"青溪故事 · 單機")

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
	var region: String = Atlas.ensure(campaign).region
	panel(Rect2(12,12,330,95),Color("241a13"))
	image_at(Chapter.HEROES.hero.art,Rect2(20,13,75,88))
	label("無名少俠",Rect2(100,31,215,30),22,GOLD)
	label("%s · 修為 %d 重" % [campaign.state.sect,campaign.state.levels.hero],Rect2(100,62,220,25),17,PAPER)
	label("青溪鎮" if region == "嘉興鎮" else region,Rect2(610,16,520,48),30,GOLD)
	button("音樂 " + ("開" if Bgm.enabled else "關"),Rect2(1280,16,142,40),func(): Bgm.set_enabled(not Bgm.enabled); render())
	panel(Rect2(15,126,310,230),Color("2b2017"))
	label("主線 · "+campaign.objective()[0],Rect2(36,158,265,30),21,GOLD)
	prose(campaign.objective()[2],Rect2(36,192,265,74),18,PAPER)
	var target: String = campaign.objective()[1]
	button("返回青溪 · 繼續主線" if region != "嘉興鎮" else ("交談 · "+Chapter.PLACES[target].npc if target == campaign.state.place and not navigating else "前往 · "+target),Rect2(34,282,268,48),quest_action,true,navigating)
	button("今日江湖 [D]",Rect2(1241,258,181,46),func(): set_page("每日"))
	button("山河行旅 [M]",Rect2(1241,311,181,46),func(): set_page("世界"))
	if daily_focus != "" and region == "嘉興鎮":
		button(daily_caption(daily_focus),Rect2(1090,536,321,47),func(): daily_action(daily_focus),true,navigating or job_clock>0 or not Daily.available(campaign,daily_focus))
	if navigating: label("沿街尋路中…",Rect2(610,745,400,35),21,GOLD)
	if region != "嘉興鎮":
		button("交談 · "+Atlas.REGIONS[region].npc,Rect2(1110,375,312,48),func(): dialogue_open=true; render(),true)
	elif not navigating and stage.is_near_npc() and campaign.objective()[1] != campaign.state.place:
		button("交談 · "+Chapter.PLACES[campaign.state.place].npc,Rect2(1110,375,312,48),func(): dialogue_open=true; render())
	if dialogue_open: render_dialogue()

func quest_action() -> void:
	if navigating: return
	var target: String = campaign.objective()[1]
	if Atlas.ensure(campaign).region != "嘉興鎮" or not stage.is_near_npc() or target != campaign.state.place:
		travel(target)
		return
	dialogue_open = true
	render()

func render_dialogue() -> void:
	var region: String = Atlas.ensure(campaign).region
	var d: Dictionary
	var portrait_art: String
	if region != "嘉興鎮":
		var r: Dictionary = Atlas.REGIONS[region]
		d = {"name":r.npc,"text":r.text+"\n"+r.rumor,"choices":[["已結案 · 再次切磋" if region in Atlas.ensure(campaign).cleared else "接受委託 · 出發迎戰","@road"],["返回青溪","@return"]]}
		portrait_art = "actor_"+Atlas.NPC_SPRITES[region]
	else:
		d = campaign.talk()
		portrait_art = Chapter.PLACES[campaign.state.place].face
	panel(Rect2(78,591,1285,203),Color("e5dcc3"))
	image_at(portrait_art,Rect2(88,503,258,284))
	label(d.name,Rect2(365,607,800,34),25,INK)
	prose(d.text,Rect2(365,651,940,69),20,Color("403324"))
	button("×",Rect2(1304,603,40,38),func(): dialogue_open=false; render())
	var choices: Array = d.choices if not navigating and (region != "嘉興鎮" or stage.is_near_npc()) else []
	if choices.is_empty(): label("點街道繼續探索，或查閱記事與地圖。",Rect2(365,741,930,28),18,Color("6f5d42"))
	var width := minf(740,950.0/maxi(1,choices.size())-10)
	for i in choices.size():
		var key: String = choices[i][1]
		button(choices[i][0],Rect2(365+i*(width+10),735,width,42),func():
			if key == "@road": start_battle("road_"+region)
			elif key == "@return": travel("青溪客棧")
			else: choose(key),i==0)

func travel(destination: String) -> void:
	if not boot_ready or battle != null or not Chapter.PLACES.has(destination): return
	if Atlas.ensure(campaign).region == "嘉興鎮" and destination == campaign.state.place and stage.is_near_npc(): dialogue_open=true; render(); return
	dialogue_open=false
	Atlas.ensure(campaign).region = "嘉興鎮"
	page = "江湖"
	campaign.state.study = ""
	job_clock = 0
	if stage.avatar == Vector2.ZERO: stage.avatar = stage.town.anchors[campaign.state.place]
	navigating = stage.go_to(destination)
	notice = "正沿街前往%s；可點另一位人物更改路線。" % destination
	render()

func _arrived(destination: String) -> void:
	dialogue_open = true
	campaign.state.place = destination
	navigating = false
	notice = "抵達%s。%s" % [destination,"可在右側繼續今日活動。" if daily_focus != "" else "可與眼前的人交談。"]
	Bgm.set_scene_context("wild" if destination in ["渡口","蘆葦蕩"] else ("dungeon" if destination == "舊倉" else "town"))
	persist()
	render()

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
	label("相識 %d 人 · 四人出戰 · 主角須留隊" % campaign.state.roster.size(),Rect2(650,99,550,30),18,MUTED)
	button("上一頁",Rect2(1115,94,135,38),func(): roster_page=maxi(0,roster_page-1); render(),false,roster_page==0)
	button("下一頁",Rect2(1260,94,135,38),func(): roster_page=mini(2,roster_page+1); render(),false,roster_page>=2)
	for i in 4:
		var roster: Array = ["hero","sword","healer","staff","blade","palm","doctor","taoist","monk","wanderer"]
		if roster_page*4+i >= roster.size(): break
		var id: String = roster[roster_page*4+i]
		var recruited: bool = id in campaign.state.roster
		var x := 26+i*350
		panel(Rect2(x,151,338,182),Color("26443b") if hero_id == id else INK)
		image_at(Chapter.HEROES[id].art,Rect2(x+8,157,106,166))
		label(Chapter.HEROES[id].name,Rect2(x+121,167,207,36),25,GOLD)
		label(Chapter.HEROES[id].role,Rect2(x+121,210,210,30),17,MUTED)
		button("查看 · %d 重" % int(campaign.state.levels[id]) if recruited else "尚未相識",Rect2(x+121,266,200,45),func(): hero_id=id; render(),hero_id==id,not recruited)
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
	label("%s · %s路" % ["前排護陣" if u.front else "後排支援",["上","中","下"][int(u.lane)]],Rect2(498,647,860,30),18)
	var cost := 12+int(campaign.state.levels[hero_id])*3
	button("消點進修 · %d 學點" % cost,Rect2(498,698,290,43),func(): notice=campaign.train(hero_id); persist(); render(),false,campaign.state.place!="演武坪")
	button("停止自修" if campaign.state.study != "" else "自修 · 每 5 秒一重",Rect2(803,698,290,43),toggle_study,true)
	button("前往師父",Rect2(1108,698,280,43),func(): travel("演武坪"))
	label("本章自修耗 8＋重數×3 學點，消點耗 12＋重數×3；兩者均提升戰鬥屬性，上限三十重。",Rect2(498,752,887,25),16,MUTED)

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
	panel(Rect2(895,163,520,498))
	item_image(items.find(inventory_selection),Rect2(929,191,92,92))
	label(inventory_selection,Rect2(1033,208,340,42),29,GOLD)
	var data: Dictionary = Chapter.SHOP[inventory_selection]
	prose(data.desc,Rect2(932,369,433,90),22,PAPER)
	label("持有 %d　·　買入 %d 銀／售出 %d 銀" % [int(campaign.state.inventory.get(inventory_selection,0)),int(data.price),int(data.sell)],Rect2(932,475,445,30),18,MUTED)
	button("購買 · %d 銀" % int(data.price),Rect2(930,289,211,47),func(): notice=campaign.trade(inventory_selection,true); persist(); render(),true,campaign.state.place!="市集")
	button("出售 · %d 銀" % int(data.sell),Rect2(1160,289,220,47),func(): notice=campaign.trade(inventory_selection,false); persist(); render(),false,campaign.state.place!="市集" or campaign.state.inventory.get(inventory_selection,0)<1)
	prose("戰鬥中每回合全隊限用一次藥。\n抵達市集後，掌櫃會按標價買賣。",Rect2(932,544,435,70),18,MUTED)
	button("前往市集 · 與掌櫃交易",Rect2(33,688,430,50),func(): travel("市集"),true)
	button("前往蘆葦蕩 · 採藥",Rect2(487,688,430,50),func(): travel("蘆葦蕩"))
	button("前往藥廬 · 交付草藥",Rect2(944,688,465,50),func(): travel("藥廬"))

func render_journal() -> void:
	label("江 湖 誌",Rect2(34,92,760,42),30)
	panel(Rect2(28,152,440,632))
	label(campaign.objective()[0],Rect2(52,180,390,40),28,GOLD)
	prose(campaign.objective()[2],Rect2(52,241,390,112),22)
	button("前往下一條線索",Rect2(53,375,390,48),func(): travel(campaign.objective()[1]),true)
	label("支線 · 救急藥方",Rect2(52,474,390,36),24,GOLD)
	prose("已完成：青棠收下草藥。" if campaign.state.flags.get("herbs",false) else "在蘆葦蕩採三株草藥，交給藥廬的沈青棠，可得兩瓶金創藥與 25 學點。",Rect2(52,529,390,145),21,MUTED)
	panel(Rect2(487,152,925,632))
	label("走過的路",Rect2(515,176,860,40),25,GOLD)
	var entries: Array = campaign.state.journal.duplicate()
	entries.reverse()
	var text := "雨夜，你帶著一封舊信踏進青溪。第一個線索，在客棧窗邊。"
	if not entries.is_empty(): text = "\n\n".join(entries)
	prose(text,Rect2(515,240,863,510),22)

func render_atlas() -> void:
	label("山 河 行 旅",Rect2(30,88,500,42),30,GOLD)
	button("武林論劍"+(" · 盟主" if campaign.state.flags.get("supremacy",false) else ""),Rect2(600,87,450,42),challenge_supremacy,true)
	button("每日必做",Rect2(1080,87,160,42),func(): set_page("每日"))
	button("返回江湖",Rect2(1252,87,160,42),func(): set_page("江湖"))
	var map_rect := Rect2(27,152,835,626)
	var background := TextureRect.new()
	background.texture = bank.get_asset("res://assets/town/world.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(background,map_rect)
	var data := Atlas.ensure(campaign)
	for name in Atlas.REGIONS:
		var r: Dictionary = Atlas.REGIONS[name]
		var p: Vector2 = map_rect.position+r.point*map_rect.size/Vector2(640,480)
		var opened: bool = campaign.state.stage >= r.stage
		var mark := "◆" if world_selection == name else ("✓" if name in data.cleared else ("" if opened else "鎖"))
		var b := button(mark,Rect2(p-Vector2(17,17),Vector2(34,34)),func(): world_selection=name; render(),world_selection==name)
		b.add_theme_font_size_override("font_size",16)
		b.add_theme_color_override("font_color",INK)
		for state_name in ["normal","hover","pressed","focus"]:
			var ring := StyleBoxFlat.new()
			ring.bg_color = Color(1,.85,.4,.3) if world_selection == name or state_name == "hover" else Color(0,0,0,0)
			ring.set_corner_radius_all(17)
			ring.border_color = GOLD
			ring.set_border_width_all(2 if world_selection == name or state_name == "hover" else 0)
			b.add_theme_stylebox_override(state_name,ring)
		b.tooltip_text = name+(" · 已結案" if name in data.cleared else (" · 可前往" if opened else " · 主線第 %d 步開放" % int(r.stage)))
	panel(Rect2(880,152,532,626),Color("1c3931"))
	var region: Dictionary = Atlas.REGIONS[world_selection]
	label(world_selection,Rect2(903,169,480,45),32,GOLD)
	label("目前所在 · "+data.region,Rect2(903,224,480,30),18,MUTED)
	if world_selection == "嘉興鎮":
		prose("青溪街巷 · 選擇目的地後沿街尋路。",Rect2(903,275,480,58),20)
		var i := 0
		for place in Chapter.PLACES:
			button(place,Rect2(903+(i%2)*247,352+(i/2)*69,234,52),func(): travel(place),place==campaign.state.place)
			i += 1
		prose("◆ 主線線索　✓ 支線完成\n遠行支線隨青溪故事開放，隊伍與武學沿用。",Rect2(903,655,480,80),18,MUTED)
	else:
		label(region.title,Rect2(903,279,480,40),25)
		label("建議修為 %d 重 · %s" % [Atlas.POWER[world_selection],"可招募 "+Chapter.HEROES[Atlas.RECRUITS[world_selection]].name if Atlas.RECRUITS.has(world_selection) else "江湖支線／切磋"],Rect2(903,313,480,26),17,GOLD)
		prose(region.text+"\n\n"+region.rumor,Rect2(903,350,480,175),21)
		var unlocked: bool = campaign.state.stage >= region.stage
		prose("首次完成：75 銀、55 學點、金創藥一瓶。\n再次切磋：30 銀、25 學點。\n已探索 %d / %d 處，結案 %d 件。" % [data.visited.size(),Atlas.REGIONS.size(),data.cleared.size()],Rect2(903,540,480,110),19,MUTED)
		button("前往 · "+world_selection if unlocked else "青溪主線第 %d 步開放" % int(region.stage),Rect2(903,689,480,53),func(): journey_to(world_selection),true,not unlocked)

func challenge_supremacy() -> void:
	if campaign.state.stage < 7 or Atlas.ensure(campaign).cleared.size() < 8 or campaign.state.levels.hero < 15:
		notice = "武林論劍：先結束青溪故事、完成八處江湖支線，主角修至十五重。三位宗師建議全隊二十五重再挑戰。"
		render()
		return
	start_battle("supremacy")

func journey_to(region: String) -> void:
	if battle != null or not boot_ready or not Atlas.REGIONS.has(region) or campaign.state.stage < Atlas.REGIONS[region].stage: return
	if region == "嘉興鎮": travel("青溪客棧"); return
	stage.cancel_walk()
	navigating = false
	job_clock = 0
	campaign.state.study = ""
	notice = Atlas.visit(campaign,region)
	world_selection = region
	page = "江湖"
	dialogue_open = true
	Bgm.set_scene_context("wild")
	persist()
	render()

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
		var locked: bool = (key == "sect" and campaign.state.sect == "未入門") or (key == "dungeon" and campaign.state.stage < 6)
		var title: String = "今日完成" if done >= task.limit else ("先拜師" if key == "sect" and locked else ("先破獲失鏢案" if locked else ("前往 · "+Daily.target(campaign,key))))
		button(title,Rect2(x+472,y+116,190,43),func(): daily_action(key),true,done >= task.limit or (key == "dungeon" and locked))
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
	if key == "dungeon" and campaign.state.stage < 6: notice="先查清失鏢案，才能重戰舊倉。"; render(); return
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
	button("音效 · "+("開" if sounds.enabled else "關"),Rect2(54,458,290,43),func(): sounds.enabled=not sounds.enabled; sounds.save(); sounds.play("accept"); render())
	button("立即存檔 · F5",Rect2(366,458,298,43),func(): persist(); notice="進度已保存。"; render(),true)
	label("音效音量",Rect2(54,523,180,30),20)
	var fx_slider := HSlider.new()
	fx_slider.min_value=0
	fx_slider.max_value=100
	fx_slider.value=sounds.volume*100
	fx_slider.value_changed.connect(func(value): sounds.volume=value/100.0; sounds.save())
	at(fx_slider,Rect2(220,523,440,30))
	prose("網頁上方可匯出／匯入完整備份。青溪故事與舊版江湖角色各自保存，未完成的戰鬥與自修不跨讀檔恢復。",Rect2(54,569,610,136),21,MUTED)
	panel(Rect2(723,151,689,632))
	label("戰鬥怎麼玩",Rect2(750,175,630,40),27,GOLD)
	prose("一、戰前在同伴頁調整前後排、上中下路與三門武學。\n\n二、每輪先替同伴選擇普攻、施招或守勢，再按「進行回合」。按速度先後出手。\n\n三、任一方普攻，全體存活者聚氣。25 真元為一格，施招需足夠真元與調息完成。\n\n四、近戰先打前排，飛燕穿雲能越陣。寨主蓄力時用陸衡封招；沈青棠療傷解毒；主角追擊流血與破甲。",Rect2(750,238,632,355),21)
	prose("青溪新章目前為單機隊伍；原有 Steam／區網、任務、副本與生活技能保留在舊版江湖。",Rect2(750,611,632,73),18,MUTED)
	button("進入舊版江湖 · F9",Rect2(750,710,630,47),func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))

func start_battle(kind: String) -> void:
	if not boot_ready or battle != null or job_clock > 0: return
	if kind == "supremacy" and (campaign.state.stage < 7 or Atlas.ensure(campaign).cleared.size() < 8 or campaign.state.levels.hero < 15): return
	if kind.begins_with("road_"):
		var region := kind.trim_prefix("road_")
		if Atlas.ensure(campaign).region != region or not Atlas.REGIONS.has(region) or campaign.state.stage < Atlas.REGIONS[region].stage: return
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
	battle = null
	stage.battle = null
	stage.selected = ""
	page = "江湖"
	if defeated:
		campaign.state.place = "青溪客棧"
		Atlas.ensure(campaign).region = "嘉興鎮"
	stage.cancel_walk()
	Bgm.set_scene_context("town")
	persist()
	render()

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
	button("音樂 " + ("開" if Bgm.enabled else "關"),Rect2(920,90,164,43),func(): Bgm.set_enabled(not Bgm.enabled); render())
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
