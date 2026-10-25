# -*- coding: utf-8 -*-
"""Compile authored dialogue. Shared code resolves actors; it never invents prose."""
import json
from copy import deepcopy
from pathlib import Path
from storybook import companions_a, companions_b, companions_c
from storybook import events_a, events_b, events_c, errands_a, errands_b, town
from storybook.residents import apply as cast_residents
from storybook.supporting import CAST, CONTACTS, GIVERS
from storybook.gossip import apply as add_gossip
from storybook.aftermath import apply as add_aftermath


def rebuild(content):
    legacy=json.loads((Path(__file__).parent/'storybook/legacy.json').read_text(encoding='utf-8'))
    cast_residents(content)
    add_gossip(content['people'])
    people,quests,heroes=content['people'],content['quests'],content['heroes']
    for key,name,role,at,permanent,lines in CAST:
        r,s=at.split('/');pid='support_'+key
        people[pid]=dict(name=name,role=role,region=r,scene=s,art='actor_story_'+key,auxiliary=True,event_only=not permanent,
            text=lines[0],reply=lines[-1],pages=[dict(speaker=pid,text=t) for t in lines],stories=[],story='')

    def contact(qid,at,giver,hint=None):
        hint=CONTACTS.get((qid,at),0) if hint is None else hint
        if isinstance(hint,str):
            assert hint in people,hint
            return hint
        r,s=at.split('/')
        candidates=[pid for pid,p in people.items() if pid.startswith('local_') and p['region']==r and p['scene']==s]
        result=candidates[hint]
        return result if result!=giver else candidates[1-hint]

    for npc in people.values():npc['idle_pages']=deepcopy(npc.get('alternate_pages',npc.get('pages',[])))
    records=[s for m in [companions_a,companions_b,companions_c,events_a,events_b,events_c,errands_a,errands_b,town] for s in m.STORIES]
    assert len(records)==129
    ids=set()
    for record in records:
        personal=record['id'].startswith('jy');hid=record['id'] if personal else ''
        qid='friend_'+hid if personal else record['id']
        assert qid not in ids,qid
        ids.add(qid)
        at=heroes[hid]['region']+'/'+heroes[hid]['scene'] if personal else record['at']
        region,home=at.split('/')
        giver=hid if personal else record.get('giver',GIVERS.get(qid,''))
        if not giver:
            giver=next(pid for pid,p in people.items() if pid.startswith('local_') and p['region']==region and p['scene']==home and int(pid[-1])==record.get('contact',0))
        assert people[giver]['region']==region and people[giver]['scene']==home,(qid,giver,at)
        q=quests.setdefault(qid,dict(reward=dict(silver=50,potential=45),source='青溪地方往事・原創'))
        q.update(name=heroes[hid]['name']+' · '+record['title'] if personal else record.get('title',q.get('name',qid)),
            region=region,scene=home,giver=giver,text=record['want'],revision=3)
        steps=[]

        def dialogue(lines,aliases):
            result=[]
            for line in lines:
                who,text=line.split('|',1);speaker=aliases.get(who,who)
                assert speaker=='' or speaker=='hero' or speaker in people,(qid,speaker)
                assert text.strip() and len(text)<=170,(qid,'oversized speech',text)
                result.append(dict(speaker=speaker,text=text))
            return result

        base=dict(g=giver,p='hero',n='',w=contact(qid,at,giver),x='')
        steps.append(dict(kind='talk',region=region,scene=home,npc=giver,text=record['want'],pages=dialogue(record['opening'],base),action='答應幫這個忙'))
        for index,raw in enumerate(record['beats']):
            r,scene=raw['at'].split('/')
            assert r in content['regions'] and scene in content['regions'][r],(qid,raw['at'])
            witness=contact(qid,raw['at'],giver,raw.get('contact'))
            aliases=dict(g=giver,p='hero',n='',w=witness,x='')
            s={k:deepcopy(v) for k,v in raw.items() if k not in ['at','dialogue','contact','enemy','rank','foe','npc','next_by_choice']}
            s.update(region=r,scene=scene)
            if raw['kind']=='battle':
                foe_id=raw.get('opponent_hero',f'foe_{qid}_{index}');enemy=f'enemy_{int(raw["enemy"]):03}';aliases['x']=foe_id
                if not raw.get('opponent_hero'):
                    people[foe_id]=dict(name=raw['foe'],role=raw['foe'],region=r,scene=scene,art='actor_'+enemy,auxiliary=True,event_only=True,stories=[qid],story=qid,text='',reply='',pages=[])
                count=int(raw.get('count',1))
                s.update(enemies=[f'enemy_{int(raw["enemy"])+i:03}' for i in range(count)],
                    foe_names=[raw['foe']]+['同夥 · '+raw['foe'] for _ in range(count-1)],story_rank=raw['rank'])
            s['pages']=dialogue(raw['dialogue'],aliases)
            if raw['kind']=='search':s['evidence']=qid+':object'
            if raw['kind'] in ['talk','report','choice'] or raw.get('npc'):
                who=raw.get('npc')
                if who is None:who=next((line.split('|',1)[0] for line in raw['dialogue'] if line.split('|',1)[0] not in ['n','p','x']),'g')
                s['npc']=aliases.get(who,who)
                assert s['npc'] in people,(qid,s['npc'])
                person=people[s['npc']]
                if person['region']!=r or person['scene']!=scene:s['visiting']=s['npc']
            if 'next_by_choice' in raw:s['next_by_choice']=[n+1 for n in raw['next_by_choice']]
            steps.append(s)
            if raw['kind']=='battle' and not raw.get('opponent_hero'):people[aliases['x']]['pages']=[line for line in s['pages'] if line['speaker']==aliases['x']]

        endings=[dialogue(lines,base) for lines in record['ending']]
        if steps[-1]['kind']=='report' and steps[-1].get('npc')==giver and steps[-1]['region']==region and steps[-1]['scene']==home:
            prefix=steps[-1]['pages']
        else:
            steps.append(dict(kind='report',npc=giver,region=region,scene=home,text='回來把這件事的收尾告訴'+people[giver]['name']+'。',action='把這件事辦完'))
            prefix=[]
        steps[-1]['pages']=prefix+endings[0]
        if len(endings)>1:steps[-1]['ending_pages']=[prefix+lines for lines in endings]
        q.update(steps=steps,endings=[next((v['text'] for v in lines if v['speaker']==giver),lines[0]['text']) for lines in endings],conclusion=endings[0][0]['text'],ending_dialogues=endings)
        if personal:
            h=heroes[hid];q['reward'].update(hero=hid,affinity=20,affinity_by_choice=[20,16])
            h.update(bio=record['want'],voice=record['voice'],join=record['join'],sprite=hid,art='actor_'+hid,
                recruit=dict(quest=qid,affinity=12,level=legacy['recruit_levels'][hid],text=record['join']))
            h['talent']=h['talent'].split('：')[0]+'：'+content['arts'][h['outer']]['text']
            people[hid].update(art='actor_'+hid,text=record['opening'][0].split('|',1)[1],reply=record['after'],voice=record['voice'],pages=dialogue(record['opening'],base),join=record['join'])
    assert ids==set(quests)
    add_aftermath(content)
    for pid,npc in people.items():
        references=[qid for qid,q in quests.items() if q['giver']==pid or any(s.get('npc')==pid or any(line['speaker']==pid for line in s['pages']) for s in q['steps'])]
        own=[qid for qid in references if quests[qid]['giver']==pid]
        npc['stories']=own+[qid for qid in references if qid not in own];npc['story']=npc['stories'][0] if npc['stories'] else ''
        if not npc['text'] and npc['pages']:npc['text']=npc['pages'][0]['text']
    editions={str(i):json.loads((Path(__file__).parent/f'storybook/legacy_quests_v{i}.json').read_text(encoding='utf-8')) for i in [1,2]}
    content.update(previous_steps=legacy['v2_steps'],previous_endings=legacy['v2_endings'],previous_clues=legacy['v2_clues'],legacy_quests=editions,story_version=3)
    return legacy['v1_steps']
