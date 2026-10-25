extends SceneTree
const Chapter=preload("res://scripts/journey/chapter.gd")
const Open=preload("res://scripts/journey/open_world.gd")
const Data=preload("res://scripts/journey/open_content.gd")
var checks:=0
var failures:=[]
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures.append(text);push_error(text)
func completed(c,id: String,choice: int) -> void:
	c.state.open_world.quests[id]={"status":"done","step":Data.QUESTS[id].steps.size(),"choices":[choice],"edition":3}
	c.state.open_world.finished.erase(id);c.state.open_world.finished.append(id)
func campaign():
	var c=Chapter.new();preload("res://scripts/journey/atlas.gd").ensure(c);Open.ensure(c)
	return c
func _init() -> void:
	for choice in 2:
		for qid in Data.QUESTS:
			var c=campaign();completed(c,qid,choice)
			var q: Dictionary=Data.QUESTS[qid]
			for pid in q.aftermath:
				var expected: Array=q.get("aftermath_choices",{}).get(str(choice),{}).get(pid,q.aftermath[pid])
				check(Open.latest_completed(c,pid)==qid,"Every participant remembers their completed event: "+qid+" / "+pid)
				check(Open.conversation(c,pid)==expected,"Post-event speech matches the saved choice for giver and witness")
				var casual: Array=Open.conversation(c,pid,true)
				check(not casual.is_empty() and casual!=q.steps[0].pages,"Casual talk does not replay the completed quest opening")
				check(Open.available_topic(c,pid)!=qid,"A finished story cannot return as an available conversation task")
				for line in expected:
					check(not q.steps.any(func(s):return s.pages.any(func(p):return p.text==line.text)),"Post-event response does not repeat a quest or reward line")
	var c=campaign();completed(c,"friend_jy06",1);completed(c,"flash_09",0)
	check("劍鞘" in Open.conversation(c,"jy06")[0].text,"Latest completed event takes priority over the first assigned story")
	var restored=Chapter.new(JSON.parse_string(JSON.stringify(c.state)))
	check(Open.latest_completed(restored,"jy06")=="flash_09","Completion order survives JSON save and load")
	check(not Open.begin_conversation(restored,"jy06") and Open.begin_conversation(restored,"jy06"),"First revisit gives the event response; subsequent visits start with everyday talk")
	var remembered=Chapter.new(JSON.parse_string(JSON.stringify(restored.state)))
	check(Open.begin_conversation(remembered,"jy06"),"The already-heard event response stays remembered after reload")
	check(Chapter.valid_save(restored.state),"Optional completion history remains a valid save")
	var old: Dictionary=c.state.duplicate(true);old.open_world.erase("finished")
	old.open_world.tracked="friend_jy06"
	var migrated=Chapter.new(old);Open.ensure(migrated)
	check(migrated.state.open_world.quests==old.open_world.quests and migrated.state.roster==old.roster and migrated.state.silver==old.silver,"Existing v0.12 progress is retained without resetting quests or companions")
	check(not Open.conversation(migrated,"jy06").is_empty(),"Old saves gain post-quest conversations without replaying the task")
	var invalid: Dictionary=restored.state.duplicate(true)
	invalid.open_world.finished.append("flash_09")
	check(not Chapter.valid_save(invalid),"Import rejects duplicate completion-history entries")
	invalid=restored.state.duplicate(true);invalid.open_world.finished=["friend_jy02"]
	check(not Chapter.valid_save(invalid),"Import rejects history entries that are not completed quests")
	var fresh=campaign();var q: Dictionary=Data.QUESTS.friend_jy02
	for pid in Data.PEOPLE:
		if Open.available_topic(fresh,pid)=="" and Data.PEOPLE[pid].get("alternate_pages",[]).size()>0:
			check(Open.conversation(fresh,pid)==Data.PEOPLE[pid].pages,"Residents without a current request retain their authored local gossip")
	check(Open.conversation(fresh,"jy02")==q.steps[0].pages,"A new character still hears the original introduction exactly once")
	Open.enter(fresh,q.region,q.scene);Open.accept(fresh,"friend_jy02","jy02");Open.action(fresh,"friend_jy02","jy02")
	check(Open.conversation(fresh,"jy02")!=q.steps[0].pages,"An accepted story does not repeat the initial request while awaiting the next step")
	print("AFTERMATH: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
