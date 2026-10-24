"""Run the actual exported Godot game in Chromium, including browser save round-trips."""
import functools
import http.server
import json
import os
from pathlib import Path
import threading
import subprocess
import time
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / 'sites/youxia-web/dist'
OUTPUT = ROOT / 'test-results'


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass


def run():
    errors = []
    checks = []
    def check(ok, description):
        checks.append(description)
        if not ok: raise AssertionError(description)
    handler = functools.partial(QuietHandler, directory=str(DIST))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    host_process = None
    host_log = None
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with sync_playwright() as p:
            installed = sorted((Path(os.environ['LOCALAPPDATA']) / 'ms-playwright').glob('chromium-*/chrome-win/chrome.exe'))
            browser = p.chromium.launch(headless=True, executable_path=str(installed[-1]) if installed else None,
                                        args=['--enable-unsafe-swiftshader', '--use-angle=swiftshader'])
            context = browser.new_context(viewport={'width': 1440, 'height': 954}, accept_downloads=True)
            page = context.new_page()
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.on('console', lambda message: errors.append(message.text) if message.type == 'error' else None)
            def launch():
                response = page.goto(f'http://127.0.0.1:{server.server_port}/')
                check(response.ok, 'Static browser entry responds successfully')
                page.get_by_role('button', name='進入江湖').click()
                page.wait_for_function("document.documentElement.dataset.gameReady === 'true'", timeout=90000)
                page.wait_for_timeout(1500)
                # The new campaign is default; this suite covers retained legacy networking.
                page.locator('#canvas').focus()
                page.keyboard.press('F9')
                page.wait_for_timeout(500)
            page.goto(f'http://127.0.0.1:{server.server_port}/')
            page.screenshot(path=str(OUTPUT / 'web-launcher.png'))
            launch()
            check(page.locator('#canvas').is_visible(), 'Exported Godot canvas starts with real WebAssembly')
            page.screenshot(path=str(OUTPUT / 'web-game.png'))
            def backup():
                with page.expect_download() as info:
                    page.get_by_role('button', name='匯出存檔', exact=True).click()
                return json.loads(Path(info.value.path()).read_text(encoding='utf-8'))
            data = backup()
            check(data['version'] == 1 and 'skills' in data['character'], 'Browser toolbar exports the real character state')
            data['character']['name'] = '網頁驗證'
            data['character']['silver'] = 789
            data['character']['life_levels'] = {'life_fishing': 12}
            data['character']['life_prof'] = {'life_fishing': 288}
            data['character']['inventory']['魚竿'] = 1
            fixture = OUTPUT / 'web-import-fixture.json'
            fixture.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
            page.once('dialog', lambda dialog: dialog.accept())
            page.locator('#save-file').set_input_files(str(fixture))
            page.wait_for_timeout(1200)
            restored = backup()
            check(restored['character']['name'] == '網頁驗證' and restored['character']['silver'] == 789,
                  'Import replaces the local character through the real file input and callback')
            # Navigate using real canvas pointer input, preserving the classic 1440 x 900 UI.
            page.mouse.click(967, 54 + 82)
            page.wait_for_function("document.documentElement.dataset.gamePage === '生活'")
            check(page.locator('.toolbar').bounding_box()['y'] == 0 and page.locator('#canvas').bounding_box()['height'] == 900,
                  'Canvas fits beneath the fixed toolbar without cutting off the HUD')
            page.screenshot(path=str(OUTPUT / 'web-life.png'))
            # Browser file-system persistence must survive reload, not just JS memory.
            page.wait_for_timeout(1000)
            launch()
            persisted = backup()
            check(persisted['character']['name'] == '網頁驗證' and persisted['character']['life_levels']['life_fishing'] == 12,
                  'IndexedDB keeps character and life progression across a real page reload')
            # Use the browser's real WebSocket implementation against a native host.
            host_log = (OUTPUT / 'browser-websocket-host.log').open('w', encoding='utf-8')
            environment = dict(os.environ, APPDATA=str(ROOT / '.tools/websocket-browser-appdata'),
                               LOCALAPPDATA=str(ROOT / '.tools/websocket-browser-local'))
            host_process = subprocess.Popen([
                'K:/Godot/Godot_v4.6.3-stable_win64_console.exe', '--headless', '--path', str(ROOT),
                '--script', 'res://scripts/web_host.gd', '--', '--no-steam',
                '--test-profile=browser-host-' + str(os.getpid()), '--web-port=24783'],
                env=environment, stdout=host_log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                if 'host ready' in (OUTPUT / 'browser-websocket-host.log').read_text(encoding='utf-8'): break
                time.sleep(.1)
            def command(text):
                page.mouse.click(500, 54 + 830)
                page.keyboard.type(text)
                page.keyboard.press('Enter')
            command('web ws://127.0.0.1:24783')
            page.wait_for_function("document.documentElement.dataset.networkMode === 'WebSocket 客戶端'", timeout=20000)
            check(True, 'Actual browser WebSocket connects and receives the host-authoritative snapshot')
            check(not errors, 'No browser or Godot errors: ' + str(errors))
            context.close()
            browser.close()
            time.sleep(.5)
            saved = json.loads((OUTPUT / ('browser-host-' + str(os.getpid()) + '.json')).read_text(encoding='utf-8'))
            check(any(guest['name'] == '網頁驗證' for guest in saved['guests'].values()),
                  'Native host persists the actual browser guest after disconnection')
    finally:
        if host_process:
            host_process.terminate()
            host_process.wait(timeout=10)
        if host_log: host_log.close()
        server.shutdown()
        server.server_close()
        (OUTPUT / 'browser-web-result.json').write_text(json.dumps({'checks': checks, 'errors': errors}, ensure_ascii=False, indent=2), encoding='utf-8')
    print('BROWSER WEB:', len(checks), 'checks passed')


if __name__ == '__main__': run()
