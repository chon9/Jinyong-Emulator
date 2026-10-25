"""Revisit NPCs after real quests, then check the reported town HUD and old saves."""
import functools,http.server,json,os,threading
from pathlib import Path
from PIL import Image
from playwright.sync_api import sync_playwright
from browser_audio_test import QuietHandler
from browser_ui_helpers import press,open_tools
from browser_jianghu_story_test import CONTENT,earn_companion,key,read_lines,seek_hero,status
ROOT=Path(__file__).resolve().parents[1]

def run():
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(QuietHandler,directory=str(ROOT/'sites/youxia-web/dist')))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    report={'checks':[],'errors':[],'conversations':{}}
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
        def shot(name):
            target=ROOT/f'test-results/aftermath-{name}.png';page.screenshot(path=str(target));return target
        def visit(region,scene):
            key(page,'M')
            if any(b['text']=='選擇 · '+region for b in page.evaluate('youxiaUI.buttons')):press(page,'選擇 · '+region,prefix=False)
            press(page,'進入 · '+region);press(page,scene,prefix=False)
        page.goto(f'http://127.0.0.1:{server.server_port}/');page.get_by_role('button',name='進入江湖').click()
        page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=180000)
        earn_companion(page,'jy02',check)
        seek_hero(page,'jy02')
        expected=CONTENT['quests']['friend_jy02']['aftermath_choices']['0']['jy02']
        post=read_lines(page);report['conversations']['huang_after']=post
        check(post==[l['text'] for l in expected],'Huang Rong discusses the saved meal outcome instead of asking for help again')
        check(not any('談談 · 黃蓉' in b['text'] for b in page.evaluate('youxiaUI.buttons')),'Completed recruitment task is absent from the conversation actions')
        press(page,'聊聊別的');casual=read_lines(page);report['conversations']['huang_casual']=casual
        check(casual==[l['text'] for l in CONTENT['people']['jy02']['idle_pages']],'Casual talk contains new character dialogue, never the broken-chair introduction')
        press(page,'聊聊近況');check(read_lines(page)==post,'Recent news explicitly returns to the resolved event')
        press(page,'×',prefix=False);seek_hero(page,'jy02')
        check(read_lines(page)==casual,'The next visit starts with everyday conversation after hearing the event response')
        shot('huang-daily');press(page,'×',prefix=False)
        # Finish the exact medical scene in the user's screenshot through its real steps.
        qid='town_03';q=CONTENT['quests'][qid];visit(q['region'],q['scene'])
        press(page,'交談 · '+CONTENT['people'][q['giver']]['name']);read_lines(page);press(page,'談談 · '+q['name'])
        for _ in range(12):
            progress=status(page)['quests'][qid]
            if progress['status']=='done':break
            step=q['steps'][progress['step']]
            key(page,'J');press(page,'進行中',prefix=False);press(page,'◆ '+q['name']);press(page,'前往目標');read_lines(page)
            press(page,step['options'][0] if step['kind']=='choice' else step['action'],prefix=False)
            if step['kind']=='battle':
                press(page,'委託 · 關',prefix=False);page.wait_for_function("youxiaChapterStatus.battle==='victory'",timeout=120000);press(page,'繼續故事',prefix=False)
        check(status(page)['quests'][qid]['status']=='done','The medical commission reaches a real awarded ending')
        press(page,'回到交談');shot('doctor-followup')
        doctor=read_lines(page);report['conversations']['doctor_after']=doctor
        check(doctor==[l['text'] for l in q['aftermath'][q['giver']]],'The doctor now talks about the apprentice checking deliveries instead of the missing medicine')
        check(not any(b['text']=='談談 · '+q['name'] for b in page.evaluate('youxiaUI.buttons')),'Finished town commission cannot be offered again')
        press(page,'×',prefix=False);path=shot('medical-hud');pixels=Image.open(path).convert('RGB')
        check(max(pixels.getpixel((446,824)))<65,'Money, learning points and counts have an opaque dark background over the bright town')
        check(max(pixels.getpixel((446,704)))<65,'Completed-event notice has its own readable panel above the dock')
        check('報酬' in status(page)['notice'],'The actual multiline reward message remains present in its scrollable message panel')
        # Export a version-0.12-shaped save, import it through the visible file UI.
        open_tools(page)
        with page.expect_download() as download:page.locator('#backup').click()
        file=ROOT/'test-results/aftermath-before-import.json';download.value.save_as(str(file))
        saved=json.loads(file.read_text(encoding='utf-8'))
        saved['chapter']['open_world'].pop('heard',None);saved['chapter']['open_world'].pop('finished',None)
        old=ROOT/'test-results/aftermath-v0120.json';old.write_text(json.dumps(saved,ensure_ascii=False),encoding='utf-8')
        page.locator('#restore').click();page.once('dialog',lambda d:d.accept());page.locator('#save-file').set_input_files(str(old));page.wait_for_timeout(500);page.locator('#tools-toggle').click()
        check('jy02' in status(page)['roster'] and status(page)['quests'][qid]['status']=='done','Existing v0.12 save keeps the earned companion and completed town quest')
        press(page,'交談 · '+CONTENT['people'][q['giver']]['name']);check(read_lines(page)==doctor,'Imported completed quest immediately gains the correct follow-up dialogue')
        press(page,'×',prefix=False)
        visit('牛家村','河邊');witness='local_01_03_1';press(page,'交談 · '+CONTENT['people'][witness]['name'])
        check(read_lines(page)==[l['text'] for l in CONTENT['quests']['friend_jy02']['aftermath'][witness]],'The fish seller also remembers the completed incident, not just the quest giver')
        press(page,'×',prefix=False);seek_hero(page,'jy02');read_lines(page);press(page,'×',prefix=False)
        page.reload();page.get_by_role('button',name='進入江湖').click();page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=180000)
        seek_hero(page,'jy02');check(read_lines(page)==casual,'Already-heard responses and ordinary conversation persist through an immediate browser reload')
        check(not report['errors'],'Follow-up conversations, clear HUD and save compatibility have no browser or engine errors')
        browser.close()
    finally:
        server.shutdown();server.server_close()
        (ROOT/'test-results/browser-aftermath.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':run()
