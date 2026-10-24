extends RefCounted
## Shared illustrated game-window, button and inventory-icon skin.
var bank
var regions: Array

func _init(resources) -> void:
	bank = resources
	regions = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_skin.json"))

func texture(index: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = bank.get_asset("res://assets/ui/skin.png")
	var r: Array = regions[index]
	atlas.region = Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
	atlas.filter_clip = true
	return atlas

func box(index: int, button: bool = false) -> StyleBoxTexture:
	var result := StyleBoxTexture.new()
	result.texture = bank.get_asset("res://assets/ui/skin.png")
	var r: Array = regions[index]
	result.region_rect = Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
	result.set_texture_margin_all(8 if button else 24)
	result.content_margin_left = 12
	result.content_margin_right = 12
	result.content_margin_top = 6
	result.content_margin_bottom = 6
	return result
