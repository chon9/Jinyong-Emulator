# 網金游俠模擬器 · v0.4.0

Godot 4.6.3 的文字武俠模擬器，可單機、Steam Spacewar 480 與區網聯機。經典介面、字型、地景與音樂沿用使用者提供的 JY-Mini OL 資源。

目前內容：270 個相連地點、292 位 NPC、174 件物品、137 種敵人、11 門派、124 門武學、12 條人物故事、71 份收集委託，以及 29 份來源學藝／入門任務資料。部分特殊任務步驟尚未開放，會明確提示，不能跳過領獎。

數值來源、歷史版本差異及尚未完全還原的內容，見 [復原研究與規則](RESTORATION.md)。上一版的 [武學與兵器分類](MARTIAL_RULES.md) 保留作歷史修正紀錄；本版消點、自修及戰鬥以 RESTORATION 為準。

## Windows 遊玩

解壓縮 `build/Youxia-0.4.0-Windows-x64.zip`，雙擊 `Youxia.exe`。不需安裝 Godot、Python 或 PowerShell。請保留 DLL、steam_appid.txt 及授權文件。

快捷鍵：F1 自修、F2 打坐、F3 尋敵、F4 金創藥、F5 存檔、F6 江湖、F7 人際、F8 音樂與聯機。Ctrl+1–7 切換燈籠頁；Esc 返回江湖。

## 前十分鐘

1. 點地圖燈籠，搜尋基本刀法／基本劍法。選擇師父，確認目的地與下一站，再按自動前往。
2. 到武館後打開武功頁，向當地師父消點。每次扣 1 學點與精，增加熟練；悟性越高越有效率。沒有實戰時最多練到五級。
3. 買相容兵器再運用外功；內功、輕功、格擋各有選擇。行囊可卸下兵器，改用拳掌。
4. 回揚州接除患懸賞，到城郊荒野刷怪。獲得終身實戰、學點與銀兩；完成懸賞後回城領賞。
5. 需要休息時打坐。普通自修每完整五秒消耗 3 學點與精，增加熟練；不再是免費練功。中斷、趕路或退出不結算未完成週期。
6. 在武功頁查看門派、性別、善惡與屬性條件。散人可先選男／女；本作提供一次先天配置，預算明標為本作便利設定。
7. 武當、華山等入門須完成引薦或試鍊。到故事頁看學藝機緣，或在地圖搜尋機緣名稱。事件武功先完成任務，再依規則消點或自修。

搜尋武功也能找授課師父或授藝事件的發起人；不會把沒有授課的同名人物當目的地。途中可看完整路線，按停止取消。跟隨隊長時先取消跟隨，才能自行尋路。

## 多人互動

最多五人組隊，同地點共同刷怪，獎勵平分、掉落只擲一次。隊員可跟隨隊長，使用自己的金創藥援護隊友，並用隊伍頻道或私聊。

切磋須雙方同意，結束恢復開戰前氣血內力。野外 PK 須雙方開啟，安全區禁止；敗者送回揚州並關閉 PK。交易在接受時重新驗證數量、裝備及銀兩，售價零即贈送。

所有人使用 v0.4.0，協議 4，Steam 大廳標記 youxia_text_v4。先開 Steam，再用 F8 開房或輸入大廳 ID。區網使用房主 IP，UDP 24780；同機可用 127.0.0.1。自動測試涵蓋雙程序真實連線；兩個 Steam 帳號跨機測試仍未完成。

主機計算移動、消點、自修、任務、戰鬥與交易，並保存客人的進度。客戶端只發指令，不提交角色數值或任務旗標。沒有主機遷移。

## 存檔

獨立 EXE：`%APPDATA%/Godot/app_userdata/網金游俠模擬器/youxia_save.json`。每 30 秒、F5 與離開時保存，另有 .bak 備份。主檔壞掉時讀取備份。

保留舊版已學等級與物品；本級熟練按比例遷移一次。舊角色等級不再加攻防或觸發全補。未完成的自修週期、行程及戰鬥不跨存檔恢復；任務、對話與已完成目標會保留。

## 開發、測試與匯出

```powershell
.\tools\run.ps1 -Headless -NoSteam -Import
.\tools\run.ps1
.\tools\test.ps1 -SocialNetwork
.\tools\export_windows.ps1
```

可用 `-Godot 'D:\Godot\Godot_v4.6.3-stable_win64_console.exe'` 指定引擎。匯出需要 Godot 4.6.3 標準版及相同版本 Windows export template。GodotSteam 4.23 已附在 addons/godotsteam。

tools/run.ps1 將開發快取及存檔隔離到 .tools，不影響 EXE 的標準存檔。匯出產物放在 build/windows-0.4.0 與 Windows ZIP，不提交 Git。

| 模組 | 位置 |
| --- | --- |
| 學習、條件、熟練遷移 | scripts/progression.gd |
| 攻防、命中、招式與消耗 | scripts/combat_rules.gd |
| 學藝機緣、對話、物品與考較 | scripts/learning_quests.gd |
| 世界指令、移動與獎勵 | scripts/world.gd |
| 組隊、交易與 PvP | scripts/social.gd |
| 主機權威、RPC 與存檔 | scripts/session.gd |
| 搜尋與經典介面 | scripts/content.gd、scripts/main.gd、scripts/classic |
| 來源轉換 | tools/build_catalog.py（唯讀來源專案） |

發布前將變更加入 Git，執行 `python tools/check_sensitive.py --asset build/Youxia-0.4.0-Windows-x64.zip`。掃描確切上傳清單、圖片中繼資料、原始碼與 ZIP；私人存檔、工具快取及測試輸出不得提交。
