"""Regress the reported scribe fragment and measure isolated real battle audio."""
import argparse
import functools
import http.server
import json
import os
from pathlib import Path
import threading
from PIL import Image
from playwright.sync_api import sync_playwright
from browser_audio_test import QuietHandler, PROBE
from browser_ui_helpers import press
from browser_jianghu_story_test import status, key

ROOT = Path(__file__).resolve().parents[1]


def run():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url')
    args = parser.parse_args()
    server = None
    if not args.url:
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(ROOT/'sites/youxia-web/dist')))
        threading.Thread(target=server.serve_forever, daemon=True).start()
    report = {'checks': [], 'errors': [], 'audio': {}}
    try:
        with sync_playwright() as p:
            chrome = sorted((Path(os.environ['LOCALAPPDATA'])/'ms-playwright').glob('chromium-*/chrome-win/chrome.exe'))[-1]
            browser = p.chromium.launch(headless=True, executable_path=str(chrome), args=[
                '--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--autoplay-policy=document-user-activation-required'])
            page = browser.new_page(viewport={'width': 1440, 'height': 900}, device_scale_factor=1)
            page.add_init_script(PROBE)
            page.on('pageerror', lambda e: report['errors'].append(str(e)))
            page.on('console', lambda m: report['errors'].append(m.text) if m.type=='error' or m.text.startswith(('ERROR:', 'SCRIPT ERROR:')) else None)

            def check(ok, text):
                assert ok, text
                report['checks'].append(text)
                print(text, flush=True)

            def peak(action=None, seconds=1.1):
                page.evaluate('audioProbe.peak=0; window.soundMeter=setInterval(()=>audioProbe.read(),16)')
                try:
                    if action: action()
                    page.wait_for_timeout(seconds*1000)
                    return page.evaluate('audioProbe.peak')
                finally:
                    page.evaluate('clearInterval(soundMeter)')

            def click_slider(x, y, target):
                page.mouse.click(x, y)
                page.keyboard.press(target)
                page.wait_for_timeout(200)

            page.goto(args.url or f'http://127.0.0.1:{server.server_port}/')
            page.get_by_role('button', name='進入江湖').click()
            page.wait_for_function("document.documentElement.dataset.gameReady==='true'", timeout=180000)
            key(page, 'M'); press(page, '選擇 · 無錫城'); press(page, '進入 · 無錫城')
            press(page, '還施水閣', prefix=False); press(page, '交談 · 賀若水')
            shot = ROOT/'test-results/presentation-scribe.png'
            page.screenshot(path=str(shot))
            check('賀若水' in status(page)['dialogue_text'] or status(page)['dialogue'], 'The reported scholar dialogue opens in the actual location')
            # The former neighboring-figure shard sampled source (717..722,294..319).
            # These screen pixels lie inside its old visible brown fragment, away
            # from the retained scholar and the text. They must now be plain paper.
            image = Image.open(shot).convert('RGB')
            paper = image.getpixel((340, 650))
            samples = [image.getpixel((x, y)) for x in [330, 331] for y in range(646, 659)]
            check(all(max(abs(a-b) for a,b in zip(pixel,paper))<=3 for pixel in samples), 'The visible neighboring portrait fragment is absent; the original paper shows through')
            press(page, '×', prefix=False)
            key(page, 'F8'); press(page, '關閉音樂', prefix=False)
            check(peak()<.000001, 'Background music is genuinely silent before measuring effects')
            heard = peak(lambda: press(page, '試聽刀劍音效'))
            report['audio']['preview'] = heard
            check(heard>.025, 'The sword preview produces clearly measurable effects with music off')
            press(page, '音效 · 開', prefix=False)
            check(peak()<.000001, 'Effect mute silences output independently of music')
            press(page, '音效 · 關', prefix=False)
            check(peak(lambda: press(page, '試聽刀劍音效'))>.025, 'Effects recover after unmuting')
            click_slider(400, 538, 'Home')
            check(status(page)['sound_settings']['volume']==0 and peak()<.000001, 'Zero effect volume really silences the browser output')
            # Explicit sound-on must recover even an old saved zero-volume value.
            press(page, '音效 · 關', prefix=False)
            check(status(page)['sound_settings']['volume']>.6, 'Explicit enable recovers the previous zero-volume setting')
            check(peak(lambda: press(page, '試聽刀劍音效'))>.025, 'Recovery from zero volume is actually audible')
            # Exercise the real combat event stream, not just a sound settings button.
            key(page, 'M'); press(page, '江湖群雄')
            foes=json.loads((ROOT/'data/open_world.json').read_text(encoding='utf-8'))['enemies']
            press(page, foes['enemy_001']['name']); press(page, '前往對手所在地'); press(page, '接受挑戰')
            check(any(b['text']=='音效 開' for b in page.evaluate('youxiaUI.buttons')), 'Battle has an independent, visible effects control')
            attack_peak=peak(lambda: press(page, '進行回合'), seconds=3.3)
            report['audio']['combat'] = attack_peak
            check(attack_peak>.025, 'Real attack and impact audio are audible while battle music stays muted')
            check('fx_sword_ready' in status(page)['sounds'] and 'fx_sword_hit' in status(page)['sounds'], 'Combat emits separate preparation and hit cues')
            page.wait_for_function("youxiaUI.buttons.some(b=>b.text==='撤退'&&!b.disabled)",timeout=15000)
            press(page, '音效 開', prefix=False)
            check(peak(lambda: press(page,'進行回合'),seconds=3.3)<.000001, 'A muted battle round generates no residual sound')
            page.wait_for_function("youxiaUI.buttons.some(b=>b.text==='撤退'&&!b.disabled)",timeout=15000)
            press(page, '音效 關', prefix=False)
            page.evaluate('audioProbe.contexts.forEach(e=>e.context.suspend())')
            check(peak(lambda: press(page,'進行回合'),seconds=3.3)>.025, 'A real canvas interaction resumes audio after browser suspension')
            page.wait_for_timeout(1200)
            page.reload(); page.get_by_role('button',name='進入江湖').click()
            page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=180000)
            key(page, 'F8')
            check(status(page)['sound_settings']['enabled'] and status(page)['sound_settings']['volume']>.6, 'Recovered effects settings survive browser reload')
            check(peak(lambda: press(page,'試聽刀劍音效'))>.025, 'Actual effects remain audible after reload with music muted')
            check(not report['errors'], 'Portraits and audio run without engine or browser errors')
            browser.close()
    finally:
        if server: server.shutdown(); server.server_close()
        (ROOT/'test-results/browser-presentation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__=='__main__': run()
