/* Browser shell around the original Godot game; no duplicate game rules. */
(() => {
  'use strict';
  const byId = id => document.getElementById(id);
  const play = byId('play');
  const status = byId('status');
  const progress = byId('progress');
  const nativeFetch = window.fetch.bind(window);
  let started = false;
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

  async function loadAssets() {
    const response = await nativeFetch('asset-manifest.json');
    if (!response.ok) throw new Error('無法取得遊戲資源清單，請重新整理再試。');
    const manifest = await response.json();
    const total = manifest.assets.reduce((sum, asset) => sum + asset.parts.reduce((n, part) => n + part.size, 0), 0);
    let received = 0;
    const assets = new Map();
    for (const asset of manifest.assets) {
      const buffers = [];
      for (const part of asset.parts) {
        const result = await nativeFetch(part.url);
        if (!result.ok) throw new Error('遊戲資源下載失敗，請檢查網路後重試。');
        const reader = result.body.getReader();
        const chunks = [];
        let length = 0;
        while (true) {
          const {done, value} = await reader.read();
          if (done) break;
          chunks.push(value); length += value.length; received += value.length;
          progress.value = received / total;
          status.textContent = `準備江湖 · ${(received / 1048576).toFixed(1)} / ${(total / 1048576).toFixed(1)} MB`;
        }
        const buffer = new Uint8Array(length);
        let offset = 0;
        for (const chunk of chunks) { buffer.set(chunk, offset); offset += chunk.length; }
        if (length !== part.size || await digest(buffer) !== part.sha256) throw new Error('資源校驗失敗，請重新整理再試。');
        buffers.push(buffer);
      }
      let stream = new Blob(buffers).stream();
      if (asset.encoding === 'gzip') stream = stream.pipeThrough(new DecompressionStream('gzip'));
      const buffer = await new Response(stream).arrayBuffer();
      if (buffer.byteLength !== asset.size || await digest(buffer) !== asset.sha256) throw new Error('遊戲資源解壓校驗失敗。');
      assets.set(new URL(asset.path, location.href).href, {buffer, type: asset.path.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream'});
    }
    // Feed verified buffers to Godot's unchanged loader. The hosted files remain
    // small chunks; no service worker, cross-origin headers or remote proxy needed.
    window.fetch = (input, options) => {
      const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, location.href).href;
      const asset = assets.get(url);
      if (!asset) return nativeFetch(input, options);
      return Promise.resolve(new Response(asset.buffer, {headers: {'Content-Type': asset.type, 'Content-Length': String(asset.buffer.byteLength)}}));
    };
    return assets;
  }

  play.addEventListener('click', async () => {
    play.disabled = true;
    byId('loading').hidden = false;
    status.textContent = '正在準備江湖…';
    try {
      const missing = Engine.getMissingFeatures({threads: false});
      if (missing.length) throw new Error('此瀏覽器缺少遊戲所需功能：' + missing.join('、') + '。請使用支援 WebGL 2 的新版 Chrome、Edge 或 Firefox。');
      if (typeof DecompressionStream === 'undefined') throw new Error('請更新瀏覽器，以支援遊戲資源解壓。');
      const assets = await loadAssets();
      status.textContent = '資源已備妥，正在展開江湖…';
      resizeCanvas();
      const engine = new Engine({...window.YOUXIA_CONFIG, canvas: byId('canvas'), canvasResizePolicy: 0, focusCanvas: false, args: ['--', '--no-steam']});
      await engine.startGame({onPrintError: (...args) => console.error(...args)});
      assets.clear();
      window.fetch = nativeFetch;
      started = true;
      byId('welcome').hidden = true;
      byId('backup').disabled = false;
      byId('restore').disabled = false;
      byId('canvas').focus({preventScroll: true});
      document.documentElement.dataset.gameReady = 'true';
    } catch (error) {
      console.error(error);
      byId('failure').textContent = (error?.message || String(error)) + '\n可重新整理頁面重試；已保存的角色不會因此刪除。';
      byId('failure').hidden = false;
      status.textContent = '尚未進入遊戲';
    }
  });
})();
