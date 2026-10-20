extends RefCounted
const Data = preload("res://scripts/content.gd")
const Life = preload("res://scripts/life_skills.gd")
const Pages = preload("res://scripts/classic/activity_pages.gd")

static func select(ui, skill: String, key: String = "") -> void:
	ui.life_skill = skill
	ui.life_recipe = key
	if key == "" and Data.LIFE[skill].mode == "CRAFT": ui.life_recipe = Data.LIFE[skill].recipes[0].id
	ui.signatures.erase("生活")
	ui.open_page(9)

static func travel(ui, place: String) -> void:
	ui._navigate(place)
	ui.open_page(9)

static func build(ui, body: VBoxContainer, p: Dictionary) -> void:
	body.add_child(ui.label("生活技藝 · 採集、製作與掛機", 23, ui.GOLD))
	var job: Dictionary = p.life_work
	if not job.is_empty():
		var status := Pages.flow(body)
		status.add_child(ui.label("%s · %s · 嘗試 %d／成功 %d%s" % [Data.LIFE[job.skill].name, "工作中" if job.active else job.message, job.done, job.successes, " · 狩獵交戰中" if not p.life_hunt.is_empty() else ""], 16, ui.GOLD))
		ui.life_timer = ui.label("", 16, ui.GOLD)
		status.add_child(ui.life_timer)
		if job.active: ui.action("停止生活掛機", "停止", "", status)
		var gained: PackedStringArray = []
		for item in job.gained: gained.append("%s × %d" % [item, job.gained[item]])
		if not gained.is_empty(): body.add_child(ui.paragraph("本輪所得：" + "、".join(gained)))
		if not job.active and not job.gained.is_empty():
			var sell := Pages.flow(body)
			for item in job.gained: ui.button("出售收成 · " + str(item), func(): ui.open_market(true, item), sell)
	if p.travel_target != "": body.add_child(ui.paragraph("正在前往「%s」，到達後即可學藝或開工。" % p.travel_target, ui.GOLD))
	var panes := Pages.columns(ui, body)
	for id in Data.LIFE:
		var lv := int(p.life_levels.get(id, 0))
		Pages.entry(ui, "%s\n%s" % [Data.LIFE[id].name, "%d 級 · 熟練 %d" % [lv, int(p.life_prof.get(id, 0))] if lv > 0 else "未學習 · 點選尋找師父"], panes[0], ui.life_skill == id, func(): select(ui, id))
	var row: Dictionary = Data.LIFE[ui.life_skill]
	var r := Life.recipe(ui.life_skill, ui.life_recipe)
	var right: VBoxContainer = panes[1]
	var lv := int(p.life_levels.get(ui.life_skill, 0))
	Pages.ui_label(ui, right, "%s · %s" % [row.name, "%d 級／上限 100" % lv if lv > 0 else "尚未學會"], 23)
	right.add_child(ui.paragraph(row.desc, ui.TEXT))
	if lv > 0:
		right.add_child(ui.paragraph("累計熟練 %d；升至 %d 級需 %d。成功率 %.1f%%。" % [int(p.life_prof.get(ui.life_skill, 0)), mini(100, lv + 1), 2 * mini(100, lv + 1) * mini(100, lv + 1), Life.chance(lv) * 100]))
	else:
		var teachers: Array = row.teachers.duplicate()
		teachers.sort_custom(func(a, b): return Data.path_to(p.place, Data.NPCS[a.npc_id].place).size() < Data.path_to(p.place, Data.NPCS[b.npc_id].place).size())
		for teacher in teachers:
			var npc: Dictionary = Data.NPCS[teacher.npc_id]
			right.add_child(ui.paragraph("師父：%s · %s\n學費 %d 兩%s" % [npc.name, npc.place, teacher.price, "，首次贈送" + teacher.tool if teacher.tool != "" else ""]))
			if p.place != npc.place:
				ui.button("尋師 · " + npc.name, func(): travel(ui, npc.place), right)
			else:
				var learn: Button = ui.action("學習%s · %d 兩" % [row.name, teacher.price], "生活學習", ui.life_skill + "|" + str(teacher.npc_id), right)
				learn.disabled = int(p.silver) < int(teacher.price) or not p.enemy.is_empty() or int(p.fight) != 0 or int(p.dungeon) != 0 or p.travel_target != ""
				if int(p.silver) < int(teacher.price): right.add_child(ui.paragraph("銀兩不足，還差 %d 兩。" % (int(teacher.price) - int(p.silver)), ui.GOLD))
	var choice := OptionButton.new()
	choice.custom_minimum_size.x = 280
	var keys: Array = []
	if row.mode != "CRAFT":
		keys.append("")
		choice.add_item(row.verb + "（狩獵實戰）" if row.mode == "HUNT" else row.verb + "（採集）")
	for rc in row.get("recipes", []):
		keys.append(rc.id)
		choice.add_item("%s · 需要 %d 級" % [rc.name, int(rc.get("min_level", 1))])
	choice.select(maxi(0, keys.find(ui.life_recipe)))
	choice.item_selected.connect(func(index: int): ui.life_recipe = keys[index]; ui.signatures.erase("生活"); ui._refresh())
	right.add_child(choice)
	right.add_child(ui.paragraph("設施：%s · 每次 %d 息 · 消耗精力 %d（現有 %d）" % [Life.FEATURES[Life.feature(row, r)], row.cooldown_s, Life.cost(row, r), p.energy], ui.GOLD))
	var locations := Life.locations(ui.life_skill, ui.life_recipe, p.place)
	if not locations.is_empty():
		var location: Dictionary = locations[0]
		if location.place == p.place: right.add_child(ui.paragraph("✓ 當前地點可以工作：" + str(p.place), ui.GOLD))
		else: ui.button("工作地點 · %s（%d 步）" % [location.place, location.steps], func(): travel(ui, location.place), right)
	var controls := Pages.flow(right)
	var counts := [1, 10, 30, 100, 0]
	var batch := OptionButton.new()
	for count in counts: batch.add_item("持續至不足自停" if count == 0 else "嘗試 %d 次後停止" % count)
	batch.select(maxi(0, counts.find(ui.life_count)))
	batch.item_selected.connect(func(index: int): ui.life_count = counts[index])
	controls.add_child(batch)
	var start: Button = ui.button("開始生活掛機", func(): Session.send("生活工作", "%s|%s|%d|%s" % [ui.life_skill, ui.life_recipe, ui.life_count, "休息" if ui.life_rest else "自停"]), controls)
	var auto_rest := CheckBox.new()
	auto_rest.text = "精力不足時自動打坐，回滿後繼續"
	auto_rest.set_pressed_no_signal(ui.life_rest)
	auto_rest.toggled.connect(func(on: bool): ui.life_rest = on; ui.signatures.erase("生活"); ui._refresh())
	right.add_child(auto_rest)
	var why := Life.reason(p, ui.life_skill, ui.life_recipe, not ui.life_rest)
	start.disabled = why != "" or job.get("active", false)
	if why != "": right.add_child(ui.paragraph(why, ui.GOLD))
	if int(p.energy) < Life.cost(row, r): ui.action("打坐恢復精力", "打坐", "", right)
	for tool in Life.tools(row, r): item_line(ui, right, p, tool, 1, "工具")
	for input in r.get("inputs", []): item_line(ui, right, p, input.item, int(input.n), "材料")
	if not r.is_empty():
		var output := Pages.flow(right)
		output.add_child(ui.label("成功產出：%s × %d" % [r.output.item, r.output.n], 16))
		ui.button("出售成品", func(): ui.open_market(true, r.output.item), output)
	else:
		var drops: PackedStringArray = []
		for item in row.get("hunt", {}).get("drops", []) if row.mode == "HUNT" else row.get("yield", []):
			drops.append("%s（%d級）" % [item.item, int(item.get("min_level", 1))])
		right.add_child(ui.paragraph("可能取得：" + "、".join(drops)))
	right.add_child(ui.paragraph("成功熟練 +5，失敗 +2；配方標示熟練倍數另計。失敗仍耗精力，製作材料保留。次數包含失敗；換活動或停止會取消未完成的一次。關閉遊戲或離線不產出。"))
	if row.mode == "HUNT": right.add_child(ui.paragraph("狩獵使用你的武功單獨戰鬥，有受傷風險；撤退或戰敗自停。", ui.GOLD))
	right.add_child(ui.paragraph("依 JY-Mini OL 資料移植；部分配方、數值與師父屬其設計提案，並非原版已證實設定。", ui.MUTED))

static func item_line(ui, parent: Node, p: Dictionary, item: String, need: int, kind: String) -> void:
	var line := Pages.flow(parent)
	line.add_child(ui.label("%s：%s × %d · 持有 %d" % [kind, item, need, int(p.inventory.get(item, 0))], 16))
	if int(p.inventory.get(item, 0)) >= need: return
	ui.button("購買" + item, func(): ui.open_market(false, item), line)
	for id in Data.LIFE:
		for rc in Data.LIFE[id].get("recipes", []):
			if rc.output.item == item: ui.button("%s · %s" % [Data.LIFE[id].name, rc.name], func(): select(ui, id, rc.id), line)
		for y in Data.LIFE[id].get("yield", []):
			if y.item == item: ui.button("用%s採集" % Data.LIFE[id].name, func(): select(ui, id), line)
