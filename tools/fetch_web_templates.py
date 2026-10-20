"""Fetch only the official Web template from the large Godot template ZIP via HTTP ranges."""
import argparse
import io
from pathlib import Path
import re
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz'


class RemoteZip(io.RawIOBase):
    def __init__(self):
        with urllib.request.urlopen(urllib.request.Request(URL, method='HEAD', headers={'User-Agent': 'Youxia-web-export'}), timeout=60) as response:
            length = int(response.headers['Content-Length'])
        request = urllib.request.Request(URL, headers={'Range': f'bytes={length - 65536}-{length - 1}', 'User-Agent': 'Youxia-web-export'})
        with urllib.request.urlopen(request, timeout=60) as response:
            content_range = response.headers.get('Content-Range', '')
            match = re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)', content_range)
            if response.status != 206 or not match:
                raise RuntimeError('Official download did not accept partial requests; no full archive was downloaded.')
            self.size = int(match[3])
            self.tail_start = int(match[1])
            self.tail = response.read()
            self.url = response.url
        self.position = 0

    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.position

    def seek(self, offset, whence=0):
        self.position = offset if whence == 0 else self.position + offset if whence == 1 else self.size + offset
        return self.position

    def read(self, size=-1):
        size = min(self.size - self.position, size if size >= 0 else self.size)
        if size <= 0: return b''
        start = self.position
        if start >= self.tail_start:
            result = self.tail[start - self.tail_start:start - self.tail_start + size]
        else:
            if size > 80 * 1024 * 1024: raise RuntimeError('Unexpectedly large template member')
            request = urllib.request.Request(self.url, headers={'Range': f'bytes={start}-{start + size - 1}', 'User-Agent': 'Youxia-web-export'})
            with urllib.request.urlopen(request, timeout=120) as response:
                expected = f'bytes {start}-{start + size - 1}/{self.size}'
                if response.status != 206 or response.headers.get('Content-Range') != expected:
                    raise RuntimeError('Invalid partial download response')
                result = response.read()
        self.position += len(result)
        return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT / '.tools/appdata/Godot/export_templates/4.6.3.stable')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    names = ['web_nothreads_release.zip', 'web_nothreads_debug.zip']
    if all((args.output / name).exists() for name in names):
        print('Web release template already installed')
        return
    with zipfile.ZipFile(RemoteZip()) as archive:
        for name in ['templates/' + n for n in names] + ['templates/version.txt']:
            info = archive.getinfo(name)
            data = archive.read(info)  # zipfile verifies the official archive member CRC.
            destination = args.output / Path(name).name
            destination.write_bytes(data)
            print(destination.name, len(data), 'bytes')


if __name__ == '__main__': main()
