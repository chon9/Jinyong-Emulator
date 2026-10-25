"""Real canvas navigation and screenshots for the open-world release."""
import functools, http.server, json, os, threading
from pathlib import Path
from playwright.sync_api import sync_playwright
from browser_audio_test import QuietHandler
from browser_ui_helpers import press
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'test-results'
def run():
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(QuietHandler,directory=str(ROOT/'sites/youxia-web/dist')))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    report={'checks':[],'errors':[]}
    try:
      with sync_playwright() as p:
        installed=sorted((Path(os.environ['LOCALAPPDATA'])/'ms-playwright').glob('chromium-*/chrome-win/chrome.exe'))
        browser=p.chromium.launch(headless=True,executable_path=str(installed[-1]),args=['--enable-unsafe-swiftshader','--use-angle=swiftshader'])
        page=browser.new_page(viewport={'width':1440,'height':900},device_scale_factor=1)
        page.on('pageerror',lambda e:report['errors'].append(str(e)))
        page.on('console',lambda m:report['errors'].append(m.text) if m.type=='error' or m.text.startswith(('ERROR:','SCRIPT ERROR:','Parse Error:')) else None)
        def check(ok,text):
            assert ok,text
            report['checks'].append(text)
            print(text,flush=True)
        def status():return page.evaluate('window.youxiaChapterStatus')
        def shot(name):
            page.wait_for_timeout(350)
            page.screenshot(path=str(OUT/f'open-{name}.png'))
        def key(k):page.locator('#canvas').focus();page.keyboard.press(k);page.wait_for_timeout(260)
        page.goto(f'http://127.0.0.1:{server.server_port}/')
        page.get_by_role('button',name='進入江湖').click()
        page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=150000)
        check(status()['region']=='牛家村' and not status()['battle'],'New player starts exploring a peaceful village')
        shot('village')
        press(page,'交談 · 穆念慈')
        check(status()['dialogue']=='jy24','Floating portrait opens the matching dialogue')
        shot('dialogue')
        press(page,'邀請同行')
        check('jy24' in status()['roster'] and status()['stage']==0,'Free recruitment works before any chapter progress')
        press(page,'委託與故事');press(page,'接下委託')
        shot('quests')
        check(status()['quests']['friend_jy24']['step']==0,'Optional quest can be accepted through conversation')
        press(page,'交談辦理');press(page,'處理委託')
        check(status()['quests']['friend_jy24']['step']==1,'Quest journal leads to a working conversation')
        key('J');press(page,'前往目標')
        check(status()['scene']=='牛家客棧' and status()['quests']['friend_jy24']['step']==2,'Quest navigation enters the requested peaceful scene and records its visit')
        key('J');press(page,'公開查驗來往證詞')
        check(status()['quests']['friend_jy24']['step']==3,'Story choice is recorded before returning to the quest giver')
        press(page,'前往目標');press(page,'處理委託')
        check(status()['quests']['friend_jy24']['status']=='done','Full optional quest reaches its rewarded ending through visible controls')
        press(page,'×',prefix=False)
        press(page,'牛家客棧',prefix=False);press(page,'交談 · 黃蓉');press(page,'邀請同行')
        check('jy02' in status()['roster'],'A second named hero recruits independently')
        key('I');shot('inventory')
        press(page,'購買 ·');check('購買' in status()['notice'] or '買入' in status()['notice'],'Local merchant purchase succeeds')
        press(page,'出售 ·');check('出售' in status()['notice'] or '售出' in status()['notice'],'Local merchant sale succeeds')
        key('C');shot('party')
        key('K');shot('martial')
        key('M');shot('atlas')
        press(page,'江湖群雄');shot('enemies')
        press(page,'前往對手所在地')
        check(status()['battle']=='','Entering an opponent location does not start a battle')
        press(page,'接受挑戰')
        check(status()['battle']=='active','Combat requires explicit challenge confirmation')
        shot('battle')
        press(page,'施招',prefix=True) if any(b['text'].startswith('施招') and not b['disabled'] for b in page.evaluate('youxiaUI.buttons')) else None
        press(page,'進行回合')
        page.wait_for_timeout(700);shot('battle-action')
        # Leave combat with the visible retreat control, preserving the optional story.
        page.wait_for_function("youxiaUI.buttons.some(b=>b.text==='撤退'&&!b.disabled)", timeout=15000)
        press(page,'撤退')
        if status()['battle']:press(page,'返回江湖')
        press(page,'返回街巷');shot('streets')
        key('F8');shot('settings')
        press(page,'刪除存檔／重新開始');shot('reset-confirmation')
        page.keyboard.press('Escape');page.wait_for_timeout(300)
        check('jy02' in status()['roster'],'Cancelling deletion keeps progress')
        press(page,'刪除存檔／重新開始')
        # Click the modal's affirmative button; cancel remains the default focus.
        page.mouse.click(615,544);page.wait_for_timeout(600)
        report['after_reset']=status()
        check(status()['roster']==['hero'] and status()['quests']=={},'Confirmed reset clears the actual browser save')
        page.reload();page.get_by_role('button',name='進入江湖').click()
        page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=150000)
        report['after_reload']=status()
        check(status()['roster']==['hero'] and status()['quests']=={},'Reload cannot restore the deleted save from a backup')
        check(not report['errors'],'Canvas flow has no browser or Godot console errors')
        browser.close()
    finally:
      server.shutdown();server.server_close()
      (OUT/'browser-open-world.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':run()
