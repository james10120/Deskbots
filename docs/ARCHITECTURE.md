# 架構：對話卡 ↔ PowerShell 終端

說明地圖裡的「對話卡」如何跟每個 Claude Code session 所在的 **PowerShell / 終端視窗**互動——
怎麼抓到那個視窗、怎麼把訊息和斜線指令打進去、以及為什麼有時會「抓不到終端」。

---

## 1. 全景資料流

```
   ┌─────────────────────── Claude Code session（跑在某個終端視窗裡）──────────────────────┐
   │                                                                                        │
   │   你在 PowerShell 打 `claude` ── TUI 跑起來                                             │
   │        │                                                                               │
   │        │  每個事件觸發 hook（settings.json 註冊）                                       │
   │        ▼                                                                               │
   │   py app/emit.py <EVENT>   ←── stdin 收到該事件的 JSON                                  │
   │        │   1. 算狀態（idle/working/waiting…）                                           │
   │        │   2. 抓終端視窗 handle（hwnd）→ winfocus.terminal_hwnd()                       │
   │        │   3. 原子寫入 runtime/sessions/<session_id>.json                              │
   │        ▼                                                                               │
   └────────┼───────────────────────────────────────────────────────────────────────────┘
            │  （檔案系統當作 IPC，零耦合）
            ▼
   runtime/sessions/<id>.json   { state, project, cwd, hwnd, transcript, ts, … }
   runtime/usage.json           ← usage_poll.py 每 2s 解析 transcript 算 token 用量
   runtime/rehire.json          ← usage_poll.py 掃歷史專案，供「重新雇用」
   runtime/rehire_hidden.json   ← 看板 ✕ 移除的人才庫項目（該專案有新活動會自動回來）
   runtime/ui_state.json        ← 視窗位置/置頂/看板狀態（main.gd 每 2s 有變才寫，下次開啟還原）
            ▲
            │  SSH 多伺服器（ssh_bridge.py 常駐；config/servers.json 熱載入）
   每台一條長連線：ssh <host> python3 ~/deskbots/app/remote_agent.py
        ├ 遠端 agent：2s 一次 session 快照（狀態在遠端衰減、時間送 age 免時鐘偏差、
        │             transcript 尾段有變才附）+ 30s 掃遠端 ~/.claude/projects
        ├ 鏡像寫 runtime/sessions/<label>__<id>.json（專案名@label、hwnd=0）
        ├ transcript 尾段落地 runtime/transcripts/ 並把路徑指過去 → 心跳/對話卡原樣生效
        ├ runtime/bridge.json         ← 連線狀態（設定卡綠點/在場數）
        └ runtime/rehire_remote.json  ← 遠端人才庫（點了開 VS Code Remote 直達資料夾）
            │
            │  Godot 每秒重讀
            ▼
   ┌──────────────── Godot 地圖（main.gd）─────────────────┐
   │   機器人精靈（依 state 換動畫）                          │
   │   點機器人 → 開「對話卡」(_detail_win)                   │
   │        ├ 顯示最近一輪 Q&A（讀 transcript）              │
   │        ├ 輸入框 + 快捷鈕（/clear /compact ⎋中斷）      │
   │        └ 「▸ 呼叫這個 session 的終端視窗」鈕            │
   │                  │                                     │
   │                  │ 用該 session 的 hwnd                 │
   │                  ▼                                     │
   │   OS.create_process("py", winfocus.py <hwnd> [--send]) │
   └──────────────────┼─────────────────────────────────────┘
                      ▼
   py app/winfocus.py <hwnd> [--send <text>]
        ├ 無 --send：focus(hwnd) 把終端叫到最前
        └ 有 --send：focus → 等它真的到前景 → SendInput 逐字注入 → Enter
                      │
                      ▼
              那個 PowerShell / 終端視窗（Claude TUI 收到輸入）
```

**核心設計**：行程之間**不直接通訊**，全靠 `runtime/` 下的 JSON 檔當信箱。
hook（emit.py）只寫、Godot 只讀、winfocus 只負責 Win32 視窗操作。任何一邊掛掉都不會拖垮另一邊。

---

## 2. 怎麼抓到 session 的終端視窗（hwnd）

這是整條鏈最脆弱的一環。`hwnd`（Windows 視窗 handle）在 **SessionStart 那一刻**由 `emit.py` 抓下，
之後**黏住**整個 session 重用（終端視窗不會變）。

`winfocus.terminal_hwnd()` 依序嘗試三種方法：

1. **`GetConsoleWindow()`** — 獨立 PowerShell 視窗最直接，自己就有 console。
2. **往上爬父行程** — VS Code / Windows Terminal 用 ConPTY，python 自己沒有可見 console，
   就沿父行程鏈找「有可見主視窗」的祖先（最多爬 12 層）。
3. **`foreground_hwnd()` 前景視窗後備** — 上面兩個都失敗時用。
   SessionStart 當下你剛在終端打完 `claude`，**終端正是前景視窗**，直接抓 `GetForegroundWindow()`。
   會用**行程名驗證**確實是終端類（見 `_TERMINAL_EXES`：WindowsTerminal / wt / openconsole /
   conhost / powershell / pwsh / cmd / code / alacritty）才採用，否則回 0——避免誤抓到地圖本身或別的 app。

> **為什麼需要前景後備（commit d50256e）**：Windows 的父行程鏈常斷。`claude` 經 npm/cmd shim 啟動，
> 那些中間 shim 行程啟動完就結束，PPID 懸空 → 方法 2 往上爬找不到視窗 → 以前就回 0 →
> 「永遠無可用終端」。前景後備繞過整條斷掉的鏈。

`emit.py` 的黏住邏輯（省效能、保穩定）：
```python
def terminal_hwnd(session_id):
    prev = states.read_state(session_id)
    if prev and prev.get("hwnd"):   # 開場抓到後就一直用，高頻事件(PreToolUse)不重抓、不 import winfocus
        return int(prev["hwnd"])
    return winfocus.terminal_hwnd()  # 第一次（通常 SessionStart）才真的抓
```

---

## 3. 對話卡怎麼送訊息 / 指令給 Claude

對話卡（`_detail_win`，一個獨立 Godot `Window`）底部有三種互動，都走同一條路：

| UI | 動作 | 呼叫 |
|----|------|------|
| 輸入框 Enter | 送一句話給 Claude | `_send_to_selected(text)` |
| `/clear` `/compact` 快捷鈕 | 送斜線指令 | `_send_to_selected("/clear")` |
| `⎋中斷` 鈕 | 中斷 Claude 當前動作 | `_send_to_selected("<ESC>")` |
| `▸ 呼叫終端` 鈕 | 只把終端叫到最前（不送字） | `_focus_selected_terminal()` |

兩者最後都 `OS.create_process("py", ["…/winfocus.py", str(hwnd), …])`，把實際的 Win32 操作丟給獨立 python 行程（Godot 不碰 ctypes）。

`winfocus.send_text(hwnd, text)` 的注入流程：
1. `focus(hwnd)`：按住 Alt 繞過 `SetForegroundWindow` 限制 → 把終端叫到最前。
2. **等它真的到前景**（聚焦是非同步的，最多輪詢 1s）；沒到就**放棄不打字**，避免打進別的視窗。
3. 用 `SendInput` + `KEYEVENTF_UNICODE` **逐個 UTF-16 code unit** 打字（支援中文 / emoji）。
4. 停 0.15s 給 TUI 一拍處理（斜線指令選單），再送 `Enter`。
5. 特例 `text == "<ESC>"`：只送一個 `VK_ESCAPE`，不送 Enter。

> **行為（commit bd1ffe0）**：按「呼叫終端」後**不**關對話卡，方便接著繼續送訊息。

---

## 4. 開新 session：launch_claude.cmd（重新雇用 / 空椅 / 選資料夾）

地圖要「開一個新的 Claude session」時，不是自己跑 claude，而是**開一個全新的獨立 PowerShell 視窗**
（這種視窗 `GetConsoleWindow()` 抓得最準）：

```bat
start "Claude" powershell.exe -NoExit -Command "Set-Location -LiteralPath '%~1'; claude %~2"
```
- 第 1 參數 = 專案資料夾。
- 第 2 參數 = 傳給 claude 的旗標，例如 `-c`（接續上次對話）= **重新雇用**。

觸發來源：
- **人才庫「↻ 重新雇用」** → `launch_claude.cmd <cwd> -c`（cwd 來自 `rehire.json`，由 usage_poll 掃歷史專案產生）。
- **選資料夾**（FileDialog）→ `launch_claude.cmd <選的資料夾>`。

> 必須維持 **ASCII-only**：cmd.exe 以 cp950 解析批次檔，含中文會被斷成亂碼指令。

---

## 5. 失敗模式：對話卡顯示「無可用終端」

當 session JSON 的 `hwnd == 0`，送訊息 / 呼叫終端都無法用。對話卡會**明確提示**而非靜默失敗
（`_refresh_detail`）：輸入框變灰、橘字說明、按鈕閃 `_detail_hint`。

| 情況 | 為什麼 hwnd=0 | 對策 |
|------|--------------|------|
| 父行程鏈斷（npm/cmd shim 退出） | 爬不到視窗 | 已修：前景視窗後備（§2 方法 3） |
| agent 自身的 session | 沒有正常可聚焦視窗 | 無解，正常現象 |
| VS Code 整合終端 | 多視窗共用、ConPTY 無可見 console | 用啟動器開的獨立 PowerShell 才穩 |
| 修正前就開著的舊 session | 開場時還沒這段程式碼 | **重開 session** 才生效（hwnd 在 SessionStart 抓） |
| Windows Terminal 多分頁 | WT 多視窗共用同一行程，只能抓到第一個 | 獨立 PowerShell 視窗最準 |

> 重點：hwnd 在 **SessionStart 抓一次就黏住**。所以任何抓取邏輯的修正，**只對之後新開的 session 生效**，
> 對當下還開著的舊 session 無效——要重開 session 才會套用。

---

## 6. 狀態機與時間衰減

事件 → 狀態的權威對照在 `app/states.py`（`EVENT_STATE`）；但 Claude Code **沒有「中斷/恢復」hook**，
所以光看事件會卡在過時狀態。兩邊（Python `states.decay_state` 與 Godot `main._upsert`）用同一套
時間衰減自我修正，**主要活躍訊號是 transcript 檔的 mtime**（正在輸出＝檔案一直在長大）：

| 規則 | 門檻 | 效果 |
|------|------|------|
| transcript 剛動過 | < 6s | 一律視為 working（覆蓋過時的 waiting/thinking） |
| done 顯示一下 | > 5~8s | 回 idle（去休息室） |
| waiting 等太久沒動作 | > 180s | 回 idle（避免卡死在等待區） |
| thinking/working 久未輸出 | > 120s | 回 idle（容忍長回合的工具空檔） |
| transcript 與事件都很舊 | > 1800s | 殭屍 session，機器人離場 |

SSH 遠端 session 的衰減在**遠端**先算（transcript 在那台才讀得到），時間以「距今秒數」傳輸、
本地還原，所以兩台機器時鐘不同步也不影響；transcript 尾段落地成本地快取檔後，
Godot 的 mtime 心跳對遠端照常生效。

---

## 相關檔案

| 檔案 | 角色 |
|------|------|
| `app/emit.py` | hook 進入點：算狀態、抓 hwnd、寫 session JSON。絕不拋例外、絕不阻塞。 |
| `app/states.py` | 共用：路徑、狀態定義、session 檔讀寫、時間衰減。零外部相依。 |
| `app/winfocus.py` | Win32（純 ctypes）：`terminal_hwnd` 抓視窗、`focus` 聚焦、`send_text` 鍵盤注入。 |
| `app/usage_poll.py` | 背景常駐：解析 transcript 算 token 用量（`usage.json`）、掃歷史專案（`rehire.json`）。 |
| `app/ssh_bridge.py` | 背景常駐：每台伺服器一條 ssh 長連線，鏡像遠端 session；`servers.json` 熱載入。 |
| `app/remote_agent.py` | 部署在遠端：串流該機 session 快照與近期專案給 bridge。 |
| `app/remote_install.py` | 一鍵部署遠端（`--bootstrap` 含 SSH 金鑰設定）；`add_server.cmd` 為遊戲內入口。 |
| `app/launch_claude.cmd` | 開新獨立 PowerShell 視窗跑 claude（含 `-c` 重新雇用）。ASCII-only。 |
| `godot/main.gd` | 主迴圈：session 掃描與狀態機、角色行為、玩家、視窗訊號接線。 |
| `godot/paths.gd` `util.gd` | 安裝路徑單一出處；JSON 讀寫／樣式／格式化共用小工具。 |
| `godot/office_map.gd` | 地圖載入、A* 走格、座位/休息點地理。 |
| `godot/drag_window.gd` | 無邊框透明卡片視窗共用底座（拖曳/卡片），三張卡片視窗的父類。 |
| `godot/detail_window.gd` | 對話卡：最近一輪 Q&A、送訊息/指令（signal 回 main 執行）。 |
| `godot/usage_board.gd` | 工作看板：負荷/LV/戰績 + 人才庫（↻ 重新雇用、✕ 移除）。 |
| `godot/settings_window.gd` | 設定卡：地圖置頂、看板開關、⏻ 離開遊戲。 |
| `runtime/sessions/*.json` | 每個 session 的狀態（含 hwnd）。emit 寫、Godot 讀。 |
