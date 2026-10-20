extends RefCounted
const Data = preload("res://scripts/content.gd")
const Guide = preload("res://scripts/quest_guide.gd")
const Market = preload("res://scripts/market.gd")
const Training = preload("res://scripts/progression.gd")

static func flow(parent: Node) -> HFlowContainer:
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 8)
	line.add_theme_constant_override("v_separation", 6)
	parent.add_child(line)
	return line

static func columns(ui, body: Node) -> Array:
	var line = ui.row(body)
	var panes: Array = []
	for i in 2:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(290 if i == 0 else 0, 370)
		if i == 1: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(scroll)
		var pane := VBoxContainer.new()
		pane.add_theme_constant_override("separation", 12)
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(pane)
		panes.append(pane)
	return panes

static func entry(ui, text: String, parent: Node, selected: bool, fn: Callable) -> Button:
	var control: Button = ui.button(text, fn, parent, text)
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.custom_minimum_size.y = 62
	control.clip_text = true
	control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	control.toggle_mode = true
	control.set_pressed_no_signal(selected)
	if selected and parent.get_parent() is ScrollContainer: parent.get_parent().ensure_control_visible.call_deferred(control)
	return control

static func notice(ui, body: Node, market: bool = false) -> void:
	ui.activity_notice_tag = "market" if market else "quest"
	ui.activity_notice = ui.paragraph(ui.market_message if market else ui.quest_message, ui.GOLD)
	ui.activity_notice.custom_minimum_size.y = 22
	body.add_child(ui.activity_notice)

static func quests(ui, body: VBoxContainer, p: Dictionary) -> void:
	ui.activity_context = "quest"
	var header = flow(body)
	ui.button("任務清單", func(): ui.journal_mode = 0; ui.signatures.erase("故事"); ui._refresh(), header)
	ui.button("人物故事", func(): ui.journal_mode = 1; ui.signatures.erase("故事"); ui._refresh(), header)
	if ui.journal_mode == 1: return
	var tick := int(Session.state.tick)
	var active: int = p.learning_quests.size()
	ui_label(ui, body, "江湖任務 · 進行中 %d / 已完成 %d" % [active, p.quests_done.size()], 22)
	var filters = flow(body)
	var names := ["進行中", "可接任務", "全部任務", "已完成"]
	for index in names.size():
		var tab: Button = ui.button(names[index], func(): ui.quest_filter = index; ui.selected_quest = ""; ui.signatures.erase("故事"); ui._refresh(), filters)
		tab.toggle_mode = true
		tab.set_pressed_no_signal(ui.quest_filter == index)
	ui.activity_search = LineEdit.new()
	ui.activity_search.placeholder_text = "搜尋任務或發起人姓名"
	ui.activity_search.text = ui.quest_query
	body.add_child(ui.activity_search)
	ui.activity_search.text_changed.connect(func(text: String): ui.quest_query = text; ui.signatures.erase("故事"); ui._refresh())
	notice(ui, body)
	var panes := columns(ui, body)
	var visible: Array = []
	for q in Data.QUESTS.values():
		var state := Guide.status(p, q, tick)
		if ui.quest_filter == 0 and state != "進行中": continue
		if ui.quest_filter == 1 and state != "可接任務": continue
		if ui.quest_filter == 3 and state != "已完成": continue
		if ui.quest_query != "" and not ui.quest_query in q.name and not ui.quest_query in str(Data.NPCS[q.giver].name): continue
		visible.append(q)
	visible.sort_custom(func(a, b):
		var a_local: bool = Data.NPCS[a.giver].place == p.place
		var b_local: bool = Data.NPCS[b.giver].place == p.place
		return a_local if a_local != b_local else a.name < b.name)
	if not visible.any(func(q): return q.id == ui.selected_quest): ui.selected_quest = visible[0].id if not visible.is_empty() else ""
	for q in visible:
		var state := Guide.status(p, q, tick)
		var nearby := " · 就在此地" if Data.NPCS[q.giver].place == p.place else ""
		entry(ui, q.name + "\n" + state + nearby, panes[0], ui.selected_quest == q.id, func(): ui.open_quest(q.id, false))
	if visible.is_empty():
		panes[0].add_child(ui.paragraph("沒有相符任務。"))
		panes[1].add_child(ui.paragraph("先到「可接任務」挑選一個任務，再按「前往接任務」。到達後可在人物旁直接接受。\n\n已加入門派的角色同樣可以接一般江湖任務。", ui.TEXT))
		ui.button("查看可接任務", func(): ui.quest_filter = 1; ui.quest_query = ""; ui.signatures.erase("故事"); ui._refresh(), panes[1])
		return
	quest_details(ui, panes[1], p, Data.QUESTS[ui.selected_quest], tick)

static func ui_label(ui, parent: Node, text: String, size: int = 18) -> void:
	var title: Label = ui.paragraph(text, ui.GOLD)
	title.add_theme_font_size_override("font_size", size)
	parent.add_child(title)

static func reward_text(q: Dictionary) -> String:
	var rewards: Dictionary = q.outcomes.values()[0].get("rewards", {}) if not q.outcomes.is_empty() else {}
	var parts: PackedStringArray = []
	for pair in [["money", "銀兩"], ["learn_points", "學點"], ["combat_xp", "實戰"], ["fame", "名聲"]]:
		if int(rewards.get(pair[0], 0)) != 0: parts.append("%s %+d" % [pair[1], int(rewards[pair[0]])])
	for skill in rewards.get("learn", {}): parts.append("學會 " + str(skill))
	if parts.is_empty(): return "完成後取得任務獎勵或後續機緣。"
	return "獎勵參考：" + " · ".join(parts) + ("（依結局而異）" if q.outcomes.size() > 1 else "")

static func quest_details(ui, body: VBoxContainer, p: Dictionary, q: Dictionary, tick: int) -> void:
	ui_label(ui, body, q.name, 22)
	body.add_child(ui.paragraph(reward_text(q)))
	var giver: Dictionary = Data.NPCS[q.giver]
	if p.quests_done.has(q.id):
		var ending: Dictionary = q.outcomes.get(str(p.quests_done[q.id]), {})
		body.add_child(ui.paragraph("已完成 · " + str(ending.get("label", "獎勵已領取")), ui.GOLD))
		return
	if not p.learning_quests.has(q.id):
		body.add_child(ui.paragraph(q.stages[0].log, ui.TEXT))
		body.add_child(ui.paragraph("發起人：%s\n所在：%s" % [giver.name, giver.place]))
		var reason := Guide.support_reason(q)
		if reason == "": reason = Training.check(p, q.conditions, tick)
		if reason != "": body.add_child(ui.paragraph("暫時不能接取：" + reason, ui.GOLD))
		if giver.place != p.place:
			ui.button("前往接任務 · " + str(giver.name), func(): ui._navigate(giver.place), body)
		else:
			var accept: Button = ui.button("接受任務", func(): ui.accept_quest(q.id), body)
			accept.disabled = reason != "" or not p.enemy.is_empty() or int(p.fight) != 0
			if not p.enemy.is_empty() or int(p.fight) != 0: body.add_child(ui.paragraph("先結束戰鬥，才能接取任務。"))
		for condition in q.conditions:
			body.add_child(ui.paragraph(("✓ " if Training.check(p, [condition], tick) == "" else "尚缺 · ") + Training.condition_text(condition)))
		return
	var state: Dictionary = p.learning_quests[q.id]
	if int(state.stage) >= q.stages.size():
		body.add_child(ui.paragraph("任務已達成，請領取獎勵。", ui.GOLD))
		for key in q.outcomes:
			if str(state.get("outcome", key)) != key: continue
			ui.button("領取獎勵 · " + str(q.outcomes[key].label), func(): ui.claim_quest(q.id, key), body)
		return
	var stage: Dictionary = q.stages[int(state.stage)]
	ui_label(ui, body, "第 %d/%d 步 · %s" % [int(state.stage) + 1, q.stages.size(), stage.title])
	body.add_child(ui.paragraph(stage.log, ui.TEXT))
	if state.get("dialogue", "") != "":
		var npc: Dictionary = Data.NPCS.get(state.get("npc", ""), {})
		if npc.get("place", p.place) != p.place:
			body.add_child(ui.paragraph("請回到 %s 身邊繼續對話。" % npc.get("name", "任務人物")))
			ui.button("前往 · " + str(npc.get("place", "")), func(): ui._navigate(npc.place), body)
			return
		var node: Dictionary = q.dialogues.get(state.dialogue, {}).get("nodes", {}).get(state.get("node", ""), {})
		body.add_child(ui.paragraph(str(node.get("text", "")), ui.TEXT))
		for option in node.get("choices", []):
			var reason := Training.check(p, option.get("requires", []), tick)
			var choose: Button = ui.action(option.label, "任務對話", q.id + "|" + option.id, body)
			choose.disabled = reason != "" or not p.enemy.is_empty() or int(p.fight) != 0
			if reason != "": body.add_child(ui.paragraph("尚缺：" + reason))
		return
	for o in stage.objectives:
		if state.done.has(o.id):
			body.add_child(ui.paragraph("✓ " + str(o.get("text", o.type))))
			continue
		var place := Guide.place_of(stage, o)
		body.add_child(ui.paragraph("下一步：" + str(o.get("text", o.type)), ui.TEXT))
		var reason := Guide.objective_reason(p, stage, o, tick, state)
		if place != "" and place != p.place:
			ui.button("前往 · " + place, func(): ui._navigate(place), body)
		else:
			var do_step: Button = ui.action("交付物品" if o.type == "DELIVER" else ("開始考較" if o.type == "FIGHT" else "繼續任務"), "任務行動", q.id + "|" + o.id, body)
			do_step.disabled = reason != ""
		if reason != "": body.add_child(ui.paragraph(reason, ui.GOLD))
		if o.type in ["COLLECT", "DELIVER", "BUY"] and int(p.inventory.get(o.get("item", ""), 0)) < int(o.get("count", 1)):
			for source in Guide.item_sources(p.place, str(o.get("item", ""))).slice(0, 3):
				ui.button(source.label + " · " + source.place, func(): ui._navigate(source.place), body)

static func shop(ui, body: VBoxContainer, p: Dictionary) -> void:
	ui.activity_context = "market"
	ui_label(ui, body, "商店 · %s　　持有 %d 兩" % [p.place, p.silver], 22)
	var modes = flow(body)
	for index in 2:
		var tab: Button = ui.button("出售物品" if index else "購買物品", func(): ui.shop_mode = index; ui.shop_item = ""; ui.shop_quantity = 1; ui.show_shop_directory = false; ui.signatures.erase("商店"); ui._refresh(), modes)
		tab.toggle_mode = true
		tab.set_pressed_no_signal(ui.shop_mode == index)
	ui.button("尋找其他商店" if not ui.show_shop_directory else "返回當地買賣", func(): ui.show_shop_directory = not ui.show_shop_directory; ui.signatures.erase("商店"); ui._refresh(), modes)
	ui.activity_search = LineEdit.new()
	ui.activity_search.placeholder_text = "搜尋物品名稱；找商店時也可輸入地名"
	ui.activity_search.text = ui.shop_query
	body.add_child(ui.activity_search)
	ui.activity_search.text_changed.connect(func(text: String): ui.shop_query = text; ui.signatures.erase("商店"); ui._refresh())
	notice(ui, body, true)
	if ui.show_shop_directory or not Market.has_shop(p.place):
		if not Market.has_shop(p.place): body.add_child(ui.paragraph("此地沒有商人。選擇一家商店即可自動前往；到達後按上方「商店」買賣。", ui.GOLD))
		var destinations := Market.shops_near(p.place, ui.shop_query)
		if destinations.is_empty(): body.add_child(ui.paragraph("沒有商店販售相符物品。試著清除搜尋字詞。"))
		for destination in destinations.slice(0, 12):
			var preview: Array = destination.stock.filter(func(item): return ui.shop_query == "" or ui.shop_query in item)
			var text := "%s · %s\n販售：%s" % [destination.place, "就在此地" if destination.steps == 0 else "%d 步" % destination.steps, "、".join(preview.slice(0, 5))]
			ui.button(text, func():
				if destination.place == p.place: ui.show_shop_directory = false; ui.signatures.erase("商店"); ui._refresh()
				else: ui._navigate(destination.place), body)
		return
	var selling: bool = ui.shop_mode == 1
	var items: Array = p.inventory.keys().filter(func(item): return int(p.inventory[item]) > 0) if selling else Market.stock(p.place)
	items = items.filter(func(item): return ui.shop_query == "" or ui.shop_query in item)
	items.sort()
	if not ui.shop_item in items: ui.shop_item = items[0] if not items.is_empty() else ""
	var panes := columns(ui, body)
	for item in items:
		var offer := Market.quote(p, selling, item)
		var count := " · 持有 %d" % int(p.inventory.get(item, 0))
		entry(ui, "%s\n%s %d 兩%s" % [item, "收購" if selling else "單價", offer.unit, count], panes[0], ui.shop_item == item, func(): ui.shop_item = item; ui.shop_quantity = 1; ui.signatures.erase("商店"); ui._refresh())
	if items.is_empty():
		panes[1].add_child(ui.paragraph("沒有相符物品。" if ui.shop_query != "" else "行囊目前沒有物品可出售。"))
		return
	var item: String = ui.shop_item
	var definition: Dictionary = Data.SHOP.get(item, {})
	ui_label(ui, panes[1], item, 24)
	panes[1].add_child(ui.paragraph(str(definition.get("desc", "")), ui.TEXT))
	panes[1].add_child(ui.paragraph("行囊持有：%d%s" % [int(p.inventory.get(item, 0)), " · 已裝備" if item in [p.weapon, p.armor] else ""]))
	var controls = ui.row(panes[1])
	controls.add_child(ui.label("交易數量", 16))
	var quantity := SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = mini(99, maxi(1, Market.sale_limit(p, item))) if selling else 99
	quantity.value = clampi(ui.shop_quantity, 1, int(quantity.max_value))
	quantity.tooltip_text = "要出售的數量" if selling else "要購買的數量"
	controls.add_child(quantity)
	var total: Label = ui.paragraph("", ui.TEXT)
	panes[1].add_child(total)
	var reason: Label = ui.paragraph("", ui.GOLD)
	panes[1].add_child(reason)
	var confirm: Button = ui.button("", func(): Session.send("出售" if selling else "購買", item + "|" + str(int(quantity.value))), panes[1])
	var update := func(_value: float = 0):
		ui.shop_quantity = int(quantity.value)
		var offer := Market.quote(p, selling, item, ui.shop_quantity)
		total.text = "%s %d 兩 × %d = 合計 %d 兩" % ["收購單價" if selling else "單價", offer.unit, ui.shop_quantity, offer.total]
		reason.text = offer.error
		confirm.text = "%s %d 件 · %s %d 兩" % ["出售" if selling else "購買", ui.shop_quantity, "獲得" if selling else "支付", offer.total]
		confirm.disabled = not offer.ok
	quantity.value_changed.connect(update)
	update.call()
	if selling and item in [p.weapon, p.armor] and p.enemy.is_empty() and int(p.fight) == 0:
		ui.action("卸下" + item + "，以便出售", "卸下", "weapon" if p.weapon == item else "armor", panes[1])
