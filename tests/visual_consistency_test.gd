extends SceneTree
const Content=preload("res://scripts/journey/open_content.gd")
const Art=preload("res://scripts/journey/character_art.gd")
const Stage=preload("res://scripts/journey/stage.gd")
var checks:=0
var failures:=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _init() -> void:
	var art=Art.new()
	var names: Dictionary={}
	for region in Content.REGIONS:
		var faces: Dictionary={}
		for person in Content.PEOPLE.values():
			if person.region!=region or not person.art.begins_with("actor_npc_"):continue
			check(not faces.has(person.art),"No repeated civilian face anywhere in "+region)
			faces[person.art]=true
			check(person.role not in ["掌事","行旅","鄉里人物"],"Civilian has a specific occupation")
			check(not names.has(person.name),"Resident has an individual name: "+person.name)
			names[person.name]=true
	var stage=Stage.new()
	stage.size=Vector2(1440,710)
	var frame_count:=0
	for key in art.data.characters:
		var entry: Dictionary=art.data.characters[key]
		for pose in entry.frames.size():
			var frame: Dictionary=art.sprite(key,pose)
			var region:=Rect2(frame.region[0],frame.region[1],frame.region[2],frame.region[3])
			check(frame.height>0 and frame.pivot[1]>0,"Actor has an anatomical height and ground point")
			var portrait_data: Array=frame.get("portrait",frame.region)
			var portrait:=Rect2(portrait_data[0],portrait_data[1],portrait_data[2],portrait_data[3])
			check(region.encloses(portrait),"Portrait never samples another actor's cell: "+key)
			if pose==0:check(region.encloses(art.portrait_region(key)),"Public portrait lookup stays inside the idle cell")
			if entry.get("portrait_only",false) or key.begins_with("resident_"):continue
			frame_count+=1
			var scale_value: float=150.0/float(frame.height)
			for lane in 3:
				var p: Vector2=stage.actor_pos({"side":0,"front":true,"lane":lane})
				var highest: float=p.y-float(frame.pivot[1])*scale_value
				var lowest: float=p.y+(float(frame.region[3])-float(frame.pivot[1]))*scale_value
				check(highest>=0 and lowest<=710,"Every combat pose stays inside the battlefield: %s pose %d lane %d"%[key,pose,lane])
				check(absf((float(frame.pivot[1])-float(frame.get("head",[0,frame.region[1],0,0])[1])+float(frame.region[1]))*scale_value-150)<30,"Body height is independent of weapons: "+key)
	stage.free()
	check(frame_count>=200,"All legacy animation poses and open-world fighters were checked")
	check(names.size()==207,"All 200 ordinary residents and seven service characters keep stable identities")
	print("VISUAL CONSISTENCY: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
