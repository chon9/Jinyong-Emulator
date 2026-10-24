"""Exercise actual downloads, retry recovery, verified cache reuse and save survival."""
import functools
import http.server
import json
import os
from pathlib import Path
import threading
from playwright.sync_api import sync_playwright
from browser_audio_test import QuietHandler

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'test-results'


def run():
    directory = ROOT / 'sites/youxia-web/dist'
    manifest = json.loads((directory / 'asset-manifest.json').read_text(encoding='utf-8'))
    parts = [part['url'] for asset in manifest['assets'] for part in asset['parts']]
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(directory)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    report = {'checks': [], 'errors': []}
    try:
        with sync_playwright() as p:
            installed = sorted((Path(os.environ['LOCALAPPDATA']) / 'ms-playwright').glob('chromium-*/chrome-win/chrome.exe'))
            browser = p.chromium.launch(headless=True, executable_path=str(installed[-1]), args=['--enable-unsafe-swiftshader', '--use-angle=swiftshader'])
            context = browser.new_context(viewport={'width': 1440, 'height': 954})
            page = context.new_page()
            page.on('pageerror', lambda error: report['errors'].append(str(error)))
            requests = []
            page.on('request', lambda req: requests.append(req.url.rsplit('/', 1)[-1]) if req.url.endswith('.bin') else None)
            failed = parts[-1]
            context.route('**/' + failed, lambda route: route.abort('connectionreset'))
            url = f'http://127.0.0.1:{server.server_port}/'

            def check(ok, text):
                assert ok, text
                report['checks'].append(text)
                print(text, flush=True)

            def ready():
                page.wait_for_function("document.documentElement.dataset.gameReady === 'true'", timeout=150000)
                check(page.evaluate('window.youxiaSceneReady && window.youxiaChapterStatus.ready'), 'Loader waits until Godot scene resources are ready')

            page.goto(url)
            page.get_by_role('button', name='進入江湖').click()
            page.locator('#failure').wait_for(state='visible', timeout=60000)
            check(page.get_by_role('button', name='重試進入江湖').is_enabled(), 'Persistent chunk failure exposes an enabled retry action')
            check(requests.count(failed) == 3, 'Failed downloads have bounded automatic retries')
            context.unroute('**/' + failed)
            page.get_by_role('button', name='重試進入江湖').click()
            ready()
            stats = page.evaluate('window.youxiaPreloadStats')
            check(stats['cachedParts'] > 0 and stats['downloadedParts'] < len(parts), 'Retry resumes verified parts instead of downloading the whole game again')
            box = page.locator('#canvas').bounding_box()
            page.mouse.click(box['x'] + 430*box['width']/1440, box['y'] + 764*box['height']/900)
            page.wait_for_function('window.youxiaChapterStatus.stage === 1')
            page.wait_for_timeout(6000)
            requests.clear()
            page.reload()
            page.get_by_role('button', name='進入江湖').click()
            ready()
            check(not requests and page.evaluate('window.youxiaPreloadStats.downloadedParts === 0'), 'Warm reload boots with zero chunk network downloads')
            check(page.evaluate('window.youxiaChapterStatus.stage === 1 && window.youxiaChapterStatus.party === 2'), 'Cache reuse preserves the actual IndexedDB story and party save')
            await_corruption = """async url => {const cache = await caches.open('youxia-verified-assets-v1'); await cache.put(url,new Response(new Uint8Array([1,2,3])));} """
            page.evaluate(await_corruption, parts[0])
            requests.clear()
            page.reload()
            page.get_by_role('button', name='進入江湖').click()
            ready()
            check(requests == [parts[0]], 'A corrupt cached part is detected and only that part is downloaded again')
            check(page.evaluate('window.youxiaChapterStatus.stage === 1'), 'Corrupt asset recovery leaves character progress intact')
            check(not report['errors'], 'Retry, reload and cache repair have no JavaScript exceptions')
            browser.close()
    finally:
        server.shutdown()
        server.server_close()
        (OUT / 'browser-preload.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    run()
