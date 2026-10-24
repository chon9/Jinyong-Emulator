extends SceneTree
const Chapter = preload("res://scripts/journey/chapter.gd")
const Battle = preload("res://scripts/journey/battle.gd")
var checks := 0
var failures: Array = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description); push_error(description)

func resolve(battle) -> void:
	battle.begin_round()
	for i in 15:
		if battle.result != "" or battle.queue.is_empty(): break
		battle.next_action()

func run() -> void:
	var c := Chapter.new()
	check(Chapter.valid_save(c.state),"Fresh campaign is a valid portable save")
	c.choose("recruit_staff")
	check(c.state.party == ["hero"],"Unmet dialogue cannot recruit a companion")
	c.choose("recruit_sword")
	check(c.state.stage == 1 and c.state.party.size()==2,"Inn dialogue recruits a real second combatant")
	c.choose("recruit_sword")
	check(c.state.party.size()==2,"Stale dialogue cannot duplicate recruits")
	var b := Battle.new(c,"ferry",42)
	check(b.living(0).size()==2 and b.living(1).size()==2,"First encounter contains independent units")
	check(b.target_for(b.by_id("hero"),"archer").id=="guard1","Melee cannot bypass front protection")
	check(b.target_for(b.by_id("sword"),"archer",true).id=="archer","Piercing skill can select a rear target")
	b.order("sword","skill","archer")
	resolve(b)
	check(b.by_id("archer").hp < 190,"Sword active damages the selected rear enemy")
	check(b.by_id("sword").cd > 0 and not b.order("sword","skill","archer"),"Cooldown prevents immediate repeat")
	for i in 15:
		if b.result != "": break
		b.auto_orders()
		resolve(b)
	check(b.result=="victory","Untrained introductory party can win by using its skills")
	c.win("ferry")
	check(c.state.stage==2 and c.state.potential==115,"First win advances story and grants real training points")
	c.state.place="藥廬"
	c.choose("recruit_healer")
	check(c.state.stage==3 and "healer" in c.state.party,"Clue leads to healer recruitment")
	c.state.place="蘆葦蕩"
	b=Battle.new(c,"reeds",42)
	for i in 20:
		if b.result != "": break
		b.auto_orders()
		resolve(b)
	check(b.result=="victory","Three roles can defeat the reeds ambush")
	c.win("reeds")
	c.state.place="古寺"
	c.choose("recruit_staff")
	check(c.state.stage==5 and c.state.party.size()==4,"Story assembles the four-person party")
	c.position_hero("hero",1,false)
	check(c.state.formation.healer.front and not c.state.formation.hero.front,"Occupied formation slots swap companions instead of overlapping")
	c.position_hero("hero",1,true)
	c.state.place="演武坪"
	c.choose("sect_武當")
	check(c.state.sect=="武當" and c.unit("hero").weapon=="拳掌","Sect unlock changes actual compatible weapon and active")
	var before: int = c.unit("hero").atk
	c.train("hero")
	check(c.unit("hero").atk>before and c.state.potential<205,"Spending points changes combat attributes")
	c.equip("staff","inner","金鐘心法")
	c.equip("healer","inner","長春功")
	b=Battle.new(c,"warehouse",42)
	var boss: Dictionary = b.by_id("boss")
	boss.charging=true
	b.order("staff","skill","boss")
	b.by_id("staff").speed=200
	b.begin_round()
	var e: Dictionary = b.next_action()
	check(e.kind=="stun" and not boss.charging and boss.stun==1,"Staff control actually interrupts a charged boss attack")
	var hero: Dictionary = b.by_id("hero")
	hero.hp=100
	hero.poison=2
	hero.bleed=2
	b.by_id("healer").speed=190
	# Finish this round, then test recovery in isolation with enough energy.
	while not b.queue.is_empty() and b.result=="": b.next_action()
	b.by_id("healer").energy=100
	b.by_id("healer").cd=0
	b.by_id("healer").speed=300
	b.order("healer","skill")
	b.begin_round()
	e=b.next_action()
	check(e.kind=="heal" and hero.hp>100 and hero.poison==0 and hero.bleed==0,"Healer restores health and removes damaging statuses")
	var energy: int = b.by_id("sword").energy
	# Use a fresh round to verify a single global qi pulse from one basic attack.
	var pulse := Battle.new(c,"warehouse",1)
	pulse.by_id("sword").speed=300
	pulse.begin_round()
	pulse.next_action()
	check(pulse.by_id("hero").energy==50+pulse.by_id("hero").qi,"Every normal attack gives allies one qi pulse")
	check(pulse.by_id("boss").energy==57,"Normal attacks also give foes qi")
	var guard_battle := Battle.new(c,"warehouse",1)
	guard_battle.by_id("staff").speed=400
	guard_battle.order("staff","guard")
	guard_battle.begin_round()
	guard_battle.next_action()
	var staff_hp: int = guard_battle.by_id("staff").hp
	var rear_hp: int = guard_battle.by_id("healer").hp
	while not guard_battle.queue.is_empty() and guard_battle.result=="": guard_battle.next_action()
	check(guard_battle.by_id("staff").hp<staff_hp and guard_battle.by_id("healer").hp==rear_hp,"Front guard intercepts enemy rear-target poison attack")
	var inventory := {"金創藥":2}
	var med := Battle.new(c,"warehouse",1)
	med.by_id("hero").hp=100
	check(not med.medicine("hero",inventory).is_empty() and med.by_id("hero").hp==240,"Medicine restores real combat health and consumes stock")
	check(med.medicine("hero",inventory).is_empty() and inventory["金創藥"]==1,"Cannot use a second medicine in one planning phase")
	var victories := 0
	for seed_value in range(1,11):
		var trial := Battle.new(c,"warehouse",seed_value)
		for i in 40:
			if trial.result!="": break
			trial.auto_orders()
			resolve(trial)
		if trial.result=="victory": victories+=1
	check(victories>=8,"Chapter boss is viable with a complete minimally trained party: %d/10 wins" % victories)
	c.state.place="舊倉"
	c.choose("choose_mercy")
	c.win("warehouse")
	c.state.place="青溪客棧"
	c.choose("ending")
	check(c.state.stage==7 and c.state.flags.choice=="mercy","Dialogue, investigation and boss reach a real chapter ending")
	var silver: int = c.state.silver
	c.choose("ending")
	check(c.state.silver==silver,"Ending rewards cannot be duplicated")
	c.state.place="市集"
	c.trade("金創藥",true)
	check(c.state.silver==silver-20,"Shop purchase subtracts its displayed price")
	c.trade("金創藥",false)
	check(c.state.silver==silver-10,"Shop sale pays its displayed sale price")
	c.state.place="蘆葦蕩"
	for i in 3: c.choose("gather")
	c.state.place="藥廬"
	c.choose("give_herbs")
	check(c.state.flags.herbs and c.state.inventory["草藥"]==0,"Optional gathering quest consumes herbs and records completion")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(c.state))
	check(Chapter.valid_save(roundtrip),"Campaign save survives JSON number conversion")
	var loaded := Chapter.new(roundtrip)
	check(loaded.state.stage==7 and loaded.state.party.size()==4 and loaded.state.flags.herbs,"Restored save retains party, ending, loadouts and side quest")
	var invalid := roundtrip.duplicate(true)
	invalid.party.append("boss")
	check(not Chapter.valid_save(invalid),"Save import rejects unknown party IDs")
	invalid=roundtrip.duplicate(true)
	invalid.levels.hero="broken"
	check(not Chapter.valid_save(invalid),"Save import rejects malformed numeric progression")
	print("JOURNEY TEST: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
