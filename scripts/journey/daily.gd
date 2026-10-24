extends RefCounted
## UTC+8 civil days. Backward clock changes cannot create an extra reset.
const TASKS := {
	"sect":{"name":"師門奔走","limit":3,"place":"演武坪","reward":"每封信：15 銀、12 學點、10 貢獻","desc":"向師父領信，走訪客棧、藥廬與古寺。師門貢獻可換修行資糧。"},
	"work":{"name":"藥廬打工","limit":2,"place":"藥廬","reward":"每爐：30 銀、15 學點","desc":"帶一株草藥協助煮藥，守爐六秒後領工錢。"},
	"escort":{"name":"鏢局運送","limit":2,"place":"青溪客棧","reward":"每趟：50 銀、20 學點","desc":"在客棧接鏢，經演武坪驗貨，再送往渡口，沿途護貨。"},
	"training":{"name":"武館指點","limit":3,"place":"演武坪","reward":"每勝：額外 15 學點","desc":"與演武教頭切磋，試驗前後排、調息和真元運用。"},
	"gather":{"name":"江岸採藥","limit":5,"place":"蘆葦蕩","reward":"每株：草藥；每日前五株另得 3 學點","desc":"採來的草藥可供打工、救急藥方或出售。"},
	"dungeon":{"name":"舊倉試煉","limit":2,"place":"舊倉","reward":"每勝：額外 20 銀、20 學點","desc":"破獲失鏢案後重戰寨主，留意蓄力與毒砂。"}
}

static func day_at(timestamp: float) -> int:
	return int(floor((timestamp+28800)/86400))

static func ensure(campaign, timestamp: float = -1) -> Dictionary:
	var day := day_at(Time.get_unix_time_from_system() if timestamp < 0 else timestamp)
	var data: Dictionary = campaign.state.get("daily",{})
	if data.is_empty() or day > int(data.get("day",0)):
		data = {"day":day,"counts":{},"errand":"","escort":0}
		campaign.state.daily = data
	return data

static func count(campaign, key: String) -> int:
	return int(ensure(campaign).counts.get(key,0))

static func available(campaign, key: String) -> bool:
	return TASKS.has(key) and count(campaign,key) < int(TASKS[key].limit)

static func target(campaign, key: String) -> String:
	var data := ensure(campaign)
	if key == "sect" and data.errand != "": return data.errand
	if key == "escort" and data.escort > 0: return "演武坪" if data.escort == 1 else "渡口"
	return TASKS[key].place

static func complete(campaign, key: String, silver: int, potential: int) -> bool:
	if not available(campaign,key): return false
	var data := ensure(campaign)
	data.counts[key] = count(campaign,key)+1
	campaign.state.silver += silver
	campaign.state.potential += potential
	return true
