"""Publish an existing reviewed commit and ZIP using in-memory Git credentials.

Tokens are never written to disk, included in command arguments, or printed.
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def token():
    for key in ('GH_TOKEN', 'GITHUB_TOKEN'):
        if os.environ.get(key):
            return os.environ[key]
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never')
    result = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n',
                            text=True, capture_output=True, env=env, timeout=25)
    fields = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    if result.returncode or not fields.get('password'):
        raise RuntimeError('No non-interactive GitHub credential is available; sign in using Git Credential Manager or GitHub CLI.')
    return fields['password']


def api(path, credential, method='GET', body=None, binary=None):
    url = path if path.startswith('https://') else 'https://api.github.com' + path
    host = urllib.parse.urlparse(url).hostname
    if host not in ('api.github.com', 'uploads.github.com'):
        raise RuntimeError('Unexpected GitHub API host')
    headers = {'Authorization': 'Bearer ' + credential, 'Accept': 'application/vnd.github+json',
               'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'Youxia-release-tools'}
    payload = None
    if binary is not None:
        headers['Content-Type'] = 'application/zip'
        payload = binary
    elif body is not None:
        headers['Content-Type'] = 'application/json'
        payload = json.dumps(body).encode()
    request = urllib.request.Request(url, data=payload, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'GitHub API {method} failed: HTTP {error.code}') from None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['check', 'draft', 'publish', 'verify'])
    parser.add_argument('--repo', default='chon9/Jinyong-Emulator')
    parser.add_argument('--tag', default='v0.3.0')
    parser.add_argument('--commit')
    parser.add_argument('--notes', type=Path)
    parser.add_argument('--asset', type=Path)
    args = parser.parse_args()
    credential = token()
    base = '/repos/' + args.repo
    if args.action == 'check':
        user = api('/user', credential)
        repo = api(base, credential)
        print(json.dumps({'login': user['login'], 'noreply_email': f"{user['id']}+{user['login']}@users.noreply.github.com",
                          'repo': repo['full_name'], 'private': repo['private'], 'permissions': repo.get('permissions', {})}))
        return
    if args.action == 'draft':
        if not args.commit or not args.notes or not args.asset:
            parser.error('draft requires --commit --notes --asset')
        # Existing releases are left untouched; drafts can be inspected and resumed.
        releases = api(base + '/releases?per_page=100', credential)
        existing = next((r for r in releases if r['tag_name'] == args.tag), None)
        if existing and not existing['draft']:
            raise RuntimeError('This tag already has a published release; use a new version.')
        release = existing or api(base + '/releases', credential, 'POST', {
            'tag_name': args.tag, 'target_commitish': args.commit, 'name': '網金游俠模擬器 ' + args.tag,
            'body': args.notes.read_text(encoding='utf-8'), 'draft': True, 'prerelease': False})
        if existing:
            release = api(base + '/releases/' + str(release['id']), credential, 'PATCH',
                          {'body': args.notes.read_text(encoding='utf-8'), 'target_commitish': args.commit})
        if any(a['name'] == args.asset.name for a in release['assets']):
            raise RuntimeError('Draft already contains this asset; verify it before reusing the draft.')
        upload_url = release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(args.asset.name)
        uploaded = api(upload_url, credential, 'POST', binary=args.asset.read_bytes())
        print(json.dumps({'release_id': release['id'], 'draft': release['draft'], 'asset': uploaded['name'],
                          'size': uploaded['size'], 'digest': uploaded.get('digest'), 'url': release['html_url']}))
        return
    releases = api(base + '/releases?per_page=100', credential)
    release = next((r for r in releases if r['tag_name'] == args.tag), None)
    if release is None:
        raise RuntimeError('Release not found')
    if args.action == 'publish':
        if not args.asset or not any(a['name'] == args.asset.name and a['size'] == args.asset.stat().st_size for a in release['assets']):
            raise RuntimeError('Expected Windows ZIP has not been uploaded completely')
        release = api(base + '/releases/' + str(release['id']), credential, 'PATCH', {'draft': False, 'make_latest': 'true'})
    print(json.dumps({'url': release['html_url'], 'tag': release['tag_name'], 'draft': release['draft'],
                      'assets': [{'name': a['name'], 'size': a['size'], 'url': a['browser_download_url'], 'digest': a.get('digest')}
                                 for a in release['assets']]}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
