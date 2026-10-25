extends SceneTree
const Chapter = preload("res://scripts/journey/chapter.gd")
const Atlas = preload("res://scripts/journey/atlas.gd")
const Daily = preload("res://scripts/journey/daily.gd")
const Battle = preload("res://scripts/journey/battle.gd")
const Town = preload("res://scripts/journey/town.gd")
var checks := 0
var failures := []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func _init() -> void:
	var c := Chapter.new()
	var old := c.state.duplicate(true)
	for id in ["blade","palm","doctor","taoist","monk","wanderer"]:
		for key in ["levels","loadouts","formation"]: old[key].erase(id)
	old.erase("roster")
	check(Chapter.valid_save(old),"Pre-expansion saves remain importable")
	var migrated := Chapter.new(old)
	check(migrated.state.levels.has("wanderer") and migrated.state.roster == ["hero"],"Old saves receive defaults without auto-recruiting anyone")
	check(Daily.day_at(57600-1)+1 == Daily.day_at(57600),"Daily boundary is UTC+8 midnight")
	var d := Daily.ensure(c,100000)
	Daily.complete(c,"work",30,15)
	check(Daily.count(c,"work") == 1,"Daily completion records actual reward progress")
	# Use the current day so ensure() in complete() does not intentionally roll over.
	d = Daily.ensure(c)
	var current := int(d.day)
	Daily.ensure(c,(current-1)*86400-28800)
	check(int(c.state.daily.day) == current and Daily.count(c,"work") == 1,"Clock rollback cannot reset rewards")
	Daily.complete(c,"work",30,15)
	var silver: int = c.state.silver
	check(not Daily.complete(c,"work",30,15) and c.state.silver == silver,"Daily quota blocks duplicate payouts")
	Daily.ensure(c,(current+1)*86400-28800)
	check(Daily.count(c,"work") == 0,"Next day resets counts exactly once")
	Atlas.ensure(c)
	Atlas.visit(c,"龍門")
	check(c.state.atlas.region == "龍門","All distant journeys are available without chapter gates")
	c.state.stage = 7
	c.state.sect = "華山"
	for id in ["sword","healer","staff"]: c.recruit(id)
	check(c.state.party == ["hero","sword","healer","staff"],"Story party keeps its original roles and positions")
	for region in Atlas.RECRUITS:
		Atlas.visit(c,region)
		Atlas.resolve(c)
		var recruited: String = Atlas.RECRUITS[region]
		check(recruited in c.state.roster and c.state.party.size() == 4,"Regional quest recruits to the roster: "+region)
		check(Chapter.HEROES[recruited].outer in c.available_outer("hero"),"Regional martial inheritance becomes learnable: "+region)
	silver = c.state.silver
	Atlas.resolve(c)
	check(c.state.silver == silver,"First-clear rewards and recruitment cannot be duplicated")
	c.swap_companion("blade","sword")
	check("blade" in c.state.party and not "sword" in c.state.party and "sword" in c.state.roster,"Substitution preserves the benched companion and caps the field at four")
	c.swap_companion("palm","hero")
	check("hero" in c.state.party and not "palm" in c.state.party,"Main character cannot be replaced")
	Atlas.visit(c,"龍門")
	c.state.place = "演武坪"
	c.state.potential = 50000
	c.train("hero")
	check(c.state.levels.hero == 1,"Distant journeys cannot use a training master left behind in Qingxi")
	c.state.place = "市集"
	silver = c.state.silver
	c.trade("金創藥",true)
	check(c.state.silver == silver,"Distant journeys cannot transact with a merchant left behind in Qingxi")
	Atlas.visit(c,"嘉興鎮")
	c.state.place = "演武坪"
	for i in 29: c.train("hero")
	check(c.state.levels.hero == 30,"Progression continues beyond the first chapter to rank thirty")
	var points: int = c.state.potential
	c.train("hero")
	check(c.state.potential == points,"Rank cap does not consume points")
	var before := Battle.new(c,"road_牛家村",12)
	var after := Battle.new(c,"road_龍門",12)
	check(after.living(1)[0].hp > before.living(1)[0].hp*3,"Distant challenges have materially different strengths")
	var town := Town.new()
	for from in town.anchors:
		for to in town.anchors:
			check(not town.route(town.anchors[from],town.anchors[to]).is_empty(),"Street route exists: "+from+" -> "+to)
	Daily.complete(c,"gather",0,3)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(c.state))
	check(Chapter.valid_save(saved),"Expanded roster, map and daily state survive portable JSON saves")
	var restored := Chapter.new(saved)
	check(restored.state.roster.size() == 10 and restored.state.atlas.cleared.size() == 6 and int(restored.state.daily.day) == int(c.state.daily.day) and int(restored.state.daily.counts.gather) == 1,"Reload retains world quests, recruits and daily progress")
	var bad := saved.duplicate(true)
	bad.daily.counts.work = 999
	check(not Chapter.valid_save(bad),"Import rejects impossible daily counts")
	bad = saved.duplicate(true)
	bad.atlas.region = "unknown"
	check(not Chapter.valid_save(bad),"Import rejects unknown world regions")
	var weak := Chapter.new()
	weak.state.stage = 7
	for id in ["sword","healer","staff"]: weak.recruit(id)
	var wins := [0,0]
	for trained in 2:
		var trial_party := Chapter.new(weak.state)
		if trained == 1:
			for id in trial_party.state.party: trial_party.state.levels[id] = 25
		for seed_value in range(1,11):
			var trial := Battle.new(trial_party,"supremacy",seed_value)
			for round_index in 40:
				if trial.result != "": break
				trial.auto_orders()
				trial.begin_round()
				while not trial.queue.is_empty() and trial.result == "": trial.next_action()
			if trial.result == "victory": wins[trained] += 1
	check(wins[0] == 0 and wins[1] >= 8,"Growth makes the final masters beatable: novice %d/10, rank-25 party %d/10" % wins)
	print("EXPANSION TEST: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
