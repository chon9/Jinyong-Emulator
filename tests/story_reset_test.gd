extends SceneTree
const Chapter=preload("res://scripts/journey/chapter.gd")
const Open=preload("res://scripts/journey/open_world.gd")
var checks:=0
var failures:=[]
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures.append(text);push_error(text)
func _init() -> void:call_deferred("run")
func run() -> void:
	var session=root.get_node("Session")
	session.save_path="res://test-results/story-reset-"+str(Time.get_ticks_usec())+".json"
	var old=Chapter.new();Open.ensure(old)
	old.state.open_world.erase("story_edition")
	old.state.silver=731
	old.state.roster=["hero","jy02"]
	old.state.open_world.quests.friend_jy24={"status":"active","step":2,"choices":[],"edition":2}
	session.chapter_data=old.state.duplicate(true)
	var legacy: Dictionary=session.chapter_data.duplicate(true)
	session.local_character.name="備份中的少俠"
	session.guest_saves={"test_friend":{"name":"同行舊客"}}
	session.local_tick=812
	check(session.migrate_story(),"Old campaign starts afresh only after a verified full backup")
	var backups: Array=session.story_backups()
	check(backups.size()==1 and session.chapter_data.is_empty(),"Narrative reset keeps one separately addressable backup")
	var text: String=FileAccess.get_file_as_string(backups[0])
	var payload: Dictionary=JSON.parse_string(text)
	check(payload.chapter==JSON.parse_string(JSON.stringify(legacy)) and payload.character.name=="備份中的少俠" and payload.guests==session.guest_saves and payload.world_tick==812,"Backup retains exact old quest, roster, inventory, classic character, guests and clock")
	var fresh=Chapter.new();Open.ensure(fresh)
	fresh.state.silver=165
	session.chapter_data=fresh.state.duplicate(true)
	check(not session.migrate_story() and session.chapter_data.silver==165,"New-edition progress is never reset on a later load")
	check(FileAccess.get_file_as_string(backups[0])==text,"Later saves do not overwrite the rewrite backup")
	session.chapter_data=legacy.duplicate(true)
	session.save_path="res://test-results/nonexistent-story-backup-directory/save.json"
	check(not session.migrate_story() and session.chapter_data==legacy,"An unwritable backup leaves the entire old campaign intact")
	check(not session.story_migration_notice.is_empty(),"Backup failure supplies an actionable explanation")
	print("STORY RESET: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
