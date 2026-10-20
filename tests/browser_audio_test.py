"""Measure real Web Audio output from the exported game, including mute and recovery."""
import argparse
import functools
import http.server
import json
import os
import re
from pathlib import Path
import threading
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
PROBE = r"""(() => {
  window.audioProbe = {contexts: [], peak: 0, starts: []};
  const connect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function(destination, ...args) {
    const entry = window.audioProbe.contexts.find(e => e.context === this.context);
    return connect.call(this, entry && destination === this.context.destination ? entry.analyser : destination, ...args);
  };
  const Context = window.AudioContext || window.webkitAudioContext;
  class ObservedContext extends Context {
    constructor(...args) {
      super(...args);
      const analyser = this.createAnalyser(); analyser.fftSize = 2048;
      connect.call(analyser, this.destination);
      window.audioProbe.contexts.push({context: this, analyser});
    }
  }
  window.AudioContext = ObservedContext;
  if (window.webkitAudioContext) window.webkitAudioContext = ObservedContext;
  const start = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function(...args) {
    window.audioProbe.starts.push({duration: this.buffer?.duration, args});
    return start.apply(this, args);
  };
  window.audioProbe.read = () => window.audioProbe.contexts.map(entry => {
    const samples = new Float32Array(entry.analyser.fftSize);
    entry.analyser.getFloatTimeDomainData(samples);
    const rms = Math.sqrt(samples.reduce((sum, value) => sum + value * value, 0) / samples.length);
    window.audioProbe.peak = Math.max(window.audioProbe.peak, rms);
    return {state: entry.context.state, rms};
  });
})();
"""


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass


def run():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url')
    parser.add_argument('--diagnose', action='store_true')
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
            context = browser.new_context(viewport={'width':1440, 'height':954})
            context.add_init_script(PROBE)
            page = context.new_page()
            page.on('pageerror', lambda error: report['errors'].append(str(error)))
            page.on('console', lambda message: report['errors'].append(message.text) if message.type == 'error' else None)
            page.goto(args.url or f'http://127.0.0.1:{server.server_port}/')
            page.get_by_role('button', name='進入江湖').click()
            page.wait_for_function("document.documentElement.dataset.gameReady === 'true'", timeout=120000)
            for _ in range(40):
                page.evaluate('window.audioProbe?.read?.()')
                page.wait_for_timeout(100)
            report['initial_audio'] = page.evaluate('window.audioProbe?.read?.()')
            report['initial_peak'] = page.evaluate('window.audioProbe?.peak')
            report['sources'] = page.evaluate('window.audioProbe?.starts')
            if args.diagnose:
                page.evaluate("""() => {const c=audioProbe.contexts[0].context; window.probeTone=c.createOscillator(); const g=c.createGain();g.gain.value=.05;probeTone.connect(g).connect(c.destination);probeTone.start();}""")
                page.wait_for_timeout(250)
                report['probe_control'] = page.evaluate('audioProbe.read()')
                page.evaluate('probeTone.stop()')
            if not args.diagnose:
                assert report['initial_peak'] and report['initial_peak'] > .0001, 'No actual audio after entering the game'
                report['checks'].append('Entering the game produces measurable Web Audio output')
                page.keyboard.press('F8')
                page.wait_for_function("document.documentElement.dataset.gamePage === '聯機'")
                page.wait_for_timeout(400)
                def peak(seconds=.6):
                    page.evaluate('audioProbe.peak = 0')
                    for _ in range(int(seconds * 10)):
                        page.evaluate('audioProbe.read()')
                        page.wait_for_timeout(100)
                    return page.evaluate('audioProbe.peak')
                page.mouse.click(100, 270)
                page.wait_for_timeout(250)
                assert peak() < .000001, 'Music checkbox did not silence output'
                report['checks'].append('In-game mute silences actual audio output')
                page.mouse.click(100, 270)
                assert peak() > .0001, 'Music did not resume after unmuting'
                report['checks'].append('Unmuting restores actual audio output')
                page.mouse.click(298, 265)
                page.keyboard.press('Home')
                page.wait_for_timeout(200)
                assert peak() < .000001, 'Zero volume did not silence output'
                page.mouse.click(298, 265)
                assert peak() > .0001, 'Volume slider did not restore output'
                report['checks'].append('Volume slider reaches silence and restores audible output')
                for index, name in enumerate(['town', 'wild', 'battle', 'boss', 'dungeon'], 1):
                    page.mouse.click(400, 309)
                    page.keyboard.press('Home')
                    for _ in range(index + 1): page.keyboard.press('ArrowDown')
                    page.keyboard.press('Enter')
                    page.wait_for_timeout(1900)
                    # Godot flushes its browser file system periodically; selection
                    # is immediate but the persisted configuration can lag behind.
                    selected = None
                    for _ in range(32):
                        saved_config = page.evaluate("""async () => {
                      for (const info of await indexedDB.databases()) {
                        const db = await new Promise((resolve,reject) => {const r=indexedDB.open(info.name);r.onsuccess=()=>resolve(r.result);r.onerror=reject;});
                        for (const store of db.objectStoreNames) {
                          const keys=await new Promise(resolve=>{const r=db.transaction(store).objectStore(store).getAllKeys();r.onsuccess=()=>resolve(r.result);});
                          const key=keys.find(k=>String(k).endsWith('/youxia_music.cfg'));
                          if(key){const value=await new Promise(resolve=>{const r=db.transaction(store).objectStore(store).get(key);r.onsuccess=()=>resolve(r.result);});db.close();return new TextDecoder().decode(value.contents);}
                        }
                        db.close();
                      }
                      return '';
                        }""")
                        selected = re.search(r'track="([^"]*)"', saved_config)
                        if selected and selected[1] == name: break
                        page.wait_for_timeout(250)
                    assert selected and selected[1] == name, 'Wrong selected track: ' + saved_config
                    assert peak() > .0001, 'No sound after switching to ' + name
                    report['checks'].append('Real audio after selecting ' + name)
                link = page.get_by_role('link', name='Windows 最新版', exact=True)
                assert link.is_visible() and link.get_attribute('href') == 'https://github.com/chon9/Jinyong-Emulator/releases/latest'
                report['checks'].append('Persistent Windows download entry uses the latest release permalink')
                assert not report['errors'], report['errors']
            page.screenshot(path=str(ROOT / 'test-results/browser-audio.png'))
            print(json.dumps(report, ensure_ascii=True))
            context.close()
            browser.close()
    finally:
        if server: server.shutdown(); server.server_close()
        (ROOT / 'test-results/browser-audio-result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__': run()
