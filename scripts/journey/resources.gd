extends Node
## Resource I/O happens during preparation, never in a drawing callback.
signal progress(done: int, total: int)
var cache := {}
var prepared := false

func prepare() -> void:
	var paths: Array[String] = []
	for folder in ["characters", "ui", "effects", "sfx", "town", "open_world"]:
		for name in DirAccess.get_files_at("res://assets/"+folder):
			if name.ends_with(".remap") or name.ends_with(".import"): continue
			if name.get_extension() in ["png", "webp", "ogg"]: paths.append("res://assets/"+folder+"/"+name)
	# Exported PCKs expose imported resources through ResourceLoader, not raw folder scans.
	paths.append("res://assets/characters/rogue.png")
	for file in ["town/qingxi.webp", "town/world.png", "characters/combat-a.png", "characters/combat-b.png", "characters/combat-c.png", "characters/hero-variants.png", "characters/hero-walk.png", "ui/skin.png", "ui/items.png", "effects/hit.png", "effects/slash.png", "effects/heal.png", "effects/burst.png", "sfx/swing.ogg", "sfx/hit.ogg", "sfx/heavy.ogg", "sfx/heal.ogg", "sfx/accept.ogg"]:
		var path: String = "res://assets/"+file
		if not path in paths: paths.append(path)
	for bg in ["bg_huayin_road", "bg_river_road", "bg_guiwang"]:
		var path: String = "res://assets/journey/"+bg+".png"
		if not path in paths: paths.append(path)
	for group in 10:paths.append("res://assets/open_world/foes-%02d.png"%(group+1))
	for group in 5:paths.append("res://assets/open_world/heroes-%d.png"%(group+1))
	for name in ["residents","mu-nianci","scene-inn","scene-temple","scene-mountain","scene-market"]:paths.append("res://assets/open_world/"+name+".png")
	paths.assign(Array(paths).reduce(func(acc,p):
		if not p in acc:acc.append(p)
		return acc,[]))
	for i in paths.size():
		cache[paths[i]] = load(paths[i])
		progress.emit(i+1,paths.size())
		await get_tree().process_frame
	prepared = true

func get_asset(path: String) -> Resource:
	return cache.get(path.simplify_path())
