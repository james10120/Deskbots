# 使用手冊

安裝見 [README](../README.md)；本文講開起來之後怎麼用。

---

## 1. 啟動模式

| 模式 | 怎麼開 | hooks | 關閉時 |
|------|--------|-------|--------|
| **乾淨模式**（推薦） | 雙擊 `app\run_deskbots.cmd` | 開啟時自動裝 | 自動還原全域設定、停背景行程、清 runtime |
| **常駐模式** | 先跑一次 `py app\apply_settings.py`，之後雙擊 `app\start_map.cmd` | 一直裝著 | 只停背景行程，設定不動 |

- 要被觀察的 Claude session 請在**地圖開啟後**才啟動（hwnd 在 SessionStart 抓一次就黏住）。
- 萬一啟動器視窗被強殺、設定沒還原：跑 `py app\apply_settings.py --remove`。
- 想讓 statusline / hooks 立即生效到「已開著」的 session：重開那個 session。

## 2. 機器人狀態

| Claude 事件 | 狀態 | 機器人行為 | 名牌色 |
|------------|------|-----------|--------|
| UserPromptSubmit | thinking | 在座位 | 藍 |
| PreToolUse / 輸出中 | working | 在座位工作 | 綠 |
| Notification（要授權） | waiting | 走到等待區滑手機 | **黃（最該看）** |
| Stop | done → idle | 走去休息室看書 | 綠 → 灰 |
| PostToolUse 出錯 | error | 在座位 | 紅 |
| SessionEnd / transcript 久未動 | 離場 | 機器人消失 | — |

中斷偵測：Claude Code 沒有中斷 hook，靠 transcript 檔的 mtime 當心跳（停止更新 → 回 idle）。

## 3. 地圖操作

- **點機器人** → 開/關對話卡
- **點空椅子** → 選資料夾，開新 PowerShell 跑 `claude`（新 session 入座）
- **按住空白處拖曳** → 移動整張地圖
- **WASD / 方向鍵** → 移動「你」的角色（純散步）
- 右上角：**設定** / **看板** / **釘選**（地圖永遠置頂）

視窗位置、置頂狀態、看板高度與顯示等會自動記住（`runtime/ui_state.json`），下次開啟還原。

## 4. 對話卡（點機器人）

- 顯示該 session **最近一輪 Q&A**（含工具呼叫摘要）
- 輸入框送訊息（Enter 送出、Shift+Enter 換行）；快捷鈕 `/clear`、`/compact`、`⎋中斷`
- **▸ 呼叫終端**：把該 session 的終端視窗叫到最前
- 送訊息原理是「聚焦終端 + 鍵盤注入」，所以**遠端 session 只顯示內容**，
  按鈕變成「▸ 在 VS Code 開啟」直達該機該資料夾
- 顯示「無可用終端」的原因與對策見 [ARCHITECTURE §5](ARCHITECTURE.md#5-失敗模式對話卡顯示無可用終端)

## 5. 工作看板

- 每個在場 session 一張卡：**負荷量表**（context 佔用，越滿越紅）、LV（隨產出成長）、
  ⚒ 產出 / 📖 閱讀 token、🔁 回合數；點卡片＝開該 session 對話卡
- 底部「**拖此調整高度**」把手；標題列 📌 釘選看板（與地圖置頂分開）
- **人才庫**：近期用過、目前沒在跑的專案（本地＋各遠端機器合併、依最後活動排序）
  - 點本地列 → 開新 PowerShell `claude -c` 接續上次對話（重新雇用）
  - 點遠端列（`專案@機器`）→ 開 VS Code Remote 直達該工作目錄
  - **✕ 移除**：從人才庫拿掉；該專案之後有新活動會自動回來

## 6. 設定卡

- **地圖永遠置頂**（與右上「釘選」同步）、**顯示/隱藏工作看板**
- **SSH 伺服器**：
  - 清單：綠點＝已連線＋在場 session 數；**VS Code** 鈕開該機的 Remote 視窗；✕ 從清單移除
  - 新增：輸入 `user@ip`（或 ssh 別名）→ **＋ 連線安裝** → 跳出終端視窗自動完成
    金鑰產生/推送（輸一次該機密碼）→ 部署 agent + hooks → 登記。**不用重開地圖**，
    橋接會熱載入，該機 session 機器人自動出現
- **⏻ 離開遊戲**：關閉地圖；乾淨模式下啟動器接著自動還原環境

SSH 指令版與需求：

```
py app\remote_install.py user@ip --bootstrap [--label 短名]   # 安裝（label 顯示在名牌）
py app\remote_install.py user@ip --remove                     # 卸載遠端 hooks
```

遠端需求：Linux/macOS、python3、sshd；本地 `ssh user@ip` 必須金鑰免密碼（bootstrap 自動設定）。

## 7. Debug 旗標

```
godot --path godot -- --grid    # 顯示格線 + S/W/L 錨點標記（座位/等待/休息）
godot --path godot -- --shot    # 跑 1 秒自動截圖（地圖/看板/開著的卡片）後退出
godot --path godot -- --bot     # 角色表檢視
```

打包版同樣支援：`godot\Deskbots.exe -- --grid`。

## 8. runtime/ 檔案一覽（全部 gitignored）

| 檔案 | 誰寫 | 內容 |
|------|------|------|
| `sessions/<id>.json` | emit.py / ssh_bridge | 每個 session 的狀態（遠端的檔名為 `<label>__<id>`） |
| `usage.json` | usage_poll | 各 session token 用量 |
| `rehire.json` / `rehire_remote.json` | usage_poll / ssh_bridge | 本地 / 遠端人才庫 |
| `rehire_hidden.json` | 看板 ✕ | 人才庫移除名單（跨次保留） |
| `ui_state.json` | main.gd | 視窗位置/置頂/看板狀態（跨次保留） |
| `bridge.json` | ssh_bridge | 各伺服器連線狀態（設定卡綠點） |
| `transcripts/` | ssh_bridge | 遠端 transcript 尾段快取（對話卡/心跳用） |

## 9. 疑難排解

| 症狀 | 原因 / 解法 |
|------|------------|
| 機器人沒出現 | session 在地圖開啟**前**就開了 → 重開該 session；或 hooks 沒裝（跑 `py app\apply_settings.py`） |
| 對話卡「無可用終端」 | 見 [ARCHITECTURE §5](ARCHITECTURE.md)；VS Code 整合終端抓不準，用啟動器/空椅開的獨立 PowerShell 最穩 |
| 遠端伺服器灰點（未連線） | `ssh user@ip` 是否免密碼？遠端有 `python3`？防火牆？看 bridge 視窗的重連訊息 |
| 中文變亂碼 | 終端切 UTF-8（啟動器已自動 `PYTHONUTF8=1`） |
| 想徹底移除 | `py app\apply_settings.py --remove`（本地）＋ `py app\remote_install.py <host> --remove`（各遠端），刪掉整個資料夾即可，不留任何系統殘留 |
