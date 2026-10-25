# -*- coding: utf-8 -*-
"""Named residents with occupation-led casting; stable person IDs preserve quests."""
import hashlib

# Same order as the four imagegen portrait sheets in art/visuals/prompts.json.
PROFILES = [
 ('客棧掌櫃','我記得每位客人的口味，也記得誰連夜退了房。','樓上的空房留給雨夜趕路的人，別急著走。'),
 ('跑堂姑娘','我端茶時聽見的話，往往比說書人的故事更真。','昨晚那桌客人沒動筷子，倒是把地圖翻了三遍。'),
 ('灶上廚師','刀工要穩，救急的熱粥也得慢慢熬。','火上還有一鍋粥，若有人受傷，先讓他吃口熱的。'),
 ('釀酒師','我做酒靠的是水和時間，不靠酒名唬人。','新酒尚烈，老友若來，替我留他坐一會兒。'),
 ('茶博士','茶葉受潮便壞，人的話卻要多聽幾遍才明白。','東邊路上有人問過一封舊信，喝完茶就匆匆走了。'),
 ('老艄公','水面平靜時也有暗流，過河的人總比浪頭急。','今夜水漲，先把傷者送上岸，船錢日後再算。'),
 ('渡船姑娘','我認得每一處淺灘，也知道誰把船纜偷偷割過。','要渡河就趁天亮；若只想問消息，我也願意說說。'),
 ('賣魚大娘','魚要新鮮，生意也得講個清白。','碼頭的木箱昨夜換了船，我看見了箱角的記號。'),
 ('鐵匠','鐵有脾氣，淬火不能只看火色。','兵器若有裂口，帶來讓我看看，別等上陣才後悔。'),
 ('鍛坊學徒','師父讓我先學認鐵，再學握錘。','這批鏢頭的鉚釘與上月不同，像是換過一家鋪子。'),
 ('綢緞商','我看布紋辨產地，看針腳辨做衣的人。','那件留下的披風針腳很細，主人應當不是普通行腳客。'),
 ('行商','一路販香料，最貴的貨其實是平安回家的消息。','商道上有人收兩次路稅，帳單卻只肯開一張。'),
 ('樵夫','樹倒向哪邊，得先想好身後的人站在哪裡。','林裡新添了路標，可刻字的刀口還沒舊。'),
 ('山中獵戶','認足跡比拉強弓有用，山裡不只有獵物。','山道有受驚的鳥群，若要探路，帶一位熟悉林子的人。'),
 ('老農','一年收成看天，也看鄰里肯不肯搭把手。','種子不能拿去抵債，我想替村裡留下一季的盼頭。'),
 ('織娘','線斷了能接，失散的人卻得有人去找。','那半幅繡樣上的花，是我年輕時學過的樣式。'),
 ('女塾先生','教孩子認字，也得教他們分清告示上的真與假。','若有人拿文書逼你交錢，先帶來讓我讀一遍。'),
 ('抄書人','一字之差足以改變一張藥方，也能改掉一份證詞。','我留著舊稿，倘若新文書有疑，不妨拿來比對。'),
 ('說書先生','我講的故事裡，無名之人也有不能輕放的分量。','茶樓有人提起一位不留姓名的俠客，你可曾見過？'),
 ('驛使','信到了才算走完一程，馬跑得快還不夠。','這封回信晚了三日，收信人卻一直在等。'),
 ('採藥人','藥性看時節，救人要先問清症候。','山陰的草才剛冒頭，別把整株連根拔走。'),
 ('坐堂郎中','江湖舊怨我不判，傷口總得先縫好。','你若缺藥，先說傷在哪裡，我替你想辦法。'),
 ('接生婆','我接住過不少初生的孩子，誰家有難瞞不過鄰里。','屋裡的婦人需要清水與熱湯，別讓爭吵驚著她。'),
 ('琴師','曲子斷在半拍，多半是彈琴的人還有話沒說完。','那聲錯弦不像失手，更像在等人回應。'),
 ('知客僧','山門迎客，不該把求助的人擋在雨裡。','客舍尚有蒲團，你若尋人，我可替你問問。'),
 ('老禪師','先問眼前的人有何苦處，再談自己的道理。','院裡的鐘已敲過，煮藥的小僧卻還沒回來。'),
 ('雲遊道人','我走遍山路，只求把欠下的人情一件件還清。','路上的石碑刻過兩次，舊字未必就不可信。'),
 ('清修女冠','修心也修眼，別讓成見遮住眼前的證據。','若兩人的說法不同，便各自聽完，再去看現場。'),
 ('行腳師太','我隨身的藥袋只裝救人的東西。','有傷者落在隊伍後頭，我想回去找找他。'),
 ('老乞者','我住過橋洞，也記得哪戶人家曾留一盞燈。','有人換了衣裳換不了腳步，昨夜那人我認得。'),
 ('巡街女捕','我查的是證據，不是誰的門派聲音最大。','人證還沒到齊，先別讓押送的人動手。'),
 ('退伍老兵','打過仗才知道，能把人帶回家比搶一面旗難。','這條路我守過，帶著傷員走時要避開陡坡。'),
]

SPECIAL = {'keeper':0,'boatman':5,'smith':8,'hunter':13,'woodcutter':12,'tea':4,'scholar':18}
SURNAMES='沈陳周許方程顧宋葉江杜柳陸林蘇白秦唐孟賀鄭羅易夏韓梅邵燕傅梁尹石'
GIVEN=['文清','守義','知秋','映雪','懷安','青禾','望舒','承遠','素心','景明','聽雨','雲岫','仲平','小滿','念慈','長寧','玉蘭','如意','柏舟','南星','若水','景行','安平','知微','秋實','照晚','元和','春曉','思齊','問山','初晴','修竹']
PRESENTATION='M F M M M M F F M F F M M F M F F M M M F M F F M M M F F M F M'.split()

def preferences(scene):
    if any(s in scene for s in ['鐵','鍛']):return [8,9,11,19,31,10]
    if any(s in scene for s in ['藥','丹','圃','蝴蝶']):return [21,20,22,27,17,14,28]
    if any(s in scene for s in ['廚','膳']):return [2,1,3,14,15,24,25]
    if any(s in scene for s in ['寺','經','宮','觀','堂','金頂','廟','銅人']):return [24,25,26,27,28,16,17,20,21,2,14,31]
    if any(s in scene for s in ['河','渡','漁','碼頭','蘆','井']):return [5,6,7,4,11,13,20,14]
    if any(s in scene for s in ['琴','書','閣']):return [23,16,17,18,10,27,21]
    if any(s in scene for s in ['茶','酒','棧','舍','驛','商','街市','集市']):return [0,1,4,3,11,10,19,18,15,7,16,22]
    if any(s in scene for s in ['演武','鏢','軍','烽火','關隘','城門','解劍']):return [30,31,19,9,26,13,28,17]
    if any(s in scene for s in ['山','林','崖','谷','荒','塞','石','墓','密道']):return [13,12,20,26,28,14,31,29,27,19,15]
    return [10,14,15,16,18,22,29,30,11,17,23,19,1,3]

def populate(content):
    people=content['people'];regions=content['regions'];used={r:set() for r in regions}
    for pid,index in SPECIAL.items():
        used[people[pid]['region']].add(index)
        people[pid]['art']=f'actor_npc_{index:02}'
        people[pid]['role']=PROFILES[index][0]
    all_names={p['name'] for p in people.values() if not p.get('name','').endswith(('掌事','過客'))}
    ordinal=0
    for pid,npc in people.items():
        if not pid.startswith('local_'):continue
        region,scene=npc['region'],npc['scene']
        wanted=preferences(scene)
        # Secondary resident has a different occupation without exhausting a city's pool.
        if pid.endswith('_1'):wanted=wanted[2:]+wanted[:2]
        available=[p for p in wanted+list(range(32)) if p not in used[region]]
        if pid.endswith('_1'):
            first=people.get(pid[:-1]+'0',{}).get('art','')
            if first.startswith('actor_npc_'):
                contrast=[p for p in available if PRESENTATION[p]!=PRESENTATION[int(first[-2:])]]
                if contrast:available=contrast
        index=available[0];used[region].add(index)
        seed=int(hashlib.sha256(pid.encode()).hexdigest()[:8],16)
        name=SURNAMES[ordinal%32]+GIVEN[(seed+ordinal//32)%32]
        while name in all_names:
            seed+=1;name=SURNAMES[(ordinal+seed//32)%32]+GIVEN[seed%32]
        all_names.add(name);ordinal+=1
        job,voice,rumor=PROFILES[index]
        local=[q for q in content['quests'].values() if q['giver']==pid]
        detail=local[0]['text'] if local else f'我在{scene}做了多年{job}。'+rumor
        npc.update(name=name,role=job,art=f'actor_npc_{index:02}',text=voice+'\n'+detail,
                   reply=f'{region}這一帶，{scene}與{regions[region][(regions[region].index(scene)+1)%len(regions[region])]}之間的路我最熟。'+rumor)
    # Special townspeople also speak as people, not as UI instructions.
    for pid,index in SPECIAL.items():
        job,voice,rumor=PROFILES[index]
        people[pid]['text']=voice+'\n'+rumor
        people[pid]['reply']='你若想幫忙，我把知道的事慢慢說給你聽。'+rumor
    for region in regions:
        portraits=[p['art'] for p in people.values() if p['region']==region and p.get('art','').startswith('actor_npc_')]
        assert len(portraits)==len(set(portraits)),f'Repeated resident portrait in {region}'
