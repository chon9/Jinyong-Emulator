"""Real controls, current resident casting and the user's four-actor battle layout."""
import functools,http.server,json,os,threading
from pathlib import Path
from playwright.sync_api import sync_playwright
from browser_audio_test import QuietHandler
from browser_ui_helpers import press,open_tools
ROOT=Path(__file__).resolve().parents[1]
def run():
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(QuietHandler,directory=str(ROOT/'sites/youxia-web/dist')))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    report={'checks':[],'errors':[]}
    try:
      with sync_playwright() as p:
        chrome=sorted((Path(os.environ['LOCALAPPDATA'])/'ms-playwright').glob('chromium-*/chrome-win/chrome.exe'))[-1]
        browser=p.chromium.launch(headless=True,executable_path=str(chrome),args=['--enable-unsafe-swiftshader','--use-angle=swiftshader'])
        page=browser.new_page(viewport={'width':1440,'height':900})
        page.on('pageerror',lambda e:report['errors'].append(str(e)))
        page.on('console',lambda m:report['errors'].append(m.text) if m.type=='error' or m.text.startswith(('ERROR:','SCRIPT ERROR:')) else None)
        def check(ok,text):
            assert ok,text
            report['checks'].append(text);print(text,flush=True)
        def status():return page.evaluate('youxiaChapterStatus')
        def key(k):page.locator('#canvas').focus();page.keyboard.press(k);page.wait_for_timeout(250)
        def shot(name):page.screenshot(path=str(ROOT/f'test-results/visual-{name}.png'))
        page.goto(f'http://127.0.0.1:{server.server_port}/');page.get_by_role('button',name='進入江湖').click()
        page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=150000)
        shot('village')
        key('M');press(page,'進入 · 嘉興鎮')
        seen={}
        for scene in ['青溪客棧','渡口','藥廬','蘆葦蕩','古寺','市集','演武坪','舊倉','茶肆','驛站']:
            press(page,scene,prefix=False)
            check(status()['scene']==scene,'Location portraits load: '+scene)
            for person in status()['people']:
                if not person['art'].startswith('actor_npc_'):continue
                check(person['art'] not in seen or seen[person['art']]==person['id'],'No duplicated civilian face across the entire town')
                check(person['role'] not in ['掌事','行旅','鄉里人物'],'Occupation has a specific in-world identity')
                seen[person['art']]=person['id']
            if scene in ['青溪客棧','渡口','市集']:shot(scene)
        check(len(seen)==22,'Twenty-two town residents have twenty-two different portraits')
        first=status()['people'][0];press(page,'交談 · '+first['name']);shot('resident-dialogue')
        check(status()['dialogue']==first['id'],'Named resident portrait opens their own dialogue')
        open_tools(page);page.locator('#restore').click();page.once('dialog',lambda d:d.accept())
        page.locator('#save-file').set_input_files(str(ROOT/'test-results/visual-party.json'))
        page.wait_for_function('youxiaChapterStatus.party===4')
        page.locator('#tools-toggle').click();key('M');press(page,'江湖群雄')
        # A durable opponent lets all four actions play before a result overlay.
        foes=json.loads((ROOT/'data/open_world.json').read_text(encoding='utf-8'))['enemies']
        target=list(foes.values())[9]['name']
        press(page,'下一頁');press(page,target);press(page,'前往對手所在地');press(page,'接受挑戰')
        check(status()['party']==4 and status()['battle']=='active','Legacy four-person save enters the corrected battle view')
        page.wait_for_timeout(300);shot('battle-idle')
        for name in ['青山一線','飛燕穿雲','回春拂穴','金剛截脈']:press(page,name)
        press(page,'進行回合')
        for index in range(8):page.wait_for_timeout(210);shot('battle-action-'+str(index))
        page.wait_for_function("youxiaUI.buttons.some(b=>b.text==='撤退'&&!b.disabled)",timeout=15000)
        check(status()['round']>=2,'All four real skill animations resolve and return to preparation')
        check(not report['errors'],'New art, dialogue and combat render without engine errors')
        browser.close()
    finally:
      server.shutdown();server.server_close()
      (ROOT/'test-results/browser-visual.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':run()
