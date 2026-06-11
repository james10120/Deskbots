<p align="center">
  <img src="assets/icon.png" width="120" alt="Deskbots">
</p>

# Deskbots — Claude Code 機器人辦公室地圖

把每個正在執行的 Claude Code session 變成一張俯瞰辦公室地圖上的小機器人：
工作時坐在自己座位、等你授權時走到等待區滑手機、忙完走去休息室看書。
透明置頂疊在桌面上，一眼看出哪個專案在忙、哪個在等你。

## 架構

```
資料層 (Python，引擎無關)              渲染層 (Godot 4，OpenGL Compatibility)
Claude Code hooks                       透明置頂疊層視窗
  └ app/emit.py <EVENT>                 Tiled 模組地圖拼接渲染
      └ 寫 runtime/sessions/<id>.json → 每 session 一隻角色 (BOT1~9)
app/statusline.py                       依狀態走位/播動畫、A* 繞牆尋路
  └ 底部狀態列文字進度                   每 ~0.4s 輪詢 sessions/ 增刪角色
```

## 狀態 → 行為 / 動畫

| Claude 事件 | state | 機器人行為 | BOT 動畫 |
|------------|-------|-----------|---------|
| SessionStart | idle | 走去休息室看書 | 看書(第8列) |
| UserPromptSubmit | thinking | 在座位 | 待機(第2列) |
| PreToolUse | working | 在座位工作 | 待機(第2列) |
| Notification | waiting | 走到等待區滑手機 | 滑手機(第7列) |
| Stop | done | 走去休息室看書 | 看書(第8列) |
| (移動中) | — | 沿走道繞牆 | 走路(第3列) |
| SessionEnd | — | 離場 | — |

中斷偵測：Claude Code 無中斷 hook，靠 transcript 檔的 mtime 當心跳（停止更新→回 idle）。

## 啟動

**乾淨模式（推薦）**：雙擊 **`app/run_deskbots.cmd`**。開啟時自動安裝 hooks/statusLine，**關閉地圖後自動還原全域設定、停背景行程、清 runtime**，跑完不在 `~/.claude/settings.json` 留任何痕跡（`try/finally` 保證收尾）。
→ 要被觀察的 Claude session 請在**開啟 Deskbots 之後**才啟動，才會出現機器人。
→ 萬一 powershell 被強制砍掉（finally 來不及跑），跑一次 `py app/apply_settings.py --remove` 即可手動還原。

**常駐模式**：先跑一次 `py app/apply_settings.py` 把 hooks/statusLine 併入全域設定（idempotent、非破壞性、會備份 `.bak`），之後雙擊 **`app/start_map.cmd`** 只開地圖。要卸載時 `py app/apply_settings.py --remove`（只移除 Deskbots 自己的設定並還原你原本的 statusLine）。

## 使用量數據窗

地圖右側面板顯示每個在場 session 的 token 用量（in/out/cache）、回合數、context 佔用條（越滿越偏紅）+ 合計。資料來自 `app/usage_poll.py`（背景常駐，增量解析各 session transcript 寫 `runtime/usage.json`）。點面板上的卡片＝跳到該 session（同點機器人，開對話卡）。

## 檔案

- `app/emit.py` — hook 進入點（`py emit.py <EVENT>`），永不拋例外、永遠 exit 0
- `app/states.py` — 共用：狀態對照、角色分配(BOT1~9)、session 檔讀寫
- `app/statusline.py` — statusLine 文字進度
- `app/bake_map.py` — 把 Tiled 模組依 `COMPOSITION` 拼成 `map_baked.json`（圖層+障礙格+座位/休息/等待錨點）
- `app/usage_poll.py` — 背景常駐，增量算各 session token 用量 → `runtime/usage.json`
- `app/clean_sessions.py` / `apply_settings.py`（套用/`--remove` 移除）— 維運
- `app/run_deskbots.cmd`(+`.ps1`) — 乾淨生命週期啟動（裝→用→關自動還原）；`start_map.cmd` — 只開地圖
- `godot/*.gd` — main(主迴圈)/office_map(地圖與地理)/detail_window(對話卡)/usage_board(看板)/settings_window(設定)/drag_window/util/paths
- `assets/characters/BOT1~9.png` — 角色動畫表（16×32 幀）
- `assets/tiled/office_*.tmj` + tileset PNG — Tiled 地圖模組（entrance/lounge/passage/room/end）
- `runtime/sessions/<id>.json` — 執行期狀態（gitignored）
- `docs/` — TILED / CHARACTERS / PACK_GUIDE / ASSETS 說明

## 調整

- 改辦公室佈局：`app/bake_map.py` 的 `COMPOSITION`（模組由左到右）——座位/休息/等待點烘焙時自動算好
- 改模組錨點：`app/bake_map.py` 的 `MODULE_ANCHORS`（每種模組的相對格座標，標一次到處用）
- `SEAT_UP_DY` / `SEAT_DOWN_DY`（godot/office_map.gd）— 座位人物上下微調（正=往上幾格）
- `SCALE`（godot/office_map.gd）— 整體縮放（視窗自動跟著）

改完存檔 → 跑 `start_map.cmd`（改佈局/地圖要重新烘焙，啟動器都會自動跑）。

## 素材

Modern Office Revamped v1.2（LimeZu）。地圖在 Tiled 編輯，匯出 `.tmj` 到 `assets/tiled/`。
