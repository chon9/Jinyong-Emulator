"""Play earned recruitment and combat presentations through shipped visible controls."""
import functools,http.server,json,os,threading
from pathlib import Path
from playwright.sync_api import sync_playwright
from browser_audio_test import QuietHandler,PROBE
from browser_ui_helpers import press,open_tools
ROOT=Path(__file__).resolve().parents[1]
CONTENT=json.loads((ROOT/'data/open_world.json').read_text(encoding='utf-8'))

def status(page):return page.evaluate('youxiaChapterStatus')
def key(page,k):page.locator('#canvas').focus();page.keyboard.press(k);page.wait_for_timeout(180)
def read_lines(page):
    lines=[]
    for _ in range(12):
        lines.append(status(page)['dialogue_text'])
        if not any(b['text']=='下一句 →' and not b['disabled'] for b in page.evaluate('youxiaUI.buttons')):break
        press(page,'下一句 →')
    assert len(lines)==len(set(lines)),'Conversation repeats the same line'
    return lines

def seek_hero(page,hid):
    h=CONTENT['heroes'][hid]
    key(page,'M')
    if any(b['text']=='選擇 · '+h['region'] for b in page.evaluate('youxiaUI.buttons')):press(page,'選擇 · '+h['region'],prefix=False)
    press(page,'進入 · '+h['region'])
    press(page,h['scene'],prefix=False);press(page,'交談 · '+h['name'])

def earn_companion(page,hid,check=lambda ok,text:None,observe=None,choice=0,invite=True):
    h=CONTENT['heroes'][hid];qid='friend_'+hid;q=CONTENT['quests'][qid]
    seek_hero(page,hid)
    opening=read_lines(page)
    if observe:observe('opening',hid,q,opening)
    check(len(opening)>=3,'Opening is a real exchange with the protagonist: '+h['name'])
    check(hid not in status(page)['roster'],'Meeting a hero does not grant recruitment')
    press(page,'結交條件');conditions=read_lines(page)
    check(q['name'] in conditions[-1],'Recruitment explicitly names the required personal story')
    press(page,'回到交談');read_lines(page);press(page,'談談 · '+h['name'])
    check(status(page)['quests'][qid]['step']==1,'Agreeing to help records the introduction without repeating it')
    for _ in range(14):
        progress=status(page)['quests'][qid]
        if progress['status']=='done':break
        step=q['steps'][progress['step']]
        key(page,'J');press(page,'進行中',prefix=False);press(page,'◆ '+q['name']);press(page,'前往目標')
        check(status(page)['scene']==step['scene'],'Journal leads to the actual witness or object location')
        lines=read_lines(page)
        if observe:observe('dialogue',hid,step,lines)
        press(page,step['options'][choice] if step['kind']=='choice' else step['action'],prefix=False)
        if step['kind']=='search':
            check(status(page)['evidence'][step['evidence']]['name']==step['item'],'Searching puts the named physical clue in the protected evidence bag')
            if observe:observe('evidence',hid,step,lines)
        if step['kind']=='battle':
            check(status(page)['battle']=='active','Story confrontation starts an actual fight')
            if observe:observe('combat',hid,step,lines)
            else:press(page,'委託 · 關',prefix=False)
            page.wait_for_function("youxiaChapterStatus.battle==='victory'",timeout=120000)
            check(status(page)['battle']=='victory','The quest battle is won through actual combat')
            press(page,'繼續故事',prefix=False)
    check(status(page)['quests'][qid]['status']=='done','Story has an explicit awarded resolution: '+q['name'])
    check(not status(page)['evidence'],'Evidence is handed back at the resolution')
    if observe:observe('ending',hid,q,[])
    if invite:
        press(page,'邀請同行',prefix=False)
        check(hid in status(page)['roster'],'Recruitment becomes available after that hero’s own story')
    else:
        if any(b['text']=='回到交談' for b in page.evaluate('youxiaUI.buttons')):
            press(page,'回到交談');read_lines(page)
        press(page,'結交條件');requirements=read_lines(page)
        check('修為' in requirements[-1] and hid not in status(page)['roster'],'A completed story still respects this companion’s cultivation requirement')
    press(page,'×',prefix=False)

def run():
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(QuietHandler,directory=str(ROOT/'sites/youxia-web/dist')))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    report={'checks':[],'errors':[],'audio':{}}
    try:
      with sync_playwright() as p:
        chrome=sorted((Path(os.environ['LOCALAPPDATA'])/'ms-playwright').glob('chromium-*/chrome-win/chrome.exe'))[-1]
        browser=p.chromium.launch(headless=True,executable_path=str(chrome),args=['--enable-unsafe-swiftshader','--use-angle=swiftshader'])
        page=browser.new_page(viewport={'width':1440,'height':900});page.add_init_script(PROBE)
        page.on('pageerror',lambda e:report['errors'].append(str(e)))
        page.on('console',lambda m:report['errors'].append(m.text) if m.type=='error' or m.text.startswith(('ERROR:','SCRIPT ERROR:')) else None)
        def check(ok,text):
            assert ok,text
            report['checks'].append(text);print(text,flush=True)
        def shot(name):page.screenshot(path=str(ROOT/f'test-results/story-{name}.png'))
        def observe(moment,hid,step,lines):
            if moment=='dialogue' and hid=='jy02':shot('dialogue-'+step['kind'])
            if moment=='evidence':
                key(page,'I');shot('evidence-bag');key(page,'J');press(page,'進行中',prefix=False)
            if moment=='ending':shot('ending-'+hid)
            if moment!='combat':return
            buttons=page.evaluate('youxiaUI.buttons')
            music=next((b['text'] for b in buttons if b['text']=='音樂 開'),None)
            if music:press(page,music,prefix=False)
            page.evaluate('audioProbe.peak=0')
            if hid=='jy24':
                press(page,'守勢',prefix=False);press(page,'打狗棒法')
                press(page,'委託 · 關',prefix=False)
                observed=page.wait_for_function("youxiaChapterStatus.event.actor==='jy02'&&youxiaChapterStatus.effects==='bamboo'?{family:youxiaChapterStatus.effects,event:youxiaChapterStatus.event}:false",polling=25,timeout=15000).json_value()
                check(observed['family']=='bamboo','Huang Rong uses her bamboo-staff action and signature presentation')
                report['staff_event']=observed
                shot('huang-rong-bamboo')
            else:press(page,'委託 · 關',prefix=False)
            for _ in range(12):page.evaluate('audioProbe.read()');page.wait_for_timeout(75)
            peak=page.evaluate('audioProbe.peak');report['audio'][hid]=peak
            check(peak>.00001,'Skill sound is measurable with background music muted')
        page.goto(f'http://127.0.0.1:{server.server_port}/');page.get_by_role('button',name='進入江湖').click()
        page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=180000)
        earn_companion(page,'jy02',check,observe)
        earn_companion(page,'jy24',check,observe)
        check(status(page)['party']==3,'Both earned recruits occupy the real active party')
        press(page,'牛家客棧',prefix=False);key(page,'I')
        press(page,'購買 ·');press(page,'出售 ·')
        check('售出' in status(page)['notice'] or '出售' in status(page)['notice'],'Buying and selling still work alongside earned recruitment')
        cues=set(status(page)['sounds'])
        check('fx_staff_ready' in cues and 'fx_staff_hit' in cues,'Staff cast and impact actually play different audio streams')
        # A real berserker telegraphs a charged blow; the player can guard or retreat.
        key(page,'M');press(page,'江湖群雄');press(page,CONTENT['enemies']['enemy_007']['name'])
        press(page,'前往對手所在地');press(page,'接受挑戰')
        press(page,'守勢',prefix=False);press(page,'進行回合')
        page.wait_for_function("youxiaChapterStatus.units.some(u=>u.states.some(s=>s.key==='charge'))",timeout=15000)
        page.wait_for_timeout(150);shot('charge-and-badges')
        check(status(page)['effects']=='charge' or any('charge'==s['key'] for u in status(page)['units'] for s in u['states']),'Charged enemy has a persistent aura and a backed duration badge')
        page.wait_for_function("youxiaUI.buttons.some(b=>b.text==='撤退'&&!b.disabled)",timeout=15000)
        check('fx_charge' in status(page)['sounds'],'Charging plays its dedicated audible cue')
        press(page,'撤退');key(page,'F8')
        press(page,'刪除存檔／重新開始');page.keyboard.press('Escape');page.wait_for_timeout(250)
        check('jy02' in status(page)['roster'],'Cancelling reset preserves earned recruits')
        page.reload();page.get_by_role('button',name='進入江湖').click()
        page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=180000)
        check('jy02' in status(page)['roster'] and status(page)['quests']['friend_jy02']['status']=='done','Earned recruits and story resolutions survive a browser reload')
        key(page,'F8');press(page,'刪除存檔／重新開始');page.mouse.click(615,544);page.wait_for_timeout(500)
        check(status(page)['roster']==['hero'] and status(page)['quests']=={},'Confirmed reset removes the earned story save')
        page.reload();page.get_by_role('button',name='進入江湖').click()
        page.wait_for_function("document.documentElement.dataset.gameReady==='true'",timeout=180000)
        check(status(page)['roster']==['hero'] and status(page)['quests']=={},'Reload cannot resurrect deleted story progress')
        check(not report['errors'],'Story, animation, effects and audio run without browser or engine errors')
        browser.close()
    finally:
      server.shutdown();server.server_close()
      (ROOT/'test-results/browser-jianghu-stories.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':run()
