extends Node
## Resource I/O happens during preparation, never in a drawing callback.
signal progress(done: int, total: int)
var cache := {}
var prepared := false

func prepare() -> void:
	var paths: Array[String] = []
	for folder in ["journey", "actors", "effects", "sfx", "town"]:
		for name in DirAccess.get_files_at("res://assets/"+folder):
			if name.ends_with(".remap") or name.ends_with(".import"): continue
			if name.get_extension() in ["png", "webp", "ogg"]: paths.append("res://assets/"+folder+"/"+name)
	# Exported PCKs expose imported resources through ResourceLoader, not raw folder scans.
	for file in ["town/qingxi.webp", "town/world.png", "actors/taoist.png", "actors/elder.png", "actors/wanderer.png", "actors/monk.png", "actors/swordsman.png", "actors/companion.png", "actors/blade.png", "actors/boss.png", "actors/rogue.png", "actors/healer.png", "actors/staff.png", "effects/hit.png", "effects/slash.png", "effects/heal.png", "effects/burst.png", "sfx/swing.ogg", "sfx/hit.ogg", "sfx/heavy.ogg", "sfx/heal.ogg", "sfx/accept.ogg"]:
		var path: String = "res://assets/"+file
		if not path in paths: paths.append(path)
	# Explicitly cover dynamically selected chapter art in exported builds.
	for art in ["unit_player_m", "unit_huashan_m", "unit_emei_f", "unit_shaolin_m", "unit_wudang_m", "unit_look_m06", "unit_m_bandit", "unit_gaibang_f", "unit_xuedao_m", "unit_xingxiu_m"]:
		for pose in ["idle", "attack", "hurt"]:
			var path: String = "res://assets/journey/"+art+"_"+pose+".png"
			if ResourceLoader.exists(path) and not path in paths: paths.append(path)
	for bg in ["bg_huayin_road", "bg_river_road", "bg_guiwang"]:
		var path: String = "res://assets/journey/"+bg+".png"
		if not path in paths: paths.append(path)
	for i in paths.size():
		cache[paths[i]] = load(paths[i])
		progress.emit(i+1,paths.size())
		await get_tree().process_frame
	prepared = true

func get_asset(path: String) -> Resource:
	return cache.get(path)
