"""Compile authored post-event speech and check every participant has a response."""
from . import after_companions, after_events, after_errands, after_witnesses

BRANCHES = '''
friend_jy02|0|小跑堂把我夾給他的雞腿記住了，今天見我就問還餓不餓。|你又叫他添飯？|沒叫！我是會吃，也不是非把人家吃窮不可。
friend_jy02|1|掌櫃把那桌多添的筷子留著了，說下回咱們坐裡頭，不擠過路的人。|你倒成了熟客。|有人同桌吃飯，菜總能多試兩樣。
friend_jy06|0|酒帳我抄下來了。這個數若還不清，下次老闆拿它往我眼前一攤，我也賴不掉。|這回不請旁人了？|請得起才請。實在不行，一起喝水。
friend_jy06|1|兩缸水挑滿，老闆才在帳上劃去一小筆。我以前喝酒，可沒覺得一碗那麼費力。|還洗碗嗎？|洗。洗破了又添帳，得比練劍還小心。
friend_jy08|0|那張叫人殺人的末頁，已撕去了。我如今再練步法，不會總想到那句命令。|還拜玉像嗎？|看可以看。要聽誰的話，卻得我自己想。
friend_jy08|1|原冊已封好，步法另抄了。我在封面寫明裡頭還有甚麼，不叫後來的人只看前半頁。|字寫得夠大嗎？|夠大。我還描粗了兩回。
flash_37|0|家師看了你捨掉那一塊的落子，叫我照原樣重擺三遍。第三遍，我才敢說真看明白。|你還守在這裡？|守。這回是陪人下棋，不是守著一盤沒人敢碰的死局。
flash_37|1|樵夫也看過破局圖了，還問自己剪了幾十年樹，怎麼竟剪到棋盤上。|你怎麼答？|我請他坐下試一局。這些年光替我收盤，還沒陪他好好下過。
'''

SUPPORT_CHAT = '''
support_wei|別替我挑背風得一絲氣也不透的屋。開半扇窗，總不至於把我吹跑。
support_miao|小女學著替我念來信，遇上不識的字便停。我也不催，先聽她把認得的念完。
support_ren|離了那間牢，才覺得外頭人說話也這樣繞。你有事直說，老夫未必答應，總會聽完。
support_su|棋盒裡少一顆白子，八成又被鳥叼走了。等我找個空檔，得給盒子添一個扣。
support_ying|我這針線總穿不好。你替我把燈挪近些，別替我穿，我還看得清。
support_ruan|琴囊上這一針，是盈盈幼時補的。難看歸難看，背了這些年，也沒再開線。
support_shen|我在練退步。你別站身後，我這會兒還顧不全兩邊。
support_huiding|今早又認了兩個字，怕忘，寫在自己的袖裡。師叔說下回別拿洗不掉的墨。
support_ashun|伯伯說下回教我看浮子。我先拿空盆練，魚還沒見著，家裡的貓倒等上了。
support_he|姊姊把常用的砝碼纏了不同的繩，摸一下便分得清。我也想替水壺纏一圈。
support_qiu|名冊我會帶回家，先收在娘放舊物的匣裡。讓她想看時，自己便能拿到。
support_jing|送信的袋子該補了。路再遠，總不能讓一場雨先把回話洗得乾乾淨淨。
support_huang|我把琴凳挪遠了半尺。以前只顧自己坐得舒坦，客人聽曲總得仰著頸。
support_hei|這局你執黑。我今日不讓子，你也別先看我的臉色才落。
support_tu|字等乾了再看。方才還嫌筆畫歪，如今墨一收，倒又有幾分可取。
support_dan|你把杯子拿開，我展半卷給你看。對，只看半卷，另一半的酒漬還沒洗掉。
'''

def rows(table, size):
    for row in table.strip().splitlines():
        fields=row.split('|')
        assert len(fields)==size,(size,row)
        yield fields

def exchange(pid, speech):
    return [{'speaker':pid if i%2==0 else 'hero','text':text} for i,text in enumerate(speech)]

def apply(content):
    people,quests=content['people'],content['quests']
    for hid,*speech in rows(after_companions.CHAT,4):
        people[hid]['idle_pages']=exchange(hid,speech)
    for pid,text in rows(SUPPORT_CHAT,2):
        people[pid]['idle_pages']=[{'speaker':pid,'text':text}]
    seen=set()
    for module in [after_companions,after_events,after_errands]:
        for qid,*speech in rows(module.GIVER,4):
            assert qid not in seen,qid
            seen.add(qid)
            q=quests[qid]
            q['aftermath']={q['giver']:exchange(q['giver'],speech)}
    assert seen==set(quests),(set(quests)-seen,seen-set(quests))
    for qid,pid,text in rows(after_witnesses.LINES,3):
        assert pid in people and pid not in quests[qid]['aftermath'],(qid,pid)
        quests[qid]['aftermath'][pid]=[{'speaker':pid,'text':text}]
    for qid,index,*speech in rows(BRANCHES,5):
        q=quests[qid]
        q.setdefault('aftermath_choices',{})[index]={q['giver']:exchange(q['giver'],speech)}
    for qid,q in quests.items():
        participants={q['giver']}
        for s in q['steps']:
            if s.get('npc'):participants.add(s['npc'])
            participants.update(line['speaker'] for line in s['pages'])
        for ending in q['ending_dialogues']:
            participants.update(line['speaker'] for line in ending)
        participants={p for p in participants if p in people and not p.startswith('foe_')}
        assert participants==set(q['aftermath']),(qid,participants-set(q['aftermath']),set(q['aftermath'])-participants)
        for pid,pages in q['aftermath'].items():
            for line in pages:
                assert line['text'] and len(line['text'])<=170,(qid,line)
                assert not any(line['text']==old['text'] for s in q['steps'] for old in s['pages']),(qid,'replayed quest line')
