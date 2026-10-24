extends RefCounted
## XP directional passages, constrained to the connected street network.
var graph := AStar2D.new()
var anchors := {}
var width := 0
var height := 0
var cells := {}

func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/town_navigation.json"))
	width = int(data.width)
	height = int(data.height)
	var pending := [Vector2i(int(data.anchors["青溪客棧"][0]),int(data.anchors["青溪客棧"][1]))]
	var directions := [[Vector2i.DOWN,1,8],[Vector2i.LEFT,2,4],[Vector2i.RIGHT,4,2],[Vector2i.UP,8,1]]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		var id := cell.y*width+cell.x
		if cells.has(id): continue
		cells[id] = cell
		graph.add_point(id,Vector2(cell)*32+Vector2(16,16))
		for d in directions:
			var next: Vector2i = cell+d[0]
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height: continue
			var other := next.y*width+next.x
			if int(data.passages[id]) & int(d[1]) or int(data.passages[other]) & int(d[2]): continue
			if not cells.has(other): pending.append(next)
	for id in cells:
		var cell: Vector2i = cells[id]
		for d in directions:
			var next: Vector2i = cell+d[0]
			var other := next.y*width+next.x
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height or not cells.has(other): continue
			if int(data.passages[id]) & int(d[1]) or int(data.passages[other]) & int(d[2]): continue
			graph.connect_points(id,other)
	for name in data.anchors:
		anchors[name] = Vector2(data.anchors[name][0]*32+16,data.anchors[name][1]*32+16)

func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	return graph.get_point_path(graph.get_closest_point(from),graph.get_closest_point(to))
