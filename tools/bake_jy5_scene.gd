extends SceneTree
## Deterministic asset conversion: reconstruct selected tiles without game scripts/events.
func _init() -> void:
	call_deferred("run")

func run() -> void:
	var input := "res://.tools/jy5-map44.json"
	var output := "res://.tools/town44.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene-json="): input=arg.trim_prefix("--scene-json=")
		if arg.begins_with("--output-image="): output=arg.trim_prefix("--output-image=")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input))
	var w:=int(data.width)
	var h:=int(data.height)
	var image:=Image.create(w*32,h*32,false,Image.FORMAT_RGBA8)
	image.fill(Color("182723"))
	if FileAccess.file_exists(data.panorama):
		var pano:=Image.load_from_file(data.panorama)
		pano.convert(Image.FORMAT_RGBA8)
		image.blend_rect(pano,Rect2i(0,0,pano.get_width(),pano.get_height()),Vector2i.ZERO)
	var tileset:=Image.load_from_file(data.tileset)
	tileset.convert(Image.FORMAT_RGBA8)
	for layer in int(data.depth):
		for y in h:
			for x in w:
				var id:=int(data.tiles[(layer*h+y)*w+x])
				if id<384: continue
				var index:=id-384
				image.blend_rect(tileset,Rect2i((index%8)*32,(index/8)*32,32,32),Vector2i(x*32,y*32))
	var error:=image.save_webp(output,true,.90) if output.ends_with(".webp") else image.save_png(output)
	print("Scene reconstructed: ",output," ",w*32,"x",h*32," status ",error)
	quit(0 if error==OK else 1)
