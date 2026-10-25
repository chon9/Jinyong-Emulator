"""Read-only alpha analysis: describe quads excluding other atlas figures.

No image files are written. Source art, detached weapons and transparent padding
stay intact; only pixels belonging to a different large figure are excluded.
Requires numpy, opencv-python and Pillow.
"""
import hashlib
import json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def quads(forbidden):
    height, width = forbidden.shape
    strips, active = [], {}
    for y in range(height):
        padded = np.pad(~forbidden[y], (1, 1)).astype(np.int8)
        edges = np.flatnonzero(np.diff(padded))
        next_active = {}
        for left, right in zip(edges[::2], edges[1::2]):
            key = (int(left), int(right-left))
            if key in active:
                strip = active[key]
                strip[3] += 1
            else:
                strip = [key[0], y, key[1], 1]
                strips.append(strip)
            next_active[key] = strip
        active = next_active
    return strips


def main():
    data = json.loads((ROOT/'data/character_art.json').read_text())['characters']
    for name in ['open_art', 'visual_art', 'companion_art', 'support_art']:
        data.update(json.loads((ROOT/f'data/{name}.json').read_text()))
    sheets = {}
    for key, entry in data.items():
        sheets.setdefault(entry['texture'], []).append((key, entry))
    masks, audit = {}, []
    for texture, entries in sheets.items():
        path = (ROOT/'assets/characters'/texture).resolve()
        with Image.open(path) as source:
            alpha = np.asarray(source.convert('RGBA'))[:, :, 3]
        _, labels, stats, _ = cv2.connectedComponentsWithStats((alpha >= 96).astype(np.uint8), 8)
        large = np.flatnonzero(stats[:, cv2.CC_STAT_AREA] > 500)
        large = large[large != 0]
        # A detached weapon or ornament is not another person. Only remove a
        # component identified as the principal body of another indexed frame.
        owners = set()
        for _, entry in entries:
            for frame in entry['frames']:
                x, y, w, h = map(int, frame['region'])
                counts = np.bincount(labels[y:y+h, x:x+w].ravel(), minlength=len(stats))
                owners.add(int(large[np.argmax(counts[large])]))
        bodies = np.array(sorted(owners))
        for key, entry in entries:
            for pose, frame in enumerate(entry['frames']):
                x, y, w, h = map(int, frame['region'])
                cell = labels[y:y+h, x:x+w]
                counts = np.bincount(cell.ravel(), minlength=len(stats))
                own = int(large[np.argmax(counts[large])])
                other = bodies[(bodies != own) & (counts[bodies] > 0)]
                if not len(other):
                    continue
                # Include antialiasing around foreign cores; never erase own core.
                foreign = np.isin(cell, other).astype(np.uint8)
                forbidden = cv2.dilate(foreign, np.ones((7, 7), np.uint8)).astype(bool)
                protected = cv2.dilate((cell == own).astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)
                forbidden &= ~protected
                strips = quads(forbidden)
                masks.setdefault(key, {})[str(pose)] = strips
                assert not np.any(forbidden[cell == own]), (key, pose, 'Own body lost')
                assert np.all(forbidden[np.isin(cell, other)]), (key, pose, 'Foreign body retained')
                audit.append({'actor': key, 'pose': pose, 'foreign_pixels': int(np.count_nonzero(np.isin(cell, other))),
                              'retained_body_pixels': int(counts[own]), 'quads': len(strips)})
        print(texture, flush=True)
    assert 'npc_17' in masks, 'The reported scribe/neighbor fragment must be masked'
    (ROOT/'data/character_masks.json').write_text(json.dumps(masks, separators=(',', ':'))+'\n', encoding='utf-8')
    report = {'frames': sum(len(v['frames']) for v in data.values()), 'masked': audit,
              'source_sha256': {t: hashlib.sha256((ROOT/'assets/characters'/t).read_bytes()).hexdigest() for t in sheets}}
    (ROOT/'test-results/character-mask-audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(f'Checked {report["frames"]} frames; masked {len(audit)} contaminated rectangles, preserving every own core pixel.')


if __name__ == '__main__':
    main()
