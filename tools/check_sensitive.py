"""Review the exact staged upload and optional release archive without echoing matches."""
import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    'GitHub credential': rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})',
    'AWS access key': rb'(?:AKIA|ASIA)[A-Z0-9]{16}',
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
    'service credential': rb'(?:xox[baprs]-[A-Za-z0-9-]{20,}|sk-(?:proj-)?[A-Za-z0-9_-]{35,})',
    'Steam account ID': rb'7656119[0-9]{10}',
    'personal Windows path': rb'[A-Za-z]:[\\/]+Users[\\/]+[A-Za-z0-9_. -]+[\\/]',
    'credential in URL': rb'https?://[^\s/:@]{3,}:[^\s/@]{8,}@',
}
PRIVATE_PARTS = {'.tools', '.godot', '.aws', '.ssh', '.codex', '.agents', 'userdata', 'test-results'}
PRIVATE_NAMES = {'youxia_save.json', 'youxia_identity.cfg', 'youxia_music.cfg', 'settings.json'}
RELEASE_FILES = {'Youxia.exe', 'steam_appid.txt', 'steam_api64.dll', 'libgodotsteam.windows.template_release.x86_64.dll',
                 'Asset-Credits.txt', 'Font-OFL.txt', 'GodotSteam-LICENSE.txt', 'Music-Credits.txt', '如何遊玩.txt'}


def png_metadata(data):
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        return []
    chunks, cursor = [], 8
    while cursor + 12 <= len(data):
        size = struct.unpack('>I', data[cursor:cursor + 4])[0]
        kind = data[cursor + 4:cursor + 8]
        payload = data[cursor + 8:cursor + 8 + size]
        if kind in (b'tEXt', b'iTXt', b'eXIf'):
            chunks.append(payload)
        elif kind == b'zTXt':
            try:
                chunks.append(zlib.decompress(payload.split(b'\x00', 1)[1][1:]))
            except (ValueError, zlib.error):
                pass
        cursor += size + 12
    return chunks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--asset', type=Path)
    parser.add_argument('--report', type=Path, default=ROOT / 'test-results' / 'sensitive-scan.json')
    args = parser.parse_args()
    result = subprocess.run(['git', 'ls-files', '--cached', '-z'], cwd=ROOT, capture_output=True, check=True)
    files = [s.decode('utf-8') for s in result.stdout.split(b'\x00') if s]
    if not files:
        raise RuntimeError('Nothing is staged for review')
    email_result = subprocess.run(['git', 'config', '--global', 'user.email'], capture_output=True, text=True)
    personal_email = email_result.stdout.strip().encode()
    findings, image_metadata = [], 0
    vendor_markers = {}
    template_path = ROOT / '.tools/appdata/Godot/export_templates/4.6.3.stable/windows_release_x86_64.exe'
    template = template_path.read_bytes() if template_path.exists() else b''

    def scan(name, data):
        nonlocal image_metadata
        path = Path(name)
        if PRIVATE_PARTS.intersection(path.parts) or path.name in PRIVATE_NAMES or path.name.startswith('.env') or path.suffix in ('.pem', '.key', '.pfx', '.p12', '.log'):
            findings.append({'file': name, 'kind': 'private file included'})
        buffers = [data]
        if data.startswith(b'\x89PNG'):
            metadata = png_metadata(data)
            image_metadata += len(metadata)
            buffers.extend(metadata)
        for kind, pattern in PATTERNS.items():
            # Godot's TLS parser embeds PEM header strings, without any key payload.
            # Accept only unchanged 128-byte contexts also present in the official
            # export template; newly introduced markers remain findings.
            if kind == 'private key' and path.name == 'Youxia.exe' and template:
                markers = list(re.finditer(pattern, data))
                complete = re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]{64,}-----END', data)
                if markers and not complete and all(data[max(0, m.start() - 64):m.end() + 64] in template for m in markers):
                    vendor_markers[name] = len(markers)
                    continue
            if any(re.search(pattern, buffer) for buffer in buffers):
                findings.append({'file': name, 'kind': kind})
        if personal_email and b'@users.noreply.github.com' not in personal_email:
            if any(personal_email.lower() in buffer.lower() for buffer in buffers):
                findings.append({'file': name, 'kind': 'personal commit email'})

    manifest = hashlib.sha256()
    for name in sorted(files):
        data = (ROOT / name).read_bytes()
        scan(name, data)
        manifest.update(name.encode('utf-8') + b'\x00' + hashlib.sha256(data).digest())
        staged = subprocess.run(['git', 'show', ':' + name], cwd=ROOT, capture_output=True, check=True).stdout
        canonical = data.replace(b'\r\n', b'\n') if b'\x00' not in data else data
        if staged != data and staged != canonical:
            findings.append({'file': name, 'kind': 'working file changed after staging'})
    entries = []
    digest = None
    if args.asset:
        digest = hashlib.sha256(args.asset.read_bytes()).hexdigest()
        with zipfile.ZipFile(args.asset) as archive:
            for entry in archive.infolist():
                if entry.is_dir(): continue
                entries.append(entry.filename)
                if entry.filename not in RELEASE_FILES:
                    findings.append({'file': entry.filename, 'kind': 'unexpected release file'})
                scan(entry.filename, archive.read(entry))
    report = {'staged_files': len(files), 'source_manifest_sha256': manifest.hexdigest(),
              'image_metadata_chunks_checked': image_metadata, 'release_files': entries,
              'release_sha256': digest, 'findings': findings,
              'verified_godot_tls_parser_header_strings': vendor_markers,
              'note': 'Pattern scan and exact upload-file review; not a proof that all possible secrets are absent.'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
