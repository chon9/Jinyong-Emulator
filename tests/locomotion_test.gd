extends SceneTree
const Motion = preload("res://scripts/journey/locomotion.gd")
const Town = preload("res://scripts/journey/town.gd")
const Art = preload("res://scripts/journey/character_art.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures+=1; push_error(message)
func _init() -> void:
	var motion = Motion.new()
	for i in 60: motion.advance(1.0/60)
	check(motion.frame()==0 and motion.position==Vector2.ZERO,"Idle does not slide or animate")
	for target in [Vector2(500,0),Vector2(500,-500),Vector2(0,-500),Vector2.ZERO]:
		motion.follow(PackedVector2Array([target]))
		for i in 600:
			motion.advance(1.0/60)
			if motion.finished: break
		check(motion.position.distance_to(target)<.01 and motion.route.is_empty(),"Exact arrival on all four directions")
		check(motion.frame()==0,"Returns to standing at arrival")
	check(motion.facing==Motion.Facing.SOUTH,"South is distinct from east/west")
	motion.follow(PackedVector2Array([Vector2.ZERO]))
	motion.advance(.016)
	check(motion.finished,"Already at destination still emits arrival once")
	motion.advance(.016)
	check(not motion.finished,"Arrival is not repeatedly emitted")
	var town=Town.new()
	for origin in town.anchors:
		for destination in town.anchors:
			var route=town.route(town.anchors[origin],town.anchors[destination])
			check(not route.is_empty(),"Every NPC remains reachable")
			for i in range(1,route.size()): check(town.line_passable(route[i-1],route[i]),"Smoothed route stays on connected streets")
	var art=Art.new()
	for key in art.data.characters:
		var base=art.sprite(key)
		for pose in 4:
			var frame=art.sprite(key,pose)
			check(frame.height>0 and absf(float(frame.body_height)/float(frame.height)-1.0)<.1,"Battle poses preserve normalized anatomical height")
			check(frame.pivot[1]<=frame.region[3],"Ground anchor remains within its cell")
	check(art.walk(0,1).region!=art.walk(2,1).region,"Front and back use separate walking art")
	check(art.walk(1,1).region==art.walk(3,1).region,"West mirrors the same east identity")
	print("LOCOMOTION TEST: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
