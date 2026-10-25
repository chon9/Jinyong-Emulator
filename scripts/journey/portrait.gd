extends Control
## The same source masks as combat, also applied to dialogue and small portraits.
const Art = preload("res://scripts/journey/character_art.gd")
var texture: Texture2D
var frame: Dictionary
var crop: Rect2

func _draw() -> void:
	if texture == null or crop.size.x <= 0 or crop.size.y <= 0: return
	var scale_value := minf(size.x/crop.size.x,size.y/crop.size.y)
	var offset := (size-crop.size*scale_value)*.5
	for source in Art.source_regions(frame,crop):
		draw_texture_rect_region(texture,Rect2(offset+(source.position-crop.position)*scale_value,source.size*scale_value),source)
