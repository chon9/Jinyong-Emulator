extends RefCounted
## Metadata-only animation lookup; original generated pixels remain unchanged.
var data: Dictionary

func _init() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/character_art.json"))
	if FileAccess.file_exists("res://data/open_art.json"):
		data.characters.merge(JSON.parse_string(FileAccess.get_file_as_string("res://data/open_art.json")))
	if FileAccess.file_exists("res://data/visual_art.json"):
		data.characters.merge(JSON.parse_string(FileAccess.get_file_as_string("res://data/visual_art.json")),true)
	if FileAccess.file_exists("res://data/companion_art.json"):
		data.characters.merge(JSON.parse_string(FileAccess.get_file_as_string("res://data/companion_art.json")),true)
	if FileAccess.file_exists("res://data/support_art.json"):
		data.characters.merge(JSON.parse_string(FileAccess.get_file_as_string("res://data/support_art.json")),true)
	if FileAccess.file_exists("res://data/character_masks.json"):
		var masks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/character_masks.json"))
		for key in masks:
			for pose in masks[key]:
				data.characters[key].frames[int(pose)].draw_regions = masks[key][pose]

static func source_regions(frame: Dictionary,crop: Rect2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var r: Array = frame.region
	var origin := Vector2(r[0],r[1])
	var bounded := crop.intersection(Rect2(origin,Vector2(r[2],r[3])))
	if not bounded.has_area(): return result
	if not frame.has("draw_regions"): return [bounded]
	for strip in frame.draw_regions:
		var source := Rect2(origin+Vector2(strip[0],strip[1]),Vector2(strip[2],strip[3])).intersection(bounded)
		if source.has_area(): result.append(source)
	return result

func sprite(key: String, pose: int = 0) -> Dictionary:
	var entry: Dictionary = data.characters.get(key,data.characters.swordsman)
	var frame: Dictionary = entry.frames[clampi(pose,0,entry.frames.size()-1)].duplicate()
	frame.texture = entry.texture
	frame.height = frame.get("scale_height",entry.height)
	return frame

func walk(direction: int, pose: int) -> Dictionary:
	var row := 0 if direction == 0 else (2 if direction == 2 else 1)
	var frame: Dictionary = data.walk[row][clampi(pose,0,3)].duplicate()
	frame.texture = "hero-walk.png"
	frame.height = data.walk_height
	return frame

func portrait_key(art: String) -> String:
	if art.begins_with("actor_"): return art.trim_prefix("actor_")
	return {"unit_player_m":"swordsman","unit_huashan_m":"companion","unit_emei_f":"healer","unit_shaolin_m":"staff","unit_m_bandit":"blade","unit_xuedao_m":"boss","unit_xingxiu_m":"rogue","unit_wudang_m":"taoist","unit_look_m06":"elder","unit_gaibang_f":"doctor"}.get(art,"swordsman")

func portrait_region(key: String) -> Rect2:
	var frame := sprite(key)
	if frame.has("portrait"):
		var p: Array=frame.portrait
		return Rect2(p[0],p[1],p[2],p[3])
	var bounds: Array = frame.bounds
	var rect: Array = frame.region
	# An upper-body crop keeps faces readable in party and dialogue medallions.
	var h := float(bounds[3])*.74
	var w := minf(float(rect[2]),h*.84)
	var x := clampf(float(frame.pivot[0])-w*.5,0,float(rect[2])-w)
	return Rect2(float(rect[0])+x,float(rect[1])+float(bounds[1]),w,h)
