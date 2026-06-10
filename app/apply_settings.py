"""把 statusLine + 輕量 hooks 併入使用者全域 ~/.claude/settings.json。

由使用者自己執行（Claude 的工具被安全機制擋住修改該檔）：
    py D:\\Work\\FunAI\\app\\apply_settings.py

可重複執行（idempotent）：只新增/覆寫 statusLine 與我們這幾個 hook 事件，
保留你原有的其他設定。執行前會先備份成 settings.json.bak。
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")   # 否則 cp950 印不出 emoji
except Exception:
    pass

SETTINGS = Path.home() / ".claude" / "settings.json"
EMIT = "py D:/Work/FunAI/app/emit.py"
STATUSLINE = "py D:/Work/FunAI/app/statusline.py"

# PreToolUse 讓「用工具的回合」狀態完全準（emit.py 對它走精簡路徑，每次 ~37ms）
EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"]


def main() -> None:
    data = {}
    if SETTINGS.exists():
        shutil.copyfile(SETTINGS, SETTINGS.with_suffix(".json.bak"))
        try:
            data = json.loads(SETTINGS.read_text(encoding="utf-8-sig"))
        except json.JSONDecodeError as e:
            print(f"!! 無法解析現有 settings.json：{e}\n   請先手動檢查，未做變更。")
            return

    data["statusLine"] = {"type": "command", "command": STATUSLINE}

    hooks = data.setdefault("hooks", {})
    for ev in EVENTS:
        hooks[ev] = [{"hooks": [{"type": "command", "command": f"{EMIT} {ev}"}]}]

    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    SETTINGS.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"✅ 已更新 {SETTINGS}")
    print(f"   statusLine + hooks: {', '.join(EVENTS)}")
    print("   備份在 settings.json.bak。重開一個 Claude Code session 即可看到狀態列機器人。")


if __name__ == "__main__":
    main()
