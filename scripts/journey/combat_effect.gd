extends Control
## Additive layer preserves the source sheets, including their original black mattes.
const Style=preload("res://scripts/journey/combat_style.gd")
var stage

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var blend:=CanvasItemMaterial.new()
	blend.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
	material=blend

func sheet(name: String,at: Vector2,progress: float,extent: float,tint: Color) -> void:
	var atlas: Dictionary=Style.data.textures[name]
	var texture: Texture2D=stage.asset(atlas.path)
	if texture==null:return
	var frame:=clampi(int(progress*int(atlas.frames)),0,int(atlas.frames)-1)
	var cell:=Vector2(texture.get_width()/5.0,texture.get_height()/float(atlas.rows))
	draw_texture_rect_region(texture,Rect2(at-Vector2.ONE*extent*.5,Vector2.ONE*extent),Rect2(Vector2(frame%5,frame/5)*cell,cell),tint)

func _draw() -> void:
	if stage==null or stage.battle==null:return
	for unit in stage.battle.units:
		if unit.hp<=0:continue
		var foot: Vector2=stage.actor_pos(unit)
		if unit.charging:
			var pulse: float=fmod(stage.clock*.7,1)
			sheet("aura",foot-Vector2(0,65),pulse,175,Color(1,.62,.23,.6))
			for i in 9:
				var phase: float=fmod(stage.clock*.8+i/9.0,1)
				draw_line(foot+Vector2(sin(i*2.4+stage.clock)*45,-phase*105),foot+Vector2(sin(i*2.4+stage.clock)*45,-phase*105-12),Color(1,.7,.35,(1-phase)*.7),2,true)
		if unit.guarding:sheet("shield",foot-Vector2(0,78),fmod(stage.clock*.4,1),170,Color(.48,.8,1,.28))
	if stage.animation<=0:return
	var event: Dictionary=stage.event
	if event.get("kind","") in ["round","skip",""]:return
	var actor: Dictionary=stage.battle.by_id(event.get("actor",""))
	if actor.is_empty():return
	var style: Dictionary=Style.profile(actor,event)
	var color:=Color(style.color)
	var progress: float=clampf(1-stage.animation/.8,0,1)
	var start: Vector2=stage.actor_pos(actor)-Vector2(0,90)
	if event.kind in ["charge","guard"]:
		sheet(style.texture,start,progress,185,color*Color(1,1,1,.7))
		return
	var hits: Array=event.get("hits",[{"id":event.get("target",""),"amount":event.get("amount",0)}])
	for hit in hits:
		var target: Dictionary=stage.battle.by_id(hit.id)
		if target.is_empty() or hit.get("dodge",false):continue
		var finish: Vector2=stage.actor_pos(target)-Vector2(0,90)
		var direction: Vector2=(finish-start).normalized()
		if progress<.4 and style.shape in ["ray","rain","snake","dragon","bamboo","arrow"]:
			var tip: Vector2=start.lerp(finish,ease(progress/.4,.55))
			var rays: int=6 if style.shape=="ray" else (9 if style.shape=="rain" else 1)
			for i in rays:
				var offset:=Vector2(0,(i-(rays-1)*.5)*7)
				draw_line(start+offset,tip+offset,color*Color(1,1,1,.7),3 if rays>1 else 7,true)
			if style.shape=="arrow":draw_colored_polygon(PackedVector2Array([tip+direction*10,tip-direction*7+direction.orthogonal()*5,tip-direction*7-direction.orthogonal()*5]),color)
		if progress>=.22:
			var phase: float=(progress-.22)/.78
			sheet(style.texture,finish,phase,210*float(style.scale),color*Color(1,1,1,.8))
			if style.shape in ["twin","music","reflect","lotus"]:
				for i in 3:draw_arc(finish,20+phase*70+i*12,phase*TAU,phase*TAU+PI*1.6,32,Color(color,.65*(1-phase)),2,true)
			if style.shape in ["crush","palm","sweep","bamboo"]:
				var radius: float=18+phase*90
				draw_arc(finish,radius,-PI*.85,PI*.85,36,Color(color,(1-phase)*.8),5 if style.shape=="crush" else 2,true)
			for i in (10 if style.shape in ["petal","lotus","poison","ice"] else 5):
				var angle: float=i*2.399+phase*.8
				var point: Vector2=finish+Vector2(cos(angle),sin(angle))*(15+phase*65)
				draw_circle(point,(3.5 if style.shape in ["petal","lotus"] else 2)*(1-phase),Color(color,.8*(1-phase)))
