"""Read reference quest definitions, retaining room interactions and test paths.

Only explicitly selected stories are added. The reference project is never written.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDITIONS = [
    'q_liu_jinpen', 'q_liu_jinpen_2', 'q_yuner', 'q_lj_chengqingshuang',
    'q_yangkang', 'q_mailu_shangren', 'q_liangfa', 'q_qingwei',
    'q_qz_paotui', 'q_qz_jiangqingrui', 'q_qz_wangchuyi', 'q_gb_xin',
    'q_jc_zhangyuanwai', 'q_ym_tuoyin', 'q_ym_xiaofeng', 'q_sm_esi_nongfu',
    'q_sm_ahuo', 'q_sm_ahong', 'q_sm_rixing', 'q_sm_litong',
]


def build(source):
    def read(path):
        return json.loads(path.read_text(encoding='utf-8-sig'))
    def rows(name):
        return read(source / (name + '.json'))['rows']
    catalog = read(ROOT / 'data/catalog.json')
    original = read(ROOT / 'data/learning_quests.json')
    sects = {s['id']: s['name'] for s in rows('sects')}
    skills = {s['id']: s['name'] for s in rows('basic_skills') + rows('martial_arts')}
    skills.update({s['sect_skill']: s['sect_skill_name'] for s in rows('sects')})
    items = {i['id']: i for i in rows('items')}
    monsters = {m['id']: m for m in rows('monsters')}
    texts = {t['id']: t.get('self', '') for t in rows('text_templates')}
    regions = {r['id']: r['name'] for r in rows('regions')}
    rooms = {r['id']: regions[m['region_id']] + '・' + r['name']
             for f in sorted((source / 'maps').glob('*.json'))
             for m in [read(f)] for r in m['rooms']}
    quests = {q['id']: q for q in rows('quests')}
    item_names = {key: row['name'] for key, row in items.items()}
    enemy_names = {key: row['name'] for key, row in monsters.items()}

    def convert(value):
        if isinstance(value, list):
            return [convert(v) for v in value]
        if not isinstance(value, dict):
            return value
        out = {}
        for key, val in value.items():
            if key in ('src_note', 'test_plan'):
                continue
            if key == 'sect': out[key] = sects.get(val, val)
            elif key == 'item': out[key] = item_names.get(val, val)
            elif key == 'skill': out[key] = skills.get(val, val)
            elif key in ('learn', 'learn_add', 'skill_prof') and isinstance(val, dict) and all(isinstance(n, (int, float)) for n in val.values()):
                out[key] = {skills.get(s, s): n for s, n in val.items()}
            elif key == 'monsters': out['enemies'] = [enemy_names[m] for m in val]
            elif key in ('room', 'to_room', 'hint_room'): out[key] = rooms.get(val, val)
            elif key == 'items' and isinstance(val, list):
                out[key] = [{'item': item_names[i.get('item', i.get('id'))], 'n': i.get('n', 1)} for i in val]
            else: out[key] = convert(val)
        if value.get('do') == 'tell': out['text'] = texts.get(value.get('key'), '請依線索繼續。')
        return out

    def walk(value):
        if isinstance(value, dict):
            yield value
            for v in value.values(): yield from walk(v)
        elif isinstance(value, list):
            for v in value: yield from walk(v)

    selected = set(original) | set(ADDITIONS)
    for qid in sorted(selected):
        raw = quests.get(qid)
        if not raw or not raw.get('stages'):
            continue
        q = copy.deepcopy(original.get(qid, {}))
        q.update({'id': qid, 'name': raw['name'], 'giver': raw['giver'],
                  'conditions': convert(raw.get('requires', [])), 'start': raw.get('start', ''),
                  'offer': raw.get('offer', ''), 'stages': [], 'dialogues': convert(raw.get('dialogues', {})),
                  'repeat': raw.get('repeat', {'max': 1, 'cooldown_days': 0}),
                  'give_items': [{'item': item_names[i['id']], 'n': i.get('n', 1)} for i in raw.get('give_items', [])],
                  'source_status': raw.get('src', 'proposal'),
                  'note': '來源故事的文字改編；場景互動與考較經本作主機結算，不聲稱官方原版完整重製。'})
        fights = {a.get('obj'): a for a in walk(raw) if a.get('do') == 'fight' and a.get('obj')}
        for stage in raw['stages']:
            st = convert(stage)
            st['title'] = stage.get('title', stage['id'])
            st['log'] = stage.get('log', '')
            st['place'] = rooms.get(stage.get('hint_room'), '')
            st.setdefault('on_enter', [])
            st.setdefault('on_complete', [])
            st.setdefault('room_actions', [])
            for o in st.get('objectives', []):
                o.setdefault('requires', [])
                if o['id'] in fights:
                    fight = fights[o['id']]
                    o['enemies'] = [enemy_names[m] for m in fight.get('monsters', [])]
                    o['no_flee'] = fight.get('no_flee', False)
                else: o.setdefault('enemies', [])
                if o['type'] == 'KILL': o['enemy_name'] = enemy_names[o['monster']]
                for act in st['room_actions']:
                    if any(a.get('obj') == o['id'] for a in act.get('do', [])):
                        o['place'] = act['room']
                        o['action'] = act['id']
                        o['hours'] = act.get('hours', [])
            q['stages'].append(st)
        if qid not in original:
            q['outcomes'] = convert(raw.get('outcomes', {}))
        original[qid] = q

    needed_items = {x['item'] for qid in selected for x in walk(quests[qid]) if isinstance(x.get('item'), str)}
    needed_items |= {i.get('id', i.get('item')) for qid in selected for x in walk(quests[qid]) for i in x.get('items', []) if isinstance(i, dict)}
    extra_items = {}
    for iid in needed_items:
        if iid not in items or items[iid]['name'] in catalog['items']: continue
        item = items[iid]
        extra_items[item['name']] = {'id': iid, 'price': max(1, item.get('price', 1)), 'type': item['tab'],
            'weapon_type': item.get('weapon_type', ''), 'attack': item.get('atk', 0), 'defense': item.get('def', 0),
            'desc': item.get('desc', ''), 'quest': item.get('quest_item', False), 'restore': {}, 'attr_bonus': {},
            'sellable': not item.get('no_sell', False)}
    support = {'items': extra_items}
    (ROOT / 'data/learning_quests.json').write_text(json.dumps(original, ensure_ascii=False, indent=2), encoding='utf-8')
    (ROOT / 'data/quest_support.json').write_text(json.dumps(support, ensure_ascii=False, indent=2), encoding='utf-8')
    # Source paths are test evidence, kept out of releases and Git.
    plans = {'rooms': rooms, 'sects': sects, 'skills': skills, 'items': item_names,
             'quests': {qid: {k: quests[qid].get(k) for k in ['requires', 'test_plan']} for qid in selected}}
    (ROOT / 'test-results/reference-quest-plans.json').write_text(json.dumps(plans, ensure_ascii=False, indent=2), encoding='utf-8')
    cases = {}
    def accept_path(nodes, node_id, seen=None):
        seen = set() if seen is None else seen
        if node_id in seen: return None
        seen = seen | {node_id}
        node = nodes.get(node_id, {})
        if any(a.get('do') == 'accept' for a in node.get('do', [])): return []
        for choice in node.get('choices', []):
            if any(a.get('do') == 'accept' for a in choice.get('do', [])):
                return [(node_id, choice['id'])]
            tail = accept_path(nodes, choice.get('goto', 'END'), seen)
            if tail is not None: return [(node_id, choice['id'])] + tail
        if node.get('goto') and not node.get('choices'):
            return accept_path(nodes, node['goto'], seen)
        return None
    tested = ADDITIONS + ['q_wd_heiyu', 'q_wd_longmen', 'q_gb_dai1', 'q_gb_dai2', 'q_hs_spy', 'q_xd_xuehai']
    for qid in tested:
        plan = quests[qid]['test_plan'][0]
        setup = copy.deepcopy(plan.get('setup', {}))
        setup['sect'] = sects.get(setup.get('sect'), '江湖散人')
        setup['skills'] = {skills.get(s, s): n for s, n in setup.get('skills', {}).items()}
        setup['items'] = {item_names.get(i, i): n for i, n in setup.get('items', {}).items()}
        path = []
        for index, step in enumerate(plan['path']):
            path.append('walk@' + rooms[step.split('@')[1]] if step.startswith('walk@') else step)
            if step.startswith('accept@'):
                npc = step.split('@')[1]
                if qid == 'q_lj_chengqingshuang':
                    path += ['choose@%s:n0:c_no' % npc, 'reopen@' + npc]
                next_step = plan['path'][index + 1] if index + 1 < len(plan['path']) else ''
                if not next_step.startswith('choose@' + npc + ':'):
                    offer = quests[qid].get('dialogues', {}).get(quests[qid].get('offer', ''), {})
                    for node, choice in accept_path(offer.get('nodes', {}), offer.get('start', 'n0')) or []:
                        path.append('choose@%s:%s:%s' % (npc, node, choice))
        cases[qid] = {'setup': setup, 'path': path, 'outcome': plan.get('outcome', 'default'),
                      'expect_items': {item_names.get(i, i): n for i, n in plan.get('expect', {}).get('items', {}).items()},
                      'expect_flags': plan.get('expect', {}).get('flags', []),
                      'repeat_cooldown': plan.get('expect', {}).get('repeat_cooldown', False)}
    fixtures = ROOT / 'tests/fixtures'
    fixtures.mkdir(exist_ok=True)
    (fixtures / 'quest_paths.json').write_text(json.dumps(cases, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'quests': len(original), 'added': len(ADDITIONS), 'support_items': len(extra_items),
                      'source_sha256': hashlib.sha256((source / 'quests.json').read_bytes()).hexdigest()}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=Path(r'K:\Project\JY-Mini OL\data'))
    build(parser.parse_args().source)
