# FunAI — Claude Code 機器人地圖

把每個正在執行的 Claude Code session 變成一張俯瞰辦公室地圖上的小機器人，
依工作狀態播放角色動畫，透明置頂疊在桌面上。一眼看出哪個專案在忙、哪個在等你授權。

## 架構

```
資料層 (Python，引擎無關)                渲染層 (Godot 4，待建)
Claude Code hooks                        透明置頂疊層視窗
  └ app/emit.py <EVENT>                  俯瞰辦公室 (Modern Interiors 瓦片)
      └ 寫 runtime/sessions/<id>.json →  每 session 一隻角色，依 state 播動畫
app/statusline.py                        每 ~200ms 輪詢 sessions/ 增刪角色
  └ 底部狀態列文字進度
```

- **解耦**：hooks 只負責「寫狀態」；狀態列與 Godot 各自獨立讀 `runtime/sessions/`。
- **多 session**：以 hook 帶的 `session_id` 分檔；`project`（cwd 末段）當名牌；
  `SessionEnd` 刪檔讓角色離場；超時自動衰減為 idle。

## 狀態對照

| Claude 事件 | state | 角色動畫 | emoji |
|------------|-------|---------|-------|
| SessionStart | idle | idle | 😴 |
| UserPromptSubmit | thinking | idle_anim | 🤔 |
| PreToolUse | working | sit | 🛠️ |
| PostToolUse (錯誤) | error | idle_anim | 💢 |
| Notification | waiting | run | 🙋 |
| Stop | done | run | ✅ |
| SessionEnd | (離場) | — | — |

對照表的權威定義在 `app/states.py`。

## 檔案

- `app/states.py` — 共用：路徑、狀態/角色對照、session 檔讀寫、穩健 stdin 載入
- `app/emit.py` — hook 進入點（`py emit.py <EVENT>`），鐵則：永不拋例外、永遠 exit 0
- `app/statusline.py` — statusLine 進入點，顯示本 session + 其他 session 概況
- `runtime/sessions/<id>.json` — 執行期狀態（gitignored）
- `assets/` — Modern Interiors 瓦片與角色精靈（待解壓）
- `godot/` — Godot 4 專案（待建）

素材：`D:\Work\GameDev\Resource\Pixel\Modern_Interiors`（LimeZu，16×16）。

## 進度

- [x] 階段 0：hooks → emit.py → session JSON（已驗證並發、離場、編碼）
- [x] 階段 1：statusline.py（已驗證 emoji 輸出 + 其他 session 概況）
- [ ] 階段 1.5：把 hooks/statusLine 接進 `~/.claude/settings.json`（全域）
- [ ] 階段 2：Godot 4 透明疊層地圖 + 角色動畫
- [ ] 階段 3：打磨（尋路、點擊氣泡、進度百分比、音效、系統匣）

## settings.json 整合（全域）

hooks 須放在「使用者全域」設定 `~/.claude/settings.json`，才能涵蓋所有專案的 session。
見專案內 `docs/settings.snippet.json`。注意：PreToolUse/PostToolUse 每次工具呼叫都會
spawn 一個 Python 行程（~0.1s），如在意延遲可改用 async hook 或只掛部分事件。
