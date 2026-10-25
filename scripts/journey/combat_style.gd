extends RefCounted
## Stable semantic art/audio cues; battle rules do not depend on presentation.
static var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/combat_fx.json"))
const WEAPONS={"月牙鏟":"staff","轉輪":"blade","鏈鞭":"snake","刀":"blade","劍":"sword","棍":"staff","拳掌":"palm","雙劍":"twin","雙匕":"blade","匕":"blade","鉤":"blade","雙鉤":"blade","月刃":"blade","雙刃":"blade","關刀":"iron","錘":"iron","戟":"staff","槍":"staff","魚叉":"staff","船槳":"staff","鎖鏈":"snake","三叉戟":"staff","長兵":"staff","拂塵":"music","杖":"staff","法鼓":"music","琴":"music","扇":"music","鐵筆":"finger","書卷":"reflect","藥杖":"herbal","銀針":"finger","飛鏢":"finger","毒掌":"venom","弓":"finger","弩":"finger","盾":"guard","爪牙":"palm","獠牙":"palm","爪喙":"palm","纏咬":"snake","尾螫":"venom","釣竿":"staff","鐵鍋":"iron"}

static func key_for(unit: Dictionary,event: Dictionary) -> String:
	var kind: String=event.get("kind","")
	if kind in ["charge","guard","dot"]:return kind
	if kind=="stun" and event.get("actor","")==event.get("target",""):return "sealed"
	var skill: String=event.get("skill","")
	if data.skills.has(skill):return data.skills[skill]
	if kind=="poison":return "venom"
	if kind=="heal":return "herbal"
	if kind=="boss_hit":return "iron"
	return WEAPONS.get(unit.get("weapon","拳掌"),"palm")

static func profile(unit: Dictionary,event: Dictionary) -> Dictionary:
	var key:=key_for(unit,event)
	var value: Dictionary=data.styles[key].duplicate()
	value.key=key
	if unit.get("weapon","") in ["弓","弩"] and event.get("kind","")=="attack":
		value.shape="arrow"
		value.texture="wind"
		value.scale=.7
	return value

static func states(unit: Dictionary) -> Array:
	var result:=[]
	if unit.get("guarding",false):result.append({"key":"guard","glyph":"盾","name":"守勢：減傷60%，援護後排","turns":1,"color":"528491"})
	if unit.get("charging",false):result.append({"key":"charge","glyph":"蓄","name":"蓄力：下一次重擊，可被封招打斷","turns":1,"color":"ba7738"})
	for entry in [["poison","毒","中毒：行動時損失25氣血","6c568f"],["bleed","血","流血：行動時損失20氣血","9e5151"],["broken","破","破甲：防禦減半","9d7750"],["stun","封","封招：失去行動並打斷蓄力","6d6897"]]:
		if int(unit.get(entry[0],0))>0:result.append({"key":entry[0],"glyph":entry[1],"name":entry[2],"turns":int(unit[entry[0]]),"color":entry[3]})
	return result
