extends RefCounted
## Classic client arrangement, adapted to the simulator's text controls.

static func at(control: Control, rect: Rect2, parent: Node) -> Control:
	parent.add_child(control)
	control.position = rect.position
	control.size = rect.size
	return control

static func panel(rect: Rect2, kind: int, parent: Node) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", ClassicFrame.style(kind))
	at(node, rect, parent)
	return node

static func column(parent: Node, separation: int = 8) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	parent.add_child(node)
	return node

static func build(ui) -> void:
	ui.backdrop = TextureRect.new()
	ui.backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ui.backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	at(ui.backdrop, Rect2(0, 0, 1440, 900), ui)
	ui.backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var veil := ColorRect.new()
	veil.color = Color(.08, .05, .02, .36)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(veil, Rect2(0, 0, 1440, 718), ui)
	at(ui.label("網 金 游 俠", 30, ui.GOLD), Rect2(28, 15, 300, 42), ui)
	ui.clock_label = ui.label("", 16)
	at(ui.clock_label, Rect2(450, 24, 530, 30), ui)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 7)
	at(navigation, Rect2(20, 64, 1000, 36), ui)
	var navigation_names := ["江湖", "任務", "商店", "行囊", "武學", "地圖", "人際", "系統"]
	var navigation_indexes := [0, 3, 7, 2, 1, 4, 6, 5]
	for i in navigation_names.size():
		var index: int = navigation_indexes[i]
		var nav: Button = ui.button(navigation_names[i], func(): ui.open_page(index), navigation)
		nav.custom_minimum_size = Vector2(114, 34)
		nav.toggle_mode = true
		nav.tooltip_text = "Ctrl+" + str(i + 1)
		ui.nav_buttons[index] = nav
	ui.narrative = panel(Rect2(20, 110, 1000, 142), ClassicFrame.Kind.INK, ui)
	var journal := column(ui.narrative, 6)
	var log_header = ui.row(journal)
	log_header.add_child(ui.label("江湖紀事", 17, ui.GOLD))
	ui.filter = OptionButton.new()
	for name in ["全部", "戰鬥", "武學", "故事", "收穫", "人際"]: ui.filter.add_item(name)
	log_header.add_child(ui.filter)
	ui.filter.item_selected.connect(func(_index: int): ui._render_log())
	ui.button("清除", func(): ui.history.clear(); ui._render_log(), log_header)
	ui.log_view = ui.rich()
	ui.log_view.scroll_following = true
	journal.add_child(ui.log_view)
	ui.scene_panel = panel(Rect2(20, 264, 1000, 128), ClassicFrame.Kind.SCROLL_SMALL, ui)
	var location := column(ui.scene_panel, 2)
	ui.location_label = ui.label("", 23, Color("9e3728"))
	location.add_child(ui.location_label)
	ui.location_desc = ui.paragraph("", Color("332b1c"))
	location.add_child(ui.location_desc)
	ui.encounter = ui.label("", 14, Color("665332"))
	location.add_child(ui.encounter)
	ui.workspace = panel(Rect2(20, 404, 1000, 298), ClassicFrame.Kind.SCROLL_SMALL, ui)
	ui.tabs = TabContainer.new()
	ui.tabs.tabs_visible = false
	ui.tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	ui.workspace.add_child(ui.tabs)
	for title in ["江湖", "武學", "行囊", "故事", "圖鑑", "聯機", "人際", "商店"]:
		var scroll := ScrollContainer.new()
		scroll.name = title
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		ui.tabs.add_child(scroll)
		var body := column(scroll, 10)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ui.pages[title] = scroll
		ui.page_bodies[title] = body
	ui.tabs.tab_changed.connect(func(_index: int): ui._refresh())
	ui._build_network(ui.page_bodies["聯機"])
	var social_panel := panel(Rect2(1034, 18, 320, 280), ClassicFrame.Kind.JADE_SMALL, ui)
	var social := column(social_panel, 7)
	social.add_child(ui.label("同在江湖 · 隊伍", 18, ui.GOLD))
	ui.roster = ui.rich()
	social.add_child(ui.roster)
	ui.task_text = ui.rich()
	ui.task_text.custom_minimum_size.y = 50
	ui.task_text.size_flags_vertical = Control.SIZE_SHRINK_END
	ui.task_text.add_theme_font_size_override("normal_font_size", 13)
	social.add_child(ui.task_text)
	var social_actions = ui.row(social)
	ui.button("組隊／切磋／交易", func(): ui.tabs.current_tab = 6, social_actions)
	ui.action("離隊", "離隊", "", social_actions)
	var automation_panel := panel(Rect2(1034, 312, 320, 390), ClassicFrame.Kind.JADE_SMALL, ui)
	var automation := column(automation_panel, 7)
	automation.add_child(ui.label("游俠控制台", 18, ui.GOLD))
	ui.auto_status = ui.label("", 17)
	automation.add_child(ui.auto_status)
	var modes = ui.row(automation)
	ui.action("自動刷怪", "掛機", "刷怪", modes)
	ui.action("停止", "停止", "", modes)
	ui.check_heal = CheckBox.new()
	ui.check_heal.text = "氣血 ≤ 45% 自動服金創藥"
	ui.check_heal.add_theme_font_size_override("font_size", 14)
	ui.check_heal.toggled.connect(func(on: bool):
		if not ui.refresh_lock: Session.send("補血設定", "開啟" if on else "關閉"))
	automation.add_child(ui.check_heal)
	ui.auto_skill = OptionButton.new()
	ui.auto_skill.item_selected.connect(func(index: int):
		if not ui.refresh_lock: Session.send("修練設定", ui.auto_skill.get_item_text(index)))
	automation.add_child(ui.auto_skill)
	var study = ui.row(automation)
	ui.button("自修", func(): Session.send("自修", ui.auto_skill.get_item_text(ui.auto_skill.selected)), study)
	ui.action("自動消點", "掛機", "消點", study)
	ui.action("打坐調息", "打坐", "", study)
	automation.add_child(ui.label("對戰策略", 15, ui.GOLD))
	var stances = ui.row(automation)
	for value in ["普通", "重擊", "防守"]: ui.action(value, "招式", value, stances)
	var battle = ui.row(automation)
	ui.action("尋敵", "打怪", "", battle)
	ui.action("逃跑", "逃跑", "", battle)
	ui.action("認輸", "認輸", "", battle)
	automation.add_child(ui.paragraph("隊友同地點可共同迎戰。\n切磋需接受邀請，野外 PK 需雙方開啟。"))
	var lanterns := VBoxContainer.new()
	lanterns.add_theme_constant_override("separation", 6)
	at(lanterns, Rect2(1368, 38, 54, 650), ui)
	var names := navigation_names
	var indexes := navigation_indexes
	for i in names.size():
		var lantern := ClassicButton.new(ClassicButton.Style.LANTERN, names[i])
		lantern.custom_minimum_size = Vector2(52, 70)
		lantern.tooltip_text = names[i] + "（Ctrl+" + str(i + 1) + "）"
		var selected: int = indexes[i]
		lantern.pressed.connect(func(): ui.tabs.current_tab = selected)
		lanterns.add_child(lantern)
	var hud := panel(Rect2(0, 718, 1440, 182), ClassicFrame.Kind.HUD, ui)
	# HUD children use a neutral Control so each part follows the classic arrangement.
	var hud_canvas := Control.new()
	hud.add_child(hud_canvas)
	ui.heading = ui.label("", 19, ui.GOLD)
	at(ui.heading, Rect2(8, 0, 268, 26), hud_canvas)
	for i in 3:
		var key: String = ["energy", "hp", "mp"][i]
		var line := HBoxContainer.new()
		at(line, Rect2(8, 30 + i * 30, 268, 27), hud_canvas)
		line.add_child(ui.label(["精", "氣", "內力"][i], 16))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 24
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ClassicTheme.vital_bar(bar, [Color("249424"), Color("b83232"), Color("3245b8")][i], [Color("9db02b"), Color("dc9494"), Color("969de0")][i])
		line.add_child(bar)
		var number: Label = ui.label("", 14)
		bar.add_child(number)
		number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number.add_theme_color_override("font_outline_color", Color("201b10"))
		number.add_theme_constant_override("outline_size", 2)
		ui.vital_labels[key] = number
		ui.vital_bars[key] = bar
	ui.vitals = ui.rich()
	ui.vitals.add_theme_font_size_override("normal_font_size", 13)
	at(ui.vitals, Rect2(8, 123, 268, 38), hud_canvas)
	var plaque: Label = ui.label("初入江湖，請多指教", 15, ui.GOLD)
	ui.notice_label = plaque
	plaque.clip_text = true
	plaque.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	at(plaque, Rect2(296, 0, 700, 25), hud_canvas)
	var hotbar := HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 7)
	at(hotbar, Rect2(296, 29, 696, 53), hud_canvas)
	var actions: Array = [func(): Session.send("自修", ui.auto_skill.get_item_text(ui.auto_skill.selected)), func(): Session.send("打坐"), func(): Session.send("打怪"), func(): Session.send("使用", "金創藥"), func(): ui._save(), func(): ui.tabs.current_tab = 0, func(): ui.tabs.current_tab = 6, func(): ui.tabs.current_tab = 5]
	var titles := ["自修", "回氣", "尋敵", "金創", "存檔", "江湖", "人際", "聯機"]
	for i in actions.size():
		var hot := ClassicButton.new(ClassicButton.Style.SLOT, titles[i])
		hot.hotkey_text = "F" + str(i + 1)
		hot.custom_minimum_size = Vector2(74, 52)
		hot.pressed.connect(actions[i])
		hotbar.add_child(hot)
		ui.hot_actions.append(actions[i])
	var commands := HBoxContainer.new()
	at(commands, Rect2(296, 88, 696, 30), hud_canvas)
	ui.command_line = LineEdit.new()
	ui.command_line.placeholder_text = "指令：拜師 武當／消點 武功／幫助"
	ui.command_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commands.add_child(ui.command_line)
	ui.command_line.text_submitted.connect(ui._command)
	ui.button("執行", func(): ui._command(ui.command_line.text), commands)
	var chat_input := HBoxContainer.new()
	at(chat_input, Rect2(296, 125, 696, 32), hud_canvas)
	ui.chat_channel = OptionButton.new()
	for name in ["千里傳音", "隊伍頻道", "密語對象"]: ui.chat_channel.add_item(name)
	chat_input.add_child(ui.chat_channel)
	ui.chat_line = LineEdit.new()
	ui.chat_line.placeholder_text = "傳音…（Enter 送出）"
	ui.chat_line.max_length = 210
	ui.chat_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.chat_line.text_submitted.connect(ui._chat_submit)
	chat_input.add_child(ui.chat_line)
	var chat_panel := panel(Rect2(1010, 0, 395, 158), ClassicFrame.Kind.INK, hud_canvas)
	ui.chat_view = ui.rich()
	ui.chat_view.scroll_following = true
	chat_panel.add_child(ui.chat_view)
	ui.status_label = ui.label("", 12, ui.GOLD)
	at(ui.status_label, Rect2(20, 701, 1325, 17), ui)
