extends Control
## Illustrated map and animated side-view actors; all rules live outside this view.
signal place_selected(place: String)
signal unit_selected(id: String)
signal arrived(place: String)
signal walking
const Locomotion = preload("res://scripts/journey/locomotion.gd")
const CharacterArt = preload("res://scripts/journey/character_art.gd")
const Town = preload("res://scripts/journey/town.gd")
const Atlas = preload("res://scripts/journey/atlas.gd")
const Chapter = preload("res://scripts/journey/chapter.gd")
const GOLD := Color("d7b77b")
const IVORY := Color("f0e6cf")
var campaign
var battle
var bank
var sounds
var town = Town.new()
var motion = Locomotion.new()
var character_art = CharacterArt.new()
var reset_camera := true
var route := PackedVector2Array()
var route_index := 0
var requested_place := ""
var synced_place := ""
var camera := Vector2.ZERO
var facing_left := false
var zoom := .92
var impact_played := false
var prepared := false
var selected := ""
var event := {}
var animation := 0.0
var clock := 0.0
var avatar := Vector2.ZERO
var destination := Vector2.ZERO
var bounds := {}
var font: Font

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	font = load("res://assets/fonts/LXGWWenKaiTC-Regular.ttf")
	set_process(true)

func tex(name: String) -> Texture2D:
	return bank.get_asset("res://assets/journey/"+name+".png") if bank != null else null

func asset(path: String) -> Texture2D:
	return bank.get_asset("res://assets/"+path) if bank != null else null

func portrait(art: String) -> Texture2D:
	var key: String = character_art.portrait_key(art)
	var frame: Dictionary = character_art.sprite(key)
	var atlas := AtlasTexture.new()
	atlas.atlas = asset("characters/"+frame.texture)
	atlas.region = character_art.portrait_region(key)
	atlas.filter_clip = true
	return atlas

func go_to(place: String) -> bool:
	if not town.anchors.has(place): return false
	requested_place = place
	route = town.route(avatar,town.anchors[place])
	route_index = 0
	motion.position = avatar
	motion.follow(route)
	return not route.is_empty()

func cancel_walk() -> void:
	route = PackedVector2Array()
	requested_place = ""
	synced_place = ""
	motion.reset(avatar)
	reset_camera = true

func sync_location() -> void:
	if campaign != null and synced_place != campaign.state.place and route.is_empty():
		avatar = town.anchors[campaign.state.place]
		synced_place = campaign.state.place
		motion.reset(avatar)
		reset_camera = true

func is_near_npc() -> bool:
	return avatar.distance_to(town.anchors[campaign.state.place]) < 65 and route.is_empty()

func show_event(value: Dictionary) -> void:
	event = value
	animation = .8
	impact_played = false
	if sounds != null and value.get("kind","") not in ["guard","charge","stun"]: sounds.play("heal" if value.get("kind","") == "heal" else "swing")
	queue_redraw()

func _process(delta: float) -> void:
	clock += delta
	animation = maxf(0,animation-delta)
	if battle != null and animation < .52 and animation > 0 and not impact_played:
		impact_played = true
		if sounds != null and int(event.get("amount",0)) > 0 and event.get("kind","") != "heal": sounds.play("heavy" if event.get("kind","") in ["boss_hit","heavy","cleave"] else "hit")
	if campaign != null and battle == null:
		sync_location()
		motion.advance(delta)
		avatar = motion.position
		route = motion.route
		route_index = motion.cursor
		facing_left = motion.facing == Locomotion.Facing.WEST
		if motion.finished:
			route = PackedVector2Array()
			if requested_place != "":
				var place := requested_place
				requested_place = ""
				synced_place = place
				arrived.emit(place)
		var target_camera := Vector2(clampf(avatar.x-size.x/(2*zoom),0,3328-size.x/zoom),clampf(avatar.y-size.y/(2*zoom),0,2304-size.y/zoom))
		camera = target_camera if reset_camera else camera.lerp(target_camera,1-exp(-delta*8))
		reset_camera = false
	queue_redraw()

func map_pos(point: Vector2) -> Vector2:
	return (point-camera)*zoom

func _gui_input(input: InputEvent) -> void:
	if input is InputEventMouseButton and input.pressed and input.button_index == MOUSE_BUTTON_LEFT:
		# In overlapping ranks the last drawn actor is the one visible in front.
		var hit_order := bounds.keys()
		hit_order.reverse()
		for key in hit_order:
			if bounds[key].has_point(input.position):
				if battle == null: place_selected.emit(key)
				else: unit_selected.emit(key)
				accept_event()
				return

		if battle == null and Atlas.ensure(campaign).region == "嘉興鎮":
			requested_place = ""
			route = town.route(avatar,input.position/zoom+camera)
			route_index = 0
			motion.position = avatar
			motion.follow(route)
			walking.emit()
			accept_event()

func text_at(value: String, at: Vector2, color: Color = IVORY, font_size: int = 18, centered: bool = false) -> void:
	if centered: at.x -= font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x/2
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw() -> void:
	if campaign == null or font == null or not prepared: return
	bounds.clear()
	if battle != null: draw_battle()
	else: draw_map()

func draw_map() -> void:
	if Atlas.ensure(campaign).region != "嘉興鎮":
		var region: String = Atlas.ensure(campaign).region
		var bg := tex("bg_huayin_road")
		if bg != null: draw_texture_rect(bg,Rect2(Vector2.ZERO,size),false)
		draw_rect(Rect2(Vector2.ZERO,size),Color(0,.05,.04,.18))

		draw_sprite("swordsman",Vector2(size.x*.28,size.y*.86),178,0,false)
		draw_sprite(Atlas.NPC_SPRITES[region],Vector2(size.x*.73,size.y*.76),178,0,true)
		return
	var art := asset("town/qingxi.webp")
	if art != null: draw_texture_rect(art,Rect2(-camera*zoom,Vector2(3328,2304)*zoom),false)
	if route_index < route.size():
		var points := PackedVector2Array([map_pos(avatar)])
		for i in range(route_index,route.size()): points.append(map_pos(route[i]))
		if points.size() > 1: draw_polyline(points,Color(1,.87,.5,.55),3,true)
	var order: Array = town.anchors.keys()
	order.append("@hero")
	order.sort_custom(func(a,b): return (avatar.y if a == "@hero" else town.anchors[a].y) < (avatar.y if b == "@hero" else town.anchors[b].y))
	var sprites := {"青溪客棧":"companion","渡口":"staff","藥廬":"healer","蘆葦蕩":"blade","古寺":"staff","市集":"rogue","演武坪":"boss","舊倉":"blade"}
	for name in order:
		if name == "@hero":
			var p := map_pos(avatar)
			draw_ellipse_shadow(p,Vector2(19,6))
			draw_arc(p,23,0,TAU,32,GOLD,1.5,true)
			draw_frame(character_art.walk(motion.facing,motion.frame()),p,100,motion.facing == Locomotion.Facing.WEST)
			continue
		var p := map_pos(town.anchors[name]+Vector2(76,-8))
		if not Rect2(-100,-100,size.x+200,size.y+200).has_point(p): continue
		draw_ellipse_shadow(p,Vector2(18,5))
		draw_sprite(sprites[name],p,100,0,true)
		var box := Rect2(p-Vector2(69,113),Vector2(138,30))
		draw_style_box(_plate(Color(.13,.09,.055,.92)),box)
		text_at(name,p-Vector2(0,91),IVORY,17,true)
		if name == campaign.objective()[1] and campaign.state.stage < 7:
			text_at("◆",p-Vector2(0,126+sin(clock*3)*3),GOLD,22,true)
		bounds[name] = Rect2(p-Vector2(65,115),Vector2(130,125))
	# Keep the full street plan visible as a minimap; the gold frame is the camera.
	var mini := Rect2(size.x-183,99,170,118)
	draw_style_box(_plate(Color(.13,.09,.055,.92)),mini.grow(4))
	if art != null: draw_texture_rect(art,mini,false,Color(.8,.85,.8))
	var scale_value := mini.size/Vector2(3328,2304)
	draw_rect(Rect2(mini.position+camera*scale_value,size/zoom*scale_value),GOLD,false,1)
	draw_circle(mini.position+avatar*scale_value,3,Color.WHITE)


func draw_sprite(key: String, foot: Vector2, height: float, frame: int, left: bool, tint: Color = Color.WHITE) -> void:
	draw_frame(character_art.sprite(key,frame),foot,height,left,tint)

func draw_frame(frame: Dictionary, foot: Vector2, height: float, left: bool, tint: Color = Color.WHITE) -> void:
	var texture := asset("characters/"+frame.texture)
	if texture == null: return
	var region: Array = frame.region
	var pivot := Vector2(float(frame.pivot[0]),float(frame.pivot[1]))
	var scale_value := height/maxf(1,float(frame.height))
	draw_set_transform(foot,0,Vector2(-scale_value if left else scale_value,scale_value))
	draw_texture_rect_region(texture,Rect2(-pivot,Vector2(float(region[2]),float(region[3]))),Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3])),tint)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

func _plate(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 5
	box.corner_radius_bottom_right = 5
	box.border_color = Color(.4,.43,.3,.5)
	box.set_border_width_all(1)
	return box

func draw_ellipse_shadow(at: Vector2, radius: Vector2) -> void:
	var points := PackedVector2Array()
	for i in 32: points.append(at+Vector2(cos(i*TAU/32)*radius.x,sin(i*TAU/32)*radius.y))
	draw_colored_polygon(points,Color(0,0,0,.2))

func actor_pos(u: Dictionary) -> Vector2:
	var x := (485.0 if u.front else 230.0) if u.side == 0 else (930.0 if u.front else 1180.0)
	if u.side == 0: x += int(u.lane)*60
	else: x += (1-int(u.lane))*70
	var y := 250.0 + int(u.lane)*110.0
	return Vector2(x,y) * Vector2(size.x/1400.0,size.y/500.0)

func draw_battle() -> void:
	var bg: String = "bg_guiwang" if battle.encounter in ["warehouse","rematch"] else "bg_river_road"
	draw_texture_rect(tex(bg),Rect2(Vector2.ZERO,size),false,Color(.65,.69,.66))
	draw_rect(Rect2(Vector2.ZERO,size),Color(.03,.07,.065,.17))
	for lane in 3:
		var y := (250.0+lane*110)*size.y/500.0
		draw_line(Vector2(size.x*.31,y+8),Vector2(size.x*.71,y+8),Color(.87,.82,.64,.15),1,true)
	text_at("後 陣",Vector2(180,size.y-14),Color(1,1,1,.45),15)
	text_at("前 陣",Vector2(460,size.y-14),Color(1,1,1,.45),15)
	var sorted: Array = battle.units.duplicate()
	sorted.sort_custom(func(a,b): return a.lane < b.lane)
	for u in sorted: draw_actor(u)
	if animation > 0:
		var victims: Array = event.get("hits",[])
		if victims.is_empty() and event.has("target"): victims = [{"id":event.target,"amount":event.get("amount",0)}]
		for hit in victims:
			var target: Dictionary = battle.by_id(hit.id)
			if target.is_empty(): continue
			var p := actor_pos(target)-Vector2(0,80)
			if hit.get("dodge",false): text_at("閃避",p,IVORY,26,true); continue
			var kind: String = event.get("kind","")
			var key := "heal" if kind == "heal" else ("burst" if kind in ["boss_hit","heavy","cleave"] else ("slash" if kind in ["attack","bleed","pierce"] else "hit"))
			var effect := asset("effects/"+key+".png")
			if effect != null and animation < .65:
				var count := int(effect.get_height()/192)*5
				var frame := mini(count-1,int((.65-animation)/.65*count))
				var tint := Color(.65,1,.64) if kind == "poison" else Color.WHITE
				draw_texture_rect_region(effect,Rect2(p-Vector2(105,105),Vector2(210,210)),Rect2((frame%5)*192,(frame/5)*192,192,192),tint)
			if int(hit.get("amount",0)) > 0:
				text_at(("+" if kind == "heal" else "−")+str(int(hit.amount)),p-Vector2(0,40+(1-animation/.8)*65),Color("b7ecc7") if kind == "heal" else Color("ffe8ab"),30,true)

func draw_actor(u: Dictionary) -> void:
	var foot := actor_pos(u)
	var active: bool = animation > 0 and event.get("actor", "") == u.id
	var hurt: bool = animation > 0 and event.get("target", "") == u.id and event.get("amount",0) > 0
	var offset := Vector2.ZERO
	if active and event.get("kind","") not in ["heal","guard","charge","stun"]: offset.x = sin(animation/.8*PI)*16*(1 if u.side == 0 else -1)
	if hurt and event.get("kind","") != "heal": offset.x += sin(animation*42)*5
	foot += offset
	draw_ellipse_shadow(foot,Vector2(45,12))
	if selected == u.id: draw_arc(foot,49,0,TAU,40,GOLD,2,true)
	if u.guarding: draw_arc(foot-Vector2(0,65),68,-PI*.8,PI*.4,40,Color(.54,.85,.8,.65),4,true)
	var color := Color.WHITE if u.hp > 0 else Color(.45,.45,.45,.35)
	if hurt and animation > .5 and event.get("kind","") != "heal": color = Color(1,.6,.5)
	var key: String = {"hero":"swordsman","sword":"companion","healer":"healer","staff":"staff","boss":"boss","poison":"rogue","archer":"rogue"}.get(u.id,"blade")
	key = u.get("sprite",key)
	if u.id == "hero" and u.weapon == "刀": key = "hero_dao"
	if u.id == "hero" and u.weapon == "棍": key = "hero_staff"
	if u.id == "hero" and u.weapon == "拳掌": key = "hero_palm"
	var phase := 0
	if active:
		var progress_value := 1-animation/.8
		phase = 1 if progress_value < .3 else (2 if progress_value < .58 else 3)
	elif u.guarding or hurt: phase = 3
	draw_sprite(key,foot,174,phase,u.side == 1,color)
	var top := foot-Vector2(0,190)
	text_at(u.name,top,IVORY if u.side == 0 else Color("f7b3a0"),18,true)
	draw_rect(Rect2(top+Vector2(-58,6),Vector2(116,7)),Color("202b26"))
	draw_rect(Rect2(top+Vector2(-58,6),Vector2(116*maxf(0,float(u.hp)/u.max_hp),7)),Color("a2c899") if u.side == 0 else Color("c36e59"))
	var tags: Array = []
	if u.stun > 0: tags.append("封")
	if u.bleed > 0: tags.append("血")
	if u.poison > 0: tags.append("毒")
	if u.broken > 0: tags.append("破")
	if u.charging: tags.append("蓄力！")
	if not tags.is_empty(): text_at(" · ".join(tags),foot+Vector2(0,25),GOLD,17,true)
	bounds[u.id] = Rect2(foot-Vector2(68,218),Vector2(136,255))
