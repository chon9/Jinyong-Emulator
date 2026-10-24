extends Control
## Character-first Godot campaign UI, shared by desktop and the browser export.
const Chapter = preload("res://scripts/journey/chapter.gd")
const Battle = preload("res://scripts/journey/battle.gd")
const Stage = preload("res://scripts/journey/stage.gd")
const INK := Color("162d2b")
const PAPER := Color("ebe3ce")
const GOLD := Color("d7b77b")
const MUTED := Color("a8b8a9")
var campaign
var battle
var stage
var layer: Control
var page := "江湖"
var hero_id := "hero"
var selected_enemy := ""
var selected_ally := "hero"
var notice := "雨停之前，先向窗邊的顧長風打聽失鏢。"
var auto_battle := false
var action_clock := 0.0
var study_clock := 0.0
var result_applied := false
var dialogue_open := true
var font: Font
var navigating := false

func _ready() -> void:
	font = load("res://assets/fonts/LXGWWenKaiTC-Regular.ttf")
	var theme_value := Theme.new()
	theme_value.default_font = font
	theme_value.default_font_size = 19
	theme = theme_value
	campaign = Chapter.new(Session.chapter_data)
	stage = Stage.new()
	stage.clip_contents = true
	stage.campaign = campaign
	add_child(stage)
	stage.place_selected.connect(travel)
	stage.unit_selected.connect(select_unit)
	Session.chapter_imported.connect(_imported)
	get_tree().root.focus_exited.connect(persist)
	render()
	persist()

func _exit_tree() -> void:
	persist()
	if is_instance_valid(Bgm): Bgm.set_scene_context("")

func _imported() -> void:
	campaign = Chapter.new(Session.chapter_data)
	stage.campaign = campaign
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
	if campaign == null: return
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
			else: set_page("江湖")
		KEY_SPACE:
			if battle != null: play_round()
		KEY_F5: persist(); notice = "進度已保存。"; render()
		KEY_F8: set_page("設定")
		KEY_F9: get_tree().change_scene_to_file("res://scenes/main.tscn")

func at(node: Control, rect: Rect2, parent: Node = null) -> Control:
	(parent if parent != null else layer).add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node

func style(bg: Color = INK, border: Color = Color("506250"), width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func panel(rect: Rect2, color: Color = INK, parent: Node = null) -> Panel:
	var box := Panel.new()
	box.add_theme_stylebox_override("panel",style(color))
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
	b.add_theme_stylebox_override("normal",style(Color("b59a65") if primary else Color("24413a"),GOLD if primary else Color("536453")))
	b.add_theme_stylebox_override("hover",style(Color("d2b77e") if primary else Color("385a49"),GOLD,2))
	b.add_theme_stylebox_override("pressed",style(Color("927b51") if primary else Color("152c29"),GOLD,2))
	b.add_theme_stylebox_override("disabled",style(Color("24332f"),Color("3b4c40")))
	b.add_theme_stylebox_override("focus",style(Color(0,0,0,0),GOLD,2))
	b.add_theme_color_override("font_color",INK if primary else PAPER)
	b.add_theme_color_override("font_hover_color",INK if primary else Color.WHITE)
	b.add_theme_color_override("font_disabled_color",Color("708376"))
	b.add_theme_font_size_override("font_size",18)
	b.disabled = disabled
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(callback)
	at(b,rect,parent)
	return b

func image_at(art: String, rect: Rect2, parent: Node = null) -> void:
	var node := TextureRect.new()
	node.texture = stage.tex(art+"_idle")
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(node,rect,parent)

func bar(value: float, maximum: float, rect: Rect2, color: Color) -> void:
	var node := ProgressBar.new()
	node.max_value = maximum
	node.value = value
	node.show_percentage = false
	var background := style(Color("102925"),Color("435648"))
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
	if layer != null:
		layer.hide()
		layer.queue_free()
	# The backdrop sits behind the persistent Stage, so battle tweens never reset.
	if not has_node("Backdrop"):
		var bg := ColorRect.new()
		bg.name = "Backdrop"
		bg.color = Color("0e2422")
		bg.size = Vector2(1440,900)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		move_child(bg,0)
	layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = Vector2(1440,900)
	add_child(layer)
	panel(Rect2(0,0,1440,76),Color("132d29"))
	label("網 金 游 俠",Rect2(28,11,250,42),32,GOLD)
	label("青溪失鏢  /  第一章",Rect2(275,19,310,30),18,MUTED)
	label("銀兩  %d     學點  %d     %s" % [campaign.state.silver,campaign.state.potential,campaign.state.sect],Rect2(810,19,475,32),19)
	button("音樂 " + ("開" if Bgm.enabled else "關"),Rect2(1290,15,122,44),func(): Bgm.set_enabled(not Bgm.enabled); render())
	stage.visible = page == "江湖" or battle != null
	if battle != null:
		render_battle()
	elif page == "江湖": render_world()
	elif page in ["同伴","武學"]: render_party()
	elif page == "行囊": render_inventory()
	elif page == "江湖誌": render_journal()
	elif page == "設定": render_settings()
	if battle == null:
		panel(Rect2(24,807,1392,72),Color("132d29"))
		var tabs := ["江湖","同伴","武學","行囊","江湖誌","設定"]
		for i in tabs.size():
			var tab: String = tabs[i]
			button(tab,Rect2(42+i*174,821,160,43),func(): set_page(tab),tab==page)
		label("F5 存檔  ·  F8 設定",Rect2(1120,830,270,30),17,MUTED)
	if battle == null:
		label(notice,Rect2(35,880,1370,20),15,GOLD)
	update_browser_status()

func update_browser_status() -> void:
	if not OS.has_feature("web"): return
	var status := {"page":page,"place":campaign.state.place,"stage":int(campaign.state.stage),"party":campaign.state.party.size(),"battle":"" if battle == null else (battle.result if battle.result != "" else "active"),"round":0 if battle == null else battle.round_no,"notice":notice}
	JavaScriptBridge.eval("window.youxiaChapterStatus = Object.freeze("+JSON.stringify(status)+");",true)
	var window := JavaScriptBridge.get_interface("window")
	if window.youxiaSetStatus != null: window.youxiaSetStatus("無名少俠",campaign.state.place,page,"青溪故事 · 單機")

func set_page(value: String) -> void:
	if battle != null: return
	page = value
	render()

func render_world() -> void:
	label("江湖在眼前，故事在路上",Rect2(32,86,760,40),28)
	label("青溪八景  ·  點地圖移動，抵達後直接交談",Rect2(770,96,650,28),17,MUTED)
	stage.position = Vector2(24,137)
	stage.size = Vector2(1034,468)
	panel(Rect2(1074,137,342,468),Color("19362f"))
	label("主 線  ·  %d / 7" % mini(int(campaign.state.stage)+1,7),Rect2(1096,154,294,30),17,GOLD)
	label(campaign.objective()[0],Rect2(1096,192,294,40),27)
	prose(campaign.objective()[2],Rect2(1096,240,293,66),19,MUTED)
	var target: String = campaign.objective()[1]
	button("交談 · 推進故事" if target == campaign.state.place else "前往 · "+target,Rect2(1095,314,300,44),quest_action,true)
	label("同行的人  %d / 4" % campaign.state.party.size(),Rect2(1096,378,290,30),18,GOLD)
	for i in campaign.state.party.size():
		var id: String = campaign.state.party[i]
		image_at(Chapter.HEROES[id].art,Rect2(1095+i*74,418,68,94))
		label(Chapter.HEROES[id].name.left(3),Rect2(1095+i*74,519,74,27),16)
	label("點同伴查看身世、武功與陣位",Rect2(1096,564,300,26),16,MUTED)
	render_dialogue()

func quest_action() -> void:
	var target: String = campaign.objective()[1]
	if target != campaign.state.place:
		travel(target)
		return
	var choices: Array = campaign.talk().choices
	if choices.is_empty():
		notice = "這裡的故事已告一段落，繼續探索或研習武學。"
	elif campaign.state.stage == 5:
		notice = "請在下方對話中選擇處置方式；你的選擇會改變即將開始的戰鬥。"
	else:
		choose(choices[0][1])
		return
	render()

func render_dialogue() -> void:
	var d: Dictionary = campaign.talk()
	panel(Rect2(24,620,1392,173),Color("e5dcc3"))
	image_at(Chapter.PLACES[campaign.state.place].face,Rect2(43,626,144,160))
	label(d.name+"  /  "+campaign.state.place,Rect2(208,631,1100,32),23,INK)
	prose(d.text,Rect2(208,671,1178,65),19,Color("394535"))
	var choices: Array = d.choices
	if choices.is_empty():
		label("點地圖繼續探索；右側主線會指出下一條線索。",Rect2(208,752,1165,30),18,Color("68745c"))
	else:
		var width := minf(570,1168.0/choices.size()-10)
		for i in choices.size():
			var key: String = choices[i][1]
			button(choices[i][0],Rect2(208+i*(width+10),744,width,39),func(): choose(key),i==0)

func route_to(destination: String) -> Array:
	var pending := [[campaign.state.place]]
	var seen := {}
	while not pending.is_empty():
		var path: Array = pending.pop_front()
		var last: String = path[-1]
		if last == destination: return path
		if seen.has(last): continue
		seen[last] = true
		for neighbor in Chapter.PLACES[last].links:
			if not seen.has(neighbor): pending.append(path+[neighbor])
	return []

func travel(destination: String) -> void:
	if battle != null or navigating or not Chapter.PLACES.has(destination): return
	var path := route_to(destination)
	if path.is_empty(): return
	page = "江湖"
	campaign.state.study = ""
	navigating = true
	for location in path:
		campaign.state.place = location
		notice = "抵達%s。" % location
		render()
		Bgm.set_scene_context("wild" if location in ["渡口","蘆葦蕩"] else ("dungeon" if location == "舊倉" else "town"))
		await get_tree().create_timer(.22).timeout
	navigating = false
	persist()

func choose(key: String) -> void:
	if battle != null or navigating: return
	# Validate that this choice still belongs to the visible conversation.
	var allowed := false
	for option in campaign.talk().choices:
		if option[1] == key: allowed = true
	if not allowed: return
	if key.begins_with("battle_"):
		start_battle(key.trim_prefix("battle_"))
		return
	notice = campaign.choose(key)
	if key.begins_with("choose_"): start_battle("warehouse")
	else:
		persist()
		render()

func render_party() -> void:
	label("同行，各有所長" if page == "同伴" else "武道，始於一招一式",Rect2(34,91,700,43),30)
	label("外功配兵器，內功養聚氣，輕功定先後",Rect2(800,99,600,30),19,MUTED)
	for i in 4:
		var id: String = ["hero","sword","healer","staff"][i]
		var recruited: bool = id in campaign.state.party
		var x := 26+i*350
		panel(Rect2(x,151,338,182),Color("26443b") if hero_id == id else INK)
		image_at(Chapter.HEROES[id].art,Rect2(x+8,157,106,166))
		label(Chapter.HEROES[id].name,Rect2(x+121,167,207,36),25,GOLD)
		label(Chapter.HEROES[id].role,Rect2(x+121,210,210,30),17,MUTED)
		button("查看 · %d 重" % int(campaign.state.levels[id]) if recruited else "尚未相識",Rect2(x+121,266,200,45),func(): hero_id=id; render(),hero_id==id,not recruited)
	if not hero_id in campaign.state.party: hero_id = "hero"
	var u: Dictionary = campaign.unit(hero_id)
	panel(Rect2(26,350,435,438))
	label("身 世 與 天 賦",Rect2(48,368,390,34),21,GOLD)
	prose(u.bio,Rect2(48,416,390,90),20)
	prose(u.talent,Rect2(48,524,390,70),19,MUTED)
	label("氣血 %d   攻擊 %d   防禦 %d" % [u.max_hp,u.atk,u.def],Rect2(48,615,390,32),18)
	label("速度 %d   聚氣 %d   兵器 · %s" % [u.speed,u.qi,u.weapon],Rect2(48,653,390,32),18)
	button("輪換前／後排",Rect2(48,714,190,46),func(): campaign.position_hero(hero_id,int(u.lane),not u.front); persist(); render())
	button("換上／中／下路",Rect2(249,714,190,46),func(): campaign.position_hero(hero_id,(int(u.lane)+1)%3,u.front); persist(); render())
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
	label("本章自修耗 8＋重數×3 學點，消點耗 12＋重數×3；兩者均提升戰鬥屬性，上限十重。",Rect2(498,752,887,25),16,MUTED)

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

func render_inventory() -> void:
	label("行囊與市集",Rect2(34,90,720,43),30)
	prose("藥要用在刀鋒落下之前。戰鬥中每回合可使用一瓶金創藥；其餘時間回鎮療傷，隊伍下次出發時氣血全滿。",Rect2(35,145,1340,68),21,MUTED)
	var i := 0
	for item in Chapter.SHOP:
		var data: Dictionary = Chapter.SHOP[item]
		var y := 255+i*195
		panel(Rect2(28,y,1384,176))
		label(item+"  × "+str(int(campaign.state.inventory.get(item,0))),Rect2(54,y+16,500,40),28,GOLD)
		prose(data.desc,Rect2(54,y+71,810,70),21)
		button("購買 · %d 銀" % int(data.price),Rect2(930,y+34,211,47),func(): notice=campaign.trade(item,true); persist(); render(),true,campaign.state.place!="市集")
		button("出售 · %d 銀" % int(data.sell),Rect2(1160,y+34,220,47),func(): notice=campaign.trade(item,false); persist(); render(),false,campaign.state.place!="市集" or campaign.state.inventory.get(item,0)<1)
		i += 1
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
	button("立即存檔 · F5",Rect2(54,486,610,48),func(): persist(); notice="進度已保存。"; render(),true)
	prose("網頁上方可匯出／匯入完整備份。青溪故事與舊版江湖角色各自保存，未完成的戰鬥與自修不跨讀檔恢復。",Rect2(54,569,610,136),21,MUTED)
	panel(Rect2(723,151,689,632))
	label("戰鬥怎麼玩",Rect2(750,175,630,40),27,GOLD)
	prose("一、戰前在同伴頁調整前後排、上中下路與三門武學。\n\n二、每輪先替同伴選擇普攻、施招或守勢，再按「進行回合」。按速度先後出手。\n\n三、任一方普攻，全體存活者聚氣。25 真元為一格，施招需足夠真元與調息完成。\n\n四、近戰先打前排，飛燕穿雲能越陣。寨主蓄力時用陸衡封招；沈青棠療傷解毒；主角追擊流血與破甲。",Rect2(750,238,632,355),21)
	prose("青溪新章目前為單機隊伍；原有 Steam／區網、任務、副本與生活技能保留在舊版江湖。",Rect2(750,611,632,73),18,MUTED)
	button("進入舊版江湖 · F9",Rect2(750,710,630,47),func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))

func start_battle(kind: String) -> void:
	campaign.state.study = ""
	battle = Battle.new(campaign,kind)
	stage.battle = battle
	selected_enemy = battle.living(1)[0].id
	selected_ally = "hero"
	stage.selected = selected_enemy
	auto_battle = false
	result_applied = false
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
		campaign.win(battle.encounter)
		notice = "此戰告捷 · 30 銀、25 學點。回鎮後全隊療傷。"
	else: notice = "暫且退回鎮上。試著調整前排、配金鐘心法，或留真元打斷首領。沒有扣除銀兩與修為。"
	persist()

func leave_battle() -> void:
	if battle == null: return
	var defeated: bool = battle.result != "victory"
	battle = null
	stage.battle = null
	stage.selected = ""
	page = "江湖"
	if defeated: campaign.state.place = "青溪客棧"
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
	stage.position = Vector2(24,131)
	stage.size = Vector2(1392,429)
	var ready: bool = battle.queue.is_empty() and battle.result == ""
	if battle.by_id(selected_enemy).get("hp",0) <= 0 and not battle.living(1).is_empty(): selected_enemy = battle.living(1)[0].id
	label("第 %02d 回合" % battle.round_no,Rect2(32,87,230,36),28,GOLD)
	label("%s  ·  %s" % ["黑風對峙" if battle.encounter in ["warehouse","rematch"] else "青溪遇襲","準備施招" if ready else "依速度出手"],Rect2(290,93,700,32),20)
	button("委託 · 開" if auto_battle else "委託 · 關",Rect2(1040,85,170,38),func(): auto_battle=not auto_battle; render(),auto_battle)
	button("進行回合  [空白]",Rect2(1220,85,195,38),play_round,true,not ready)
	for i in campaign.state.party.size():
		var id: String = campaign.state.party[i]
		var u: Dictionary = battle.by_id(id)
		var x: float = 25+i*350
		panel(Rect2(x,573,339,231),Color("29473c") if selected_ally == id else INK)
		button(u.name,Rect2(x+12,582,138,33),func(): select_unit(id),selected_ally==id,u.hp<=0)
		label("%d / %d" % [u.hp,u.max_hp],Rect2(x+164,585,160,26),18)
		bar(u.hp,u.max_hp,Rect2(x+14,623,310,8),Color("9ebd8a"))
		bar(u.energy,100,Rect2(x+14,641,310,7),Color("739ba7"))
		var art: Dictionary = Chapter.ARTS[u.outer]
		var reason: String = battle.cast_reason(id)
		var command: Dictionary = battle.orders.get(id,{"action":"attack","target":""})
		label("真元 %d  ·  聚氣 +%d  ·  %s" % [u.energy,u.qi,"守勢" if command.action == "guard" else ("施招" if command.action == "skill" else "普攻")],Rect2(x+14,653,310,29),16,MUTED)
		var skill := button(art.skill+" · %d 格" % (int(art.cost)/25),Rect2(x+13,691,310,41),func(): queue_order(id,"skill"),command.action=="skill",not ready or reason!="")
		skill.tooltip_text = art.text+"\n消耗 %d 真元，調息 %d 回合。" % [art.cost,art.cd]
		button("普攻",Rect2(x+13,740,94,42),func(): queue_order(id,"attack"),false,not ready or u.hp<=0)
		button("守勢",Rect2(x+115,740,94,42),func(): queue_order(id,"guard"),false,not ready or u.hp<=0)
		label(reason if reason!="" else "施招可用",Rect2(x+217,746,115,30),15,GOLD if reason=="" else MUTED)
	panel(Rect2(24,817,1392,61),Color("19362f"))
	var target: Dictionary = battle.by_id(selected_enemy)
	var target_text: String = target.name+" · "+target.intent if not target.is_empty() else "點敵人選目標"
	label(target_text,Rect2(40,832,830,34),18,GOLD)
	button("金創藥 ×%d" % int(campaign.state.inventory.get("金創藥",0)),Rect2(905,827,230,42),use_medicine,false,not ready or battle.medicine_used)
	button("收拾行裝，繼續故事" if battle.result=="victory" else ("退回客棧" if battle.result!="" else "撤退"),Rect2(1150,827,250,42),leave_battle,battle.result!="",not battle.queue.is_empty() and battle.result=="")
	label(notice,Rect2(32,881,1380,19),15,PAPER)
	if battle.result != "":
		panel(Rect2(480,250,480,180),Color(.075,.17,.15,.97))
		label("此 戰 告 捷" if battle.result=="victory" else "勝 敗 乃 兵 家 常 事",Rect2(515,267,430,45),31,GOLD)
		label("30 銀  ·  25 學點" if battle.result=="victory" else "調整武學與陣型，再戰江湖。",Rect2(515,326,430,34),22)
		button("繼續故事" if battle.result=="victory" else "回鎮療傷",Rect2(514,378,412,39),leave_battle,true)
