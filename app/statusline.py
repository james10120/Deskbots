"""Claude Code statusLine 進入點。

用法（settings.json，路徑由 apply_settings.py 動態填入安裝位置）：
    "statusLine": { "type": "command", "command": "py <安裝路徑>/app/statusline.py" }

讀自己 session 的 stdin → 顯示「本 session 機器人狀態」+「其他 session 概況」。
最實用：一眼看出有沒有別的專案在等你授權 (🙋waiting)。
"""
from __future__ import annotations

import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")  # 否則 cp950 無法輸出 emoji
except Exception:
    pass

try:
    import states
except Exception:
    print("🤖")
    sys.exit(0)


def main() -> None:
    data = states.load_stdin()
    my_id = str(data.get("session_id") or "")
    project = states.project_name(data)

    all_sessions = states.read_all()
    mine = next((s for s in all_sessions if s.get("session") == my_id), None)

    # 本 session
    if mine:
        emoji = states.STATE_EMOJI.get(mine["state"], "🤖")
        st = mine["state"]
        tool = mine.get("tool") or ""
        seg = f"{emoji} {st}" + (f" · {tool}" if tool else "")
    else:
        seg = f"🤖 {project}"

    # 其他 session 概況
    others = [s for s in all_sessions if s.get("session") != my_id]
    extra = ""
    if others:
        waiting = [s for s in others if s.get("state") == states.WAITING]
        parts = [f"+{len(others)} 機器人"]
        if waiting:
            names = ", ".join(s.get("project", "?") for s in waiting)
            parts.append(f"🙋 {names} 等你")
        extra = "  |  " + " · ".join(parts)

    print(f"{seg}{extra}")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("🤖")
    sys.exit(0)
