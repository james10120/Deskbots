"""共用模組：路徑、狀態/角色對照、session 檔案讀寫。

emit.py（hook 進入點）與 statusline.py 都 import 這個檔。
刻意零外部相依，只用標準函式庫 —— hook 必須在任何環境都能跑。
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path


def load_stdin() -> dict:
    """穩健讀取 hook/statusline 的 stdin JSON。

    處理：cp950 等地區編碼、PowerShell/Windows 可能加的 UTF-8 BOM、空輸入。
    任何失敗都回空 dict，絕不拋例外。
    """
    try:
        try:
            sys.stdin.reconfigure(encoding="utf-8")  # 強制 UTF-8，避免 cp950
        except Exception:
            pass
        raw = sys.stdin.read()
    except Exception:
        return {}
    raw = raw.lstrip("﻿").strip()  # 去 BOM + 前後空白
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {}

# ── 路徑（相對於本檔位置，與 hook 當下的 cwd 無關）──────────────
#   states.py 位於  <root>/app/states.py  →  ROOT = <root>
ROOT = Path(__file__).resolve().parent.parent
RUNTIME_DIR = ROOT / "runtime"
SESSIONS_DIR = RUNTIME_DIR / "sessions"

# ── 狀態定義 ───────────────────────────────────────────────────
#   Claude Code 事件 → 機器人狀態。Godot / statusline 都讀這個。
IDLE = "idle"
THINKING = "thinking"
WORKING = "working"
WAITING = "waiting"   # 需要使用者授權/輸入 —— 最該醒目
DONE = "done"
ERROR = "error"

# 事件 → 狀態（emit.py 用指令參數傳事件名，所以這裡是權威對照）
EVENT_STATE = {
    "SessionStart": IDLE,
    "UserPromptSubmit": THINKING,
    "PreToolUse": WORKING,
    "PostToolUse": WORKING,   # 仍在忙；錯誤時 emit.py 會改成 ERROR
    "Notification": WAITING,
    "Stop": DONE,
    "SubagentStop": WORKING,
}

# 狀態 → statusline 顯示的 emoji（Godot 端另有精靈動畫對照）
STATE_EMOJI = {
    IDLE: "😴",
    THINKING: "🤔",
    WORKING: "🛠️",
    WAITING: "🙋",
    DONE: "✅",
    ERROR: "💢",
}

# 狀態 → 角色精靈動畫名（Godot 端依此挑 Modern Interiors 動作圖）
STATE_ANIM = {
    IDLE: "idle",
    THINKING: "idle_anim",
    WORKING: "sit",
    WAITING: "run",
    DONE: "run",
    ERROR: "idle_anim",
}

# 可用角色（BOT1~BOT9）—— 依 session 雜湊分配，固定不變
CHARACTERS = [f"BOT{i}" for i in range(1, 10)]

# done 狀態維持多久後視為 idle（秒）；Godot/statusline 端依時間衰減
DONE_DECAY_SEC = 8
# 多久沒更新就視為 idle（秒）
IDLE_AFTER_SEC = 90


def character_for(session_id: str) -> str:
    """以 session_id 穩定雜湊挑一個角色（同一 session 永遠同角色）。"""
    if not session_id:
        return CHARACTERS[0]
    h = sum(ord(c) for c in session_id)
    return CHARACTERS[h % len(CHARACTERS)]


def project_name(data: dict) -> str:
    """從 hook/statusline 的 stdin 取專案名（資料夾最後一段）。"""
    ws = data.get("workspace") or {}
    path = ws.get("project_dir") or data.get("cwd") or ""
    name = os.path.basename(str(path).rstrip("/\\"))
    return name or "?"


def session_file(session_id: str) -> Path:
    safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in str(session_id))
    return SESSIONS_DIR / f"{safe or 'unknown'}.json"


def write_state(session_id: str, payload: dict) -> None:
    """原子寫入單一 session 的狀態檔。"""
    SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
    target = session_file(session_id)
    tmp = target.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, target)


def remove_state(session_id: str) -> None:
    """session 結束 → 移除檔案（Godot 端讓機器人離場）。"""
    try:
        session_file(session_id).unlink()
    except FileNotFoundError:
        pass


def read_all() -> list[dict]:
    """讀取所有 session 狀態，套用時間衰減。statusline / 工具用。"""
    out: list[dict] = []
    if not SESSIONS_DIR.exists():
        return out
    now = time.time()
    for f in SESSIONS_DIR.glob("*.json"):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        age = now - d.get("ts", now)
        if d.get("state") == DONE and age > DONE_DECAY_SEC:
            d["state"] = IDLE
        elif age > IDLE_AFTER_SEC and d.get("state") not in (WAITING, ERROR):
            d["state"] = IDLE
        out.append(d)
    return out
