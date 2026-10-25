"""Read complete stories using rendered controls; verify backup-before-reset through UI."""
import functools,http.server,json,os,threading
from pathlib import Path
from playwright.sync_api import sync_playwright
from browser_audio_test import QuietHandler
from browser_ui_helpers import press,open_tools
from browser_jianghu_story_test import CONTENT,earn_companion,key,read_lines,status
ROOT=Path(__file__).resolve().parents[1]

def run():
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(QuietHandler,directory=str(ROOT/'sites/youxia-web/dist')))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    report={'checks':[],'errors':[],'transcripts':{}}
    try:
      with sync_playwright() as p:
        chrome=sorted((Path(os.environ['LOCALAPPDATA'])/'ms-playwright').glob('chromium-*/chrome-win/chrome.exe'))[-1]
        browser=p.chromium.launch(headless=True,executable_path=str(chrome),args=['--enable-unsafe-swiftshader','--use-angle=swiftshader'])
        page=browser.new_page(viewport={'width':1440,'height':900},accept_downloads=True)
        page.on('pageerror',lambda e:report['errors'].append(str(e)))
        page.on('console',lambda m:report['errors'].append(m.text) if m.type=='error' or m.text.startswith(('ERROR:','SCRIPT ERROR:')) else None)
        def check(ok,text):
            assert ok,text
            report['checks'].append(text);print(text,flush=True)
        def shot(name):page.screenshot(path=str(ROOT/f'test-results/narrative-{name}.png'))
        def observe(moment,hid,step,lines):
            if moment in ['opening','dialogue']:
                report['transcripts'].setdefault(hid,[]).append({'moment':moment,'goal':step.get('text',step['name'] if 'name' in step else ''),'lines':lines})
            if moment=='opening':shot(hid+'-opening')
            if moment=='combat':press(page,'委託 · 關',prefix=False)
            if moment=='ending':shot(hid+'-ending')
        page.goto(f'http://127.0.0.1:{server.server_port}/');page.get_by_role('button',name='進入江湖').click()
        page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=180000)
        old=json.loads((ROOT/'test-results/visual-party.json').read_text(encoding='utf-8'))
        old['chapter'].get('open_world',{}).pop('story_edition',None)
        fixture=ROOT/'test-results/old-story-import.json';fixture.write_text(json.dumps(old,ensure_ascii=False),encoding='utf-8')
        open_tools(page);page.locator('#restore').click();page.once('dialog',lambda d:d.accept());page.locator('#save-file').set_input_files(str(fixture))
        page.wait_for_timeout(700);page.locator('#tools-toggle').click()
        check(status(page)['roster']==['hero'] and status(page)['quests']=={},'Importing an old story starts the rewritten campaign afresh')
        key(page,'F8')
        with page.expect_download() as download:press(page,'匯出重寫前舊檔',prefix=False)
        target=ROOT/'test-results/downloaded-before-story.json';download.value.save_as(str(target))
        backup=json.loads(target.read_text(encoding='utf-8'))
        check(backup==old,'The visible backup button exports the exact original pre-reset save, including all metadata')
        key(page,'Escape')
        earn_companion(page,'jy06',check,observe,choice=1,invite=False)
        check(not any(s['kind']=='battle' for s in CONTENT['quests']['friend_jy06']['steps']),'Wine debt resolves through conversation, a practical promise and return of the old sword')
        # The correct chess answer bypasses the lesson, not merely a different final sentence.
        key(page,'M');press(page,'選擇 · 西夏城');press(page,'進入 · 西夏城');press(page,'擂鼓山',prefix=False)
        q=CONTENT['quests']['flash_37']
        press(page,'交談 · 蘇星河');read_lines(page);press(page,'談談 · '+q['name'])
        key(page,'J');press(page,'進行中',prefix=False);press(page,'◆ '+q['name']);press(page,'前往目標');read_lines(page)
        press(page,q['steps'][1]['options'][0],prefix=False)
        check(status(page)['quests']['flash_37']['step']==3,'Solving the board skips the remedial lesson and opens the final meeting')
        shot('chess-route')
        key(page,'J');press(page,'進行中',prefix=False);press(page,'◆ '+q['name']);press(page,'前往目標');read_lines(page);press(page,q['steps'][3]['action'],prefix=False)
        check(status(page)['quests']['flash_37']['status']=='done','The chosen chess route can be resolved with the actual giver')
        report['before_reload']=status(page)
        page.reload();page.get_by_role('button',name='進入江湖').click();page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=180000)
        report['after_reload']=status(page)
        check(status(page)['quests']['friend_jy06']['status']=='done' and status(page)['quests']['flash_37']['status']=='done','Reload preserves the new edition instead of resetting again')
        check(not report['errors'],'New stories, reset, backup export and reload have no browser or engine errors')
        browser.close()
    finally:
        server.shutdown();server.server_close()
        (ROOT/'test-results/browser-narrative.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':run()
