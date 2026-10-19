extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var session = root.get_node("Session")
	session.world.players[1].name = "青衫游俠"
	session.world.add_player(2, "墨客")
	session.world.add_player(3, "燕十三")
	session.world.act(1, "組隊邀請", "2")
	session.world.act(2, "接受邀請", "1")
	session.world.act(3, "切磋", "1")
	session._publish()
	var ui = load("res://scenes/main.tscn").instantiate()
	root.add_child(ui)
	ui.selected_peer = 2
	ui.tabs.current_tab = 6
	ui._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://test-results/social-preview.png")
	quit()
