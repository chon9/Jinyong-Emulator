extends RefCounted
## Regional journeys share party builds and saves with the Qingxi story.
const RECRUITS := {"牛家村":"blade","襄陽城":"palm","無錫城":"doctor","武當派":"taoist","少林派":"monk","華山派":"wanderer"}
const POWER := {"嘉興鎮":1,"牛家村":1,"東渡口":2,"無錫城":3,"襄陽城":4,"衡山城":6,"福州城":7,"少林派":8,"武當派":9,"華山派":10,"長安城":12,"全真教":14,"大理城":16,"峨嵋派":18,"西夏城":20,"龍門":22}
const FOES := {
	"牛家村":["糧道匪首","攔糧刀手","枯井暗哨"],"東渡口":["水匪頭目","斷纜刀客","霧中伏兵"],
	"無錫城":["換箱管事","碼頭打手","藏賬毒客"],"襄陽城":["伏路頭領","黑甲刀手","奪信客"],
	"衡山城":["斷弦客","追音劍客","藏弦毒手"],"福州城":["毀旗刀客","劫鏢護衛","追證密探"],
	"少林派":["護院首座","持戒僧","試陣僧"],"武當派":["松風教習","守靜道人","玄機劍客"],
	"華山派":["問劍客","守崖劍士","飛羽劍客"],"長安城":["長街刀首","夜行護衛","熄燈客"],
	"全真教":["守觀教習","持劍道士","問心道人"],"大理城":["商道寨主","山茶刀客","扣信毒客"],
	"峨嵋派":["雲海師太","護山弟子","清風劍客"],"西夏城":["沙盜首領","奪水刀手","蠍砂客"],
	"龍門":["關外刀王","斷刀追客","雪夜毒師"]
}
const NPC_SPRITES := {"嘉興鎮":"companion","牛家村":"blade","東渡口":"healer","無錫城":"healer","襄陽城":"elder","衡山城":"elder","福州城":"companion","少林派":"staff","武當派":"taoist","華山派":"wanderer","長安城":"rogue","全真教":"taoist","大理城":"healer","峨嵋派":"healer","西夏城":"blade","龍門":"boss"}
const REGIONS := {
	"嘉興鎮":{"point":Vector2(435,299),"stage":0,"tier":0,"title":"青溪 · 水鄉故人","text":"嘉興城外的青溪鎮，斷鏢與藥箱牽起四人的命運。","npc":"顧長風","rumor":"客棧、渡口、藥廬和演武坪，都在青溪的街道上。"},
	"牛家村":{"point":Vector2(547,296),"stage":1,"tier":0,"title":"支線 · 井畔藏鏢","text":"井畔的燕行舟撿起浸透的鏢單：糧車若不能送達，全村都要挨餓。","npc":"燕行舟","rumor":"山道有人盯上送糧的車，車夫只敢在天亮後出發。"},
	"東渡口":{"point":Vector2(613,324),"stage":2,"tier":0,"title":"支線 · 不渡之舟","text":"渡船停了三日。船家說，有人趁霧把航標全換了位置。","npc":"渡船娘","rumor":"霧裡藏著兩名水匪，先制住快刀，船家才能重新點燈。"},
	"無錫城":{"point":Vector2(474,256),"stage":3,"tier":1,"title":"支線 · 空箱換藥","text":"溫梨剛卸下進城的藥材，卻發現箱裡空空如也。她求你一起找回救命藥。","npc":"溫梨","rumor":"找回藏在碼頭的賬簿，藥鋪才能追回被換走的藥材。"},
	"襄陽城":{"point":Vector2(330,252),"stage":3,"tier":1,"title":"支線 · 城下急信","text":"裴照守著城門，請你護住送信人。信上的血，是他失散弟子的。","npc":"裴照","rumor":"伏兵守著入城路；守住前排，留真元救回送信人。"},
	"衡山城":{"point":Vector2(357,375),"stage":4,"tier":1,"title":"支線 · 琴弦有聲","text":"山間琴聲夜夜只彈半曲，斷弦裡藏著失蹤弟子的求救。","npc":"修琴老人","rumor":"攔路人擅長毒砂，帶上能解毒的同伴再進山。"},
	"福州城":{"point":Vector2(562,439),"stage":4,"tier":1,"title":"支線 · 鏢旗重立","text":"鏢旗被扯下後，年輕鏢師仍守在空院，等一個能作證的人。","npc":"年輕鏢師","rumor":"先破護衛，再逼退領頭的刀客，才能護住證人。"},
	"少林派":{"point":Vector2(325,180),"stage":5,"tier":2,"title":"切磋 · 山門護陣","text":"護院僧明照邀你試陣：若能守住同伴，他願離開山門，隨你護更多人。","npc":"明照","rumor":"蓄力的棍勢須及時打斷，單憑猛攻難以闖過山門。"},
	"武當派":{"point":Vector2(207,300),"stage":5,"tier":2,"title":"切磋 · 松風試劍","text":"宋知白在松下候客，說一場試劍便能看出彼此是否值得同行。","npc":"宋知白","rumor":"調整出手次序，破甲後再讓劍客追擊。"},
	"華山派":{"point":Vector2(224,207),"stage":5,"tier":2,"title":"切磋 · 崖邊問劍","text":"葉停雲以木劍迎客。若你接得下這一劍，他便隨你去看青溪故事外的江湖。","npc":"葉停雲","rumor":"快劍會直取後排；先護陣，再找出反擊的空隙。"},
	"長安城":{"point":Vector2(227,140),"stage":6,"tier":2,"title":"支線 · 長街燈影","text":"花燈熄滅的瞬間，一枚舊鏢釘進了茶樓的柱子。","npc":"茶樓掌櫃","rumor":"失鏢舊案的另一條線，藏在領頭人隨身的信箋裡。"},
	"全真教":{"point":Vector2(143,257),"stage":6,"tier":2,"title":"切磋 · 古觀鐘聲","text":"古觀晨課後，年輕道士邀你演練一場守中帶攻的陣法。","npc":"守觀道士","rumor":"別把真元全用在第一輪；留一手應對第二輪的蓄勢。"},
	"大理城":{"point":Vector2(116,378),"stage":7,"tier":2,"title":"支線 · 山茶舊約","text":"賣花人守著一盆枯山茶，等那個帶著家書出門的人回來。","npc":"賣花人","rumor":"商道盡頭的寨中扣著送信人，護送他回來便能續上舊約。"},
	"峨嵋派":{"point":Vector2(49,309),"stage":7,"tier":2,"title":"切磋 · 雲海問心","text":"雲海前的師太說，救人與破敵，從來是同一門修行。","npc":"雲海師太","rumor":"帶好解毒與療傷，守勢能替你爭取調息的一輪。"},
	"西夏城":{"point":Vector2(27,137),"stage":7,"tier":2,"title":"支線 · 沙中水囊","text":"風沙埋了舊路，商隊最後一個水囊卻掛在陌生人的馬上。","npc":"商隊領路人","rumor":"護住商隊，擊退截路首領，就能沿著星光走出風沙。"},
	"龍門":{"point":Vector2(247,58),"stage":7,"tier":2,"title":"支線 · 關外歸客","text":"客棧外，歸客抱著一柄斷刀，說欠了江南一個永遠還不清的人情。","npc":"關外歸客","rumor":"替他攔下追兵，那封帶不回家的信，便有人願意接過。"}
}

static func ensure(campaign) -> Dictionary:
	if not campaign.state.has("atlas"): campaign.state.atlas = {"region":"嘉興鎮","visited":["嘉興鎮"],"cleared":[]}
	return campaign.state.atlas

static func visit(campaign, region: String) -> String:
	var data := ensure(campaign)
	if not REGIONS.has(region) or campaign.state.stage < REGIONS[region].stage: return "先完成青溪主線，取得這條路上的人脈與線索。"
	data.region = region
	if not region in data.visited:
		data.visited.append(region)
		campaign.record("初到%s。%s" % [region,REGIONS[region].text])
	return "抵達%s。%s" % [region,REGIONS[region].text]

static func resolve(campaign) -> String:
	var data := ensure(campaign)
	if data.region in data.cleared: return "切磋告捷，得到戰利品。"
	data.cleared.append(data.region)
	campaign.state.silver += 45
	campaign.state.potential += 30
	campaign.state.inventory["金創藥"] = mini(9999,int(campaign.state.inventory.get("金創藥",0))+1)
	var text: String = "%s完成：線索交還%s。額外獲得 45 銀、30 學點、金創藥一瓶。" % [REGIONS[data.region].title,REGIONS[data.region].npc]
	if RECRUITS.has(data.region):
		var id: String = RECRUITS[data.region]
		campaign.recruit(id)
		text += " %s願意同行；可在同伴頁換入隊伍，並研習其武學傳承。" % campaign.HEROES[id].name
	campaign.record(text)
	return text
