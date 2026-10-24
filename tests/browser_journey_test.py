"""Play the shipped Godot chapter using canvas mouse input, including its ending."""
import argparse
import functools
import http.server
import json
import os
from pathlib import Path
import threading
from playwright.sync_api import sync_playwright
from browser_audio_test import PROBE, QuietHandler

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'test-results'


def run():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url')
    args = parser.parse_args()
    server = None
    if not args.url:
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(ROOT / 'sites/youxia-web/dist')))
        threading.Thread(target=server.serve_forever, daemon=True).start()
    report = {'checks': [], 'errors': []}
    try:
        with sync_playwright() as p:
            installed = sorted((Path(os.environ['LOCALAPPDATA']) / 'ms-playwright').glob('chromium-*/chrome-win/chrome.exe'))
            browser = p.chromium.launch(headless=True, executable_path=str(installed[-1]) if installed else None,
                                       args=['--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--autoplay-policy=document-user-activation-required'])
            context = browser.new_context(viewport={'width': 1440, 'height': 954}, accept_downloads=True)
            context.add_init_script(PROBE)
            page = context.new_page()
            page.on('pageerror', lambda error: report['errors'].append(str(error)))
            page.on('console', lambda message: report['errors'].append(message.text) if message.type == 'error' else None)
            url = args.url or f'http://127.0.0.1:{server.server_port}/'

            def wait(expression, timeout=30000):
                page.wait_for_function('window.youxiaChapterStatus && (' + expression + ')', timeout=timeout)

            def status():
                return page.evaluate('window.youxiaChapterStatus')

            def click(x, y):
                box = page.locator('#canvas').bounding_box()
                page.mouse.click(box['x'] + x * box['width'] / 1440, box['y'] + y * box['height'] / 900)
                page.wait_for_timeout(180)

            def check(ok, description):
                assert ok, description
                report['checks'].append(description)
                print(description, flush=True)

            def launch():
                response = page.goto(url)
                assert response.ok
                page.get_by_role('button', name='進入江湖').click()
                page.wait_for_function("document.documentElement.dataset.gameReady === 'true'", timeout=120000)
                wait('youxiaChapterStatus.page === "江湖"')

            def next_place(place):
                click(1240, 336)
                wait('youxiaChapterStatus.place === ' + json.dumps(place))
                page.wait_for_timeout(900)

            def win_battle():
                wait('youxiaChapterStatus.battle === "active"')
                click(1120, 104)
                wait('youxiaChapterStatus.battle === "victory" || youxiaChapterStatus.battle === "defeat"', 240000)
                assert status()['battle'] == 'victory', status()
                click(720, 397)
                wait('youxiaChapterStatus.battle === ""')

            def backup():
                with page.expect_download() as info:
                    page.get_by_role('button', name='匯出存檔', exact=True).click()
                return json.loads(Path(info.value.path()).read_text(encoding='utf-8'))

            launch()
            check(status()['stage'] == 0 and status()['party'] == 1, 'Default export starts the illustrated Qingxi campaign')
            page.screenshot(path=str(OUT / 'journey-browser-world.png'))
            page.wait_for_timeout(2500)
            click(1350, 37)
            page.wait_for_timeout(300)
            samples = page.evaluate('audioProbe.read()')
            check(all(item['rms'] < .000001 for item in samples), 'New in-game music control silences real browser audio')
            click(1350, 37)
            page.wait_for_timeout(1000)
            samples = page.evaluate('audioProbe.read()')
            check(any(item['rms'] > .0001 for item in samples), 'New in-game music control restores actual BGM')
            click(430, 764)
            wait('youxiaChapterStatus.stage === 1 && youxiaChapterStatus.party === 2')
            check(True, 'Opening dialogue recruits the swordsman through the visible button')
            next_place('渡口')
            click(430, 764)
            win_battle()
            check(status()['stage'] == 2, 'First real animated party encounter advances the clue')
            next_place('藥廬')
            click(430, 764)
            wait('youxiaChapterStatus.stage === 3 && youxiaChapterStatus.party === 3')
            next_place('蘆葦蕩')
            click(430, 764)
            win_battle()
            check(status()['stage'] == 4, 'Healer recruitment and reeds rescue battle form a playable second quest step')
            next_place('古寺')
            click(430, 764)
            wait('youxiaChapterStatus.stage === 5 && youxiaChapterStatus.party === 4')
            click(440, 842)
            wait('youxiaChapterStatus.page === "武學"')
            click(1248, 720)
            wait('youxiaChapterStatus.place === "演武坪"')
            page.wait_for_timeout(900)
            click(410, 764)
            click(440, 842)
            click(640, 720)
            click(640, 720)
            data = backup()
            check(data['chapter']['levels']['hero'] == 3 and data['chapter']['sect'] == '華山', 'Sect dialogue and spend-point training change the portable character build')
            click(945, 720)
            page.wait_for_timeout(5300)
            click(945, 720)
            data = backup()
            check(data['chapter']['levels']['hero'] == 4, 'Timed self-study consumes points and persists a real progression level')
            page.screenshot(path=str(OUT / 'journey-browser-martial.png'))
            click(125, 842)
            click(430, 764)
            check(backup()['chapter']['flags'].get('advanced'), 'Learning the advanced sect art checks prerequisites and unlocks it')
            next_place('舊倉')
            click(430, 764)
            wait('youxiaChapterStatus.battle === "active"')
            page.screenshot(path=str(OUT / 'journey-browser-boss.png'))
            win_battle()
            check(status()['stage'] == 6, 'Story choice and four-role party can defeat the charged-strike boss')
            next_place('青溪客棧')
            click(430, 764)
            wait('youxiaChapterStatus.stage === 7')
            check(True, 'The complete browser quest chain reaches its awarded chapter ending')
            click(640, 842)
            click(220, 712)
            wait('youxiaChapterStatus.place === "市集"')
            page.wait_for_timeout(900)
            click(640, 842)
            original = backup()['chapter']
            click(1040, 313)
            bought = backup()['chapter']
            click(1250, 313)
            sold = backup()['chapter']
            check(bought['silver'] == original['silver'] - 20 and sold['silver'] == original['silver'] - 10, 'Browser merchant buttons perform real purchase and sale transactions')
            check(sold['party'] == ['hero', 'sword', 'healer', 'staff'] and sold['stage'] == 7, 'Toolbar export includes the complete new party and story alongside the old character')
            link = page.get_by_role('link', name='Windows 最新版', exact=True)
            check(link.is_visible() and link.get_attribute('href').endswith('/releases/latest'), 'Latest Windows download stays available during gameplay')
            page.wait_for_timeout(6000)
            launch()
            check(status()['stage'] == 7 and status()['party'] == 4, 'Reload restores the completed campaign from actual IndexedDB storage')
            page.set_viewport_size({'width': 1024, 'height': 700})
            page.wait_for_timeout(1000)
            click(295, 842)
            wait('youxiaChapterStatus.page === "同伴"')
            check(True, 'Canvas navigation still works after resizing to a smaller landscape window')
            page.screenshot(path=str(OUT / 'journey-browser-small.png'))
            check(not report['errors'], 'No JavaScript or Godot console errors during the chapter playthrough')
            browser.close()
    finally:
        if server: server.shutdown(); server.server_close()
        (OUT / 'browser-journey.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'checks': len(report['checks']), 'errors': report['errors']}))


if __name__ == '__main__': run()
