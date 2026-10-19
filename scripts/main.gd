extends Control
## Classic client shell; gameplay and combat remain text based.
const Data = preload("res://scripts/content.gd")
const Rules = preload("res://scripts/world.gd")
const Training = preload("res://scripts/progression.gd")
const GOLD := Color("e6c77a")
const INK := Color("24180f")
const MUTED := Color("c8bc9c")
const TEXT := Color("f4f0e6")
var heading: Label
var vitals: RichTextLabel
var task_text: RichTextLabel
var status_label: Label
var location_label: Label
var location_desc: Label
var encounter: Label
var auto_status: Label
var roster: RichTextLabel
var log_view: RichTextLabel
var chat_view: RichTextLabel
var tabs: TabContainer
var pages: Dictionary = {}
var page_bodies: Dictionary = {}
var signatures: Dictionary = {}
var command_line: LineEdit
var chat_line: LineEdit
var filter: OptionButton
var history: Array = []
var chat_history: Array = []
var clock_label: Label
var address: LineEdit
var lobby_input: LineEdit
var character_name: LineEdit
var auto_skill: OptionButton
var check_heal: CheckBox
var map_search: LineEdit
var target := ""
var refresh_lock := false
var skill_labels: Dictionary = {}
var backdrop: TextureRect
var scene_panel: PanelContainer
var narrative: PanelContainer
var workspace: PanelContainer
var vital_bars: Dictionary = {}
var vital_labels: Dictionary = {}
var notice_label: Label
var hot_actions: Array = []
var chat_channel: OptionButton
var selected_peer := 0
var last_backdrop := ""
var music_label: Label
var music_toggle: CheckBox
var music_volume: HSlider
var navigation_query := ""

func _ready() -> void:
	_build_theme()
	_build()
	Session.updated.connect(_refresh)
	Session.message.connect(_message)
	Bgm.changed.connect(_refresh_music)
	_refresh_music()
	_refresh()
	_message("江湖", "一人，一劍，一段自己的江湖。先赴門派拜師，再向師父消點，或挑一門已學武功潛心自修。")
	_message("系統", "F1 自修、F2 打坐、F3 尋敵、F4 金創藥、F5 存檔、F7 人際。點右側燈籠開啟武功、裝備與聯機選單。")
	if "--capture" in OS.get_cmdline_user_args(): _capture.call_deferred()

func _build_theme() -> void:
	theme = ClassicTheme.build()

func style(bg: Color, border: Color, padding: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = padding
	s.content_margin_bottom = padding
	return s

func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node

func paragraph(text: String, color: Color = MUTED) -> Label:
	var node := label(text, 15, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

func rich() -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = false
	node.selection_enabled = true
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node

func button(text: String, fn: Callable, parent: Node, tip: String = "") -> Button:
	var node := Button.new()
	node.text = text
	node.tooltip_text = tip
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(fn)
	parent.add_child(node)
	return node

func action(text: String, command: String, arg: String, parent: Node) -> Button:
	return button(text, func(): Session.send(command, arg), parent)

func row(parent: Node) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", 8)
	parent.add_child(node)
	return node

func box(parent: Node, title: String, width: float = 0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style(INK, Color("31413c"), 16))
	panel.custom_minimum_size.x = width
	parent.add_child(panel)
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", 12)
	panel.add_child(node)
	if title != "": node.add_child(label(title, 17, GOLD))
	return node

func _build() -> void:
	preload("res://scripts/classic/layout.gd").build(self)

func clear_page(title: String) -> VBoxContainer:
	var body: VBoxContainer = page_bodies[title]
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	return body

func _refresh() -> void:
	status_label.text = Session.status + "    /    " + SteamBridge.status + "    /    v" + str(ProjectSettings.get_setting("application/config/version", ""))
	if Session.state.is_empty(): return
	var p: Dictionary = Session.state.player
	refresh_lock = true
	heading.text = "%s · %s" % [p.name, p.sect]
	vitals.text = "銀 %d · 學點 %d · 神 %d/%d\n攻勢 %d / 格擋 %d · 實戰 %d" % [p.silver, p.potential, p.spirit, p.max_spirit, Rules.attack(p), Rules.defense(p), p.combat_xp]
	for stat in vital_bars:
		vital_bars[stat].max_value = 100 if stat == "energy" else int(p["max_" + stat])
		vital_bars[stat].value = int(p[stat])
		vital_labels[stat].text = "%d / %d" % [p[stat], vital_bars[stat].max_value]
	location_label.text = p.place
	location_desc.text = Data.PLACES[p.place].desc
	encounter.text = "平安無事  ·  可拜訪人物與修練" if p.enemy.is_empty() else "%s  %d / %d 氣血  ·  你的策略：%s" % [p.enemy.name, p.enemy.hp, p.enemy.max_hp, p.stance]
	var battle: Dictionary = Session.state.get("social", {}).get("battle", {})
	if not battle.is_empty() and battle.kind != "PVE": encounter.text = "正在%s · 你的策略：%s · 可用右側認輸結束" % [battle.kind, p.stance]
	auto_status.text = "● " + (str(battle.kind) + "交戰中" if not battle.is_empty() else ("戰鬥中" if not p.enemy.is_empty() else str(p.auto)))
	check_heal.button_pressed = p.auto_heal
	var skills: Array = p.skills.keys()
	if auto_skill.item_count != skills.size():
		auto_skill.clear()
		for skill in skills: auto_skill.add_item(skill)
	auto_skill.select(maxi(0, skills.find(p.auto_skill)))
	var job := "未接懸賞"
	if not p.job.is_empty(): job = "%s  %d/%d" % [p.job.name, p.job.count, p.job.need]
	task_text.text = "探索 %d/%d · 訪談 %d/%d\n%s · 本次刷怪 %d" % [p.visited.size(), Data.PLACES.size(), p.talked.size(), Data.NPCS.size(), job, p.session_kills]
	var names: PackedStringArray = []
	var party: Dictionary = Session.state.get("social", {}).get("party", {})
	for member in Session.state.roster:
		var emblem := "★ " if int(party.get("leader", 0)) == int(member.id) else ("◆ " if int(p.party) != 0 and int(member.party) == int(p.party) else "")
		names.append("%s%s · %d/%d\n  %s" % [emblem, member.name, member.hp, member.max_hp, member.place])
	var pending: Array = Session.state.get("social", {}).get("requests", [])
	if not pending.is_empty(): names.append("〔%d 份邀請待回覆 · 按 F7〕" % pending.size())
	roster.text = "\n".join(names)
	var seconds: int = Session.state.tick
	clock_label.text = "江湖第 %d 日 · 第 %d 息    %d 人在線" % [seconds / 1440 + 1, seconds % 1440, Session.state.roster.size()]
	var selected := tabs.get_tab_title(tabs.current_tab)
	_classic_workspace(selected, p.place)
	var signature := "static"
	match selected:
		"江湖": signature = str([p.place, p.sect, p.job, p.searched, p.deliveries, target, p.travel_target, Session.state.roster.map(func(r: Dictionary): return [r.id, r.name, r.place])])
		"武學": signature = str([p.place, p.sect, p.skills, p.equipped, p.inner, p.movement, p.parry, p.weapon, p.armor, p.gender, p.sect_master, p.flags, p.attrs, p.attributes_locked])
		"圖鑑": signature = str([p.place, p.sect])
		"故事": signature = str([p.stories, p.story_choices, p.place, p.learning_quests, p.quests_done])
		"行囊": signature = str([p.place, p.inventory, p.weapon, p.armor])
		"人際": signature = str([selected_peer, p.party, p.follow, p.pk_enabled, Session.state.get("social", {}).get("requests", []), Session.state.roster.map(func(r: Dictionary): return [r.id, r.name, r.place, r.party, r.fight])])
	if signatures.get(selected, "") != signature:
		signatures[selected] = signature
		match selected:
			"江湖": _world_page(p)
			"武學": _skills_page(p)
			"行囊": _inventory_page(p)
			"故事": _story_page(p)
			"圖鑑": _catalog_page(p)
			"人際": _social_page(p)
	if selected == "武學":
		for skill in skill_labels:
			if is_instance_valid(skill_labels[skill]): skill_labels[skill].text = _skill_text(p, skill)
	refresh_lock = false

func _world_page(p: Dictionary) -> void:
	var body := clear_page("江湖")
	var travel := row(body)
	button("去哪裡？搜尋地點／人物／武功", func():
		tabs.current_tab = 4
		_refresh()
		if is_instance_valid(map_search): map_search.grab_focus(), travel)
	if p.travel_target != "":
		body.add_child(paragraph("正在前往：%s · 尚餘 %d 步 · 停止可取消行程" % [p.travel_target, p.travel_route.size()], GOLD))
		action("停止趕路", "停止", "", travel)
	if target != "" and Data.PLACES.has(target):
		var route: Array = Data.path_to(p.place, target)
		var progress := " · 已抵達" if p.place == target else (" · 無可通行路線" if route.is_empty() else " · %d 步\n下一站：%s" % [route.size(), route[0]])
		body.add_child(paragraph("目的地：" + target + progress, GOLD))
		if not route.is_empty():
			var go := row(body)
			action("自動前往目的地", "尋路", target, go)
			action("只走下一步", "前往", str(route[0]), go)
			var preview := button("查看完整路線", func(): _message("行路", str(p.place) + " → " + " → ".join(route)), go)
			preview.tooltip_text = str(p.place) + " → " + " → ".join(route)
		button("清除目的地", func(): Session.send("停止"); target = ""; signatures.clear(); _refresh(), body)
	body.add_child(label("山 川 有 路", 15, GOLD))
	var exits := HFlowContainer.new()
	exits.add_theme_constant_override("h_separation", 6)
	exits.add_theme_constant_override("v_separation", 6)
	body.add_child(exits)
	for destination in Data.PLACES[p.place].exits:
		var shortcut: bool = p.place == "揚州城" and Data.SECTS.values().any(func(s: Dictionary): return s.place == destination)
		action(("驛站 · " if shortcut else "") + destination, "前往", destination, exits)
	for sect in Data.SECTS:
		if Data.SECTS[sect].place == p.place and p.sect == "江湖散人":
			action("拜入" + sect + " · " + Data.SECTS[sect].style, "拜師", sect, body)
	if not p.searched.has(p.place): action("仔細搜查 · 尋找江湖遺物（3 精力）", "搜查", "", body)
	if p.place == "揚州城":
		var jobs := row(body)
		action("接取除患懸賞", "任務", "", jobs)
		action("回城領賞", "領賞", "", jobs)
	var local: Array = Data.local_npcs(p.place)
	body.add_child(label("此 地 人 物  /  %d" % local.size(), 15, GOLD))
	if local.is_empty(): body.add_child(paragraph("路上暫無人影。四處走走，或在此潛心修練。"))
	for npc_id in local:
		var npc: Dictionary = Data.NPCS[npc_id]
		var line := row(body)
		action("交談 · " + npc.name, "對話", npc_id, line)
		if not npc.teach.is_empty(): button("請教武學", func(): tabs.current_tab = 1, line)
		if Data.QUESTS.values().any(func(q: Dictionary): return q.giver == npc_id): button("學藝機緣", func(): tabs.current_tab = 3; _refresh(), line)
		if not npc.teach.is_empty() and Data.SECTS.get(p.sect, {}).get("personal_master", false): action("投師門下", "投師", npc_id, line)
		body.add_child(paragraph(npc.desc))
		for request in npc.get("requests", []):
			if p.deliveries.has(npc_id + "|" + request.item): continue
			body.add_child(paragraph("%s託你尋找%s。線索：%s；酬謝 %d 兩與 %d 學點。" % [npc.name, request.item, request.place, request.silver, request.points]))
			var choices := row(body)
			button("尋找 " + request.item, func(): _navigate(request.place), choices)
			action("交付 " + request.item, "交付", npc_id + "|" + request.item, choices)
	if not Data.PLACES[p.place].safe:
		var enemies: Array = Data.PLACES[p.place].get("enemies", [Data.PLACES[p.place].enemy])
		body.add_child(paragraph("可能遭遇：" + "、".join(enemies)))
	body.add_child(label("江 湖 同 行", 16, GOLD))
	for other in Session.state.roster:
		if other.place == p.place and int(other.id) != int(Session.state.self_id):
			button("與" + other.name + "互動 · 組隊／切磋／交易", func(): selected_peer = int(other.id); tabs.current_tab = 6; signatures.erase("人際"); _refresh(), body)
	_paper_text(body)

func _paper_text(node: Node) -> void:
	if node is Label:
		var color: Color = node.get_theme_color("font_color")
		if color == GOLD: node.add_theme_color_override("font_color", Color("8d3327"))
		elif color == MUTED: node.add_theme_color_override("font_color", Color("685333"))
		else: node.add_theme_color_override("font_color", Color("332b1c"))
	for child in node.get_children(): _paper_text(child)

func _classic_workspace(selected: String, place: String) -> void:
	var home := selected == "江湖"
	narrative.visible = home
	scene_panel.visible = home
	workspace.position = Vector2(20, 422) if home else Vector2(20, 74)
	workspace.size = Vector2(1000, 280) if home else Vector2(1000, 628)
	workspace.add_theme_stylebox_override("panel", ClassicFrame.style(ClassicFrame.Kind.SCROLL_SMALL if home else ClassicFrame.Kind.JADE))
	var image_name := "bg_dali_wild"
	if "少林" in place: image_name = "bg_shaolin"
	elif "武當" in place: image_name = "bg_wudang"
	elif "西夏" in place or "黑風" in place: image_name = "bg_xixia_wild"
	if image_name != last_backdrop:
		backdrop.texture = load("res://assets/classic/" + image_name + ".png")
		last_backdrop = image_name

func _peer_name(id: int) -> String:
	for other in Session.state.roster:
		if int(other.id) == id: return str(other.name)
	return "離線少俠"

func _social_page(p: Dictionary) -> void:
	var body := clear_page("人際")
	body.add_child(label("江湖人際 · 組隊與交鋒", 24, GOLD))
	body.add_child(paragraph("五人隊伍可同地點合擊刷怪、平分獎勵、跟隨隊長及互相療傷。切磋不扣銀兩、不掉裝備，結束恢復開戰前氣血內力；野外 PK 雙方需先開啟。"))
	var settings := row(body)
	action("關閉野外 PK" if p.pk_enabled else "開啟野外 PK", "PK設定", "關閉" if p.pk_enabled else "開啟", settings)
	if int(p.party) != 0:
		action("離開隊伍", "離隊", "", settings)
		action("取消跟隨" if p.follow else "跟隨隊長", "跟隨", "關閉" if p.follow else "開啟", settings)
	body.add_child(label("待回覆邀請", 18, GOLD))
	var pending: Array = Session.state.get("social", {}).get("requests", [])
	if pending.is_empty(): body.add_child(paragraph("目前沒有待處理邀請。"))
	for invite in pending:
		var desc := "%s · %s" % [_peer_name(int(invite.from)), invite.kind]
		if invite.kind == "交易": desc += " · %s ×%d / %d 兩" % [invite.payload.item, invite.payload.quantity, invite.payload.price]
		body.add_child(label(desc, 16))
		var reply := row(body)
		action("接受", "接受邀請", str(invite.id), reply)
		action("拒絕", "拒絕邀請", str(invite.id), reply)
	body.add_child(label("在線少俠 · 點選互動對象", 18, GOLD))
	for other in Session.state.roster:
		if int(other.id) == int(Session.state.self_id): continue
		button("%s · 實戰 %d · %s%s" % [other.name, int(other.get("combat_xp", 0)), other.place, " 〔目前對象〕" if selected_peer == int(other.id) else ""], func(): selected_peer = int(other.id); signatures.erase("人際"); _refresh(), body)
	if Session.state.roster.size() == 1: body.add_child(paragraph("目前只有你一人。先在右側「系統」燈籠開房，邀朋友加入。"))
	var exists: bool = Session.state.roster.any(func(r: Dictionary): return int(r.id) == selected_peer)
	if not exists: return
	body.add_child(label("與 " + _peer_name(selected_peer) + " 互動", 20, GOLD))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	body.add_child(actions)
	for pair in [["邀請組隊", "組隊邀請"], ["切磋邀請", "切磋"], ["野外 PK", "PK"], ["用金創藥援護", "治療隊友"], ["移交隊長", "移交隊長"], ["請離隊伍", "踢出隊伍"]]: action(pair[0], pair[1], str(selected_peer), actions)
	button("與對方密語", func(): chat_channel.select(2); chat_line.placeholder_text = "密語給 " + _peer_name(selected_peer); chat_line.grab_focus(), actions)
	body.add_child(label("當面交易 · 售物與贈物", 18, GOLD))
	body.add_child(paragraph("選擇物品、數量和售價後送出邀請；對方接受時才同時交換物品與銀兩。售價 0 表示贈送。任務信物與身上最後一件裝備不可交易。"))
	var trade := row(body)
	var items := OptionButton.new()
	items.custom_minimum_size.x = 180
	for item in p.inventory:
		if int(p.inventory[item]) > 0 and not Data.SHOP.get(item, {}).get("quest", true): items.add_item(item)
	trade.add_child(items)
	var quantity := SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = 999
	quantity.value = 1
	quantity.tooltip_text = "交易數量"
	trade.add_child(quantity)
	var price := SpinBox.new()
	price.min_value = 0
	price.max_value = 1000000
	price.value = 0
	price.suffix = " 兩"
	trade.add_child(price)
	button("送出交易邀請", func():
		if items.item_count > 0: Session.send("交易", "%d|%s|%d|%d" % [selected_peer, items.get_item_text(items.selected), quantity.value, price.value]), trade)

func _chat_submit(text: String) -> void:
	match chat_channel.selected:
		0: Session.send("說", text)
		1: Session.send("隊伍說", text)
		2: Session.send("私聊", str(selected_peer) + "|" + text)
	chat_line.clear()

func _skills_page(p: Dictionary) -> void:
	var body := clear_page("武學")
	skill_labels.clear()
	var a := Training.attrs(p)
	body.add_child(paragraph("悟性 %d · 消點每學點 +%d 熟練，耗 %d 精；自修每完整 5 秒耗 3 學點，+%d 熟練。\n實戰 %d · 武學實戰上限 %d · 特殊武功 %d/16\n外功：%s　內功：%s　輕功：%s" % [a.wit, Training.lesson_gain(p), Training.energy_cost(p), Training.study_gain(p), p.combat_xp, Training.xp_cap(p), Training.special_count(p), p.equipped, p.inner if p.inner != "" else "無", p.movement if p.movement != "" else "無"], TEXT))
	body.add_child(paragraph("臂力 %d　根骨 %d　機敏 %d　定力 %d　膽識 %d　福緣 %d\n善惡 %d　歷練 %d　師承：%s" % [a.str, a.con, a.agi, a.cal, a.guts, a.luck, p.morality, p.lilian, Data.NPCS.get(p.sect_master, {}).get("name", "未選個人師承")]))
	if not p.attributes_locked:
		var respec := VBoxContainer.new()
		respec.visible = false
		button("配置先天屬性 · 本作每人可確認一次", func(): respec.visible = not respec.visible, body)
		body.add_child(respec)
		respec.add_child(paragraph("本作開局配置：七項合計 180，每項 15–30。請先查看心儀武功的門檻；確認後不能重新配置。基本功與裝備加成不佔此額度。"))
		var fields := HFlowContainer.new()
		respec.add_child(fields)
		var controls := {}
		for key in Training.ATTRS:
			fields.add_child(label(Training.ATTRS[key], 14))
			var box := SpinBox.new()
			box.min_value = 15
			box.max_value = 30
			box.value = int(p.attrs.get(key, 25))
			fields.add_child(box)
			controls[key] = box
		button("確認先天配置（僅一次）", func():
			var values := {}
			for key in controls: values[key] = int(controls[key].value)
			Session.send("先天配點", JSON.stringify(values)), respec)
	if p.sect == "江湖散人":
		var background := row(body)
		action("身世：男", "身世", "M", background)
		action("身世：女", "身世", "F", background)
	elif p.sect == "丐幫": action("門派晉升 · 目前 %d 袋" % int(p.sect_rank), "晉升", "", body)
	var slots := row(body)
	slots.add_child(label("出力（1–10 成）", 14))
	var force := SpinBox.new()
	force.min_value = 1
	force.max_value = 10
	force.value = int(p.power)
	force.value_changed.connect(func(value: float): Session.send("出力", str(int(value))))
	slots.add_child(force)
	body.add_child(paragraph("格擋運用：" + Rules.guard_art(p) + "；可與攻擊外功分開選擇。"))
	if p.inner != "": action("停止運內功", "卸下", "inner", slots)
	if p.movement != "": action("停止運輕功", "卸下", "movement", slots)
	_local_lessons_page(body, p)
	body.add_child(label("已 學 武 學", 17, GOLD))
	for skill in p.skills:
		var line := row(body)
		var text := label(_skill_text(p, skill), 14)
		skill_labels[skill] = text
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		var study_reason := Training.eligibility(p, skill, true, {}, int(Session.state.tick))
		var study := action("自修", "自修", skill, line)
		study.disabled = study_reason != ""
		study.tooltip_text = study_reason if study_reason != "" else "每完整 5 秒消耗 3 學點與精，累積熟練。"
		if Data.role(skill) in ["EXTERNAL", "INNER", "MOVEMENT"]:
			var use := action("運用", "裝備", skill, line)
			use.disabled = Data.role(skill) == "EXTERNAL" and not Data.fits(skill, p.weapon)
			use.tooltip_text = Data.requirement_text(skill)
			if Data.role(skill) == "EXTERNAL":
				var guard := action("格擋", "格擋", skill, line)
				guard.disabled = not Data.fits(skill, p.weapon)
	body.add_child(label("尋 師 訪 道", 17, GOLD))
	for npc_id in Data.NPCS:
		var npc: Dictionary = Data.NPCS[npc_id]
		var own: PackedStringArray = []
		for lesson in npc.teach:
			var sect: String = Data.SKILLS.get(lesson.skill, {}).get("sect", "")
			if sect == p.sect or (p.sect == "江湖散人" and sect == ""): own.append(lesson.skill)
		if own.is_empty(): continue
		var line := row(body)
		button(npc.name + " · 尋路", func(): _navigate(npc.place), line)
		line.add_child(paragraph("、".join(own)))

func _local_lessons_page(body: VBoxContainer, p: Dictionary) -> void:
	body.add_child(label("當 地 師 父 · 授 業", 17, GOLD))
	var lessons: Array = Session.world.local_lessons(p)
	if lessons.is_empty(): body.add_child(paragraph("此處沒有可向你授業的師父。先拜師，再前往山內授業地點。"))
	for lesson in lessons:
		var npc: Dictionary = Data.NPCS[lesson.npc]
		var line := row(body)
		var reqs: PackedStringArray = []
		for req in lesson.requires: reqs.append("%s %d" % [req.skill, req.level])
		for req in Data.SKILLS.get(lesson.skill, {}).get("conditions", []): reqs.append(Training.condition_text(req))
		var desc := label("%s · %s\n上限 %d 級 · %d 兩%s" % [npc.name, lesson.skill, lesson.cap, lesson.price, " · 需 " + "、".join(reqs) if not reqs.is_empty() else ""], 14)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(desc)
		var reason := Training.eligibility(p, lesson.skill, false, lesson, int(Session.state.tick))
		var learn := action("消點", "消點", lesson.npc + "|" + lesson.skill, line)
		learn.disabled = reason != ""
		learn.tooltip_text = reason
		if reason != "": body.add_child(paragraph("尚缺：" + reason, MUTED))

func _skill_text(p: Dictionary, skill: String) -> String:
	var level := int(p.skills[skill])
	return "%s  Lv.%d  ·  熟練 %d/%d%s\n%s · 目前自修上限 %d" % [skill, level, int(p.skill_xp.get(skill, 0)), Training.needed(skill, level), " 〔運用中〕" if skill in [p.equipped, p.inner, p.movement] else "", Data.requirement_text(skill), Training.study_cap(p, skill)]

func _inventory_page(p: Dictionary) -> void:
	var body := clear_page("行囊")
	body.add_child(paragraph("已裝備：%s ／ %s" % [p.weapon if p.weapon != "" else "徒手", p.armor if p.armor != "" else "布衣"]))
	if p.weapon != "": action("卸下兵器 · 改用拳掌", "卸下", "weapon", body)
	for item in p.inventory:
		if int(p.inventory[item]) < 1: continue
		var line := row(body)
		var definition: Dictionary = Data.SHOP.get(item, {})
		var kind := " · " + Data.category_label(Data.weapon_type(item)) if definition.get("type", "") == "WEAPON" else ""
		var text := label("%s × %d%s" % [item, p.inventory[item], kind], 15)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		if Data.SHOP.has(item):
			if Data.SHOP[item].type in ["WEAPON", "ARMOR"]: action("裝備", "裝備", item, line)
			elif not Data.SHOP[item].get("restore", {}).is_empty(): action("使用", "使用", item, line)
			action("出售", "出售", item, line)
			body.add_child(paragraph(Data.SHOP[item].desc))
	body.add_child(label("當 地 商 店", 17, GOLD))
	var stock: Array = Data.SHOP.keys() if p.place == "揚州城" else Data.PLACES[p.place].get("shop", [])
	if stock.is_empty(): body.add_child(paragraph("當地沒有商店，可回揚州城採購。"))
	for item in stock:
		if Data.SHOP[item].get("quest", false): continue
		var line := row(body)
		var kind := " · " + Data.category_label(Data.weapon_type(item)) if Data.SHOP[item].type == "WEAPON" else ""
		var text := label("%s · %d 兩%s" % [item, Data.SHOP[item].price, kind], 15)
		text.tooltip_text = Data.SHOP[item].desc
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		action("購買", "購買", item, line)

func _story_page(p: Dictionary) -> void:
	var body := clear_page("故事")
	_learning_routes(body, p)
	body.add_child(paragraph("江湖拾遺：以金庸人物與故事脈絡重新撰寫的訪談支線。跨作品人物共處一個模擬江湖；並非原著逐字內容，也不對應單一歷史時間線。", TEXT))
	for story in Data.STORIES:
		var stage := int(p.stories.get(story.id, 0))
		body.add_child(label(story.title + "  %d/%d" % [stage, story.npcs.size()], 17, GOLD))
		for i in range(stage): body.add_child(paragraph(story.scenes[i], TEXT))
		if p.story_choices.has(story.id):
			body.add_child(paragraph(story.ending[int(p.story_choices[story.id])], GOLD))
		elif stage >= story.npcs.size():
			for i in range(story.choices.size()): action(story.choices[i] + ("（善惡 +20）" if i == 0 else "（善惡 -20）"), "故事選擇", story.id + "|" + str(i), body)
		else:
			var npc: Dictionary = Data.NPCS[story.npcs[stage]]
			button("拜訪 " + npc.name + " · " + npc.place, func(): _navigate(npc.place), body)
		body.add_child(HSeparator.new())

func _learning_routes(body: VBoxContainer, p: Dictionary) -> void:
	body.add_child(label("學 藝 機 緣 · 任 務 解 鎖", 20, GOLD))
	body.add_child(paragraph("先滿足條件，再依階段交談、交付或接受真實考較。完成後選擇結局，才會取得武功或解鎖旗標。這些是來源任務的文字改編；未開放的特殊步驟會明確停止，不能跳過。"))
	for q in Data.QUESTS.values():
		if p.quests_done.has(q.id): continue
		var reason := Training.check(p, q.conditions, int(Session.state.tick))
		var own := false
		for condition in q.conditions:
			if condition.get("type", "") == "sect" and condition.sect == p.sect: own = true
		if not own and not p.learning_quests.has(q.id) and p.sect != "江湖散人": continue
		body.add_child(label(q.name, 18, GOLD))
		if not p.learning_quests.has(q.id):
			var line := row(body)
			button("拜訪 " + str(Data.NPCS[q.giver].name), func(): _navigate(Data.NPCS[q.giver].place), line)
			var accept := action("接受機緣", "接受任務", q.id, line)
			accept.disabled = reason != "" or p.place != Data.NPCS[q.giver].place
			accept.tooltip_text = reason if reason != "" else "到發起人身邊接受"
			if reason != "": body.add_child(paragraph("尚缺：" + reason, MUTED))
			continue
		var state: Dictionary = p.learning_quests[q.id]
		if int(state.stage) == 0 and q.get("dialogues", {}).has("d_offer"):
			var origin := row(body)
			button("回發起人", func(): _navigate(Data.NPCS[q.giver].place), origin)
			action("詢問機緣緣起", "任務緣起", q.id, origin)
		if int(state.stage) >= q.stages.size():
			for key in q.outcomes:
				if str(state.get("outcome", key)) == key: action(q.outcomes[key].label, "任務結局", q.id + "|" + key, body)
			continue
		if state.get("dialogue", "") != "":
			var node: Dictionary = q.get("dialogues", {}).get(state.dialogue, {}).get("nodes", {}).get(state.get("node", ""), {})
			body.add_child(paragraph(str(node.get("text", "")), TEXT))
			for option in node.get("choices", []):
				var choose := action(option.label, "任務對話", q.id + "|" + option.id, body)
				var lock := Training.check(p, option.get("requires", []), int(Session.state.tick))
				choose.disabled = lock != ""
				choose.tooltip_text = lock
		var stage: Dictionary = q.stages[int(state.stage)]
		body.add_child(paragraph("%d/%d · %s\n%s" % [int(state.stage) + 1, q.stages.size(), stage.title, stage.log]))
		for objective in stage.objectives:
			if state.done.has(objective.id): continue
			var line := row(body)
			var npc: String = objective.get("npc", objective.get("target", ""))
			var place: String = Data.NPCS.get(npc, {}).get("place", stage.place)
			if place != "": button("前往 · " + place, func(): _navigate(place), line)
			action(objective.get("text", objective.type), "任務行動", q.id + "|" + objective.id, line)
		body.add_child(HSeparator.new())

func _catalog_page(_p: Dictionary) -> void:
	var had_focus := is_instance_valid(map_search) and map_search.has_focus()
	var caret := map_search.caret_column if is_instance_valid(map_search) else 0
	var body := clear_page("圖鑑")
	body.add_child(label("江湖地圖 · 找人、尋師、前往目的地", 20, GOLD))
	body.add_child(paragraph("%d 地點　%d 人物　%d 物品　%d 敵人\n%d 門派　%d 武學　%d 故事支線" % [Data.PLACES.size(), Data.NPCS.size(), Data.SHOP.size(), Data.ENEMIES.size(), Data.SECTS.size(), Data.SKILLS.size(), Data.STORIES.size()], TEXT))
	map_search = LineEdit.new()
	map_search.placeholder_text = "輸入地名、人物或想學的武功，例如：張三丰、武當心法"
	map_search.text = navigation_query
	body.add_child(map_search)
	var results := VBoxContainer.new()
	results.add_theme_constant_override("separation", 8)
	body.add_child(results)
	map_search.text_changed.connect(func(query: String): navigation_query = query; _search_catalog(results, query))
	map_search.text_submitted.connect(func(query: String): _search_catalog(results, query))
	var shortcuts := row(body)
	button("回揚州", func(): _navigate("揚州城"), shortcuts)
	button("找武館", func(): map_search.text = "武師"; _search_catalog(results, "武師"), shortcuts)
	button("學讀書識字", func(): map_search.text = "讀書識字"; _search_catalog(results, "讀書識字"), shortcuts)
	if Data.SECTS.has(_p.sect): button("回本門山門", func(): _navigate(Data.SECTS[_p.sect].place), shortcuts)
	_search_catalog(results, navigation_query)
	if had_focus:
		map_search.grab_focus()
		map_search.caret_column = caret

func _search_catalog(results: VBoxContainer, query: String) -> void:
	for child in results.get_children(): results.remove_child(child); child.queue_free()
	var start: String = Session.state.player.place
	var found := Data.destinations(query, start)
	if found.is_empty(): results.add_child(paragraph("找不到相符目的地。可輸入部分地名、人物名或武功名稱。"))
	for entry in found.slice(0, 60):
		var destination: String = entry.place
		var text := "%s · %s\n%s · %s" % [entry.kind, entry.title, destination, "就在此地" if destination == start else "%d 步" % int(entry.steps)]
		button(text, func(): _navigate(destination), results)
	if found.size() > 60: results.add_child(paragraph("還有 %d 個結果，請輸入更精確的關鍵字。" % (found.size() - 60)))
	if query == "": return
	for item in Data.SHOP:
		if query in item: results.add_child(paragraph("物品 · " + item + "\n" + Data.SHOP[item].desc, TEXT))
	for enemy in Data.ENEMIES:
		if query in enemy:
			var e: Dictionary = Data.ENEMIES[enemy]
			results.add_child(paragraph("敵人 · %s · 氣血 %d / 攻擊 %d / 防禦 %d\n%s" % [enemy, e.hp, e.attack, e.defense, e.get("desc", "")], TEXT))
	for skill in Data.SKILLS:
		if query in skill: results.add_child(paragraph("武學 · %s · %s\n%s\n根基：%s\n%s" % [skill, Data.SKILLS[skill].sect, Data.requirement_text(skill), Data.SKILLS[skill].get("base", ""), Data.SKILLS[skill].desc], TEXT))

func _navigate(place: String) -> void:
	if not Data.PLACES.has(place):
		_message("提示", "目的地已失效，請重新搜尋。")
		return
	if Session.state.player.travel_target != "" and Session.state.player.travel_target != place: Session.send("停止")
	target = place
	signatures.clear()
	tabs.current_tab = 0
	_refresh()

func _build_network(body: VBoxContainer) -> void:
	body.add_child(label("江湖聲韻 · 背景音樂", 22, GOLD))
	music_label = label("", 16)
	body.add_child(music_label)
	var music := row(body)
	music_toggle = CheckBox.new()
	music_toggle.text = "播放 BGM"
	music_toggle.toggled.connect(func(on: bool): Bgm.set_enabled(on))
	music.add_child(music_toggle)
	music_volume = HSlider.new()
	music_volume.min_value = 0
	music_volume.max_value = 100
	music_volume.step = 1
	music_volume.custom_minimum_size.x = 260
	music_volume.tooltip_text = "背景音樂音量"
	music_volume.value_changed.connect(func(value: float): Bgm.set_volume(value / 100.0))
	music.add_child(music_volume)
	var track := OptionButton.new()
	track.add_item("隨場景自動切換", 0)
	var keys: Array = Bgm.TRACKS.keys()
	for key in keys: track.add_item(Bgm.TRACKS[key].title)
	track.select(keys.find(Bgm.override_track) + 1)
	track.item_selected.connect(func(index: int): Bgm.set_override("" if index == 0 else keys[index - 1]))
	body.add_child(track)
	body.add_child(paragraph("城鎮、野外、地城、一般戰鬥與首領戰各有曲目，切換時交叉淡化；音量與播放偏好會保存。"))
	body.add_child(HSeparator.new())
	body.add_child(label("邀 三 五 知 己，共 一 個 江 湖", 19, GOLD))
	body.add_child(paragraph("房主負責所有戰鬥、消點、自修與獎勵結算。朋友的角色存於房主世界；單機角色保留在自己的存檔中。房主離線後回到各自單機。", TEXT))
	var identity := row(body)
	character_name = LineEdit.new()
	character_name.placeholder_text = "少俠名號（最多 12 字）"
	character_name.max_length = 12
	character_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(character_name)
	button("更改名號", func(): Session.send("改名", character_name.text), identity)
	body.add_child(label("Steam / Spacewar 480", 17, GOLD))
	var steam_row := row(body)
	button("Steam 開房", func(): Session.host_steam(), steam_row)
	button("邀請好友", func(): SteamBridge.invite(), steam_row)
	button("複製大廳編號", func():
		if SteamBridge.lobby_id > 0: DisplayServer.clipboard_set(str(SteamBridge.lobby_id)), steam_row)
	var join := row(body)
	lobby_input = LineEdit.new()
	lobby_input.placeholder_text = "Steam 大廳編號"
	lobby_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.add_child(lobby_input)
	button("加入大廳", func(): Session.join_steam(lobby_input.text.to_int()), join)
	body.add_child(paragraph("雙方先啟動 Steam 與本遊戲，使用不同 Steam 帳號。可由好友邀請或大廳編號加入。本遊戲使用獨立標記，只接受相容大廳。"))
	body.add_child(label("區網 / 直連", 17, GOLD))
	var lan := row(body)
	button("區網開房", func(): Session.host_lan(), lan)
	address = LineEdit.new()
	address.text = "127.0.0.1"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lan.add_child(address)
	button("連線", func(): Session.join_lan(address.text), lan)
	body.add_child(paragraph("區網埠：UDP 24780。同機測試可用 127.0.0.1；區網朋友填房主 IP。"))
	button("返回單機江湖", func(): Session.start_offline(), body)

func _refresh_music() -> void:
	if music_label == null: return
	music_label.text = ("正在播放：" if Bgm.enabled and Bgm.volume > 0 else "已靜音：") + str(Bgm.TRACKS.get(Bgm.current_track, {}).get("title", "江湖聲韻")) + " · %d%%" % int(Bgm.volume * 100)
	music_toggle.set_pressed_no_signal(Bgm.enabled)
	music_volume.set_value_no_signal(Bgm.volume * 100)

func _message(channel: String, text: String) -> void:
	var time := Time.get_time_string_from_system().left(5)
	var entry := {"channel": channel, "text": "%s  〔%s〕 %s" % [time, channel, text]}
	if channel in ["世界", "隊聊", "私聊"]:
		chat_history.append(entry)
		if chat_history.size() > 100: chat_history.pop_front()
		chat_view.text = "\n\n".join(chat_history.map(func(e: Dictionary): return e.text))
	else:
		notice_label.text = text
		notice_label.tooltip_text = text
		notice_label.add_theme_color_override("font_color", Color("ff9f78") if channel == "提示" else GOLD)
		history.append(entry)
		if history.size() > 300: history.pop_front()
		_render_log()

func _render_log() -> void:
	var choice: String = filter.get_item_text(filter.selected)
	var lines: PackedStringArray = []
	for entry in history:
		if choice == "全部" or entry.channel == choice or (choice == "武學" and entry.channel in ["消點", "自修", "修行"]) or (choice == "人際" and entry.channel in ["隊伍", "交易", "PK", "切磋"]): lines.append(entry.text)
	log_view.text = "\n".join(lines)

func _command(value: String) -> void:
	var text := value.strip_edges()
	if text == "": return
	command_line.clear()
	if text in ["幫助", "help", "?"]:
		_message("提示", Data.HELP + " 消點 武功名｜自修 武功名。可在圖鑑搜尋人物並尋路。")
		return
	var parts := text.split(" ", false, 1)
	Session.send(parts[0], parts[1] if parts.size() == 2 else "")

func _save() -> void:
	if Session.mode.ends_with("客戶端"):
		_message("系統", "聯機角色由房主自動存檔。")
	else:
		_message("系統", "江湖進度已保存。" if Session.save_game() else "存檔失敗，請檢查磁碟空間。")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode >= KEY_F1 and event.keycode <= KEY_F8:
		hot_actions[event.keycode - KEY_F1].call()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode >= KEY_1 and event.keycode <= KEY_7:
		tabs.current_tab = [0, 1, 2, 3, 4, 6, 5][event.keycode - KEY_1]
	elif event.keycode == KEY_ESCAPE: tabs.current_tab = 0

func _capture() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-results")
	get_viewport().get_texture().get_image().save_png("res://test-results/preview.png")
