extends SceneTree
const Rules = preload("res://scripts/world.gd")
var failures: Array = []
var checks := 0
var messages: Array = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); push_error(description)

func request_for(world, target: int, kind: String) -> int:
	for r in world.social.requests.values():
		if r.to == target and r.kind == kind: return int(r.id)
	return 0

func accept_party(world, leader: int, member: int) -> void:
	check(world.act(leader, "組隊邀請", str(member)), "Party invitation sent")
	check(world.act(member, "接受邀請", str(request_for(world, member, "組隊"))), "Party invitation accepted")

func run() -> void:
	var w := Rules.new()
	w.rng.seed = 7
	w.event.connect(func(id: int, channel: String, text: String): messages.append([id, channel, text]))
	for id in range(1, 8):
		w.add_player(id, "少俠" + str(id))
		w.players[id].auto_heal = false
	check(not w.act(1, "組隊邀請", "1"), "Self party invite rejected")
	w.players[2].place = "城郊荒野"
	check(not w.act(1, "組隊邀請", "2"), "Remote party invitation rejected")
	w.players[2].place = "揚州城"
	check(w.act(1, "組隊邀請", "2"), "Party invitation created")
	var invite := request_for(w, 2, "組隊")
	check(not w.act(3, "接受邀請", str(invite)), "Third party cannot accept another player's invitation")
	check(w.act(2, "接受邀請", str(invite)), "Recipient can accept")
	check(not w.act(2, "接受邀請", str(invite)), "Invitation cannot be replayed")
	check(w.players[1].party == w.players[2].party, "Players share a party")
	check(not w.act(2, "組隊邀請", "3"), "Members cannot issue leader invitations")
	for id in [3, 4, 5]: accept_party(w, 1, id)
	check(w.social.members(1).size() == 5, "Party supports five members")
	check(not w.act(1, "組隊邀請", "6"), "Sixth member blocked")
	check(not w.act(2, "踢出隊伍", "3"), "Only leader can kick")
	check(w.act(1, "移交隊長", "2"), "Leadership transferable")
	check(w.act(2, "踢出隊伍", "5") and w.players[5].party == 0, "Leader kick clears member association")
	check(w.act(1, "跟隨", "開啟"), "Member can follow leader")
	check(w.act(2, "前往", "城郊荒野"), "Leader can travel")
	check(w.players[1].place == "城郊荒野" and w.players[3].place == "揚州城", "Only nearby opted-in members follow")
	check(w.players[1].visited.has("城郊荒野"), "Following records exploration")
	messages.clear()
	check(w.act(1, "隊伍說", "秘密訊息"), "Party chat works at distance")
	check(messages.filter(func(m: Array): return m[1] == "隊聊").size() == 4, "Party chat delivered only to members")
	messages.clear()
	check(w.act(1, "私聊", "6|密語"), "Private chat reaches distant online player")
	check(messages.size() == 2 and messages.all(func(m: Array): return m[0] in [1, 6]), "Private chat is not broadcast")
	check(w.act(1, "離隊") and w.players[1].party == 0, "Leave party clears membership")
	w.social.disconnect_peer(2)
	check(w.social.parties[int(w.players[3].party)].leader == 3, "Disconnect promotes a remaining leader")
	# Fresh pair for actual shared PvE and reward accounting.
	w = Rules.new()
	w.rng.seed = 11
	w.add_player(1)
	w.add_player(2)
	w.players[1].auto_heal = false
	w.players[2].auto_heal = false
	accept_party(w, 1, 2)
	w.act(2, "跟隨", "開啟")
	w.act(1, "前往", "城郊荒野")
	check(w.act(1, "打怪"), "Party hunt starts")
	check(w.players[1].fight != 0 and w.players[1].fight == w.players[2].fight, "One shared encounter used by both members")
	check(w.players[1].enemy.hp == 72, "Party encounter health scales for two members")
	w.social.battles.values()[0].enemy["combat_xp"] = 1
	check(not w.act(1, "前往", "揚州城"), "Cannot teleport out of shared combat")
	check(not w.act(1, "離隊"), "Cannot reshuffle parties during shared combat")
	for i in 10: w.step()
	check(w.players[1].kills == 1 and w.players[2].kills == 1, "Survivors both receive kill credit")
	check(w.players[1].exp + w.players[2].exp == 26, "Experience split without multiplication")
	check(w.players[1].combat_xp + w.players[2].combat_xp == 0, "Small lifetime XP rewards cannot multiply through a party")
	check(w.players[1].silver + w.players[2].silver == 172, "Coin split conserves total reward")
	check(w.social.battles.is_empty() and w.players[1].fight == 0 and w.players[2].enemy.is_empty(), "Shared battle cleanup")
	w.players[2].hp = 20
	var meds: int = w.players[1].inventory["金創藥"]
	check(w.act(1, "治療隊友", "2"), "Heal nearby ally")
	check(w.players[2].hp == 90 and w.players[1].inventory["金創藥"] == meds - 1, "Ally healing consumes sender's medicine")
	# Duels need consent and restore pre-match health and inner power.
	w.players[1].place = "揚州城"
	w.players[2].place = "揚州城"
	w.players[1].hp = 35
	w.players[2].hp = 35
	w.players[1].mp = 23
	w.players[1].stance = "重擊"
	check(w.act(1, "切磋", "2"), "Duel invitation valid in safe zone")
	check(w.players[1].fight == 0, "Invitation alone does not begin PvP")
	check(w.act(2, "接受邀請", str(request_for(w, 2, "切磋"))), "Duel begins on acceptance")
	check(w.players[1].fight != 0, "PvP state synchronized")
	check(not w.act(2, "打坐"), "Meditation blocked during PvP")
	for i in 8:
		w.step()
		if w.social.battles.is_empty(): break
	check(w.social.battles.is_empty(), "Duel reaches an outcome")
	check(w.players[1].hp == 35 and w.players[2].hp == 35 and w.players[1].mp == 23, "Duel restores original HP and MP")
	check(w.players[1].pvp_wins + w.players[2].pvp_wins == 1, "PvP records one winner")
	check(w.players[1].silver + w.players[2].silver == 172, "Duel creates no farmable currency")
	check(not w.act(1, "PK", "2"), "PK rejected in safe zone")
	w.players[1].place = "城郊荒野"
	w.players[2].place = "城郊荒野"
	w.act(1, "離隊")
	w.act(1, "PK設定", "開啟")
	check(not w.act(1, "PK", "2"), "PK requires target opt-in")
	w.act(2, "PK設定", "開啟")
	check(w.act(1, "PK", "2"), "Opted-in wilderness PK starts")
	check(not w.act(1, "PK設定", "關閉"), "Cannot toggle invulnerability mid-fight")
	check(w.act(2, "認輸"), "Player can surrender")
	check(w.players[2].place == "揚州城" and not w.players[2].pk_enabled and w.players[2].fight == 0, "PK loss returns player safely and disables PK")
	# Atomic transactions: resources are validated again when accepted.
	w.players[1].place = "揚州城"
	w.players[2].silver = 100
	w.players[1].silver = 100
	w.players[1].inventory["金創藥"] = 5
	w.players[2].inventory["金創藥"] = 5
	check(not w.act(1, "交易", "2|金創藥|-1|10"), "Negative trade amounts rejected")
	check(w.act(1, "交易", "2|金創藥|2|30"), "Valid trade proposed")
	var offer := request_for(w, 2, "交易")
	check(w.act(2, "接受邀請", str(offer)), "Buyer accepts trade")
	check(w.players[1].inventory["金創藥"] == 3 and w.players[2].inventory["金創藥"] == 7, "Items transfer exactly once")
	check(w.players[1].silver == 130 and w.players[2].silver == 70, "Silver moves atomically")
	check(not w.act(2, "接受邀請", str(offer)), "Trade acceptance cannot replay")
	check(w.act(1, "交易", "2|金創藥|3|20"), "Second offer created")
	w.players[1].inventory["金創藥"] = 1
	check(not w.act(2, "接受邀請", str(request_for(w, 2, "交易"))), "Inventory change invalidates pending trade")
	check(w.players[2].silver == 70 and w.players[2].inventory["金創藥"] == 7, "Failed trade preserves buyer resources")
	w.players[1].inventory["精鋼劍"] = 1
	w.players[1].weapon = "精鋼劍"
	check(not w.act(1, "交易", "2|精鋼劍|1|0"), "Last equipped weapon cannot be traded")
	w.act(1, "切磋", "2")
	var expires := request_for(w, 2, "切磋")
	w.tick += 46
	w.social.step()
	check(not w.act(2, "接受邀請", str(expires)), "Expired invitation rejected")
	w.act(1, "切磋", "2")
	w.act(2, "接受邀請", str(request_for(w, 2, "切磋")))
	w.social.disconnect_peer(2)
	check(w.players[1].fight == 0 and w.social.battles.is_empty(), "Disconnect cleans up opponent combat")
	var file := FileAccess.open("res://test-results/social.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	file.close()
	print("SOCIAL TEST: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
