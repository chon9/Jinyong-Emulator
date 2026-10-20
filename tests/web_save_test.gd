extends SceneTree
var checks := 0
var failures: Array = []

func _init() -> void: call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); push_error(text)

func run() -> void:
	var session = root.get_node("Session")
	session.save_path = "res://test-results/web-save-fixture.json"
	var p: Dictionary = session.world.add_player(1, "原有少俠")
	p.silver = 456
	p.life_levels = {"life_fishing": 12}
	p.life_prof = {"life_fishing": 288}
	var data := {"version": 1, "character": p.duplicate(true), "world_tick": 320}
	data.character.name = "匯入少俠"
	data.character.auto = "生活"
	data.character.travel_target = "黑風林"
	data.character.life_work = {"active": true}
	check(session.import_save_text(JSON.stringify(data)), "Compatible desktop save imports")
	var restored: Dictionary = session.world.players[1]
	check(restored.name == "匯入少俠" and int(restored.silver) == 456 and int(restored.life_prof.life_fishing) == 288 and session.world.tick == 320, "Import retains inventory, life progress and world clock")
	check(restored.auto == "停止" and restored.life_work.is_empty() and restored.travel_target == "", "Imported incomplete activities do not resume")
	check(not session.import_save_text('{"version":1,"character":{"inventory":[]}}'), "Malformed inventory rejected")
	check(not session.import_save_text('{"version":1,"character":{"inventory":{"x":"bad"}}}'), "Malformed quantities rejected")
	check(session.world.players[1].name == "匯入少俠", "Rejected imports preserve the current character")
	session.mode = "WebSocket 客戶端"
	check(not session.import_save_text(JSON.stringify(data)), "Client cannot import local stats into a host-owned character")
	session.mode = "單機"
	var file := FileAccess.open("res://test-results/web-save-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	print("WEB SAVE: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
