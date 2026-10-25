extends SceneTree
const Chapter=preload("res://scripts/journey/chapter.gd")
const Open=preload("res://scripts/journey/open_world.gd")
const Data=preload("res://scripts/journey/open_content.gd")
const Battle=preload("res://scripts/journey/battle.gd")
const Art=preload("res://scripts/journey/character_art.gd")
const Style=preload("res://scripts/journey/combat_style.gd")
var checks:=0
var failures:=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func campaign():
	var c=Chapter.new()
	preload("res://scripts/journey/atlas.gd").ensure(c)
	Open.ensure(c)
	return c
func complete(c,id: String,choice: int) -> void:
	var q: Dictionary=Data.QUESTS[id]
	Open.enter(c,q.region,q.scene);Open.accept(c,id,q.giver)
	for i in 20:
		if c.state.open_world.quests[id].status=="done":return
		var step: Dictionary=q.steps[int(c.state.open_world.quests[id].step)]
		Open.enter(c,step.region,step.scene)
		var action: Dictionary=Open.action(c,id,step.get("npc",""),choice)
		if action.has("battle"):
			var battle=Battle.new(c,action.battle,123)
			for turn in 80:
				if battle.result!="":break
				battle.auto_orders();battle.begin_round()
				while not battle.queue.is_empty() and battle.result=="":battle.next_action()
			check(battle.result=="victory","Early personal story can be completed by a fresh protagonist")
			if battle.result!="victory":return
			Open.battle_won(c,action.battle)
func _init() -> void:
	var art=Art.new();var clues:=[]
	check(Data.QUESTS.size()==129,"Original 121 quests retained, plus eight authored Qingxi stories")
	for id in Data.HEROES:
		var hero: Dictionary=Data.HEROES[id]
		check(art.data.characters[id].frames.size()==4,"Every recruit has ready, wind-up, strike and guard poses: "+hero.name)
		var source:=[]
		for pose in art.data.characters[id].frames:source.append(str(pose.region))
		check(source.size()==4 and source[0]!=source[1] and source[1]!=source[2] and source[2]!=source[3],"Animation uses distinct source poses, not a duplicated standing image")
		check(hero.recruit.quest=="friend_"+id and Data.QUESTS.has(hero.recruit.quest),"Each recruit's gate references their own story")
	for id in Data.QUESTS:
		var q: Dictionary=Data.QUESTS[id]
		check(q.endings.size()==2 and q.endings[0]!=q.endings[1],"Choices have recorded narrative consequences: "+id)
		for step in q.steps:
			if step.kind=="battle":
				for enemy in step.enemies:check(not int(enemy.trim_prefix("enemy_")) in range(81,91),"Named human antagonists never use animal sprites")
			check(step.region in Data.REGIONS and step.scene in Data.REGIONS[step.region],"Every story step has a reachable location")
			check(step.pages.size()>=2,"Every task step has multiple dialogue lines")
			for line in step.pages:
				check(line.text.length()>5 and (line.speaker=="" or line.speaker=="hero" or Data.PEOPLE.has(line.speaker)),"Dialogue has meaningful text and a known speaker")
			if step.has("npc"):
				var person: Dictionary=Data.PEOPLE[step.npc]
				check(person.region==step.region and person.scene==step.scene,"Witness or giver is actually present at the task location")
			if step.kind=="search":clues.append(step.evidence)
	check(clues.size()==129,"Each story includes a real discoverable piece of evidence")
	var c=campaign();Open.enter(c,"牛家村","牛家客棧")
	var before: String=JSON.stringify(Open.conversation(c,"jy02"))
	Open.invite(c,"jy02")
	check(not "jy02" in c.state.roster,"Fresh Huang Rong invitation is gated")
	complete(c,"friend_jy02",0)
	Open.enter(c,"牛家村","牛家客棧");Open.invite(c,"jy02")
	check("jy02" in c.state.roster and c.state.open_world.affinity.jy02==20,"Her own complete story and relationship unlock her")
	check(JSON.stringify(Open.conversation(c,"jy02"))!=before,"Post-resolution NPC conversation remembers the outcome")
	var other=campaign();complete(other,"friend_jy02",1)
	check(other.state.open_world.quests.friend_jy02.choices==[1],"Second resolution is persisted")
	check(other.state.open_world.affinity.jy02==16 and other.state.open_world.honor==0,"Alternate resolution changes relationship and honor")
	check(c.state.open_world.evidence.is_empty(),"Evidence is handed back exactly once at the ending")
	var legacy: Dictionary=c.state.duplicate(true)
	legacy.open_world.version=1;legacy.open_world.erase("evidence")
	legacy.open_world.quests.friend_jy02.step=Data.LEGACY_STEPS.friend_jy02
	legacy.open_world.quests.friend_jy24={"status":"active","step":2,"choices":[]}
	check(Chapter.valid_save(legacy),"Existing v0.10.1 save schema remains readable")
	var loaded=Chapter.new(JSON.parse_string(JSON.stringify(legacy)))
	Open.ensure(loaded)
	check("jy02" in loaded.state.roster and loaded.state.open_world.quests.friend_jy02.status=="done","Migration preserves existing companions and earned endings")
	check(loaded.state.open_world.quests.friend_jy24.step==0 and loaded.state.open_world.version==2,"Unfinished old scripts restart at the new testimony without fabricated evidence")
	var styles:=[]
	for skill in ["降龍十八掌","打狗棒法","六脈神劍","玄鐵劍法","獨孤九劍","玉女素心劍","七心海棠訣","冰蠶寒掌","星宿毒術","玉簫劍法"]:
		styles.append(Style.key_for({}, {"kind":"skill","skill":skill}))
	check(styles.size()==10 and styles.count("sword")==0,"Signature skills select distinct named presentation styles")
	for key in Style.data.styles:
		var fx: Dictionary=Style.data.styles[key]
		check(FileAccess.file_exists("res://assets/sfx/"+fx.start+".ogg"),"Every presentation has an actual starting sound")
		check(Style.data.textures.has(fx.texture),"Every presentation has an actual sprite sheet")
	var unit: Dictionary={"guarding":true,"charging":true,"poison":2,"bleed":1,"broken":3,"stun":1}
	check(Style.states(unit).size()==6,"All buffs and debuffs expose background color, glyph, duration and tooltip")
	check(Style.key_for({}, {"kind":"charge"})=="charge" and Style.data.styles.charge.start!="","Charging is audible and has a persistent aura style")
	for enemy in Data.ENEMIES.values():check(Style.WEAPONS.has(enemy.weapon),"Actual enemy weapon type has an appropriate presentation family")
	check(Style.profile({"weapon":"弓"},{"kind":"attack"}).shape=="arrow","Ordinary bow attacks use an arrow, not six finger-energy beams")
	for hid in ["jy03","jy28"]:
		var duel=campaign();duel.recruit(hid);duel.state.party=["hero",hid]
		var battle=Battle.new(duel,"wild:enemy_010",12)
		var event: Dictionary=battle._resolve(battle.by_id(hid),"skill","")
		check(event.skill==Data.HEROES[hid].outer,"Heavy and poison casts retain their own skill names")
	print("JIANGHU STORIES: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
