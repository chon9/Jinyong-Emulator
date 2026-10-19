"""Convert the user's JY-Mini OL content into this simulator's independent schema.

Source is read only. Runtime requires only data/catalog.json, never the old project.
"""
import argparse
import collections
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def build(source):
    def rows(table):
        return json.loads((source / (table + '.json')).read_text(encoding='utf-8-sig'))['rows']

    texts = {t['id']: t.get('self', '') for t in rows('text_templates')}
    regions = {r['id']: r for r in rows('regions')}
    maps = [json.loads(f.read_text(encoding='utf-8-sig')) for f in sorted((source / 'maps').glob('*.json'))]
    rooms = {r['id']: (r, m['region_id']) for m in maps for r in m['rooms']}
    names = {rid: regions[region]['name'] + '・' + r['name'] for rid, (r, region) in rooms.items()}
    sects = {s['id']: s for s in rows('sects')}
    all_skills = rows('basic_skills') + rows('martial_arts')
    # 門派技能也可消點與自修，與特殊武功的學習條件相連。
    for sid, s in sects.items():
        all_skills.append({'id': s['sect_skill'], 'name': s['sect_skill_name'], 'sect_id': sid,
                           'category': 'SECT', 'desc': '本門修養，影響師父是否願意傳授更深武學。'})
    skill_names = {s['id']: s['name'] for s in all_skills}
    basic_categories = {'basic_blade': 'BLADE', 'basic_sword': 'SWORD', 'basic_whip': 'WHIP',
                        'basic_staff': 'STAFF', 'basic_spear': 'SPEAR', 'basic_fist': 'FIST',
                        'basic_stab': 'STAB', 'basic_inner': 'INNER', 'basic_body': 'LIGHTNESS',
                        'basic_dodge': 'DODGE', 'basic_parry': 'PARRY', 'basic_hidden': 'HIDDEN',
                        'basic_poison': 'POISON', 'basic_medic': 'MEDIC', 'basic_formation': 'FORMATION'}
    arts = {}
    for a in all_skills:
        if a.get('monster_only'): continue
        name = skill_names[a['id']]
        category = a.get('category', basic_categories.get(a['id'], 'UTILITY'))
        base = skill_names.get(a.get('base_skill'), '')
        # 官方武學限制表歸為槍法；原專案的 STAB 是筆法的暫代分類。
        if a['id'] == 'wd_yitian': category, base = 'SPEAR', skill_names['basic_spear']
        role = ('EXTERNAL' if category in ['FIST', 'STAB', 'BLADE', 'SWORD', 'STAFF', 'SPEAR', 'WHIP']
                else 'INNER' if category == 'INNER' else 'MOVEMENT' if category in ['LIGHTNESS', 'DODGE']
                else 'UTILITY')
        arts[name] = {'id': a['id'], 'name': name, 'sect': sects.get(a.get('sect_id'), {}).get('name', ''),
                      'category': category, 'role': role, 'base': base,
                      'weapon_types': (['UNARMED', 'CLAW'] if category in ['FIST', 'STAB'] else [category]) if role == 'EXTERNAL' else [],
                      'basic': a['id'].startswith('basic_'),
                      'desc': a.get('desc', '紮穩根基，方能登堂入室。'),
                      'difficulty': a.get('difficulty', 1.0), 'cap': a.get('max_level', 100),
                      'study_cap': a.get('self_study_cap', 0) or a.get('max_level', 100),
                      'learn_cap': 1 if a['id'] in ['hs_zixia', 'em_jiuyang', 'gm_jiuyin'] else 0,
                      'requires': [{'skill': skill_names[r['skill']], 'level': r['value']} for r in a.get('requires', [])
                                   if r['type'] == 'skill_min' and r['skill'] in skill_names],
                      'moves': [m['name'] for m in a.get('moves', [])]}
    item_names = {i['id']: i['name'] for i in rows('items')}
    items = {}
    for i in rows('items'):
        restore = {}
        for effect in i.get('effects', []):
            if effect['type'] == 'restore':
                stat = {'qi': 'hp', 'jing': 'energy', 'shen': 'mp', 'food': 'energy', 'water': 'mp'}.get(effect['stat'])
                if stat: restore[stat] = restore.get(stat, 0) + effect['value']
        items[i['name']] = {'id': i['id'], 'price': max(1, i.get('price', 1)), 'desc': i.get('desc', ''),
                            'type': i['tab'], 'attack': i.get('atk', 0), 'defense': i.get('def', 0),
                            'restore': restore, 'quest': i.get('quest_item', False),
                            'sellable': not i.get('no_sell', False), 'weapon_type': i.get('weapon_type', '')}
    enemies = {}
    enemy_names = {m['id']: m['name'] for m in rows('monsters')}
    for index, m in enumerate(rows('monsters')):
        stats = m['stats']
        level = max(1, min(45, round(m.get('combat_xp_ref', 100) ** .43 / 5)))
        enemies[m['name']] = {'id': m['id'], 'hp': max(35, round(stats['qi'] * .55)),
                              'attack': max(5, round(stats['str'] * 1.2 + level * 1.5)),
                              'defense': max(0, round(m.get('armor_power', 0) / 8)),
                              'exp': max(12, m.get('combat_xp', 10) * 3),
                              'potential': max(8, m.get('learn_points', 2) * 3),
                              'silver': max(5, m.get('money', {}).get('max', 5)),
                              'level': level, 'desc': m.get('desc', ''),
                              'drops': [{'item': item_names[d['item']], 'chance': d['chance']}
                                        for d in m.get('drops', []) if d['item'] in item_names]}
    # 新增有獨立戰鬥定位的遭遇，補足百種敵人；不標為原作已驗證內容。
    extra = [
        ('荒原狐', 1, '疾行'), ('赤尾蛇', 2, '毒牙'), ('荊棘野豬', 3, '蠻衝'), ('斷橋水匪', 4, '刀客'),
        ('黑風斥候', 5, '疾行'), ('山道攔路客', 6, '刀客'), ('鹽幫打手', 7, '剛猛'), ('青衣劍客', 8, '劍客'),
        ('漠北馬賊', 9, '蠻衝'), ('寨門刀手', 10, '刀客'), ('毒砂客', 11, '毒牙'), ('流亡棍僧', 12, '剛猛'),
        ('白猿王', 13, '蠻衝'), ('林海獵手', 14, '疾行'), ('鐵掌門徒', 15, '剛猛'), ('雪嶺刀客', 16, '刀客'),
        ('古道劍痴', 18, '劍客'), ('赤砂寨主', 20, '剛猛'), ('幽谷毒叟', 22, '毒牙'), ('孤峰劍衛', 24, '劍客'),
        ('玄鐵守衛', 26, '剛猛'), ('白駝遊騎', 28, '疾行'), ('冰河巨熊', 30, '蠻衝'), ('黑風寨主', 32, '刀客')]
    for index, (name, level, style) in enumerate(extra):
        enemies[name] = {'id': 'yx_enemy_' + str(index), 'hp': 45 + level * 23,
                          'attack': 6 + level * 4, 'defense': level * 2, 'exp': 18 + level * 17,
                          'potential': 10 + level * 9, 'silver': 8 + level * 7, 'level': level,
                          'style': style, 'desc': '游俠江湖新增遭遇：' + name + '，擅長' + style + '。',
                          'drops': [{'item': list(items)[index % len(items)], 'chance': .2}]}
    places = {}
    for rid, (r, region) in rooms.items():
        pool = [enemy_names[e['monster']] for e in r.get('encounter', {}).get('table', []) if e['monster'] in enemy_names]
        places[names[rid]] = {'id': rid, 'region': regions[region]['name'], 'desc': r['desc'],
                             'exits': list(dict.fromkeys(names[e['to']] for e in r.get('exits', []) if e['to'] in names)),
                             'safe': not bool(pool), 'enemy': pool[0] if pool else '', 'enemies': pool,
                             'level': min((enemies[n]['level'] for n in pool), default=0), 'npcs': [], 'shop': []}
    npcs = {}
    for n in rows('npcs'):
        if n['room'] not in names: continue
        def dialogue_line(value):
            value = value.replace('{npc_name}', n['name'])
            for token, replacement in {'{gege}': '朋友', '{honorific}': '少俠', '{shaoxia}': '少俠', '{shidi}': '同門'}.items():
                value = value.replace(token, replacement)
            return value
        talk = dialogue_line(texts[n['talk']])
        variants = [dialogue_line(v) for k, v in texts.items() if k.startswith(n['talk'] + '@')]
        npcs[n['id']] = {'id': n['id'], 'name': n['name'], 'place': names[n['room']], 'desc': n.get('desc', ''),
                         'dialogue': [talk] + variants, 'kind': n['kind'], 'teach': []}
        places[names[n['room']]]['npcs'].append(n['id'])
        places[names[n['room']]]['shop'].extend(item_names[x] for x in n.get('shop', {}).get('items', []) if x in item_names)
    independent_dialogue = {
        'n_amb_etou_xe': '礦道旁的惡人頭子掂著一塊碎鐵：礦工過我的地界，總得留點過路錢。你若要管這樁閒事，先掂量掂量自己的拳頭。',
        'n_amb_etou_dlw': '蒼山林道的惡人頭子把草帽壓低：城裡藥商的車明日要經這裡。你若肯繞道，咱們互不相擾；若不肯，就莫怪我攔路。',
        'n_amb_etou_ss': '少室山下的惡人頭子冷笑：山上的鐘敲得再響，也管不到這條小路。留下盤纏，我便當沒見過你。'
    }
    for npc_id, line in independent_dialogue.items():
        if npc_id in npcs: npcs[npc_id]['dialogue'][0] = line
    # 讓每件任務物品都有可取得的位置及一次性交付用途，不只存在於圖鑑。
    quest_givers = {}
    for quest in rows('quests'):
        for step in quest.get('steps', []):
            if step.get('item') in item_names and quest.get('giver') in npcs:
                quest_givers[item_names[step['item']]] = quest['giver']
    npc_ids = list(npcs)
    for index, (item, definition) in enumerate((k, v) for k, v in items.items() if v['quest']):
        giver = quest_givers.get(item, npc_ids[(index * 3) % len(npc_ids)])
        home = npcs[giver]['place']
        candidates = [name for name in places if places[name]['region'] == places[home]['region'] and name != home]
        pickup = candidates[index % len(candidates)] if candidates else home
        places[pickup].setdefault('finds', []).append(item)
        npcs[giver].setdefault('requests', []).append({'item': item, 'place': pickup, 'silver': 35, 'points': 25})
    for m in rows('masters'):
        if m['npc_id'] not in npcs or m['skill_id'] not in skill_names: continue
        skill = skill_names[m['skill_id']]
        if skill not in arts: continue
        requirements = []
        for req in m.get('requires', []):
            if req['type'] == 'skill_min' and req['skill'] in skill_names:
                requirements.append({'skill': skill_names[req['skill']], 'level': req['value']})
        requirements += [r for r in arts[skill]['requires'] if r not in requirements]
        npcs[m['npc_id']]['teach'].append({'skill': skill, 'cap': arts[skill]['learn_cap'] or min(arts[skill]['cap'], m['cap']),
                                         'price': max(1, m.get('price', 1)), 'requires': requirements})
    sect_data = {}
    for sid, s in sects.items():
        own = [a for a in arts.values() if a['sect'] == s['name'] and a['category'] != 'SECT']
        if not own: continue
        head = npcs.get(s['head_npc'])
        sect_data[s['name']] = {'place': names[s['gate_room']], 'master': head['name'] if head else s['name'] + '掌門',
                                'basic': next((a['name'] for a in own if a['role'] == 'EXTERNAL'), own[0]['name']),
                                'advanced': next((a['name'] for a in reversed(own) if a['role'] == 'EXTERNAL'), own[-1]['name']), 'hp': 20, 'attack': 3,
                                'style': s['sect_skill_name'] + '立身，循師承逐級學藝',
                                'virtue': s['sect_skill_name'], 'gender': s.get('gender', []),
                                'note': '本作允許自由選派；不套用原版性別限制。'}
        # 山門的知客師父可教本門修養，避免初學者卡死。
        gate_npcs = places[names[s['gate_room']]]['npcs']
        if gate_npcs:
            npcs[gate_npcs[0]]['teach'].append({'skill': s['sect_skill_name'], 'cap': 60, 'price': 1, 'requires': []})
    taught = {lesson['skill'] for npc in npcs.values() for lesson in npc['teach']}
    for skill, art in arts.items():
        if skill in taught: continue
        # 原專案部分武學由事件授予；本模擬器改為有前置條件的師父授課。
        instructor = 'n_xx_wushi'
        if art['sect']:
            own_sect = next(s for s in sects.values() if s['name'] == art['sect'])
            if own_sect['head_npc'] in npcs: instructor = own_sect['head_npc']
        elif skill == '九陰真經': instructor = 'n_gm_xiaolongnu'
        required = art['base'] or '基本內功'
        requirements = [{'skill': required, 'level': 20}] if required != skill else []
        requirements += [r for r in art['requires'] if r not in requirements]
        npcs[instructor]['teach'].append({'skill': skill, 'cap': art['learn_cap'] or 60, 'price': 5,
                                          'requires': requirements})
    # 確保 100+ 種遭遇均可在地圖實際遇見，保留原本遭遇，另加輪替池。
    wilds = [v for v in places.values() if not v['safe']]
    for i, name in enumerate(enemies):
        target = min(wilds, key=lambda w: abs(w['level'] - enemies[name]['level']) + len(w['enemies']) * .25)
        if name not in target['enemies']: target['enemies'].append(name)
    # 既有資料包含事件封閉房間。本作保留地點，增加可步行的驛道，使全部內容可達。
    for name, place in places.items():
        for other in list(place['exits']):
            if name not in places[other]['exits']: places[other]['exits'].append(name)
    start = names['xx_square']
    def reachable():
        seen, queue = {start}, [start]
        while queue:
            for dest in places[queue.pop()]['exits']:
                if dest not in seen: seen.add(dest); queue.append(dest)
        return seen
    while len(reachable()) < len(places):
        seen = reachable()
        dest = next(n for n in places if n not in seen)
        anchor = next((n for n in seen if places[n]['region'] == places[dest]['region']), start)
        places[anchor]['exits'].append(dest)
        places[dest]['exits'].append(anchor)
    catalog = {'version': 1, 'provenance': 'Converted from user project JY-Mini OL, 2026-10-19; combat and progression values adapted for this simulator.',
               'places': places, 'npcs': npcs, 'items': items, 'enemies': enemies, 'skills': arts, 'sects': sect_data,
               'entry': start}
    (ROOT / 'data').mkdir(exist_ok=True)
    (ROOT / 'data/catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: len(v) for k, v in catalog.items() if isinstance(v, dict)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=Path(r'K:\Project\JY-Mini OL\data'))
    build(parser.parse_args().source)
