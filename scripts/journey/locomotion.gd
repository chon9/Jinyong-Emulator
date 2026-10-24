extends RefCounted
## Grounded walking: animation phase follows distance, not elapsed wall time.
enum Facing { SOUTH, EAST, NORTH, WEST }
const WALK_CYCLE := [1,2,3,2]
const STRIDE := 148.0
const MAX_SPEED := 185.0
const ACCELERATION := 620.0
var position := Vector2.ZERO
var route := PackedVector2Array()
var cursor := 0
var speed := 0.0
var distance_walked := 0.0
var facing := Facing.SOUTH
var finished := false
var last_motion := Vector2.ZERO

func reset(at: Vector2) -> void:
	position = at
	route = PackedVector2Array()
	cursor = 0
	speed = 0
	last_motion = Vector2.ZERO
	finished = false

func follow(points: PackedVector2Array) -> void:
	route = points
	cursor = 0
	finished = false
	while cursor < route.size()-1 and position.distance_to(route[cursor]) < .1: cursor += 1

func advance(delta: float) -> void:
	finished = false
	last_motion = Vector2.ZERO
	if route.is_empty(): speed = 0; return
	var remaining := position.distance_to(route[cursor])
	for i in range(cursor+1,route.size()): remaining += route[i-1].distance_to(route[i])
	var desired := minf(MAX_SPEED,maxf(32,sqrt(2*ACCELERATION*remaining)))
	speed = move_toward(speed,desired,ACCELERATION*delta)
	var allowance := speed*maxf(0,delta)
	var before := position
	while cursor < route.size() and allowance > 0:
		var distance := position.distance_to(route[cursor])
		var step := minf(allowance,distance)
		position = position.move_toward(route[cursor],step)
		allowance -= step
		distance_walked += step
		if distance <= step+.01: cursor += 1
	last_motion = position-before
	if last_motion.length_squared() > .001:
		# Hysteresis prevents east/north flicker on shallow diagonal routes.
		var horizontal := absf(last_motion.x)
		var vertical := absf(last_motion.y)
		if horizontal > vertical*1.25: facing = Facing.WEST if last_motion.x < 0 else Facing.EAST
		elif vertical > horizontal*1.25: facing = Facing.NORTH if last_motion.y < 0 else Facing.SOUTH
		elif facing in [Facing.EAST,Facing.WEST] and horizontal > .01: facing = Facing.WEST if last_motion.x < 0 else Facing.EAST
		else: facing = Facing.NORTH if last_motion.y < 0 else Facing.SOUTH
	if cursor >= route.size():
		route = PackedVector2Array()
		cursor = 0
		speed = 0
		finished = true

func frame() -> int:
	if route.is_empty() or last_motion.length_squared() < .001: return 0
	return WALK_CYCLE[int(fmod(distance_walked,STRIDE)/STRIDE*WALK_CYCLE.size())%WALK_CYCLE.size()]
