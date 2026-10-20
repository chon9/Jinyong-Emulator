extends RefCounted
const Data = preload("res://scripts/content.gd")
const Pages = preload("res://scripts/classic/activity_pages.gd")

static func build(ui, body: VBoxContainer, p: Dictionary) -> void:
	body.add_child(ui.label("江湖副本 · 單人或五人隊伍", 23, ui.GOLD))
	var run: Dictionary = Session.state.get("dungeon", {})
	if not run.is_empty():
		active(ui, body, p, run)
		return
	body.add_child(ui.paragraph("到入口後由隊長建立副本，每位隊員按準備才開戰。每關之間可打坐、用藥；通關自動發獎。以下均為本作改編玩法。"))
	var panes := Pages.columns(ui, body)
	for id in Data.DUNGEONS:
		var d: Dictionary = Data.DUNGEONS[id]
		Pages.entry(ui, "%s\n%d 關 · 首通 %s" % [d.name, d.stages.size(), "已領" if int(p.dungeon_clears.get(id, 0)) > 0 else "未領"], panes[0], ui.selected_dungeon == id, func(): ui.selected_dungeon = id; ui.signatures.erase("副本"); ui._refresh())
	var d: Dictionary = Data.DUNGEONS[ui.selected_dungeon]
	Pages.ui_label(ui, panes[1], d.name, 23)
	panes[1].add_child(ui.paragraph(d.desc, ui.TEXT))
	panes[1].add_child(ui.paragraph("入口：%s\n實戰門檻：%d　·　通關冷卻 %d 分鐘\n建議：%s" % [d.entry, d.min_xp, int(d.cooldown) / 60, d.recommended]))
	if p.place != d.entry:
		ui.button("前往副本入口 · " + str(d.entry), func(): ui._navigate(d.entry), panes[1])
	else:
		var reason: String = Session.world.dungeons.entry_reason(int(Session.state.self_id), d) if Session.world.players.has(int(Session.state.self_id)) else ""
		# Clients use replicated character fields; the host checks every member again.
		if Session.mode.ends_with("客戶端"):
			reason = "實戰不足，需要 %d。" % int(d.min_xp) if int(p.combat_xp) < int(d.min_xp) else ""
			var left := int(p.dungeon_cooldowns.get(d.id, 0)) - int(Time.get_unix_time_from_system())
			if left > 0: reason = "冷卻尚餘 %d 秒。" % left
		if int(p.party) != 0 and int(Session.state.get("social", {}).get("party", {}).get("leader", 0)) != int(Session.state.self_id): reason = "請由隊長建立副本，所有隊員須在入口集合。"
		var members: Array = Session.state.get("social", {}).get("party", {}).get("members", [])
		for member in Session.state.roster:
			if int(member.id) in members and member.place != d.entry: reason = "%s尚未抵達入口：%s" % [member.name, d.entry]
		var enter: Button = ui.action("建立副本 · 隊員稍後逐一準備" if int(p.party) != 0 else "進入副本", "副本進入", d.id, panes[1])
		enter.disabled = reason != "" or not p.enemy.is_empty() or int(p.fight) != 0
		if reason != "": panes[1].add_child(ui.paragraph(reason, ui.GOLD))
	panes[1].add_child(ui.paragraph("每人通關：%d 兩、%d 學點、%d 實戰。\n首次另加 %d 學點與首通道具。" % [d.rewards.silver, d.rewards.points, d.rewards.xp, d.first_clear.points], ui.GOLD))
	for item in d.first_clear.get("items", []): panes[1].add_child(ui.paragraph("首通道具：%s × %d" % [item.item, item.n]))
	for stage in d.stages:
		var names: PackedStringArray = []
		for e in stage.enemies: names.append(e.enemy)
		panes[1].add_child(ui.paragraph(stage.name + " · " + "、".join(names)))

static func active(ui, body: VBoxContainer, p: Dictionary, run: Dictionary) -> void:
	var d: Dictionary = Data.DUNGEONS[run.definition]
	Pages.ui_label(ui, body, "%s · %s · 已過 %d/%d 關" % [d.name, {"READY": "等待準備", "FIGHT": "交戰中", "CLEARED": "已通關", "FAILED": "挑戰失敗"}.get(run.phase, run.phase), run.cleared, d.stages.size()], 21)
	var buttons := Pages.flow(body)
	if run.phase == "READY":
		ui.action("取消準備" if run.ready.get(Session.state.self_id, false) else "我已準備", "副本準備", "", buttons)
		if int(run.leader) == int(Session.state.self_id):
			var start: Button = ui.action("開始這一關", "副本開戰", "", buttons)
			start.disabled = run.roster.any(func(member): return not member.ready or int(member.hp) <= 0)
			if start.disabled: body.add_child(ui.paragraph("所有隊員按準備後，隊長才能開戰。", ui.GOLD))
		ui.action("打坐療傷", "打坐", "", buttons)
	if run.phase == "CLEARED": body.add_child(ui.paragraph("通關與首通獎勵已自動入帳。任務頁的討伐委託可另外領賞。", ui.GOLD))
	if run.phase == "FAILED": body.add_child(ui.paragraph("未發通關獎勵。退出療傷後可重新挑戰。", ui.GOLD))
	ui.button("退出副本（本次進度不保留）" if not run.phase in ["CLEARED", "FAILED"] else "返回江湖", func(): Session.send("副本離開"); ui.open_page(0), buttons)
	for member in run.roster:
		var line := Pages.flow(body)
		line.add_child(ui.label("%s%s · 氣血 %d/%d · %s" % ["★ " if int(run.leader) == int(member.id) else "", member.name, member.hp, member.max_hp, "失去戰力" if member.down else ("已準備" if member.ready else "未準備")], 16))
		if int(member.id) != int(Session.state.self_id):
			var heal: Button = ui.action("金創藥援護", "治療隊友", str(member.id), line)
			heal.disabled = member.down or int(member.hp) >= int(member.max_hp) or int(p.inventory.get("金創藥", 0)) < 1
	if not run.enemy.is_empty(): body.add_child(ui.paragraph("目前敵人：%s · %d/%d 氣血" % [run.enemy.name, run.enemy.hp, run.enemy.max_hp], ui.GOLD))
	body.add_child(ui.paragraph("\n".join(run.log.slice(-7)), ui.TEXT))
