"""Create portable, verified browser assets small enough for static Site hosting."""
import argparse
import gzip
import hashlib
import json
import re
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]


def package(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    # Only remove generated chunk files owned by this packager; retain other source.
    for old in destination.glob('index.*.bin'):
        if re.fullmatch(r'index\.(wasm|pck)\.(?:[a-f0-9]{12}\.)?\d+\.bin', old.name) and old.resolve().parent == destination.resolve(): old.unlink()
    for file in source.iterdir():
        if file.is_file() and file.suffix not in ['.wasm', '.pck']:
            shutil.copy2(file, destination / file.name)
    for name in ['launcher.js', 'launcher.css', 'credits.html']:
        shutil.copy2(ROOT / 'web' / name, destination / name)
    shutil.copy2(ROOT / 'assets/fonts/OFL.txt', destination / 'Font-OFL.txt')
    shutil.copy2(ROOT / 'assets/bgm/SOURCE.txt', destination / 'Music-Credits.txt')
    shutil.copy2(ROOT / 'assets/classic/bg_dali_wild.png', destination / 'landscape.png')
    manifest = {'version': 1, 'assets': []}
    for name in ['index.wasm', 'index.pck']:
        raw = (source / name).read_bytes()
        compressed = gzip.compress(raw, compresslevel=9, mtime=0)
        tag = hashlib.sha256(compressed).hexdigest()[:12]
        item = {'path': name, 'size': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(), 'encoding': 'gzip', 'parts': []}
        for n, start in enumerate(range(0, len(compressed), 8 * 1024 * 1024)):
            part = compressed[start:start + 8 * 1024 * 1024]
            filename = name + f'.{tag}.{n:02}.bin'
            (destination / filename).write_bytes(part)
            item['parts'].append({'url': filename, 'size': len(part), 'sha256': hashlib.sha256(part).hexdigest()})
        manifest['assets'].append(item)
    (destination / 'asset-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'download_bytes': sum(p['size'] for a in manifest['assets'] for p in a['parts']),
                      'largest_asset': max(p.stat().st_size for p in destination.iterdir() if p.is_file())}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT / 'build/web-raw')
    parser.add_argument('--output', type=Path, default=ROOT / 'sites/youxia-web/dist')
    args = parser.parse_args()
    package(args.source, args.output)
