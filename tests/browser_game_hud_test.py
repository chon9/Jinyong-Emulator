"""Capture the actual game HUD, modal windows and on-street walking."""
import argparse,functools,http.server,json,os,threading
from pathlib import Path
from playwright.sync_api import sync_playwright
from browser_audio_test import QuietHandler
from browser_ui_helpers import press,converse
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'test-results'
def run():
    parser=argparse.ArgumentParser()
    parser.add_argument('--combat-save',type=Path)
    args=parser.parse_args()
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(QuietHandler,directory=str(ROOT/'sites/youxia-web/dist')))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    errors=[]
    try:
        with sync_playwright() as p:
            chrome=sorted((Path(os.environ['LOCALAPPDATA'])/'ms-playwright').glob('chromium-*/chrome-win/chrome.exe'))[-1]
            browser=p.chromium.launch(headless=True,executable_path=str(chrome),args=['--enable-unsafe-swiftshader','--use-angle=swiftshader'])
            context=browser.new_context(viewport={'width':1440,'height':900},record_video_dir=str(OUT/'hud-video'),record_video_size={'width':1440,'height':900})
            page=context.new_page()
            page.on('pageerror',lambda e:errors.append(str(e)))
            page.on('console',lambda m:errors.append(m.text) if m.type=='error' else None)
            page.goto(f'http://127.0.0.1:{server.server_port}/')
            page.screenshot(path=str(OUT/'game-title.png'))
            page.get_by_role('button',name='進入江湖').click()
            page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=120000)
            page.wait_for_timeout(500)
            assert not page.locator('#game-tools').is_visible()
            bounds=page.locator('#canvas').bounding_box()
            assert bounds['y']==0 and bounds['height']==900
            page.screenshot(path=str(OUT/'game-hud-world.png'))
            press(page,'交談 ·',last=True)
            page.screenshot(path=str(OUT/'game-hud-dialogue.png'))
            converse(page)
            press(page,'前往 ·')
            page.wait_for_timeout(1800)
            page.screenshot(path=str(OUT/'game-hud-walking.png'))
            page.wait_for_function('!youxiaChapterStatus.navigating',timeout=60000)
            page.keyboard.press('Escape')
            for key,name in [('c','party'),('k','martial'),('i','inventory'),('j','journal'),('m','atlas'),('d','daily')]:
                page.keyboard.press(key)
                page.wait_for_timeout(350)
                page.screenshot(path=str(OUT/f'game-hud-{name}.png'))
                press(page,'返回江湖')
            page.set_viewport_size({'width':1024,'height':700})
            page.wait_for_timeout(500)
            press(page,'隊伍',prefix=False)
            assert page.evaluate('youxiaChapterStatus.page')=='同伴'
            page.screenshot(path=str(OUT/'game-hud-small.png'))
            if args.combat_save:
                page.set_viewport_size({'width':1440,'height':900})
                page.once('dialog',lambda dialog:dialog.accept())
                page.locator('#save-file').set_input_files(str(args.combat_save.resolve()))
                page.wait_for_function('youxiaChapterStatus.party===4 && youxiaChapterStatus.page==="江湖"')
                press(page,'前往 ·')
                page.wait_for_function('!youxiaChapterStatus.navigating',timeout=60000)
                converse(page)
                page.wait_for_function('youxiaChapterStatus.battle==="active"')
                page.screenshot(path=str(OUT/'game-hud-final-battle.png'))
                press(page,'進行回合')
                page.wait_for_timeout(1100)
                page.screenshot(path=str(OUT/'game-hud-final-strike.png'))
            assert not errors,errors
            video=page.video
            context.close()
            video.save_as(str(OUT/'game-walking.webm'))
            browser.close()
        (OUT/'game-hud.json').write_text(json.dumps({'full_canvas':True,'modal_pages':6,'small_window':True,'errors':errors}),encoding='utf-8')
        print('GAME HUD: full scene, 6 modal windows, walking capture, smaller window; no errors')
    finally:server.shutdown();server.server_close()
if __name__=='__main__':run()
