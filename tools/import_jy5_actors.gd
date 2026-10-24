extends SceneTree
## Import only explicitly selected, owner-supplied character/effect sheets.
func _init() -> void:
	call_deferred("run")

func run() -> void:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="): source = arg.trim_prefix("--source=")
	if source == "": quit(1); return
	var selection := {"swordsman":"huashandizi_battle.png", "companion":"huashandizi_battle2.png", "blade":"tianlongsword2.png", "boss":"tianbattle.png", "rogue":"gujianchenbattle.png", "healer":"azhu.png", "staff":"monk2.png", "taoist":"wudang.png", "elder":"huatiegan.png", "wanderer":"yangguo.png", "monk":"oldmonkbattle.png"}
	for name in selection:
		var sheet := Image.load_from_file(source+"/Graphics/Characters/"+selection[name])
		sheet.convert(Image.FORMAT_RGBA8)
		var rows := 1 if name == "staff" else (2 if name == "healer" else 4)
		# Keep the same source-cell registration across frames; remove only the XP colour key.
		var out := Image.create(8*160,rows*160,false,Image.FORMAT_RGBA8)
		for row in rows:
			for frame in 8:
				out.blit_rect(sheet,Rect2i(frame*200+20,row*200+20,160,160),Vector2i(frame*160,row*160))
		for y in out.get_height():
			for x in out.get_width():
				var c := out.get_pixel(x,y)
				if c.r > .85 and c.b > .85 and c.g < .15: out.set_pixel(x,y,Color.TRANSPARENT)
		out.save_png("res://assets/actors/"+name+".png")
		print("Imported character: ",name)
	for entry in [["hit","003-Attack01.png"],["slash","007-Weapon02.png"],["heal","013-Heal02.png"],["burst","023-Burst01.png"]]:
		var effect := Image.load_from_file(source+"/Graphics/Animations/"+entry[1])
		effect.save_png("res://assets/effects/"+entry[0]+".png")
	quit()
