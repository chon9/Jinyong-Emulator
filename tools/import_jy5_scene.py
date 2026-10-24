"""Read an owner-supplied RPG Maker XP scene without executing Ruby or game events.

Only map geometry/tiles, passage flags and selected image names are exported.
Dialogue, event commands, saves and scripts are never included in the output.
"""
import argparse
import collections
import json
from pathlib import Path
import struct


class MarshalReader:
    def __init__(self, data):
        if data[:2] != b'\x04\x08':
            raise ValueError('Expected Ruby Marshal 4.8')
        self.data, self.pos, self.symbols, self.objects = data, 2, [], []

    def take(self, n):
        result = self.data[self.pos:self.pos+n]
        if len(result) != n: raise ValueError('Truncated Marshal input')
        self.pos += n
        return result

    def integer(self):
        c = struct.unpack('b', self.take(1))[0]
        if c == 0: return 0
        if c > 4: return c - 5
        if c < -4: return c + 5
        raw = self.take(abs(c))
        return int.from_bytes(raw, 'little') - (1 << (8 * abs(c)) if c < 0 else 0)

    def register(self, value):
        self.objects.append(value)
        return value

    @staticmethod
    def decode(data):
        for encoding in ['utf-8', 'gb18030']:
            try: return data.decode(encoding)
            except UnicodeDecodeError: pass
        return data.decode('latin1')

    def read(self):
        kind = self.take(1)
        if kind == b'0': return None
        if kind == b'T': return True
        if kind == b'F': return False
        if kind == b'i': return self.integer()
        if kind == b':':
            value = self.decode(self.take(self.integer()))
            self.symbols.append(value)
            return value
        if kind == b';': return self.symbols[self.integer()]
        if kind == b'@': return self.objects[self.integer()]
        if kind == b'"': return self.register(self.decode(self.take(self.integer())))
        if kind == b'[':
            out = self.register([])
            for _ in range(self.integer()): out.append(self.read())
            return out
        if kind in [b'{', b'}']:
            out = self.register({})
            for _ in range(self.integer()):
                key = self.read()
                out[key] = self.read()
            if kind == b'}': self.read()
            return out
        if kind == b'o':
            out = self.register({'_class': self.read()})
            for _ in range(self.integer()):
                key = self.read()
                out[key] = self.read()
            return out
        if kind == b'u':
            name = self.read()
            return self.register({'_class': name, 'data': self.take(self.integer())})
        if kind == b'I':
            value = self.read()
            for _ in range(self.integer()): self.read(); self.read()
            return value
        if kind == b'f': return self.register(float(self.take(self.integer()).decode('ascii')))
        raise ValueError('Unsupported Marshal type: ' + repr(kind))


def load(path):
    return MarshalReader(path.read_bytes()).read()


def table(value):
    data = value['data']
    dimensions, width, height, depth, count = struct.unpack_from('<5I', data)
    return width, height, depth, list(struct.unpack_from('<' + str(count) + 'h', data, 20))


def export_navigation(scene, destination):
    """Export only directional street geometry, with no source paths or event data."""
    w, h = scene['width'], scene['height']
    passages = []
    for y in range(h):
        for x in range(w):
            blocked = 0
            for bit in (1, 2, 4, 8):
                for z in range(scene['depth'] - 1, -1, -1):
                    tile = scene['tiles'][(z*h+y)*w+x]
                    if not tile:
                        continue
                    if scene['passages'][tile] & bit:
                        blocked |= bit
                        break
                    if scene['priorities'][tile] == 0:
                        break
            passages.append(blocked)
    start = (35, 40)
    seen = {start}
    pending = collections.deque([start])
    while pending:
        x, y = pending.popleft()
        for dx, dy, bit, opposite in [(0,1,1,8),(-1,0,2,4),(1,0,4,2),(0,-1,8,1)]:
            nx, ny = x+dx, y+dy
            if 0 <= nx < w and 0 <= ny < h and (nx,ny) not in seen and not passages[y*w+x] & bit and not passages[ny*w+nx] & opposite:
                seen.add((nx,ny))
                pending.append((nx,ny))
    landmarks = {'青溪客棧': (1140,1280), '渡口': (800,2130), '藥廬': (2050,1760),
                 '蘆葦蕩': (2900,1150), '古寺': (2810,570), '市集': (2280,1830),
                 '演武坪': (1970,1030), '舊倉': (330,980)}
    anchors = {key: list(min(seen, key=lambda c: (c[0]*32+16-target[0])**2+(c[1]*32+16-target[1])**2)) for key, target in landmarks.items()}
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps({'width':w, 'height':h, 'passages':passages, 'anchors':anchors}, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--map', type=int)
    parser.add_argument('--output', type=Path, default=Path('.tools/jy5-scene.json'))
    parser.add_argument('--navigation', type=Path)
    args = parser.parse_args()
    if args.map is None:
        info = load(args.source / 'Data/MapInfos.rxdata')
        print(json.dumps({k: v.get('@name') for k, v in info.items()}, ensure_ascii=False))
        return
    scene = load(args.source / ('Data/Map%03d.rxdata' % args.map))
    tileset = load(args.source / 'Data/Tilesets.rxdata')[scene['@tileset_id']]
    w, h, z, tiles = table(scene['@data'])
    result = {'width': w, 'height': h, 'depth': z, 'tiles': tiles,
              'tileset': str(args.source / 'Graphics/Tilesets' / (tileset['@tileset_name'] + '.png')),
              'panorama': str(args.source / 'Graphics/Panoramas' / (tileset['@panorama_name'] + '.png')),
              'autotiles': tileset.get('@autotile_names', []),
              'passages': table(tileset['@passages'])[3], 'priorities': table(tileset['@priorities'])[3]}
    if not Path(result['tileset']).exists(): result['tileset'] = str(Path(result['tileset']).with_suffix('.jpg'))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False), encoding='utf-8')
    if args.navigation:
        if args.map != 44:
            raise ValueError('The selected Qingxi landmark layout requires map 44.')
        export_navigation(result, args.navigation)
    print(json.dumps({k: v for k, v in result.items() if k not in ['tiles', 'passages', 'priorities']}, ensure_ascii=False))


if __name__ == '__main__': main()
