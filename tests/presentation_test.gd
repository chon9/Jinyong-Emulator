extends SceneTree
const Art=preload("res://scripts/journey/character_art.gd")
const Stage=preload("res://scripts/journey/stage.gd")
const Sounds=preload("res://scripts/journey/sfx.gd")
var checks:=0
var failures:=[]
class FakeBattle:
	extends RefCounted
	func by_id(_id: String) -> Dictionary: return {"weapon":"劍"}
class RecordingSounds:
	extends RefCounted
	var history: Array=[]
	func play(key: String) -> void: history.append(key)
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var art=Art.new()
	var frame: Dictionary=art.sprite("npc_17")
	check(frame.has("draw_regions"),"The reported scholar includes a foreign-figure exclusion mask")
	var stage=Stage.new()
	var portrait=stage.portrait("actor_npc_17")
	check(portrait.frame.draw_regions==frame.draw_regions,"Dialogue actually uses the masked renderer")
	var head=stage.portrait("actor_npc_17",true)
	check(head.frame.draw_regions==frame.draw_regions,"Town portrait uses the same exclusion mask")
	for key in art.data.characters:
		var entry: Dictionary=art.data.characters[key]
		for pose in entry.frames.size():
			var value: Dictionary=art.sprite(key,pose)
			var r: Array=value.region
			var full:=Rect2(r[0],r[1],r[2],r[3])
			for crop in [full,art.portrait_region(key) if pose==0 else full]:
				var regions=Art.source_regions(value,crop)
				check(not regions.is_empty(),"A masked figure remains visible: "+key)
				for source in regions:check(full.encloses(source) and crop.encloses(source),"Every quad stays in its figure and requested portrait")
	stage.battle=FakeBattle.new()
	stage.sounds=RecordingSounds.new()
	var attack={"kind":"attack","actor":"hero","amount":30}
	stage.show_event(attack)
	stage._process(1.2)
	check(stage.sounds.history==["fx_sword_ready","fx_sword_hit"],"A frame longer than the animation still plays its impact")
	stage._process(.1)
	check(stage.sounds.history.size()==2,"The delayed impact is not duplicated")
	stage.show_event(attack)
	stage.show_event(attack)
	check(stage.sounds.history.slice(2)==["fx_sword_ready","fx_sword_hit","fx_sword_ready"],"A new action cannot discard a pending impact")
	var sounds=Sounds.new()
	root.add_child(sounds)
	sounds.enabled=true
	sounds.set_volume(.65)
	var bus:=AudioServer.get_bus_index("Effects")
	check(bus>=0 and not AudioServer.is_bus_mute(bus),"Effects has its own audible bus")
	var music=root.get_node("Bgm")
	music.set_enabled(false)
	check(not AudioServer.is_bus_mute(bus),"Muting music does not mute battle effects")
	sounds.toggle()
	check(AudioServer.is_bus_mute(bus),"Effect mute affects currently playing voices immediately")
	sounds.toggle()
	check(not AudioServer.is_bus_mute(bus),"Unmute restores effects")
	sounds.set_volume(0)
	check(not sounds.audible() and AudioServer.is_bus_mute(bus),"Zero effects volume is silent")
	sounds.toggle()
	check(sounds.audible() and is_equal_approx(sounds.volume,.65),"Explicit sound-on recovers a previously zero-volume setting")
	music.set_enabled(true)
	portrait.free();head.free();stage.free();sounds.queue_free()
	print("PRESENTATION: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
