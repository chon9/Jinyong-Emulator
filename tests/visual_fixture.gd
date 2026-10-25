extends SceneTree
func _init() -> void:call_deferred("run")
func run() -> void:
	var session=root.get_node("Session")
	assert(session.save_path.contains("test-results"))
	var campaign=preload("res://scripts/journey/chapter.gd").new()
	preload("res://scripts/journey/atlas.gd").ensure(campaign)
	preload("res://scripts/journey/open_world.gd").enter(campaign,"嘉興鎮","青溪客棧")
	for id in ["sword","healer","staff"]:campaign.recruit(id)
	campaign.state.silver=500
	campaign.state.potential=500
	campaign.state.inventory["金創藥"]=6
	campaign.state.formation={"hero":{"lane":1,"front":true},"sword":{"lane":2,"front":false},"healer":{"lane":1,"front":false},"staff":{"lane":0,"front":true}}
	# Keep defaults for reserve formation entries required by save validation.
	for id in campaign.HEROES:
		if not campaign.state.formation.has(id):campaign.state.formation[id]={"lane":0,"front":false}
	session.chapter_data=campaign.state.duplicate(true)
	assert(session.save_game())
	print("VISUAL FIXTURE: four legacy companions exported for real browser import")
	quit()
