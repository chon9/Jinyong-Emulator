"""Import life recipes/facilities from the user's read-only JY-Mini OL data."""
import argparse
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def build(source):
    def rows(name):
        return json.loads((source / (name + '.json')).read_text(encoding='utf-8-sig'))['rows']
    catalog = json.loads((ROOT / 'data/catalog.json').read_text(encoding='utf-8'))
    items = {v['id']: k for k, v in catalog['items'].items()}
    enemies = {v['id']: k for k, v in catalog['enemies'].items()}
    places = {v['id']: k for k, v in catalog['places'].items()}
    def convert(value):
        if isinstance(value, list):
            return [convert(v) for v in value]
        if isinstance(value, dict):
            result = {k: convert(v) for k, v in value.items()}
            for key in ['item', 'tool']:
                if result.get(key):
                    result[key] = items[result[key]]
            if 'tools' in result:
                result['tools'] = [items[v] for v in result['tools']]
            if 'monsters' in result:
                result['monsters'] = [enemies[v] for v in result['monsters']]
            return result
        return value
    skills = {}
    for raw in rows('life_skills'):
        row = convert(copy.deepcopy(raw))
        row.setdefault('mode', 'CRAFT' if row.get('recipes') and not row.get('yield') else 'GATHER')
        row['teachers'] = [convert(v) for v in rows('masters') if v['skill_id'] == raw['id']]
        assert row['teachers'] and all(not v.get('requires') for v in row['teachers'])
        assert all(v['npc_id'] in catalog['npcs'] for v in row['teachers'])
        skills[row['id']] = row
    facilities = {}
    for file in sorted((source / 'maps').glob('*.json')):
        for room in json.loads(file.read_text(encoding='utf-8-sig'))['rooms']:
            if room['id'] not in places or not room.get('features'):
                continue
            facilities[places[room['id']]] = {
                'features': room['features'],
                'hunt_table': [{'enemy': enemies[e['monster']], 'w': e.get('w', 1)}
                               for e in room.get('hunt_table', [])],
            }
    result = {'skills': skills, 'facilities': facilities}
    (ROOT / 'data/life_skills.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Life skills:', len(skills), 'recipes:', sum(len(v.get('recipes', [])) for v in skills.values()),
          'workplaces:', len(facilities))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    build(parser.parse_args().source)
