param([string]$Godot = 'K:\Godot\Godot_v4.6.3-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$youxiaRoot = Split-Path -Parent $PSScriptRoot
$youxiaVersion = (Select-String -LiteralPath (Join-Path $youxiaRoot 'project.godot') -Pattern '^config/version="([^"]+)"').Matches[0].Groups[1].Value
$youxiaOutput = Join-Path $youxiaRoot "build\windows-$youxiaVersion"
$youxiaExe = Join-Path $youxiaOutput 'Youxia.exe'
$youxiaOriginalAppData = $env:APPDATA
$youxiaOriginalLocal = $env:LOCALAPPDATA
$youxiaOriginalTemp = $env:TEMP
$youxiaOriginalTmp = $env:TMP
$youxiaBuildHome = Join-Path $youxiaRoot '.tools\appdata'
$youxiaTemplateDirectory = Join-Path $youxiaBuildHome 'Godot\export_templates\4.6.3.stable'
New-Item -ItemType Directory -Path $youxiaTemplateDirectory,$youxiaOutput -Force | Out-Null

# Read the already-installed official template; the export does not require a download.
$youxiaTemplateName = 'windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath (Join-Path $youxiaTemplateDirectory $youxiaTemplateName))) {
    $youxiaInstalledTemplates = Join-Path $youxiaOriginalAppData 'Godot\export_templates\4.6.3.stable'
    foreach ($youxiaFile in @($youxiaTemplateName,'version.txt')) {
        $youxiaSource = Join-Path $youxiaInstalledTemplates $youxiaFile
        if (-not (Test-Path -LiteralPath $youxiaSource)) { throw "Missing Godot 4.6.3 export template: $youxiaSource" }
        Copy-Item -LiteralPath $youxiaSource -Destination $youxiaTemplateDirectory -Force
    }
}
try {
    $env:APPDATA = $youxiaBuildHome
    $env:LOCALAPPDATA = Join-Path $youxiaRoot '.tools\localappdata'
    $env:TEMP = Join-Path $youxiaRoot '.tools\build-temp'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
    & $Godot --headless --path $youxiaRoot --import -- --no-steam
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    & $Godot --headless --path $youxiaRoot --export-release 'Windows Release' $youxiaExe -- --no-steam
    if ($LASTEXITCODE -ne 0) { throw 'Windows export failed.' }
} finally {
    $env:APPDATA = $youxiaOriginalAppData
    $env:LOCALAPPDATA = $youxiaOriginalLocal
    $env:TEMP = $youxiaOriginalTemp
    $env:TMP = $youxiaOriginalTmp
}
Copy-Item -LiteralPath (Join-Path $youxiaRoot 'steam_appid.txt') -Destination $youxiaOutput -Force
Copy-Item -LiteralPath (Join-Path $youxiaRoot 'addons\godotsteam\LICENSE.txt') -Destination (Join-Path $youxiaOutput 'GodotSteam-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $youxiaRoot 'assets\fonts\OFL.txt') -Destination (Join-Path $youxiaOutput 'Font-OFL.txt') -Force
Copy-Item -LiteralPath (Join-Path $youxiaRoot 'assets\bgm\SOURCE.txt') -Destination (Join-Path $youxiaOutput 'Music-Credits.txt') -Force
$youxiaCredits = @'
Classic presentation assets adapted with permission from the user's JY-Mini OL project:
- LXGW WenKai TC Regular, distributed under the SIL Open Font License (Font-OFL.txt).
- Four landscape backgrounds from assets/art/bg.
- Legacy chapter poses, river/cave scenery and map parchment from assets/art/units, bg and map.
- Cast, walking/action sheets, game skin and icons generated with built-in imagegen; prompts in art/characters-v2/PROMPTS.md.
- 100 enemy designs, 40 hero designs, 8 peaceful residents, 4 scenes and a replacement Mu Nianci sprite generated with built-in imagegen; prompts in art/open-world-jobs.json.
- 32 civilian portraits and 15 four-pose combat sheets generated with built-in imagegen; prompts in art/visuals/prompts.json.
- 41 companion four-pose sets generated with built-in imagegen; prompts in art/companions/prompts.json.
- 16 supporting story portraits generated with built-in imagegen; prompts in art/story-cast/prompts.json.
- Additional 19 animation sheets and 23 audio cues copied unchanged from owner-provided resources; exact sources and hashes in art/combat-fx.json.
- Selected town tiles/panorama, world map, character animation sheets, effects and SFX from the owner-supplied Jinyong Heroes 5 installation; see source repository assets/town/SOURCE.txt. No source scripts, event commands, saves or dialogue were imported.
- ui_frame.gd, ui_theme.gd and jy_button.gd, adapted into scripts/classic.
- Five owner-supplied BGM recordings from assets/bgm; see Music-Credits.txt.
Combat, inventory, party, trade and networking remain the Youxia simulator implementation.
Open-world dialogue and rules are independently written. Flash JY3 event topics and names are researched from public walkthroughs; see docs/OPEN-WORLD.md.
'@
Set-Content -LiteralPath (Join-Path $youxiaOutput 'Asset-Credits.txt') -Value $youxiaCredits -Encoding utf8
$youxiaReadme = @'
網金游俠模擬器 / Youxia __VERSION__ — Windows x64

解壓縮整個資料夾，雙擊 Youxia.exe 即可遊玩；不需要安裝 Godot、Python 或 PowerShell。
請把同資料夾的 DLL 與 steam_appid.txt 留在原位，給朋友時傳送整個 ZIP。

單機：直接啟動即可。Steam 未開啟時仍可玩單機。
預設進入自由江湖：100處命名場景、129份可選委託、41位新增可招募人物、100種獨立繪製對手。
新角色從牛家村開始，點頭像逐句交談，查看結交條件或個人往事。所有道路開放，不需要先清第一章。
新群俠須先完成自己的故事、累積交情並達到個別修為才可招募。
每位人物有獨立起因、行動和結局；借物、還債、護送、音律與棋局的流程各不相同，並非全部要求戰鬥。
41位新增群俠各有4格戰鬥姿勢；招式依武學區分特效與音效，蓄力有氣場，狀態標記顯示餘下回合。
委託接下後在「進行中」查看；前往目標直接帶到場景，交談、交付、切磋與回報都有實際效果。
到其他場景先見人物與故事，不會自動開戰；「附近挑戰」或「江湖群雄」可尋找對手，再自行接受挑戰。
隊伍四人、主角留隊，候補保留修為。外功、內功、輕功與前後排、上中下路都會影響戰鬥。
每輪先替同伴選普攻、施招或守勢，再按空白鍵／進行回合，依速度先後出手。
普攻帶動全體聚氣，25真元一格；技能受真元與調息限制。封招、破甲、越陣、療傷與蓄力有不同用途。
可拜入華山／武當／少林／全真／古墓。師父處消點耗12＋重數×3學點；自修每完成5秒耗8＋重數×3，上限三十重。
本作對話、任務步驟與平衡重新編寫，參照Flash金庸群俠傳3題材，並非原作逐字劇本或官方公式。
各地商店、客棧與指定醫館可買賣。選單可刪除存檔／重新開始；會再次確認，取消保留進度。
任務完成後可與人物談事件後續，再訪會聊日常；已完成委託不再重接。下方資訊列明列銀兩、學點、已探索地點和已招募同伴，事件提示有獨立深色底。v0.12.2沿用現有進度。「前往師父」依已加入的門派前往傳功地點，抵達後可直接消點。
C 同伴、K 武學、I 行囊、J 委託、M 地圖、D 每日、F8 選單、Esc 返回。
進度自動保存。v0.12.0首次載入舊自由江湖會先完整備份，再從牛家村重開；備份失敗保留原進度。選單可匯出重寫前舊檔，Windows會打開備份資料夾。新版其後讀檔不會重置，經典角色和聲音設定保留。
設定 → 進入舊版江湖／F9：開啟原有任務、副本、生活、Steam、區網與 WebSocket 聯機。
舊版左上「青溪新章」可返回新版；以下聯機和經典玩法說明適用於舊版江湖。
Steam：雙方先開 Steam 與遊戲，進「系統」頁開房／加入。開發測試 App ID 為 480。
區網：使用「區網開房」與房主 IP，UDP 24780。

互動：按 F7 或「人際」燈籠，選擇在線少俠，便可組隊、切磋、交易、援護及密語。
組隊：最多五人，隊員可跟隨隊長；同地點自動參與共同刷怪，獎勵平分、掉落擲一次。
切磋：需雙方同意，結束恢復開戰前氣血內力，沒有金錢或裝備損失。
PK：雙方先開啟野外 PK，安全區禁止；敗者送回揚州並關閉 PK。
交易：對方接受時才扣物品和銀兩，售價 0 表示贈送。
聊天：底部可切換千里傳音、隊伍頻道、密語對象。
快捷鍵：F1 自修、F2 打坐、F3 尋敵、F4 金創藥、F5 存檔、F6 江湖、F7 人際、F8 聯機。
BGM：按 F8／系統，可開關音樂、調整音量，或指定曲目；預設依場景及戰鬥自動切換。
武學：消點每次花 1 學點換熟練；自修每完整 5 秒花 3 學點，依悟性增加熟練，會耗精。
外功須配相容兵器；內功、輕功與格擋分開運用。武功頁顯示學習門檻、自修上限及尚缺條件。
任務：上方「任務 → 可接任務」，選任務後按「前往接任務」。到人物身旁可直接接取。
進行中任務有下一步、目的地、對話與交付按鈕；完成後按「領取獎勵」。一般任務不因加入門派而隱藏。
買賣：按上方「商店」，選購買或出售、物品與數量，確認總價。沒有商人時可點附近商店自動前往。
行囊：可使用物品、裝備、卸下，或直接跳到出售；任務信物不能買賣。
尋路：按地圖燈籠，輸入地名、人物或武功名，點目的地即自動前往。每秒走一站，停止可取消。
副本：按上方「副本」，選入口並前往；單人可直接進入，隊伍由隊長建立，所有隊員先按準備再開戰。
四個改編副本：黑風寨剿匪、銅人試陣、血刀密窟、高昌秘窟。每關可療傷，通關自動發獎；首通另有道具。
副本中可援護隊友；全隊戰敗或退出不發通關獎。未完成的副本不跨存檔恢復，已領獎勵、首通和冷卻會保留。
任務新增金盆洗手、尋找楊康、雲兒、清為等來源故事；場景互動、時辰及下一步都在任務頁操作。
可重複任務與副本按現實時間冷卻；等待任務保留已過的世界時間，離線不跳時。
Ctrl+1–9：江湖、任務、副本、商店、行囊、武學、地圖、人際、系統。
生活：上方「生活」或 Ctrl+0，選技能、尋師、學藝領工具，再前往工作地點、選配方與次數後開工。
11 技能：種田、樵夫、釣魚、廚師、挖礦、打鐵、鑄劍、工匠、織布、裁縫、獵人；38 配方、62 工作地點。
精力不足可自動打坐續作；缺材料、工具或其他條件不足會自停。工作每次完整等待才結算，可隨時停止。
缺料可跳到採集、製作或商店；成品與收成可直接開出售頁。狩獵使用自己的武功單獨戰鬥，有受傷風險。
生活熟練與已得物品會保存，未完成工作不跨讀檔恢復，沒有離線收益。部分配方、數值與教師是參考專案的設計提案。
劍法先學基本劍法，再買木劍；裝備兵器會選擇已學的相容外功。行囊可卸下兵器改用拳掌。
舊存檔的基本拳腳會自動更名為搏擊格鬥，保留等級與熟練。聯機雙方請使用相同版本。

存檔：%APPDATA%\Godot\app_userdata\網金游俠模擬器\youxia_save.json
每 30 秒、按 F5、退出遊戲時儲存，另保留 .bak 備份。
此 EXE 使用 Windows 的標準存檔位置；專案 tools/run.ps1 的隔離測試存檔不會自動搬入。

Godot Engine license and third-party attributions: https://godotengine.org/license/
GodotSteam license: GodotSteam-LICENSE.txt
'@
Set-Content -LiteralPath (Join-Path $youxiaOutput '如何遊玩.txt') -Value $youxiaReadme.Replace('__VERSION__', $youxiaVersion) -Encoding utf8
$youxiaArchive = Join-Path $youxiaRoot "build\Youxia-$youxiaVersion-Windows-x64.zip"
Compress-Archive -Path (Join-Path $youxiaOutput '*') -DestinationPath $youxiaArchive -Force
Get-ChildItem -LiteralPath $youxiaOutput | Select-Object Name,Length
Write-Output "ZIP: $youxiaArchive"
