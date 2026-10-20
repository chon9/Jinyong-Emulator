extends SceneTree
const Data = preload("res://scripts/content.gd")
const Rules = preload("res://scripts/world.gd")
const Market = preload("res://scripts/market.gd")
var checks := 0
var failures: Array = []
var ui
var session

class ErrorLog extends Logger:
	var errors: Array = []
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor: bool, error_type: int, _traces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING: errors.append(rationale if rationale != "" else code)

func _init() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); push_error(description)

func controls(node: Node, type: String) -> Array:
	var found: Array = []
	if node.is_class(type): found.append(node)
	for child in node.get_children(): found.append_array(controls(child, type))
	return found

func find_button(prefix: String) -> Button:
	for b in controls(ui, "Button"):
		if b.is_visible_in_tree() and b.text.begins_with(prefix): return b
	return null

func click(control: Control) -> bool:
	if control == null:
		check(false, "Required control exists")
		quit(1)
		return false
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(control)
		ancestor = ancestor.get_parent()
	await process_frame
	await process_frame
	var point := control.get_global_rect().get_center()
	check(root.get_visible_rect().has_point(point), "Click is inside viewport: " + str(control.name))
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	var clicked := {"value": false}
	var is_button := control is Button
	if is_button: control.pressed.connect(func(): clicked.value = true, CONNECT_ONE_SHOT)
	for pressed in [true, false]:
		root.push_input(motion.duplicate(), true)
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await process_frame
	if is_button:
		var hovered: Control = root.gui_get_hovered_control()
		check(clicked.value, "Mouse click reaches button %s; hovered %s" % [str(control.text) if is_instance_valid(control) else "(freed)", str(hovered)])
	return true

func click_named(prefix: String) -> void:
	await click(find_button(prefix))

func walk() -> void:
	var p: Dictionary = session.world.players[1]
	var guard := 0
	while p.travel_target != "" and guard < 400:
		session._tick()
		guard += 1
		await process_frame
	check(p.travel_target == "", "Automatic travel reaches its destination")

func run() -> void:
	var logger := ErrorLog.new()
	OS.add_logger(logger)
	session = root.get_node("Session")
	session.save_path = "res://test-results/ui-flow-save.json"
	for timer in session.get_children():
		if timer is Timer: timer.stop()
	var p: Dictionary = session.world.add_player(1, "介面驗證")
	p.sect = "古墓"
	p.silver = 1000
	session._publish()
	ui = load("res://scenes/main.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	check(ui.nav_buttons.size() == 10, "Ten permanent labeled destinations including life work")
	await click(ui.nav_buttons[3])
	check(ui.tabs.current_tab == 3, "Task navigation opens the quest journal")
	check(find_button("驛站送信\n") != null, "A sect member can discover common quests")
	await click(ui.activity_search)
	for character in "驛站":
		var key := InputEventKey.new()
		key.unicode = character.unicode_at(0)
		key.pressed = true
		root.push_input(key, true)
		await process_frame
		await process_frame
	check(ui.quest_query == "驛站" and ui.activity_search.has_focus(), "Search accepts consecutive characters across refreshes")
	await click_named("驛站送信\n")
	check(ui.selected_quest == "q_letter", "Click selects the actual quest")
	await click_named("前往接任務")
	check(p.travel_target == Data.NPCS[Data.QUESTS.q_letter.giver].place, "Go-to button starts travel immediately")
	await walk()
	await click_named("接任務 · 驛站送信")
	check(p.learning_quests.has("q_letter"), "NPC's accept button reaches host quest acceptance")
	check(int(p.inventory.get("驛站信函", 0)) == 1, "Accepted letter quest supplies its letter")
	await click_named("前往 · 大理・大理驛站")
	await walk()
	await click(ui.nav_buttons[3])
	await click_named("交付物品")
	check(int(p.inventory.get("驛站信函", 0)) == 0, "Quest delivery consumes the real item")
	var before := int(p.silver)
	await click_named("領取獎勵")
	check(p.quests_done.has("q_letter") and not p.learning_quests.has("q_letter") and p.silver > before, "UI flow completes quest and awards reward once")
	check(ui.quest_filter == 3, "Completed quest remains discoverable in history")
	await click(ui.nav_buttons[7])
	check(find_button("購買物品") != null and find_button("出售物品") != null, "Buy and sell have explicit tabs")
	check(not Market.has_shop(p.place), "Fixture arrives at a location without a shop")
	var nearby := Market.shops_near(p.place)
	var destination: String = nearby[0].place
	await click_named(destination + " ·")
	check(p.travel_target == destination, "Shop finder starts actual travel")
	await walk()
	await click(ui.nav_buttons[7])
	var item: String = Market.stock(p.place)[0]
	await click_named(item + "\n")
	var quantity: SpinBox = controls(ui.page_bodies["商店"], "SpinBox")[0]
	quantity.value = 3
	before = int(p.silver)
	var held := int(p.inventory.get(item, 0))
	var unit := int(Data.SHOP[item].price)
	await click_named("購買 3 件")
	check(int(p.inventory.get(item, 0)) == held + 3 and p.silver == before - unit * 3, "Purchase button atomically exchanges stated quantity and silver")
	await click_named("出售物品")
	await click_named(item + "\n")
	quantity = controls(ui.page_bodies["商店"], "SpinBox")[0]
	quantity.value = 2
	before = int(p.silver)
	await click_named("出售 2 件")
	check(int(p.inventory[item]) == held + 1 and p.silver == before + maxi(1, unit / 3) * 2, "Sale button exchanges real items for the displayed price")
	p.silver = 0
	session._publish()
	await click_named("購買物品")
	await click_named(item + "\n")
	var buy := find_button("購買 1 件")
	check(buy != null and buy.disabled, "Insufficient funds visibly disable purchase")
	check(controls(ui.page_bodies["商店"], "Label").any(func(l): return "銀兩不足" in l.text), "Insufficient-funds reason is visible without a tooltip")
	p.silver = 1000
	p.inventory["木劍"] = 1
	p.weapon = "木劍"
	session._publish()
	await click_named("出售物品")
	await click_named("木劍\n")
	check(find_button("出售 1 件").disabled, "Equipped last copy cannot be sold through the UI")
	await click_named("卸下木劍")
	check(p.weapon == "" and not find_button("出售 1 件").disabled, "Shop offers an explicit way to unequip before selling")
	await click_named("出售 1 件")
	check(int(p.inventory["木劍"]) == 0, "Unequipped item can actually be sold")
	await click(ui.nav_buttons[2])
	check(find_button("購買物品") != null and find_button("出售物品") != null, "Inventory links directly to both shop modes")
	var saved := p.duplicate(true)
	for arg in [item + "|0", item + "|-2", item + "|100", item + "|bad", item + "|1|1"]:
		check(not session.world.act(1, "購買", arg), "Host rejects invalid quantity: " + arg)
	check(p.inventory == saved.inventory and p.silver == saved.silver, "Rejected requests do not partially charge or grant items")
	var w := Rules.new()
	var other: Dictionary = w.add_player(1)
	other.place = Data.NPCS[Data.QUESTS.q_bandit.giver].place
	check(w.act(1, "接受任務", "q_bandit"), "Bandit quest accepts")
	other.place = Data.QUESTS.q_bandit.stages[0].place
	check(w.act(1, "任務行動", "q_bandit|o_0") and other.enemy.get("quest_enemies", []).size() == 2, "Monster target is not mistaken for NPC and three kills are required")
	for sample in [["q_hs_spy", "s_fight"], ["q_xd_xuehai", "s_hunt"]]:
		var q: Dictionary = Data.QUESTS[sample[0]]
		for index in q.stages.size():
			var stage: Dictionary = q.stages[index]
			if stage.id != sample[1]: continue
			other = w.add_player(1)
			other.learning_quests[q.id] = {"stage": index, "done": {}, "started": 0, "vars": {}, "effects": {}, "dialogue": ""}
			for o in stage.objectives: other.learning_quests[q.id].done[o.id] = true
			w.quests.advance(1, q.id)
			var quest_item: String = stage.on_complete[0].item
			check(int(other.inventory.get(quest_item, 0)) == 1, "Stage completion supplies its required quest item: " + q.id)
	OS.remove_logger(logger)
	check(logger.errors.is_empty(), "No engine or script errors: " + str(logger.errors))
	var result := {"checks": checks, "failures": failures, "scope": "Mouse-input quest acceptance, travel, delivery, reward, buying and selling; host validation edge cases"}
	var output := FileAccess.open("res://test-results/ui-flow.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	print("UI FLOW TEST: ", checks, " checks, ", failures.size(), " failures")
	ui.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
