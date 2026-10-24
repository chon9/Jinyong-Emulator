/* Browser shell around the original Godot game; no duplicate game rules. */
(() => {
  'use strict';
  const byId = id => document.getElementById(id);
  const play = byId('play');
  const status = byId('status');
  const progress = byId('progress');
  const nativeFetch = window.fetch.bind(window);
  let started = false;
  const closeTools = () => { byId('game-tools').hidden = true; byId('tools-toggle').setAttribute('aria-expanded', 'false'); };
  byId('tools-toggle').addEventListener('click', () => {
    const open = byId('game-tools').hidden;
    byId('game-tools').hidden = !open;
    byId('tools-toggle').setAttribute('aria-expanded', String(open));
  });
  document.addEventListener('keydown', event => { if (event.key === 'Escape') closeTools(); });
  byId('canvas').addEventListener('pointerdown', closeTools);
  window.youxiaSetStatus = (name, place, page, mode) => {
    byId('live-location').textContent = `${name} · ${place} · ${page}`;
    document.documentElement.dataset.gamePage = page;
    document.documentElement.dataset.networkMode = mode;
    document.documentElement.dataset.gamePlace = place;
  };
  const resizeCanvas = () => {
    const canvas = byId('canvas');
    const bounds = byId('stage').getBoundingClientRect();
    canvas.width = Math.round(bounds.width);
    canvas.height = Math.round(bounds.height);
  };
  new ResizeObserver(resizeCanvas).observe(byId('stage'));
  resizeCanvas();

  window.youxiaDownloadSave = text => {
    const url = URL.createObjectURL(new Blob([text], {type: 'application/json;charset=utf-8'}));
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `youxia-save-${new Date().toISOString().slice(0,10)}.json`;
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  };
  window.youxiaChooseSave = () => {
    if (!started) return;
    byId('save-file').value = '';
    byId('save-file').click();
  };
  byId('restore').addEventListener('click', window.youxiaChooseSave);
  byId('backup').addEventListener('click', () => window.youxiaExportSave?.());
  byId('save-file').addEventListener('change', async event => {
    const file = event.target.files[0];
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) { alert('存檔過大，請選擇網金游俠的角色 JSON 備份。'); return; }
    const text = await file.text();
    try {
      const data = JSON.parse(text);
      if (data.version !== 1 || !data.character || Array.isArray(data.character) || typeof data.character !== 'object') throw Error();
    } catch { alert('這不是相容的網金游俠存檔。'); return; }
    if (confirm('匯入會替換目前單機角色。請先匯出備份。確定匯入？')) window.youxiaImportSave?.(text);
  });
  byId('fullscreen').addEventListener('click', () => {
    const action = document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen?.();
    action?.catch(() => {});
  });

  async function digest(bytes) {
    const result = await crypto.subtle.digest('SHA-256', bytes);
    return [...new Uint8Array(result)].map(b => b.toString(16).padStart(2, '0')).join('');
  }

  const CACHE = 'youxia-verified-assets-v1';
  let engineAttempted = false;
  window.youxiaSetPreloadProgress = value => {
    status.textContent = `正在準備人物、街巷與招式 · ${value}%`;
    progress.value = .95 + value * .0005;
  };

  async function loadAssets() {
    const response = await nativeFetch('asset-manifest.json', {cache: 'no-store', signal: AbortSignal.timeout(30000)});
    if (!response.ok) throw new Error('無法取得遊戲資源清單，請稍後重試。');
    const manifest = await response.json();
    if (manifest.version !== 1 || !Array.isArray(manifest.assets) || manifest.assets.length !== 2) throw new Error('遊戲資源清單格式不相容。');
    const parts = manifest.assets.flatMap(asset => asset.parts);
    if (parts.some(p => !/^index\.(wasm|pck)\.[a-f0-9]{12}\.\d+\.bin$/.test(p.url) || !Number.isSafeInteger(p.size) || p.size < 1 || !/^[a-f0-9]{64}$/.test(p.sha256))) throw new Error('遊戲資源清單不完整。');
    const total = parts.reduce((n, p) => n + p.size, 0);
    const received = new Map();
    const buffers = new Map();
    const cancel = new AbortController();
    const stats = {cachedParts: 0, downloadedParts: 0, retries: 0};
    window.youxiaPreloadStats = stats;
    let cache = null;
    try { cache = await caches.open(CACHE); } catch { /* Storage may be unavailable; downloads still work. */ }
    function update(part, length) {
      received.set(part.url, length);
      const count = [...received.values()].reduce((n, value) => n + value, 0);
      progress.value = count / total * .85;
      status.textContent = `下載／快取校驗 · ${(count / 1048576).toFixed(1)} / ${(total / 1048576).toFixed(1)} MB`;
    }
    async function verified(part, bytes) { return bytes.byteLength === part.size && await digest(bytes) === part.sha256; }
    async function partBuffer(part) {
      if (cache) {
        try {
          const found = await cache.match(part.url);
          if (found) {
            const bytes = await found.arrayBuffer();
            if (await verified(part, bytes)) { stats.cachedParts++; update(part, bytes.byteLength); return bytes; }
            await cache.delete(part.url);
          }
        } catch { /* A cache error must not prevent play. */ }
      }
      for (let attempt = 0; attempt < 3; attempt++) {
        if (cancel.signal.aborted) throw cancel.signal.reason;
        if (attempt) { stats.retries++; await new Promise(resolve => setTimeout(resolve, attempt * 600)); }
        const timeout = new AbortController();
        let timer;
        const resetTimer = () => { clearTimeout(timer); timer = setTimeout(() => timeout.abort(new Error('下載逾時')), 30000); };
        const stop = () => timeout.abort(cancel.signal.reason);
        cancel.signal.addEventListener('abort', stop, {once: true});
        resetTimer();
        try {
          const result = await nativeFetch(part.url, {cache: 'no-store', signal: timeout.signal});
          if (!result.ok) throw new Error('下載失敗');
          const reader = result.body.getReader();
          const chunks = [];
          let length = 0;
          while (true) {
            const {done, value} = await reader.read();
            if (done) break;
            length += value.length;
            if (length > part.size) { await reader.cancel(); throw new Error('資源大小不正確'); }
            chunks.push(value); update(part, length); resetTimer();
          }
          const bytes = new Uint8Array(length);
          let offset = 0;
          for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
          if (!await verified(part, bytes)) throw new Error('資源校驗失敗');
          if (cache) { try { await cache.put(part.url, new Response(bytes)); } catch { /* Quota: verified memory buffer remains usable. */ } }
          stats.downloadedParts++;
          return bytes;
        } catch (error) {
          update(part, 0);
          if (attempt === 2 || cancel.signal.aborted) throw new Error('遊戲資源下載未完成。可重試，已校驗的部分會保留。', {cause: error});
        } finally {
          clearTimeout(timer);
          cancel.signal.removeEventListener('abort', stop);
        }
      }
    }
    let cursor = 0;
    let failure;
    const workers = Array.from({length: Math.min(3, parts.length)}, async () => {
      try {
        while (cursor < parts.length && !cancel.signal.aborted) {
          const part = parts[cursor++];
          buffers.set(part.url, await partBuffer(part));
        }
      } catch (error) { failure ??= error; cancel.abort(error); }
    });
    await Promise.all(workers);
    if (failure) throw failure;
    const assets = new Map();
    for (const [i, asset] of manifest.assets.entries()) {
      status.textContent = `解壓與完整性校驗 · ${i + 1} / ${manifest.assets.length}`;
      progress.value = .85 + .04 * i;
      let stream = new Blob(asset.parts.map(p => buffers.get(p.url))).stream();
      if (asset.encoding === 'gzip') stream = stream.pipeThrough(new DecompressionStream('gzip'));
      const buffer = await new Response(stream).arrayBuffer();
      if (buffer.byteLength !== asset.size || await digest(buffer) !== asset.sha256) throw new Error('遊戲資源解壓校驗失敗。');
      assets.set(new URL(asset.path, location.href).href, {buffer, type: asset.path.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream'});
    }
    buffers.clear();
    // Only prune this game's outdated chunks; saves live in a separate IndexedDB.
    if (cache) {
      try {
        const current = new Set(parts.map(p => new URL(p.url, location.href).href));
        for (const request of await cache.keys()) if (!current.has(request.url)) await cache.delete(request);
      } catch { /* Cleanup is optional. */ }
    }
    window.fetch = (input, options) => {
      const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, location.href).href;
      const asset = assets.get(url);
      if (!asset) return nativeFetch(input, options);
      return Promise.resolve(new Response(asset.buffer, {headers: {'Content-Type': asset.type, 'Content-Length': String(asset.buffer.byteLength)}}));
    };
    return assets;
  }

  play.addEventListener('click', async () => {
    if (engineAttempted) { location.reload(); return; }
    play.disabled = true;
    byId('failure').hidden = true;
    byId('loading').hidden = false;
    status.textContent = '正在準備江湖…';
    let assets;
    try {
      const missing = Engine.getMissingFeatures({threads: false});
      if (missing.length) throw new Error('此瀏覽器缺少遊戲所需功能：' + missing.join('、') + '。請使用支援 WebGL 2 的新版 Chrome、Edge 或 Firefox。');
      if (typeof DecompressionStream === 'undefined') throw new Error('請更新瀏覽器，以支援遊戲資源解壓。');
      assets = await loadAssets();
      status.textContent = '資源已備妥，正在啟動引擎…';
      progress.value = .94;
      resizeCanvas();
      const engine = new Engine({...window.YOUXIA_CONFIG, canvas: byId('canvas'), canvasResizePolicy: 0, focusCanvas: false, args: ['--', '--no-steam']});
      engineAttempted = true;
      window.youxiaSceneReady = false;
      await engine.startGame({onPrintError: (...args) => console.error(...args)});
      const deadline = performance.now() + 90000;
      while (!window.youxiaSceneReady) {
        if (performance.now() > deadline) throw new Error('場景準備時間過長，請重新啟動。');
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      progress.value = 1;
      started = true;
      document.documentElement.dataset.playing = 'true';
      byId('welcome').hidden = true;
      byId('backup').disabled = false;
      byId('restore').disabled = false;
      byId('canvas').focus({preventScroll: true});
      document.documentElement.dataset.gameReady = 'true';
    } catch (error) {
      console.error(error);
      byId('failure').textContent = (error?.message || String(error)) + '\n按下方按鈕重試；已保存的角色會保留。';
      byId('failure').hidden = false;
      status.textContent = '尚未進入遊戲';
      play.disabled = false;
      play.textContent = engineAttempted ? '重新啟動江湖' : '重試進入江湖';
    } finally {
      window.fetch = nativeFetch;
      assets?.clear();
    }
  });
})();
