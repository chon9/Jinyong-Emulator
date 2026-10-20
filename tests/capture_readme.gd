extends SceneTree

func _init() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://docs/screenshots/" + name + ".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/screenshots")
	var session = root.get_node("Session")
	session.world.add_player(1, "青衫游俠")
	session.world.add_player(2, "墨客")
	session.world.add_player(3, "燕十三")
	session.world.players[1].flags["wd_recommended"] = true
	session.world.players[1].morality = 50
	session.world.act(1, "前往", session.world.Data.SECTS["武當"].place)
	session.world.act(1, "拜師", "武當")
	for id in [2, 3]: session.world.players[id].place = session.world.players[1].place
	session.world.act(1, "組隊邀請", "2")
	session.world.act(2, "接受邀請", "1")
	session.world.act(3, "切磋", "1")
	session._publish()
	var ui = load("res://scenes/main.tscn").instantiate()
	root.add_child(ui)
	ui._message("隊伍", "墨客加入隊伍。五湖四海，從此有人同行。")
	await capture("jianghu")
	ui.selected_peer = 2
	ui.tabs.current_tab = 6
	ui._refresh()
	await capture("multiplayer")
	ui.tabs.current_tab = 5
	ui._refresh()
	await capture("music")
	var p: Dictionary = session.world.players[1]
	p.skills.merge({"基本劍法": 20, "太極劍法": 30, "武當心法": 25, "梯雲縱": 15, "俠義": 35}, true)
	p.combat_xp = 25000
	p.inventory["木劍"] = 1
	session.world.act(1, "裝備", "木劍")
	session.world.act(1, "裝備", "武當心法")
	session.world.act(1, "裝備", "梯雲縱")
	p.place = session.world.Data.NPCS["n_wd_zhangsongxi"].place
	session._publish()
	ui.tabs.current_tab = 1
	ui._refresh()
	await capture("martial")
	ui.navigation_query = "武當心法"
	ui.tabs.current_tab = 4
	ui._refresh()
	await capture("navigation")
	ui._navigate(session.world.Data.NPCS["n_wd_yudaiyan"].place)
	await capture("route")
	p.enemy = {}
	p.travel_target = ""
	p.travel_route = []
	p.skills.merge({"武當身法": 40, "俠義": 40}, true)
	p.place = session.world.Data.NPCS[session.world.Data.QUESTS.q_wd_yinliu.giver].place
	if not session.world.act(1, "接受任務", "q_wd_yinliu"):
		push_error("Screenshot fixture failed to accept quest")
		quit(1)
		return
	session._publish()
	ui.open_quest("q_wd_yinliu")
	await capture("quests")
	p.place = "揚州城"
	p.silver = 1000
	session._publish()
	ui.open_market(false, "金創藥")
	await capture("shop")
	session.world.social.leave_party(1)
	p.place = "黑風林"
	p.dungeon_cooldowns = {}
	session._publish()
	ui.open_page(8)
	await capture("dungeons")
	if not session.world.act(1, "副本進入", "blackwind"):
		push_error("Screenshot fixture failed to enter dungeon")
		quit(1)
		return
	session.world.act(1, "副本準備")
	session.world.act(1, "副本開戰")
	session._publish()
	await capture("dungeon-combat")
	session.world.act(1, "副本離開")
	for timer in session.get_children():
		if timer is Timer: timer.stop()
	p.place = session.world.Life.locations("life_mining", "", "揚州城")[0].place
	p.life_levels = {"life_mining": 25, "life_fishing": 12, "life_smithing": 20, "life_woodcut": 20}
	p.life_prof = {"life_mining": 1250, "life_fishing": 288, "life_smithing": 800, "life_woodcut": 800}
	p.energy = 100
	p.inventory["十字鎬"] = 1
	session.world.rng.seed = 42
	if not session.world.act(1, "生活工作", "life_mining||10|休息"):
		push_error("Screenshot fixture failed to start mining")
		quit(1)
		return
	for i in 18: session.world.step()
	session._publish()
	ui.life_skill = "life_mining"
	ui.life_recipe = ""
	ui.open_page(9)
	await capture("life-skills")
	quit()
