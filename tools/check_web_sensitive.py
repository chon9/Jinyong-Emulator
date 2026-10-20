"""Review exact static assets, reconstruct/verify chunks, and scan the game pack before upload."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import zipfile
from check_sensitive import PATTERNS, png_metadata

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dist', type=Path, default=ROOT / 'sites/youxia-web/dist')
    args = parser.parse_args()
    directory = args.dist.resolve()
    findings = []
    files = {}
    allowed = {'index.html', 'index.js', 'index.png', 'index.icon.png', 'index.apple-touch-icon.png',
               'index.audio.worklet.js', 'index.audio.position.worklet.js', 'launcher.js', 'launcher.css',
               'landscape.png', 'asset-manifest.json', 'credits.html', 'Font-OFL.txt', 'Music-Credits.txt'}
    manifest = json.loads((directory / 'asset-manifest.json').read_text(encoding='utf-8'))
    for asset in manifest['assets']:
        allowed.update(part['url'] for part in asset['parts'])
    def scan(name, data):
        buffers = [data] + png_metadata(data)
        for kind, pattern in PATTERNS.items():
            if any(re.search(pattern, buffer) for buffer in buffers): findings.append({'file': name, 'kind': kind})
    for file in sorted(directory.rglob('*')):
        if not file.is_file(): continue
        name = file.relative_to(directory).as_posix()
        if file.is_symlink() or file.resolve().parent != directory or name not in allowed:
            findings.append({'file': name, 'kind': 'unexpected hosted asset'})
        data = file.read_bytes()
        files[name] = hashlib.sha256(data).hexdigest()
        if not file.name.endswith('.bin'): scan(name, data)
    with zipfile.ZipFile(ROOT / '.tools/appdata/Godot/export_templates/4.6.3.stable/web_nothreads_release.zip') as z:
        official_wasm = z.read('godot.wasm')
    for asset in manifest['assets']:
        parts = []
        for part in asset['parts']:
            file = (directory / part['url']).resolve()
            if file.parent != directory: raise RuntimeError('Invalid chunk path')
            data = file.read_bytes()
            if len(data) != part['size'] or hashlib.sha256(data).hexdigest() != part['sha256']: raise RuntimeError('Chunk integrity mismatch')
            parts.append(data)
        raw = gzip.decompress(b''.join(parts))
        if len(raw) != asset['size'] or hashlib.sha256(raw).hexdigest() != asset['sha256']: raise RuntimeError('Asset integrity mismatch')
        if asset['path'] == 'index.wasm':
            if raw != official_wasm: raise RuntimeError('WebAssembly differs from official Godot template')
        elif asset['path'] == 'index.pck': scan('uncompressed-game-pack', raw)
        else: raise RuntimeError('Unexpected virtual asset')
    report = {'files': files, 'verified_official_wasm': hashlib.sha256(official_wasm).hexdigest(), 'findings': findings}
    (ROOT / 'test-results/web-sensitive-scan.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({'hosted_files': len(files), 'verified_official_wasm': True, 'findings': findings}))
    return 1 if findings else 0


if __name__ == '__main__': raise SystemExit(main())
