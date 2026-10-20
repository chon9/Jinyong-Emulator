extends SceneTree
var failures: Array = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); push_error(description)

func run() -> void:
	var session = root.get_node("Session")
	session.save_path = "res://test-results/persistence.json"
	var ui = load("res://scenes/main.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	for i in 9:
		ui.tabs.current_tab = i
		await process_frame
		check(ui.page_bodies[ui.tabs.get_tab_title(i)].get_child_count() > 0, "Tab populated: " + str(i))
	check(ui.hot_actions.size() == 8 and ui.vital_bars.size() == 3, "Classic HUD has working shortcuts and vital bars")
	check(ui.backdrop.texture != null and ui.theme.default_font != null, "Reference art and font loaded")
	check(ui.music_label.text.length() > 0 and ui.music_volume.max_value == 100, "Music controls render with saved preferences")
	var p: Dictionary = session.world.players[1]
	p.name = "存檔驗證"
	p.silver = 321
	p.skills["基本拳腳"] = 17
	p.skill_xp["基本拳腳"] = 9
	p.inventory["金創藥"] = 8
	check(session.save_game(), "First save succeeds")
	p.silver = 654
	check(session.save_game(), "Replace existing save succeeds")
	session.local_character = {}
	session._load()
	check(int(session.local_character.silver) == 654, "Latest save read back")
	session._restore(1, session.local_character)
	p = session.world.players[1]
	check(p.name == "存檔驗證" and p.skills["搏擊格鬥"] == 17 and not p.skills.has("基本拳腳") and p.inventory["金創藥"] == 8, "Legacy fist name migrates without losing character progress")
	check(p.skill_xp["搏擊格鬥"] == 9 and p.auto == "停止" and p.enemy.is_empty(), "Progress preserved, combat and automation reset safely")
	var corrupt := FileAccess.open(session.save_path, FileAccess.WRITE)
	corrupt.store_string("{incomplete")
	corrupt.close()
	session.local_character = {}
	session._load()
	check(int(session.local_character.silver) == 321, "Damaged main save recovers previous valid backup")
	check(session.save_game(), "Saving after recovery preserves a valid backup")
	ui._refresh()
	ui._message("世界", "[b]測試[/b] [url=bad]安全文字[/url]")
	check(not ui.chat_view.bbcode_enabled and "[b]測試[/b]" in ui.chat_view.text, "User chat remains literal text")
	ui._command("幫助")
	ui._command("改名 測試名號")
	check(p.name == "測試名號", "Command line reaches real game actions")
	ui.tabs.current_tab = 7
	await process_frame
	check(ui.nav_buttons.has(7) and ui.shop_item != "", "Shop has a permanent navigation entry and selectable stock")
	var result := {"checks": checks, "failures": failures}
	var file := FileAccess.open("res://test-results/ui.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("UI + SAVE TEST: ", checks, " checks, ", failures.size(), " failures")
	ui.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
