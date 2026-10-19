extends RefCounted
## Session-only interactions. Peer identities, offers and fights never survive reconnects.
var _owner: WeakRef
var world:
	get: return _owner.get_ref()
var parties: Dictionary = {}
var requests: Dictionary = {}
var battles: Dictionary = {}
var party_sequence := 0
var request_sequence := 0
var battle_sequence := 0
const LIMIT := 5
const COMMANDS := ["組隊邀請", "接受邀請", "拒絕邀請", "離隊", "移交隊長", "踢出隊伍", "跟隨", "切磋", "PK設定", "PK", "認輸", "隊伍說", "私聊", "交易", "治療隊友"]

func _init(owner) -> void:
	_owner = weakref(owner)

func reset() -> void:
	parties.clear()
	requests.clear()
	battles.clear()

func members(id: int) -> Array:
	if not world.players.has(id): return []
	return parties.get(int(world.players[id].party), {}).get("members", [])

func busy(id: int) -> bool:
	return world.players.has(id) and (not world.players[id].enemy.is_empty() or int(world.players[id].fight) != 0)

func peer(arg: String) -> int:
	return arg.to_int() if arg.is_valid_int() else 0

func valid_target(id: int, target: int, nearby: bool = true) -> bool:
	return target != id and world.players.has(target) and (not nearby or world.players[id].place == world.players[target].place)

func notify(ids: Array, text: String, channel: String = "隊伍") -> void:
	for id in ids:
		if world.players.has(id): world.tell(id, text, channel)

func request(id: int, target: int, kind: String, payload: Dictionary = {}) -> bool:
	if not valid_target(id, target): return world.reject(id, "請選擇同地點的其他少俠。")
	for r in requests.values():
		if r.from == id and r.to == target and r.kind == kind: return world.reject(id, "邀請仍在等候回覆。")
	var count := 0
	for r in requests.values():
		if r.from == id or r.to == target: count += 1
	if count >= 8: return world.reject(id, "待處理邀請過多，請稍候。")
	request_sequence += 1
	requests[request_sequence] = {"id": request_sequence, "from": id, "to": target, "kind": kind, "expires": world.tick + 45, "payload": payload}
	notify([id, target], "%s向%s發出%s邀請（45 息內回覆）。" % [world.players[id].name, world.players[target].name, kind], "人際")
	return true

func act(id: int, command: String, arg: String) -> bool:
	var p: Dictionary = world.players[id]
	var target := peer(arg)
	match command:
		"組隊邀請":
			if busy(id): return world.reject(id, "交戰時不能變更隊伍。")
			if p.party != 0 and int(parties[int(p.party)].leader) != id: return world.reject(id, "只有隊長能邀請隊員。")
			if members(id).size() >= LIMIT: return world.reject(id, "隊伍上限為五人。")
			if not valid_target(id, target) or world.players[target].party != 0: return world.reject(id, "對方不在此地，或已有隊伍。")
			return request(id, target, "組隊")
		"接受邀請", "拒絕邀請":
			if not requests.has(target) or int(requests[target].to) != id: return world.reject(id, "這不是發給你的邀請。")
			var r: Dictionary = requests[target]
			requests.erase(target)
			if command == "拒絕邀請": notify([id, r.from], "邀請已拒絕。", "人際"); return true
			if int(r.expires) <= world.tick or not valid_target(id, int(r.from)): return world.reject(id, "邀請已失效，或雙方不在同一地點。")
			if busy(id) or busy(int(r.from)): return world.reject(id, "有一方正在交戰，無法接受邀請。")
			match r.kind:
				"組隊": return join_party(id, int(r.from))
				"切磋": return start_pvp(int(r.from), id, "切磋")
				"交易": return settle_trade(int(r.from), id, r.payload)
		"離隊":
			if busy(id): return world.reject(id, "交戰時不能離隊。")
			leave_party(id)
		"移交隊長", "踢出隊伍":
			if p.party == 0 or int(parties[int(p.party)].leader) != id: return world.reject(id, "只有隊長能執行此操作。")
			if not target in members(id) or target == id or busy(id) or busy(target): return world.reject(id, "請選擇閒置中的隊友。")
			if command == "踢出隊伍": leave_party(target)
			else:
				parties[int(p.party)].leader = target
				world.players[target].follow = false
				notify(members(id), "%s成為隊長。" % world.players[target].name)
		"跟隨":
			if p.party == 0 or int(parties[int(p.party)].leader) == id: return world.reject(id, "入隊後，隊員可開啟跟隨隊長。")
			p.follow = arg == "開啟"
			world.tell(id, "跟隨隊長：" + ("開啟" if p.follow else "關閉"), "隊伍")
		"隊伍說":
			if p.party == 0: return world.reject(id, "你目前沒有隊伍。")
			notify(members(id), "%s：%s" % [p.name, clean_text(arg)], "隊聊")
		"私聊":
			var pair := arg.split("|", false, 1)
			if pair.size() != 2 or not valid_target(id, peer(pair[0]), false): return world.reject(id, "私聊需要在線玩家與內容。")
			notify([id, peer(pair[0])], "%s → %s：%s" % [p.name, world.players[peer(pair[0])].name, clean_text(pair[1])], "私聊")
		"切磋":
			if busy(id) or not valid_target(id, target) or busy(target): return world.reject(id, "請向同地點、閒置中的少俠提出切磋。")
			return request(id, target, "切磋")
		"PK設定":
			if busy(id): return world.reject(id, "交戰中不能切換 PK 模式。")
			p.pk_enabled = arg == "開啟"
			world.tell(id, "野外 PK " + ("已開啟；離開安全區後可與開啟 PK 的玩家交戰。" if p.pk_enabled else "已關閉。"), "PK")
		"PK": return start_pvp(id, target, "PK")
		"認輸":
			if p.fight == 0 or not battles.has(int(p.fight)) or battles[int(p.fight)].kind == "PVE": return world.reject(id, "你目前沒有與玩家交戰。")
			finish_pvp(int(p.fight), id)
		"交易":
			var values := arg.split("|", true)
			if values.size() != 4 or not values[2].is_valid_int() or not values[3].is_valid_int(): return world.reject(id, "交易格式：玩家編號|物品名|數量|售價。")
			target = peer(values[0])
			var item: String = values[1]
			var quantity := int(values[2])
			var price := int(values[3])
			if busy(id) or not valid_target(id, target) or busy(target): return world.reject(id, "雙方需同地點且不在交戰。")
			if not transferable(id, item, quantity) or price < 0 or price > 1000000: return world.reject(id, "數量、售價無效，或物品不可交易。")
			return request(id, target, "交易", {"item": item, "quantity": quantity, "price": price})
		"治療隊友":
			if not valid_target(id, target) or not target in members(id): return world.reject(id, "只能治療同地點的隊友。")
			if int(p.fight) != 0 and battles.get(int(p.fight), {}).get("kind", "") != "PVE": return world.reject(id, "玩家對戰期間不可援護。")
			var other: Dictionary = world.players[target]
			if int(other.fight) != 0 and battles.get(int(other.fight), {}).get("kind", "") != "PVE": return world.reject(id, "對方正在玩家對戰。")
			if int(p.inventory.get("金創藥", 0)) <= 0 or other.hp >= other.max_hp: return world.reject(id, "沒有金創藥，或隊友氣血已滿。")
			p.inventory["金創藥"] -= 1
			other.hp = mini(int(other.max_hp), int(other.hp) + 70)
			notify([id, target], "%s消耗一瓶金創藥，為%s療傷。" % [p.name, other.name], "隊伍")
		_: return false
	return true

static func clean_text(text: String) -> String:
	return text.replace("\n", " ").replace("\r", " ").strip_edges().left(220)

func join_party(id: int, inviter: int) -> bool:
	var p: Dictionary = world.players[id]
	var lead: Dictionary = world.players[inviter]
	if p.party != 0: return world.reject(id, "你已加入另一支隊伍。")
	if lead.party == 0:
		party_sequence += 1
		parties[party_sequence] = {"leader": inviter, "members": [inviter]}
		lead.party = party_sequence
	var party: Dictionary = parties[int(lead.party)]
	if int(party.leader) != inviter or party.members.size() >= LIMIT: return world.reject(id, "隊長已變更或隊伍已滿。")
	party.members.append(id)
	p.party = lead.party
	notify(party.members, "%s加入隊伍。共 %d/%d 人。" % [p.name, party.members.size(), LIMIT])
	return true

func leave_party(id: int) -> void:
	if not world.players.has(id): return
	var p: Dictionary = world.players[id]
	var party_id := int(p.party)
	p.party = 0
	p.follow = false
	if not parties.has(party_id): return
	var party: Dictionary = parties[party_id]
	party.members.erase(id)
	notify(party.members + [id], "%s離開隊伍。" % p.name)
	if party.members.size() <= 1:
		for member in party.members:
			world.players[member].party = 0
			world.players[member].follow = false
		parties.erase(party_id)
	elif int(party.leader) == id:
		party.leader = party.members[0]
		world.players[int(party.leader)].follow = false
		notify(party.members, "%s接任隊長。" % world.players[int(party.leader)].name)

func moved(id: int, origin: String) -> void:
	var p: Dictionary = world.players[id]
	if p.party == 0 or int(parties[int(p.party)].leader) != id: return
	for member in members(id):
		if member == id: continue
		var other: Dictionary = world.players[member]
		if other.follow and other.place == origin and not busy(member):
			other.place = p.place
			other.auto = "停止"
			if not other.visited.has(p.place): other.visited[p.place] = true; other.potential += 2
			world.tell(member, "你跟隨隊長來到%s。" % p.place, "隊伍")

func transferable(id: int, item: String, quantity: int) -> bool:
	if not world.Data.SHOP.has(item) or quantity < 1 or quantity > 999: return false
	if world.Data.SHOP[item].get("quest", false): return false
	var p: Dictionary = world.players[id]
	var owned := int(p.inventory.get(item, 0))
	return owned >= quantity and (not item in [p.weapon, p.armor] or owned > quantity)

func settle_trade(seller: int, buyer: int, offer: Dictionary) -> bool:
	if not transferable(seller, offer.item, int(offer.quantity)) or int(world.players[buyer].silver) < int(offer.price):
		return world.reject(buyer, "交易失敗：物品或銀兩已變動，沒有扣除任何資產。")
	var from: Dictionary = world.players[seller]
	var to: Dictionary = world.players[buyer]
	from.inventory[offer.item] -= int(offer.quantity)
	to.inventory[offer.item] = int(to.inventory.get(offer.item, 0)) + int(offer.quantity)
	to.silver -= int(offer.price)
	from.silver += int(offer.price)
	notify([seller, buyer], "交易完成：%s × %d，%d 兩。" % [offer.item, offer.quantity, offer.price], "交易")
	return true

func start_pvp(id: int, target: int, kind: String) -> bool:
	if not valid_target(id, target) or busy(id) or busy(target): return world.reject(id, "雙方需同地點且不在交戰。")
	var p: Dictionary = world.players[id]
	var q: Dictionary = world.players[target]
	if kind == "PK":
		if world.Data.PLACES[p.place].safe: return world.reject(id, "安全區禁止 PK；切磋仍可提出邀請。")
		if not p.pk_enabled or not q.pk_enabled: return world.reject(id, "雙方必須先開啟野外 PK。")
		if target in members(id): return world.reject(id, "不能 PK 同隊玩家，可先離隊或切磋。")
	if p.hp < 2 or q.hp < 2: return world.reject(id, "氣血不足，請先療傷。")
	battle_sequence += 1
	battles[battle_sequence] = {"kind": kind, "members": [id, target], "rounds": 0, "saved": {id: {"hp": p.hp, "mp": p.mp}, target: {"hp": q.hp, "mp": q.mp}}}
	for member in [id, target]:
		world.players[member].fight = battle_sequence
		world.players[member].auto = "停止"
	notify([id, target], "%s與%s開始%s。可改變策略、用藥或認輸。" % [p.name, q.name, kind], kind)
	return true

func finish_pvp(fight: int, loser: int, reason: String = "") -> void:
	if not battles.has(fight): return
	var b: Dictionary = battles[fight]
	var winner := 0
	for member in b.members:
		if member != loser and world.players.has(member): winner = member
	for member in b.members:
		if not world.players.has(member): continue
		var p: Dictionary = world.players[member]
		p.fight = 0
		p.auto = "停止"
		if b.kind == "切磋":
			p.hp = b.saved[member].hp
			p.mp = b.saved[member].mp
		else:
			p.hp = maxi(1, int(p.hp))
		if member == loser:
			p.pvp_losses += 1
			if b.kind == "PK":
				p.place = "揚州城"
				p.hp = maxi(1, int(p.max_hp) / 2)
				p.pk_enabled = false
		elif winner != 0: p.pvp_wins += 1
	notify(b.members, "%s結束：%s。%s" % [b.kind, (world.players[winner].name + "獲勝") if winner != 0 else "對手離線", reason], b.kind)
	battles.erase(fight)

func party_hunt(id: int, enemy: Dictionary) -> bool:
	var allies: Array = []
	for member in members(id):
		var p: Dictionary = world.players[member]
		if p.place == world.players[id].place and not busy(member) and int(p.hp) * 100 >= int(p.max_hp) * 25: allies.append(member)
	if allies.size() < 2: return false
	battle_sequence += 1
	var shared: Dictionary = enemy.duplicate(true)
	shared.hp = int(shared.hp * (1.0 + .5 * (allies.size() - 1)))
	shared.max_hp = shared.hp
	battles[battle_sequence] = {"kind": "PVE", "members": allies, "enemy": shared, "rounds": 0, "place": world.players[id].place, "participants": allies.size()}
	for member in allies:
		world.players[member].fight = battle_sequence
		world.players[member].enemy = shared
	notify(allies, "隊伍共同迎戰%s！氣血 %d，勝利後平分獎勵。" % [shared.name, shared.hp], "戰鬥")
	return true

func flee(id: int) -> bool:
	var fight := int(world.players[id].fight)
	if fight == 0 or not battles.has(fight): return false
	var b: Dictionary = battles[fight]
	if b.kind != "PVE": finish_pvp(fight, id, "一方認輸或逃離。"); return true
	b.members.erase(id)
	world.players[id].enemy = {}
	world.players[id].fight = 0
	world.players[id].auto = "停止"
	world.players[id].hp = maxi(1, int(world.players[id].hp) - 12)
	notify(b.members + [id], "%s離開戰鬥，未取得本場獎勵。" % world.players[id].name, "戰鬥")
	if b.members.is_empty(): battles.erase(fight)
	return true

func disconnect_peer(id: int) -> void:
	if not world.players.has(id): return
	if world.players[id].fight != 0: flee(id)
	leave_party(id)
	for key in requests.keys():
		if requests[key].from == id or requests[key].to == id: requests.erase(key)

func step() -> void:
	for key in requests.keys():
		if int(requests[key].expires) <= world.tick:
			notify([requests[key].from, requests[key].to], "邀請已逾時。", "人際")
			requests.erase(key)
	for key in battles.keys():
		if not battles.has(key): continue
		var b: Dictionary = battles[key]
		b.rounds += 1
		if b.kind == "PVE": pve_round(key); continue
		if b.rounds > 120:
			finish_pvp(key, int(b.members[1]), "對戰超過 120 息，按先手判定結束。")
			continue
		# 先手逐回合交換，避免永遠由房主先攻。
		var order: Array = b.members.duplicate()
		if b.rounds % 2 == 0: order.reverse()
		for attacker in order:
			var defender: int = b.members[1] if attacker == b.members[0] else b.members[0]
			var p: Dictionary = world.players[attacker]
			var q: Dictionary = world.players[defender]
			var damage: int = world.roll_damage(p, world.defense(q))
			if q.stance == "防守": damage = maxi(1, int(damage * .45))
			q.hp = maxi(0, int(q.hp) - damage)
			notify(b.members, "%s以%s攻擊%s，造成 %d 傷害。" % [p.name, world.active_art(p), q.name, damage], b.kind)
			if q.hp <= 0: finish_pvp(key, defender); break

func pve_round(fight: int) -> void:
	var b: Dictionary = battles[fight]
	var e: Dictionary = b.enemy
	for id in b.members.duplicate():
		var p: Dictionary = world.players[id]
		var damage: int = world.roll_damage(p, int(e.defense))
		e.hp = maxi(0, int(e.hp) - damage)
		notify(b.members, "%s以%s對%s造成 %d 傷害（%d/%d）。" % [p.name, world.active_art(p), e.name, damage, e.hp, e.max_hp], "戰鬥")
		if e.hp <= 0:
			var survivors: Array = b.members.duplicate()
			var reward: Dictionary = e.duplicate(true)
			for stat in ["exp", "potential", "silver"]: reward[stat] = maxi(1, int(e[stat]) / int(b.participants))
			# 掉落只擲一次，指定一名存活隊友獲得，防止每人複製掉落。
			var loot_owner: int = survivors[world.rng.randi_range(0, survivors.size() - 1)]
			for member in survivors:
				world.players[member].fight = 0
				world.victory(member, reward, member == loot_owner)
			battles.erase(fight)
			return
	if b.members.is_empty(): battles.erase(fight); return
	var target: int = b.members[world.rng.randi_range(0, b.members.size() - 1)]
	var defender: Dictionary = world.players[target]
	var hurt := maxi(1, int(e.attack) - int(world.defense(defender)))
	if defender.stance == "防守": hurt = maxi(1, int(hurt * .45))
	defender.hp = maxi(0, int(defender.hp) - hurt)
	notify(b.members, "%s反擊%s，造成 %d 傷害。" % [e.name, defender.name, hurt], "戰鬥")
	if defender.hp == 0:
		b.members.erase(target)
		world.defeat(target)
		if b.members.is_empty(): battles.erase(fight)

func snapshot(id: int) -> Dictionary:
	var party: Dictionary = parties.get(int(world.players[id].party), {}).duplicate(true)
	var pending: Array = []
	for r in requests.values():
		if int(r.to) == id: pending.append(r.duplicate(true))
	var battle: Dictionary = battles.get(int(world.players[id].fight), {}).duplicate(true)
	return {"party": party, "requests": pending, "battle": battle}
