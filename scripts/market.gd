extends RefCounted
## Shared quotes keep the shop's buttons and host validation in agreement.
const Data = preload("res://scripts/content.gd")

static func stock(place: String) -> Array:
	var items: Array = Data.SHOP.keys() if place == "揚州城" else Data.PLACES.get(place, {}).get("shop", []).duplicate()
	return items.filter(func(item): return Data.SHOP.has(item) and not Data.SHOP[item].get("quest", false))

static func has_shop(place: String) -> bool:
	return not stock(place).is_empty()

static func sale_limit(p: Dictionary, item: String) -> int:
	var count := int(p.inventory.get(item, 0))
	if item in [p.weapon, p.armor]: count -= 1
	return maxi(0, count)

static func quote(p: Dictionary, selling: bool, item: String, quantity: int = 1) -> Dictionary:
	var definition: Dictionary = Data.SHOP.get(item, {})
	var unit := maxi(1, int(definition.get("price", 1)) / 3) if selling else maxi(1, int(definition.get("price", 1)))
	var error := ""
	if not p.enemy.is_empty() or int(p.fight) != 0: error = "交戰中無法買賣，請先結束戰鬥。"
	elif not has_shop(p.place): error = "此地沒有商人。請選擇下方商店，自動前往。"
	elif definition.is_empty(): error = "找不到這件物品。"
	elif quantity < 1 or quantity > 99: error = "每次交易數量須為 1–99。"
	elif definition.get("quest", false): error = "任務信物不可買賣。"
	elif selling:
		if not definition.get("sellable", false): error = "這件物品不可出售。"
		elif int(p.inventory.get(item, 0)) < quantity: error = "行囊中的數量不足。"
		elif sale_limit(p, item) < quantity: error = "須保留身上正在裝備的一件；先卸下才能出售。"
	elif not item in stock(p.place): error = "當地商店沒有販售這件物品。"
	elif int(p.silver) < unit * quantity: error = "銀兩不足：需要 %d 兩，還差 %d 兩。" % [unit * quantity, unit * quantity - int(p.silver)]
	return {"ok": error == "", "error": error, "unit": unit, "total": unit * quantity}

static func transact(world, id: int, selling: bool, argument: String) -> bool:
	var parts := argument.split("|", true)
	if parts.size() < 1 or parts.size() > 2 or (parts.size() == 2 and not parts[1].is_valid_int()): return world.reject(id, "請選擇物品與有效的交易數量。")
	var item: String = parts[0]
	var quantity := int(parts[1]) if parts.size() == 2 else 1
	var p: Dictionary = world.players[id]
	var offer := quote(p, selling, item, quantity)
	if not offer.ok: return world.reject(id, offer.error)
	p.inventory[item] = int(p.inventory.get(item, 0)) + (-quantity if selling else quantity)
	p.silver += int(offer.total) * (1 if selling else -1)
	world.tell(id, "%s%s × %d，%s %d 兩。" % ["售出" if selling else "購得", item, quantity, "獲得" if selling else "花費", offer.total], "行囊")
	return true

static func shops_near(place: String, query: String = "") -> Array:
	var found: Array = []
	for destination in Data.PLACES:
		var goods := stock(destination)
		if goods.is_empty(): continue
		if query != "" and not query in destination and not goods.any(func(item): return query in item): continue
		var route: Array = Data.path_to(place, destination)
		if destination != place and route.is_empty(): continue
		found.append({"place": destination, "steps": route.size(), "stock": goods})
	found.sort_custom(func(a, b): return a.steps < b.steps if a.steps != b.steps else a.place < b.place)
	return found
