"""Original open-world content and an explicit Flash JY3 coverage ledger."""
import json
from open_world_details import enrich
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REGIONS={
'嘉興鎮':['青溪客棧','渡口','藥廬','蘆葦蕩','古寺','市集','演武坪','舊倉','茶肆','驛站'],
'牛家村':['村口','牛家客棧','破廟','河邊','樹林','馮家鐵鋪'],
'東渡口':['渡船','漁棚','蘆灣','歸雲莊','神龍島','俠客島'],
'無錫城':['街市','藥王莊','梅莊','還施水閣','碼頭','茶樓'],
'襄陽城':['城門','軍營','酒樓','絕情谷','古道','烽火臺'],
'衡山城':['山亭','鏢局','琴坊','衡山書院','古井','林間'],
'福州城':['福威鏢局','林家老宅','茶肆','山道','小巷','渡亭'],
'少林派':['山門','羅漢堂','藏經閣','廚房','銅人巷','後山'],
'武當派':['紫霄宮','演武場','丹房','松林','解劍池','太和殿'],
'華山派':['玉女峰','思過崖','後山木屋','正氣堂','膳堂','山腳'],
'長安城':['聚賢莊','京城','御膳房','莊府','商行','城外'],
'全真教':['重陽宮','古墓','後山','碑林','演武臺','密道'],
'大理城':['無量山洞','天龍寺','客舍','蝴蝶谷','苗人鳳居','胡斐居'],
'峨嵋派':['金頂','客舍','演武場','清音閣','藥圃','山門'],
'西夏城':['王府','集市','雪谷','擂鼓山','回部營地','冰谷'],
'龍門':['塞外','客棧','石窟','荒野','沙井','關隘']}
# name, region, scene, weapon, art, effect, own encounter premise
ROWS=[
('郭靖','襄陽城','城門','拳掌','降龍十八掌','cleave','城下糧車比城上旗幟更重要。我想先把老百姓平安送過橋。'),
('黃蓉','牛家村','牛家客棧','棍','打狗棒法','break','桌上的菜被人調了鹽，送菜的小孩卻被說成偷錢賊。我想聽聽他的說法。'),
('楊過','襄陽城','絕情谷','劍','玄鐵劍法','heavy','斷橋旁的刻字不是求救，是一個不願失約的人留給同伴的路標。'),
('小龍女','全真教','古墓','劍','玉女素心劍','pierce','蜂群忽然不肯回巢。外面的世界若有變故，也不該先傷這些小生命。'),
('張無忌','大理城','蝴蝶谷','拳掌','乾坤大挪移','break','兩派弟子都說對方下毒，藥碗裡卻只有治傷的藥。我願先替兩邊看診。'),
('令狐沖','華山派','思過崖','劍','獨孤九劍','pierce','山下送來一壺酒，壺底卻夾著一張討債單。這杯酒，我不能白喝。'),
('任盈盈','無錫城','梅莊','劍','清音劍訣','stun','琴弦少了一根，送信人便失約一日。我想知道他是失信，還是失去了回來的路。'),
('段譽','大理城','無量山洞','拳掌','六脈神劍','pierce','石壁上的路線或許不是武功，是避開山洪的舊道。我們去問問山民。'),
('喬峰','龍門','塞外','拳掌','降龍廿八掌','cleave','關外有人用我的名號趕走牧民。若只問勝負，不問緣由，便又多一筆冤帳。'),
('虛竹','少林派','山門','拳掌','天山折梅手','stun','我不懂高深的道理，只知道雨夜裡的病人不能一直等在山門外。'),
('胡斐','大理城','胡斐居','刀','胡家刀法','bleed','一封缺角的信把故人引向山道。我不肯只憑一個姓氏判定誰該還債。'),
('程靈素','無錫城','藥王莊','拳掌','七心海棠訣','heal','解藥原料不算珍貴，難的是讓兩個互不信任的人各交出半張藥方。'),
('王語嫣','無錫城','還施水閣','拳掌','百家辨招','break','兩份劍譜的錯字一模一樣。有人故意留下破綻，等著讀書的人替他背鍋。'),
('周芷若','峨嵋派','金頂','劍','峨嵋劍法','bleed','借出去的劍沒有回來，帶回來的卻是一群受傷的山民。我想親自查明。'),
('韋小寶','長安城','京城','刀','神行匕法','pierce','我這回真沒拿他的銀票！要不你陪我去找開票的人，大家把話說清楚。'),
('雙兒','長安城','莊府','拳掌','點穴手','stun','失散的人各留下一半繡樣。若能把兩半送到同一張桌上，也許還來得及。'),
('林平之','福州城','林家老宅','劍','辟邪劍法','pierce','舊宅的門被人換了鎖。我要找回的不是財物，是那本記著故人姓名的帳冊。'),
('岳靈珊','華山派','玉女峰','劍','玉女十九劍','stun','送藥的師弟跌傷了腳。我既然答應陪他下山，就不該讓他一個人扛著。'),
('郭襄','襄陽城','酒樓','劍','峨嵋初祖劍','pierce','我收下三封陌生人的謝信，才發現他們謝的是同一位不留姓名的旅人。'),
('阿九','長安城','城外','劍','鐵劍門劍法','break','旗幟能換，車裡的人不能丟。這一趟我只護送難民，不替誰爭天下。'),
('袁承志','華山派','後山木屋','劍','金蛇劍法','bleed','鐵匠說那柄怪劍是凶器，持劍人卻拿它撬開了困住工人的石門。'),
('香香公主','西夏城','回部營地','拳掌','清心回元','heal','部落的經卷丟失後，兩隊商旅彼此猜疑。先找到那位受傷的馱夫吧。'),
('公孫綠萼','襄陽城','絕情谷','劍','柔絲劍法','stun','谷中草木都認得路，迷路的卻總是人。我留下的藥包，只想有人能帶出去。'),
('穆念慈','牛家村','村口','棍','楊家槍法','break','擂臺不是賣人的地方。我想用贏來的盤纏，把流落街頭的孩子送回家。'),
('游坦之','衡山城','林間','拳掌','冰蠶寒掌','poison','我戴著面具，不想再被人認出。但那個被困在林子裡的人，總得有人去救。'),
('慕容復','無錫城','還施水閣','劍','斗轉星移','break','有人仿造家傳印信招攬死士。我不喜歡受人擺佈，更不容別人借我的名字。'),
('蘇荃','東渡口','神龍島','拳掌','神龍掌法','stun','島上的人習慣了聽令。我想讓他們第一次自己選擇，留在此地還是乘船離開。'),
('阿紫','西夏城','冰谷','拳掌','星宿毒術','poison','我說過瓶裡的是毒，偏有人不信。先把人救回來，帳可以慢慢再算。'),
('狄雲','龍門','石窟','刀','血刀刀法','bleed','他們說穿破衣的人最會撒謊。我只想帶你去看看，雪裡究竟埋著誰的行囊。'),
('歐陽克','西夏城','集市','拳掌','白駝雪山掌','poison','商隊把失蹤的貨都算到我頭上。先查清那枚足印，再來談我是否值得信任。'),
('田伯光','衡山城','山亭','刀','狂風快刀','heavy','有人在山路冒我的名攔客。我的名聲本來就不好，卻也不願替人擔這筆帳。'),
('霍都','龍門','關隘','棍','鐵扇功','break','這份通關文書上的印章是假的。若只憑拳頭過關，商隊明日仍得受人勒索。'),
('西夏公主','西夏城','王府','拳掌','夢回拂穴','heal','王府的藥房可以救很多人，卻偏偏進不了一個牧童。我想讓規矩改一改。'),
('半瓶神仙醋','長安城','聚賢莊','拳掌','江湖百味','cleave','我收故事，不收過路費。你遇見的人越多，這壇半滿的醋便越有滋味。'),
('黃藥師','東渡口','歸雲莊','劍','玉簫劍法','stun','殘曲故意少了一拍。知音若只依譜行事，便永遠聽不出那聲求援。'),
('洪七公','牛家村','河邊','棍','天下無狗','cleave','這鍋粥少了一把米，多了幾滴眼淚。誰偷走的賑糧，就讓誰自己背回來。'),
('周伯通','全真教','後山','拳掌','空明拳','stun','我畫的箭頭明明指左，他們卻都向右走。你陪我去看看，是不是有人改了路牌？'),
('一燈大師','大理城','天龍寺','拳掌','一陽指','heal','有人求我判誰對誰錯。若能先放下刀，或許兩個人都還有說完故事的機會。'),
('趙敏','武當派','解劍池','劍','倚天截劍','break','假使每一封信都是真的，這世上便不需要查案的人。先看落款，再看送信的人。'),
('水笙','龍門','客棧','劍','連城雪劍','pierce','雪地留下的腳印到了石橋便消失。我不願再把沒有回來的人，輕易當成逃走。'),
('儀琳','衡山城','山亭','拳掌','慈航渡厄','heal','若人人都只救自己認識的人，那些孤身上路的傷者，又能向誰求助呢？')]
ENEMY_NAMES=[
'斷橋刀匪 笠下短刃 赤巾女盜 獨眼鐵錘 纜鉤老賊 山口槍匪 九環劫客 青衣掏手 狼裘寨首 黑巾弩哨',
'蘆衣漁寇 藍巾船娘 刺青棹手 白鬚魚叉 赤衫鎖客 綠衣船弓 墨鬚海首 灰蓑雙鉤 紫巾鹽梟 靛衣三叉',
'銅盔槍衛 藍甲斥候 灰甲旗官 北地騎衛 白甲禁劍 綠營弩長 金盔鐵盾 墨甲獄吏 赤衣傳騎 紫甲女將',
'白衣山劍 赤袍雙劍 碧袍劍姑 黑蓑細劍 藍袍劍師 盲眼雙鋒 錦衣劍嗣 灰笠左劍 紫衫毒劍 青面劍衛',
'黃衣棍僧 橙袍月鏟 白鬚拂塵 素衣女冠 墨衣苦行 綠袍山隱 紅衣法鼓 紫衣劍尼 灰衣銅棍 枯木野僧',
'赤影雙刃 銀髮霜劍 碧衣獵弓 墨綢毒姥 素衣雙鉤 金紗月刃 紅甲女衛 紫巾飛鏢 青衣針師 黑白夜行',
'西域鐵盾 金袍轉輪 沙漠彎刀 藍裘異劍 蒙地摔手 雪帽雙匕 綠纏沙弓 赤日掌師 靛紗鏈鞭 黑銅戰戟',
'曲背釣叟 盲眼琴客 笑面鐵鍋 黃衫茶扇 長鬚鐵筆 紅鼻醉棍 白髮藥杖 墨衣抬棺 鑄鐵老匠 銀髮說書',
'斑額山虎 北林棕熊 寒原灰狼 黑牙野豕 神雕 山澤巨鱷 金環巨蟒 金斑獵豹 蒼山巨猿 赤甲毒蠍',
'玄袍掌尊 赤劍女宗 白裘刀王 銅身杖尊 玉面琴魔 紫袍毒祖 銀槍女師 赤金關刀 墨袍孤劍 碧衣扇尊']
FLASH_TITLES='四十二章經的秘密|闖王寶藏的秘密|唐詩選輯的秘密|落花流水鬥血刀僧|華山論劍|救治青翼蝠王|歸雲莊英雄大會|王語嫣的悲哀|放蕩形骸的浪子|絕情谷婚宴|悲情楊過|獨孤求敗的寵物|昔日皇妃|韋小寶性命危矣|莊家的復仇|魔教聖姑|死守襄陽|神雕俠的三件禮物|四個江湖惡客|田歸農的挑戰|回部的聖物|群寇爭鏢銀|老尼姑的險境|峨嵋派替天行道|西夏招親|救治盲女|青城派的仇怨|東郭狼子心|全真與桃花島的恩怨|桃花島主的名聲|崑崙冰蠶|毒王之爭|天王老子傲四方|御廚的無奈|臘八粥|迷途小和尚|擂鼓山棋局|鏢車被劫|爪下白骨|阮姓無辜做冤魂|丐幫與星宿惡鬥|少林與武當惡鬥：調停|少林與武當惡鬥：護送|官逼民受苦|神秘商人'.split('|')
FLASH_REGIONS=['長安城','大理城','龍門','龍門','華山派','西夏城','東渡口','無錫城','華山派','襄陽城','襄陽城','全真教','大理城','長安城','長安城','無錫城','襄陽城','襄陽城','衡山城','大理城','西夏城','福州城','衡山城','峨嵋派','西夏城','西夏城','福州城','大理城','全真教','東渡口','西夏城','龍門','無錫城','長安城','東渡口','少林派','西夏城','福州城','全真教','衡山城','無錫城','武當派','少林派','長安城','牛家村']
PREMISES=[
'散落的經卷頁角印著不同商號的記號，聚賢莊請你沿路找齊線索，查出經箱失落的去向。',
'舊藏寶圖被分成兩份，兩個保管人都認為對方背約。先核對圖上的山川，再決定寶物如何分配。',
'詩集的頁碼與驛站的貨號相合，詩中的秘密牽涉一筆多年未送達的賑糧。',
'風雪困住一行旅人，衣衫破舊的刀客被指為兇手。留下活口問清楚，或許比立即拔刀更難。',
'山頂有三位不問門戶的武人設下試場。每一關都可暫退，磨練之後再來。',
'病人畏寒卻不肯說出身分，雪地裡的毒物只是病因的一半，另一半藏在被換掉的藥方裡。',
'英雄會的請帖被人拿去收取過橋費。會場要的不是更多掌聲，而是一個能護住路人的人。',
'王語嫣認出劍譜裡一處故意寫錯的註釋。她想知道是誰借復國之名，讓年輕弟子去送命。',
'醉客留下一張付清的酒單，賣酒人卻說從未收到錢。兩人的往來藏著一份不肯明說的相助。',
'婚宴的採辦箱中藏著求援紙條，谷中的路被封住了。你可以幫人離谷，也可以查清封路的理由。',
'傷者不願接受陌生人的施捨，藥草與一封故人的短信，也許能讓他願意留下來。',
'大雕守著洞口不讓人接近。山民說牠在護巢，劍客卻認為牠在守護一份不願被人打擾的傳承。',
'兩位老人各持一張舊信，信紙的折痕恰能相合。他們需要的或許只是一個肯把信送完的人。',
'追兵追著一個小人物，銀票的號碼卻指向另一樁案子。別讓他還沒說完話便被押走。',
'莊府的倖存者想要討回公道，卻有人想借他們的憤怒再奪一次家產。請把證人安全帶到。',
'一曲未彈完的琴聲，牽著一份未能送出的名冊。先找回送信人，再談江湖門戶。',
'敵騎尚未來到，糧道先被切斷。守城者想請你護住一支載著傷員的車隊。',
'三份禮物分別送給無名的人：受傷的斥候、缺糧的村落，以及不願再戰的老兵。',
'四名惡客各執一詞，旁人的遭遇卻無人過問。你可以出手制止，也可以先替受害者找回行囊。',
'挑戰書送到時，刀客正在替人修屋。他願赴約，但請你先確認這場比武不是另一個圈套。',
'經卷被帶離營地，兩支商隊互相指責。循著駝鈴與藥包，還有機會找到真正的保管人。',
'鏢箱裡裝的不是銀兩，而是一座村子熬過冬天的藥錢。幾方都說自己才是貨主。',
'年老的師太護著避難弟子，山路卻被惡客截斷。先送傷者離開，再談比武。',
'有人假借峨嵋名號四處討債，山門與客舍各有一份說法。請你核實兩邊的證詞。',
'招親大會成了江湖人的擂臺，王府卻想借人潮尋找一名走失的牧童。你想先幫哪一邊？',
'看不見的人分辨得出草藥的味道，卻被假藥耽誤了病情。找回原藥，再請她自己決定去處。',
'四封匿名信都指向同一個山門。是世仇，還是有人故意讓兩家再也不能坐下說話？',
'求醫者把病情說得很重，隨行人卻連藥都不讓他碰。先見到病人本人再下判斷。',
'道觀與海島各失去一份武學筆記，兩邊都認為是對方所取，第三封信卻另有落款。',
'一首被唱歪的舊曲傳遍江湖。島主不在乎嘲笑，卻要知道是誰拿這曲子向百姓索銀。',
'冰谷商旅不肯出售冰蠶，因為那是救治病童的最後一味藥。你可以另尋交換的藥材。',
'兩種毒物都被人引向村路，捕毒者只爭名號。先把過路人引開，再處理爭端。',
'一位豪客被數派圍住，雙方的說法都有缺口。查明被藏起的名冊，才能判斷是否出手。',
'御廚逃出城門，背的不是金銀而是食譜。他想把一道能讓病人進食的羹湯傳下去。',
'海島設粥宴，來客卻有人只想奪走石壁上的字。護住煮粥的人，再看看你讀懂了什麼。',
'小和尚記得病人的住處，卻記不得回寺的路。他請你先把藥送到，再送自己回去。',
'一盤無人落子的棋局等著過客。解題之前，先問問守棋的人，究竟想讓誰活著走下山。',
'鏢車被截在山口，車夫與劫客各有一張收據。護貨、追查，或勸他們共同到官府驗票。',
'山路出現奇怪的爪痕，村民不敢出門。查清痕跡，別讓恐懼先變成傷人的傳聞。',
'阮家的遺物被人當作贓物出售。替他們找回信物，也替活著的人留下一份說法。',
'乞者與毒客為一處水井爭執。井水關係整條街，先把取水的孩子送到安全地方。',
'兩派弟子在解劍池爭執，傷者卻同時需要兩邊的藥。試著讓他們把刀劍放下。',
'停戰的消息已送出，回程信使卻遭伏擊。把信送完，才能讓調停成為真的。',
'告示上的稅銀多了兩行字。先讓百姓保住生計，再找出多收銀兩的去向。',
'神秘商人出售真假混雜的貨。你可以付錢驗貨，也可以替他找回被搶走的貨單。']

def main():
    heroes={}; arts={}; quests={}; people={}; enemies={}
    kinds=['bleed','break','stun','pierce','cleave','poison','heavy']
    for i,(name,region,scene,weapon,art,kind,premise) in enumerate(ROWS):
        hid=f'jy{i+1:02}'
        sprite=hid if i<40 else 'resident_0'
        hp=355+(i%7)*37; atk=58+(i%9)*4
        if name in ['郭靖','喬峰','洪七公']: hp+=115;atk+=12
        if kind=='heal': hp-=35;atk-=9
        role={'heal':'醫護續航','stun':'封招制敵','break':'破甲開路','pierce':'越陣突擊','cleave':'橫掃破陣','bleed':'流血追擊','poison':'毒傷消耗','heavy':'重擊強攻'}[kind]
        heroes[hid]={'name':name,'role':weapon+' · '+role,'art':'actor_'+sprite,'sprite':sprite,'hp':hp,'atk':atk,'def':18+i%6*3,'speed':65+i%11*4,'qi':8+i%5,'lane':i%3,'front':kind not in ['heal','poison','pierce'],'outer':art,'inner':'長春功' if kind=='heal' else '吐納功','light':'踏雪步' if i%3==0 else '雁行步','bio':premise,'talent':role+'：招式使用真元並受調息限制；同行支線可提升好感與武學。','region':region,'scene':scene}
        arts[art]={'slot':'outer','weapon':weapon,'skill':art,'kind':kind,'power':2.8 if kind=='heal' else (1.35 if kind=='cleave' else 1.7),'cost':75 if kind in ['cleave','heavy'] else 50,'cd':3 if kind=='stun' else 2,'text':role+'。'+('治療最低氣血同伴並清毒。' if kind=='heal' else '可在戰前搭配內功、輕功及陣位。')}
        people[hid]={'name':name,'region':region,'scene':scene,'art':'actor_'+sprite,'hero':hid,'role':'江湖同伴','text':premise,'reply':'若願意同行，路上的事便一起商量。各人都有自己的路，我也不會要求你先替誰做完一整段故事。'}
        qid=f'friend_{hid}'
        dest=REGIONS[region][(REGIONS[region].index(scene)+1)%len(REGIONS[region])]
        mode=['visit','deliver','battle','talk'][i%4]
        steps=[{'kind':'talk','npc':hid,'region':region,'scene':scene,'text':'聽'+name+'說明來意。'},
               {'kind':'visit','region':region,'scene':dest,'text':'到'+dest+'核對線索。'}]
        if mode=='deliver': steps.append({'kind':'deliver','item':'草藥','count':1+i%3,'region':region,'scene':scene,'text':'帶草藥回來，幫傷者配藥。'})
        elif mode=='battle': steps.append({'kind':'battle','enemies':[f'enemy_{(i*7)%90+1:03}'],'region':region,'scene':dest,'text':'護住現場的人，擊退攔路者。'})
        elif mode=='talk': steps.append({'kind':'choice','region':region,'scene':dest,'text':'選擇公開證詞，或先保護送信人。','options':['公開查驗來往證詞','先護送當事人離開']})
        else: steps.append({'kind':'talk','npc':hid,'region':region,'scene':scene,'text':'把調查結果交給'+name+'。'})
        steps.append({'kind':'report','npc':hid,'region':region,'scene':scene,'text':'與'+name+'商量這件事的結局。'})
        quests[qid]={'name':name+' · '+['路上有信','一味良藥','護人之約','故物歸人'][i%4],'region':region,'scene':scene,'giver':hid,'text':premise,'steps':steps,'reward':{'silver':55+i*2,'potential':40+i%7*5,'affinity':12,'hero':hid},'source':'原創同行支線'}
    regions=list(REGIONS)
    for group,line in enumerate(ENEMY_NAMES):
        for j,name in enumerate(line.split()):
            i=group*10+j; eid=f'enemy_{i+1:03}'; region=regions[i%len(regions)]
            level=1+(i%10)*2+(5 if group==9 else 0)
            effect=kinds[(group+j)%len(kinds)]
            enemies[eid]={'name':name,'sprite':eid,'region':region,'scene':REGIONS[region][i%len(REGIONS[region])],'level':level,'hp':190+level*33+j*9,'atk':35+level*4+group,'def':10+level*2+j,'speed':48+(i*13)%65,'qi':6+i%8,'evade':(i%5)*2,'weapon':['刀','棍','劍','拳掌'][group%4],'kind':effect,'ai':['fighter','healer','sentinel','assassin','venom','breaker','berserker'][i%7],'skill':name+' · '+{'bleed':'裂傷','break':'破甲','stun':'截脈','pierce':'越陣','cleave':'橫掃','poison':'淬毒','heavy':'重擊'}[effect],'text':['擅長先手搶攻，須保護後排。','耐久較高，先破甲再集中攻擊。','出招後有調息空檔，可趁隙反擊。','留意蓄氣，封招可打斷攻勢。'][i%4]}
    # Peaceful service portraits; each scene gets independently named residents.
    for rindex,(region,scenes) in enumerate(REGIONS.items()):
        for si,scene in enumerate(scenes):
            for n,(role,resident) in enumerate([('掌事',2),('行旅',7)]):
                nid=f'local_{rindex:02}_{si:02}_{n}'
                name=scene+('掌事' if n==0 else '過客')
                people[nid]={'name':name,'region':region,'scene':scene,'art':f'actor_resident_{resident}','role':role,'text':f'{scene}的事，得坐下來慢慢說。'+['有人帶著舊信來尋人，我把他引到客舍歇腳。','近來商旅多了，幾位不同門派的人都留在此地問路。','山路昨夜落了雨，若要出行，記得先備些藥。','你若替人辦事，先問清他真正想要的是什麼。'][si%4],'reply':'這裡的委託都由你自己選。想趕路便趕路，想交朋友便多坐一會兒。'}
    special=[('boatman','老船翁','嘉興鎮','渡口',1),('keeper','陳掌櫃','嘉興鎮','青溪客棧',2),('hunter','老獵人','牛家村','樹林',3),('woodcutter','樵夫','牛家村','樹林',4),('smith','馮鐵匠','牛家村','馮家鐵鋪',5),('tea','茶博士','牛家村','河邊',6),('scholar','說書秀才','牛家村','村口',7)]
    for nid,name,region,scene,sprite in special:
        people[nid]={'name':name,'region':region,'scene':scene,'art':f'actor_resident_{sprite}','role':'鄉里人物','text':{'boatman':'船是載人過河的，不是擺在路邊嚇人的。你若想問渡口的舊事，就坐下喝碗熱茶。','keeper':'客棧的大門對每位過路人都開著。要找人、買藥、聽消息，都能從這裡開始。','hunter':'山裡的足跡各有不同。認得牠們，比只比誰的箭快更有用。','woodcutter':'砍柴也講收勢。把斧頭收得住，才不會傷到身後的人。','smith':'兵器不只看名氣。拿得順手、修得起，才能陪你走遠路。','tea':'茶能讓不相識的人坐在同一張桌上。想問江湖，就別急著喝完。','scholar':'故事從來不只一條線。你今天聽見誰的名字，明日便可能在另一座城見到他。'}[nid],'reply':'你在此地見到的人與委託，都不受任何主線章節限制。'}
    for i,title in enumerate(FLASH_TITLES):
        region=FLASH_REGIONS[i]; scene=REGIONS[region][i%len(REGIONS[region])]
        giver=next(k for k,v in people.items() if v['region']==region and v['scene']==scene)
        dest=REGIONS[region][(i+1)%len(REGIONS[region])]
        qid=f'flash_{i+1:02}'
        steps=[{'kind':'talk','npc':giver,'region':region,'scene':scene,'text':'與委託人核實事情的起因。'}]
        if i in [0,1,2,17]:
            for n in range(3): steps.append({'kind':'visit','region':regions[(regions.index(region)+n)%16],'scene':REGIONS[regions[(regions.index(region)+n)%16]][(i+n)%len(REGIONS[regions[(regions.index(region)+n)%16]])],'text':'尋訪第 %d 處線索。'%(n+1)})
        else: steps.append({'kind':'visit','region':region,'scene':dest,'text':'前往'+dest+'尋找當事人。'})
        if i%5 in [0,2]: steps.append({'kind':'deliver','item':'草藥' if i%2 else '金創藥','count':1,'region':region,'scene':dest,'text':'交付一份救急物資，替對方解除眼前的困難。'})
        if i%4!=1: steps.append({'kind':'battle','enemies':[f'enemy_{(i*3)%100+1:03}',f'enemy_{(i*3+1)%100+1:03}'] if i%3==0 else [f'enemy_{(i*3)%100+1:03}'],'region':region,'scene':dest,'text':'準備妥當後，再選擇出手護人或接受切磋。'})
        steps.append({'kind':'choice','region':region,'scene':dest,'text':'事情已見分曉，由你決定如何了結。','options':['護人為先 · 增進情義','追查到底 · 多得修為']})
        steps.append({'kind':'report','npc':giver,'region':region,'scene':scene,'text':'回到'+scene+'交代結果，領取報酬。'})
        quests[qid]={'name':title,'region':region,'scene':scene,'giver':giver,'text':PREMISES[i],'steps':steps,'reward':{'silver':70+i*3,'potential':45+i%10*6},'source':'Flash 公告事件 '+str(i+1)+' 的獨立改寫'}
    extra_names=['獵戶的膽囊','樵夫的柴束','河邊失竿','破廟毒蟲','鐵鋪試刃','茶香問路','梵文舊頁','送藥入山','官道護民','客舍尋親','羅漢堂試藝','達摩堂破陣','般若堂問掌','少林廚房幫工','武當丹房煉藥','解劍池問道','華山膳堂採辦','思過崖藏劍','全真碑林養生','重陽宮會武','古墓蜂房','石門迷徑','梅莊四友','林宅舊物','苗家解毒','胡家舊譜','神龍島送舟','天龍寺問指','冰谷問藥','渡口尋礦','酒肆送酒','回部護商','還施水閣辨譜','松林試步','武林新秀會']
    for i,title in enumerate(extra_names):
        region=regions[i%16];scene=REGIONS[region][i%len(REGIONS[region])];giver=next(k for k,v in people.items() if v['region']==region and v['scene']==scene)
        quests[f'errand_{i+1:02}']={'name':title,'region':region,'scene':scene,'giver':giver,'text':f'{scene}的居民請你協助「{title}」。先問清來意，再由你選擇何時動身。','steps':[{'kind':'talk','npc':giver,'region':region,'scene':scene,'text':'聽取居民的需要。'},{'kind':'deliver' if i%2==0 else 'battle','item':'草藥','count':1+i%2,'enemies':[f'enemy_{(i*11)%100+1:03}'],'region':region,'scene':scene,'text':'備妥草藥交付。' if i%2==0 else '與當地對手切磋，證明能夠護送。'},{'kind':'report','npc':giver,'region':region,'scene':scene,'text':'向居民交代成果。'}],'reward':{'silver':40+i,'potential':25+i},'source':'村莊／門派／場所支線改寫'}
    content={'regions':REGIONS,'heroes':heroes,'arts':arts,'people':people,'enemies':enemies,'quests':quests}
    enrich(content)
    (ROOT/'data/open_world.json').write_text(json.dumps(content,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    gd='extends RefCounted\n## Generated by tools/build_open_world.py; original dialogue, no imported game scripts.\n'
    for key,data in content.items(): gd+='const '+key.upper()+':= '+json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n'
    (ROOT/'scripts/journey/open_content.gd').write_text(gd,encoding='utf-8')
    ledger={'scope':'Flash 正式／1.08 與賀歲版公開資料；原創改寫，非逐字劇本移植','sources':['https://www.gamez.com.tw/t/topic/391207','https://mmap.page/dapi/jyqxz3-cheat/','https://blog.sina.cn/dpool/blog/s/blog_7e7f9ac00100svkm.html','https://ak963520.pixnet.net/blog/posts/2024940377'],'flash_event_ids':{str(i+1):'flash_%02d'%(i+1) for i in range(45)},'recruit_names':[x[0] for x in ROWS],'counts':{'recruits':len(heroes),'enemy_designs':len(enemies),'optional_quests':len(quests),'locations':sum(map(len,REGIONS.values()))},'differences':['所有任務可自由接取，不保留 Flash 五日拜師／一年出師的全域時間鎖。','每位人物可對話邀請入候補；同行支線獨立進行。','西夏公主在不同攻略中是否可入隊有分歧，本作提供招募。','公告 42／43 的兩派衝突編碼以調停與護送兩條委託呈現。','保留來源題材及角色名，對話、數值與支線步驟均重新編寫。']}
    (ROOT/'docs/JY3-COVERAGE.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(ledger['counts'])
if __name__=='__main__':main()
