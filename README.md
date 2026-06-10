# FunAI — Claude Code 機器人辦公室地圖

把每個正在執行的 Claude Code session 變成一張俯瞰辦公室地圖上的小機器人：
工作時坐在自己座位、等你授權時走到等待區滑手機、忙完走去休息室看書。
透明置頂疊在桌面上，一眼看出哪個專案在忙、哪個在等你。

## 架構

```
資料層 (Python，引擎無關)              渲染層 (Godot 4，OpenGL Compatibility)
Claude Code hooks                       透明置頂疊層視窗
  └ app/emit.py <EVENT>                 Tiled 辦公室地圖 (office.tmj) 渲染
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

雙擊 **`app/start_map.cmd`**（清殭屍 session → 烘焙地圖 → 啟動 Godot）。
首次需先跑 `app/apply_settings.py`（自己執行）把 hooks + statusLine 併入 `~/.claude/settings.json`，再開新的 Claude Code session。

## 檔案

- `app/emit.py` — hook 進入點（`py emit.py <EVENT>`），永不拋例外、永遠 exit 0
- `app/states.py` — 共用：狀態對照、角色分配(BOT1~9)、session 檔讀寫
- `app/statusline.py` — statusLine 文字進度
- `app/bake_map.py` — 把 Tiled `office.tmj` 解壓成 Godot 好讀的 `map_baked.json` + 障礙格
- `app/clean_sessions.py` / `apply_settings.py` / `start_map.cmd` — 維運/啟動
- `godot/main.gd` — 渲染、行為、尋路、圖層、動畫（座位/圖層調整參數在檔案最上方）
- `assets/characters/BOT1~9.png` — 角色動畫表（16×32 幀）
- `assets/tiled/office.tmj` + tileset PNG — Tiled 辦公室地圖
- `runtime/sessions/<id>.json` — 執行期狀態（gitignored）
- `docs/` — TILED / CHARACTERS / PACK_GUIDE / ASSETS 說明

## 調整（godot/main.gd 最上方常數）

- `SEATS` / `LOUNGE_TILES` / `WAIT_TILES` — 座位、休息點、等待點的格座標
- `CHAR_LAYER_DEFAULT` / `CHAR_LAYER_UPSEAT` — 角色插入的 Tiled 圖層深度（用空白圖層當插入點）
- `SEAT_UP_DY` / `SEAT_DOWN_DY` — 座位人物上下微調（正=往上幾格）
- `SCALE` — 整體縮放（視窗自動跟著）

改完存檔 → 跑 `start_map.cmd`（改程式不用重新烘焙；改地圖才要）。

## 素材

Modern Office Revamped v1.2（LimeZu）。地圖在 Tiled 編輯，匯出 `.tmj` 到 `assets/tiled/`。
