extends Control
## Illustrated map and animated side-view actors; all rules live outside this view.
signal place_selected(place: String)
signal unit_selected(id: String)
const Chapter = preload("res://scripts/journey/chapter.gd")
const GOLD := Color("d7b77b")
const IVORY := Color("f0e6cf")
var campaign
var battle
var textures := {}
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
	if not textures.has(name):
		var path := "res://assets/journey/" + name + ".png"
		textures[name] = load(path) if ResourceLoader.exists(path) else null
	return textures[name]

func show_event(value: Dictionary) -> void:
	event = value
	animation = .8
	queue_redraw()

func _process(delta: float) -> void:
	clock += delta
	animation = maxf(0,animation-delta)
	if campaign != null and battle == null:
		destination = map_pos(Chapter.PLACES[campaign.state.place].pos) + Vector2(-38,24)
		if avatar == Vector2.ZERO: avatar = destination
		avatar = avatar.move_toward(destination,delta*650)
	queue_redraw()

func map_pos(point: Vector2) -> Vector2:
	return point * Vector2(size.x/1230.0,size.y/620.0)

func _gui_input(input: InputEvent) -> void:
	if input is InputEventMouseButton and input.pressed and input.button_index == MOUSE_BUTTON_LEFT:
		for key in bounds:
			if bounds[key].has_point(input.position):
				if battle == null: place_selected.emit(key)
				else: unit_selected.emit(key)
				accept_event()
				return

func text_at(value: String, at: Vector2, color: Color = IVORY, font_size: int = 18, centered: bool = false) -> void:
	if centered: at.x -= font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x/2
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw() -> void:
	if campaign == null or font == null: return
	bounds.clear()
	if battle != null: draw_battle()
	else: draw_map()

func draw_map() -> void:
	draw_texture_rect(tex("map_region_bg"),Rect2(Vector2.ZERO,size),false,Color(.83,.86,.78))
	# A river, linked footpaths, and villages make the destination map readable.
	var river := PackedVector2Array()
	for i in range(50):
		var y := i * size.y/49.0
		river.append(Vector2(size.x*.61+sin(i*.14)*size.x*.09,y))
	draw_polyline(river,Color(.29,.47,.48,.3),40,true)
	draw_polyline(river,Color(.63,.75,.69,.55),25,true)
	var drawn := {}
	for name in Chapter.PLACES:
		var p := map_pos(Chapter.PLACES[name].pos)
		for link in Chapter.PLACES[name].links:
			var key := "|".join([name,link] if name < link else [link,name])
			if drawn.has(key): continue
			drawn[key] = true
			var end := map_pos(Chapter.PLACES[link].pos)
			draw_line(p,end,Color(.37,.31,.22,.24),9,true)
			draw_dashed_line(p,end,Color(.9,.84,.68,.8),3,8,true)
	# Seeded scenery is stable, with plenty of negative space around landmarks.
	var scenery := RandomNumberGenerator.new()
	scenery.seed = 241
	for i in 72:
		var p := Vector2(scenery.randf_range(18,size.x-20),scenery.randf_range(12,size.y-14))
		var close := false
		for name in Chapter.PLACES:
			if p.distance_to(map_pos(Chapter.PLACES[name].pos)) < 66: close = true
		if close: continue
		draw_line(p+Vector2(0,4),p+Vector2(0,17),Color(.38,.33,.22,.5),3)
		draw_circle(p,scenery.randf_range(8,17),Color(.27,.36,.25,.38))
		draw_circle(p-Vector2(3,4),scenery.randf_range(5,12),Color(.41,.48,.31,.6))
	for name in Chapter.PLACES:
		var p := map_pos(Chapter.PLACES[name].pos)
		var current: bool = name == campaign.state.place
		var quest: bool = name == campaign.objective()[1] and campaign.state.stage < 7
		var icons := {"青溪客棧":"inn","渡口":"water","藥廬":"field","蘆葦蕩":"wild","古寺":"sect","市集":"shop","演武坪":"master","舊倉":"cave"}
		var icon: Texture2D = tex("map_icon_"+icons[name])
		draw_ellipse_shadow(p+Vector2(0,12),Vector2(40,10))
		if icon != null: draw_texture_rect(icon,Rect2(p-Vector2(48,72),Vector2(96,100)),false)
		var box := Rect2(p+Vector2(-65,28),Vector2(130,34))
		draw_style_box(_plate(Color("234a42") if current else Color("e9ddbd")),box)
		text_at(name,p+Vector2(0,52),IVORY if current else Color("3c3e2d"),20,true)
		if quest:
			var bob := sin(clock*3)*3
			draw_circle(p+Vector2(47,-40+bob),13,GOLD)
			text_at("!",p+Vector2(47,-34+bob),Color("3c3021"),22,true)
		if current: draw_arc(p+Vector2(0,5),45,0,TAU,60,Color(.17,.39,.32,.65),2,true)
		bounds[name] = Rect2(p-Vector2(62,60),Vector2(124,124))
	var art: Texture2D = tex("unit_player_m_idle")
	draw_ellipse_shadow(avatar+Vector2(0,14),Vector2(18,6))
	if art != null: draw_texture_rect(art,Rect2(avatar-Vector2(23,66),Vector2(46,80)),false)
	text_at("青 溪 鎮",Vector2(30,44),Color(.22,.29,.23),30)
	text_at("點地點前往  ·  金色 ! 為當前故事",Vector2(30,70),Color(.37,.4,.31),16)

func house(p: Vector2, factor: float, temple: bool) -> void:
	var w := 32*factor
	var top := p+Vector2(0,-42*factor)
	draw_ellipse_shadow(p+Vector2(0,8),Vector2(42,10)*factor)
	draw_colored_polygon(PackedVector2Array([p+Vector2(-w,-24),p+Vector2(0,-10),p+Vector2(0,10),p+Vector2(-w,-4)]),Color("c6ba96"))
	draw_colored_polygon(PackedVector2Array([p+Vector2(0,-10),p+Vector2(w,-24),p+Vector2(w,-4),p+Vector2(0,10)]),Color("ac9d7c"))
	var roof := PackedVector2Array([p+Vector2(-w-9,-26),top,p+Vector2(w+9,-26),p+Vector2(0,-6)])
	draw_colored_polygon(roof,Color("545e52") if temple else Color("6f6954"))
	draw_polyline(roof,Color("444f43"),2,true)
	draw_line(top,p+Vector2(0,-6),Color("9c9e7c"),2,true)
	draw_line(p+Vector2(8,-5),p+Vector2(8,7),Color("595640"),7)
	if temple:
		draw_line(top+Vector2(-13,2),top+Vector2(0,-12),Color("55604e"),4,true)
		draw_line(top+Vector2(0,-12),top+Vector2(13,2),Color("55604e"),4,true)

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
	if animation > 0 and event.has("actor"):
		var actor: Dictionary = battle.by_id(event.actor)
		var target: Dictionary = battle.by_id(event.target)
		if not actor.is_empty() and not target.is_empty() and actor.id != target.id:
			var start := actor_pos(actor)-Vector2(0,70)
			var end := actor_pos(target)-Vector2(0,70)
			var color := Color(.67,.89,.72,animation) if event.kind == "heal" else Color(.95,.82,.49,animation)
			draw_line(start,end,color,2+animation*3,true)
			if animation > .4: draw_arc(end,40,PI*.9,PI*1.9,20,color,4,true)

func draw_actor(u: Dictionary) -> void:
	var foot := actor_pos(u)
	var active: bool = animation > 0 and event.get("actor", "") == u.id
	var hurt: bool = animation > 0 and event.get("target", "") == u.id and event.get("amount",0) > 0
	var offset := Vector2.ZERO
	if active and event.get("kind","") not in ["heal","guard","charge","stun"]: offset.x = sin(animation/.8*PI)*38*(1 if u.side == 0 else -1)
	if hurt and event.get("kind","") != "heal": offset.x += sin(animation*42)*5
	foot += offset
	draw_ellipse_shadow(foot,Vector2(45,12))
	if selected == u.id: draw_arc(foot,49,0,TAU,40,GOLD,2,true)
	if u.guarding: draw_arc(foot-Vector2(0,65),68,-PI*.8,PI*.4,40,Color(.54,.85,.8,.65),4,true)
	var pose := "attack" if active else ("hurt" if hurt and event.get("kind","") != "heal" else "idle")
	var art: Texture2D = tex(u.art+"_"+pose)
	if art == null: art = tex(u.art+"_idle")
	var color := Color.WHITE if u.hp > 0 else Color(.45,.45,.45,.35)
	if art != null:
		var rect := Rect2(foot-Vector2(69,176),Vector2(138,180))
		if u.side == 1:
			rect.size.x *= -1
		draw_texture_rect(art,rect,false,color)
	if u.hp > 0:
		# Owner art has open hands; show the actual equipped weapon beside each actor.
		var hand := foot+Vector2(35 if u.side==0 else -35,-72)
		var direction := Vector2(1 if u.side==0 else -1,-1).normalized()
		if u.weapon in ["劍","刀"]:
			draw_line(hand-direction*10,hand+direction*70,Color("d2d9c8"),3,true)
			draw_line(hand+Vector2(-7,-7),hand+Vector2(7,7),GOLD,4,true)
		elif u.weapon == "棍": draw_line(hand-direction*50,hand+direction*70,Color("ba9765"),5,true)
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
	if hurt:
		var label_value := "+%d" % int(event.amount) if event.kind == "heal" else "−%d" % int(event.amount)
		text_at(label_value,foot-Vector2(0,100+(1-animation/.8)*55),Color("b7ecc7") if event.kind == "heal" else Color("ffe8ab"),32,true)
	bounds[u.id] = Rect2(foot-Vector2(68,218),Vector2(136,255))
