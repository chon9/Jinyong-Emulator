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
	var grid := graph.get_point_path(graph.get_closest_point(from),graph.get_closest_point(to))
	if grid.size() < 3: return grid
	var result := PackedVector2Array([grid[0]])
	var index := 0
	while index < grid.size()-1:
		var furthest := index+1
		for next in range(index+2,grid.size()):
			if line_passable(grid[index],grid[next]): furthest = next
		result.append(grid[furthest])
		index = furthest
	return result

func connected(from: Vector2i, to: Vector2i) -> bool:
	if to.x < 0 or to.y < 0 or to.x >= width or to.y >= height: return false
	var a := from.y*width+from.x
	var b := to.y*width+to.x
	return graph.has_point(a) and graph.has_point(b) and (a == b or graph.are_points_connected(a,b))

func line_passable(from: Vector2, to: Vector2) -> bool:
	var count := maxi(1,int(ceil(from.distance_to(to)/4)))
	var previous := Vector2i(floor(from.x/32),floor(from.y/32))
	for i in range(1,count+1):
		var p := from.lerp(to,float(i)/count)
		var current := Vector2i(floor(p.x/32),floor(p.y/32))
		if current == previous: continue
		if current.x != previous.x and current.y != previous.y:
			var side_x := Vector2i(current.x,previous.y)
			var side_y := Vector2i(previous.x,current.y)
			if not connected(previous,side_x) or not connected(side_x,current) or not connected(previous,side_y) or not connected(side_y,current): return false
		elif not connected(previous,current): return false
		previous = current
	return true
