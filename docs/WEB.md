# 網金游俠瀏覽器版

入口：[瀏覽器江湖](https://youxia-jianghu-web.alexchon911.chatgpt.site)。目前是 Sites 的私人部署，只有擁有者可開啟。按「進入江湖」載入遊戲，第一次下載連同地景約 46 MB。

這是現有 Godot 4.6.3 遊戲的 WebAssembly 匯出，沒有另外重寫武學、任務、副本或生活規則。畫面沿用經典客戶端，主要適合電腦與平板橫向操作；不是手機原生介面的重製。需要 WebAssembly 與 WebGL 2，建議新版 Chrome、Edge 或 Firefox。採用單執行緒模板，不需要 SharedArrayBuffer 或跨來源隔離標頭。[Godot 官方 Web 匯出說明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)。

## 存檔與背景掛機

單機角色保存在此網站／此瀏覽器的 IndexedDB。定期存檔與 F5 遊戲存檔仍在，工具列提供角色 JSON 備份匯出和匯入。可以匯入 Windows 版的 `youxia_save.json`，或把匯出的 JSON 作為桌面版角色備份使用。匯入會停止未完成行程、戰鬥、副本與掛機，保留已獲物品與熟練。

匯入前會檢查版本、資料容器與基本數量型別，並要求確認替換。聯機角色由房主保存，客戶端不能匯入自己的數值到房主角色。不要在開著桌面遊戲時替換桌面版的存檔；先退出，並保留原檔備份。

清除網站資料、無痕模式或禁止儲存可能令角色無法保留，建議定期匯出。離開／關閉分頁後不會補算單機收益，瀏覽器亦可能暫停背景分頁；這不等於雲端掛機。背景與儲存限制詳見 [Godot 官方說明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#limitations)。

## 聯機

Sites 目前只承載瀏覽器遊戲檔案，沒有內建雲端房主。瀏覽器版的「系統」頁只顯示 WebSocket 聯機；原生版本仍保留 Steam 與 UDP。

有 Godot 與此原始碼的房主可執行：

```powershell
.\tools\run.ps1 -Headless -NoSteam -Script res://scripts/web_host.gd -GameArgs '--web-port=24781'
```

以本版原始碼執行的原生圖形介面也有「WebSocket 開房 · 24781」；先前發布的 v0.6.0 Windows ZIP 尚未包含此入口。本機測試用 `ws://127.0.0.1:24781`；正式 HTTPS 網站須連 `wss://`。可用 HTTPS 反向代理接到房主的 TCP 24781。瀏覽器也可在遊戲指令列輸入 `web wss://房主網址`。

房主與訪客沿用協議 7：角色登記、移動、學藝、戰鬥、組隊、PK、交易、生活工作與存檔都由房主處理。WebSocket 模式用安裝識別碼記住訪客，適合受信任的朋友；目前未新增帳號登入、公開伺服器管理或跨房主角色同步。HTTPS／WSS 外部反向代理和跨機連線尚未在本環境實測。

## 建置與部署

```powershell
python tools/fetch_web_templates.py
.\tools\export_web.ps1
python tests/browser_web_test.py
.\tools\test.ps1 -WebSocketNetwork -NetworkOnly
python tools/check_web_sensitive.py
```

模板工具只從官方 GitHub 發布包以 HTTP 範圍請求取出單執行緒 Web 模板，不下載整個 1.25 GB 模板合集。匯出工具在 `.tools/web-project` 建立隔離來源，只包含遊戲的 scripts、scenes、assets、data 與 web，不帶入 GodotSteam 原生擴充、私人存檔或測試資料。

原始匯出位於 `build/web-raw`；網站檔案位於 `sites/youxia-web/dist`。引擎與 PCK 以 gzip 壓縮並分割成最多 8 MiB 的內容雜湊分塊，啟動器逐塊檢查 SHA-256、解壓後再驗證完整檔案，交給 Godot 原本的載入器。沒有外部資源代理或 Service Worker。重新匯出會更新分塊名稱，避免舊資源快取與新版本混用。

Sites 的 project ID 保存在 `sites/youxia-web/.openai/hosting.json`，來源同步、打包與私人發布使用 Sites 官方技能流程。同一個網站應沿用此 ID，不要重複建立。部署檔與 Sites 來源 Git 目錄不提交到遊戲 GitHub 原始碼庫，網站只發送明確的靜態成品。

## 已驗證

- Chromium 真實啟動、畫布大小、滑鼠切頁、JSON 匯入／匯出、重新整理後的 IndexedDB 持久儲存。
- 真實瀏覽器透過 WebSocket 接原生房主，以及房主保存訪客；雙原生程序另驗證完整組隊、PK、交易與生活工作流程。
- 原有世界、武學、任務路徑、副本、生活技能、介面與存檔回歸測試。
- 上傳前掃描來源、網站檔案、重建後 PCK、PNG 中繼資料；WASM 必須逐位元符合官方模板。

未完成手機專項操作驗收、所有瀏覽器／裝置相容性，以及跨機 Steam／外部 WSS 驗證。
