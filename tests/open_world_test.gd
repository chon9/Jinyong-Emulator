extends SceneTree
const Chapter=preload("res://scripts/journey/chapter.gd")
const Atlas=preload("res://scripts/journey/atlas.gd")
const Open=preload("res://scripts/journey/open_world.gd")
const Data=preload("res://scripts/journey/open_content.gd")
const Battle=preload("res://scripts/journey/battle.gd")
var checks:=0
var failures:=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func campaign():
	var c=Chapter.new()
	Atlas.ensure(c)
	Open.ensure(c)
	return c
func _init() -> void:
	var c=campaign()
	check(Data.HEROES.size()>=34,"Recruitment meets researched Flash roster and requested minimum")
	check(Data.QUESTS.size()>=45,"Optional quests exceed all 45 documented Flash event slots")
	check(Data.ENEMIES.size()==100,"Exactly 100 independently illustrated adversaries")
	var locations:=0
	for region in Data.REGIONS:
		locations+=Data.REGIONS[region].size()
		Atlas.visit(c,region)
		check(c.state.atlas.region==region and c.state.stage==0,"All regions accessible before any chapter progress")
		for scene in Data.REGIONS[region]:
			Open.enter(c,region,scene)
			check(Open.people(c).size()>=2,"Every location has at least two dialogue NPCs")
	check(locations==100,"One hundred named exploration locations")
	for id in Data.HEROES:
		var h: Dictionary=Data.HEROES[id]
		Open.enter(c,h.region,h.scene)
		Open.invite(c,id)
		check(not id in c.state.roster,"Meeting alone cannot recruit a companion: "+h.name)
		var n: int=c.state.roster.size()
		Open.invite(c,id)
		check(c.state.roster.size()==n and c.state.party.size()<=4,"Repeated invitations cannot duplicate a companion")
		var u: Dictionary=c.unit(id)
		check(u.outer==h.outer and u.weapon==Data.ARTS[h.outer].weapon,"Companion weapon and own martial art are consistent")
	# Finish both sets of choices through the live rules and real battle resolution.
	for id in c.state.party:c.state.levels[id]=30
	c.state.sect="華山"
	c.state.inventory["草藥"]=500
	c.state.inventory["金創藥"]=500
	for id in Data.QUESTS:
		var quest: Dictionary=Data.QUESTS[id]
		Open.enter(c,quest.region,quest.scene)
		Open.accept(c,id,quest.giver)
		var guard:=0
		while Open.ensure(c).quests[id].status=="active" and guard<20:
			guard+=1
			var before: int=Open.ensure(c).quests[id].step
			var step: Dictionary=quest.steps[before]
			Open.enter(c,step.region,step.scene)
			if Open.ensure(c).quests[id].step!=before:continue
			var result: Dictionary=Open.action(c,id,step.get("npc",""),0)
			if result.has("battle"):
				var battle=Battle.new(c,result.battle,123)
				for turn in 120:
					if battle.result!="":break
					battle.auto_orders()
					battle.begin_round()
					while not battle.queue.is_empty() and battle.result=="":battle.next_action()
				check(battle.result=="victory","Quest battle is playable: "+id)
				if battle.result!="victory":break
				Open.battle_won(c,result.battle)
		check(Open.ensure(c).quests[id].status=="done","Every optional quest reaches an awarded ending: "+id)
		var silver: int=c.state.silver
		Open.action(c,id,quest.giver,0)
		check(c.state.silver==silver,"Completed quest cannot pay twice: "+id)
	var alternate=campaign()
	alternate.state.levels.hero=30
	alternate.state.inventory["草藥"]=500
	alternate.state.inventory["金創藥"]=500
	for id in Data.QUESTS:
		var q: Dictionary=Data.QUESTS[id]
		Open.enter(alternate,q.region,q.scene);Open.accept(alternate,id,q.giver)
		for turn in 20:
			if alternate.state.open_world.quests[id].status=="done":break
			var step: Dictionary=q.steps[int(alternate.state.open_world.quests[id].step)]
			Open.enter(alternate,step.region,step.scene)
			var result: Dictionary=Open.action(alternate,id,step.get("npc",""),1)
			if result.has("battle"):
				var b=Battle.new(alternate,result.battle,321)
				for round_number in 120:
					if b.result!="":break
					b.auto_orders();b.begin_round()
					while not b.queue.is_empty() and b.result=="":b.next_action()
				check(b.result=="victory","Alternate route includes a winnable actual fight: "+id)
				if b.result!="victory":break
				Open.battle_won(alternate,result.battle)
		check(alternate.state.open_world.quests[id].status=="done","Alternative choices reach a real ending: "+id)
	for id in Data.HEROES:
		var h: Dictionary=Data.HEROES[id]
		Open.enter(c,h.region,h.scene)
		Open.invite(c,id)
		check(id in c.state.roster,"Story, relationship and cultivation unlock actual recruitment: "+h.name)
	for id in Data.ENEMIES:
		var b=Battle.new(c,"wild:"+id,1)
		check(b.living(1).size()==1 and b.living(1)[0].sprite==id,"Each enemy is a reachable combatant with its own art")
		b.auto_orders();b.begin_round()
		for i in 10:
			if b.queue.is_empty() or b.result!="":break
			b.next_action()
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	FileAccess.open("res://test-results/story-completion.json",FileAccess.WRITE).store_string(JSON.stringify(saved))
	check(Open.valid_save(saved.open_world),"Completed stories and evidence conform to the world-save schema")
	check(Chapter.valid_save(saved),"All new recruits, relationships, quests and discoveries survive JSON save")
	var loaded=Chapter.new(saved)
	check(loaded.state.roster.size()==c.state.roster.size() and loaded.state.open_world.quests.size()==Data.QUESTS.size(),"Restored progress contains every completed story")
	var bad: Dictionary=saved.duplicate(true)
	bad.open_world.quests.values()[0].step=-1
	check(not Chapter.valid_save(bad),"Save import rejects malformed quest progress")
	var fresh=campaign()
	Open.enter(fresh,"牛家村","村口")
	Open.accept(fresh,"friend_jy24","jy24")
	var before: int=fresh.state.silver
	Open.battle_won(fresh,"quest:friend_jy24:3")
	check(fresh.state.silver==before and fresh.state.open_world.quests.friend_jy24.step==0,"Stale or forged battle result cannot skip quest conditions")
	print("OPEN WORLD TEST: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
