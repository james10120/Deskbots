"""Claude Code hook 進入點。

用法（在 settings.json 的 hook command 裡）：
    python D:/Work/FunAI/app/emit.py <EVENT>
例如 PreToolUse 的 command 就寫 `python .../emit.py PreToolUse`。

職責：讀 stdin 的 hook JSON → 算出狀態 → 寫 runtime/sessions/<id>.json。
鐵則：絕不拋例外、絕不阻塞、永遠 exit 0 —— 不能干擾真正的 Claude Code。
"""
from __future__ import annotations

import sys
import time

try:
    import states
except Exception:  # 連 import 都失敗也不能炸掉 hook
    sys.exit(0)


def detect_error(data: dict) -> bool:
    """PostToolUse 時粗略判斷工具是否出錯。"""
    resp = data.get("tool_response")
    if isinstance(resp, dict):
        if resp.get("success") is False or resp.get("is_error") or resp.get("error"):
            return True
    # 部分版本把結果放 tool_result 字串
    for key in ("tool_result", "tool_response"):
        v = data.get(key)
        if isinstance(v, str) and v.lower().startswith(("error", "command failed")):
            return True
    return False


def main() -> None:
    event = sys.argv[1] if len(sys.argv) > 1 else ""

    data = states.load_stdin()
    session_id = str(data.get("session_id") or "unknown")

    # SessionEnd → 角色離場
    if event == "SessionEnd":
        states.remove_state(session_id)
        return

    state = states.EVENT_STATE.get(event, states.WORKING)
    tool = data.get("tool_name") or ""

    if event == "PostToolUse" and detect_error(data):
        state = states.ERROR

    # 給人看的進度短句
    if state == states.WORKING and tool:
        message = f"{tool}"
    elif state == states.WAITING:
        message = "等你授權/輸入"
    elif state == states.THINKING:
        message = "思考中"
    elif state == states.DONE:
        message = "完成"
    elif state == states.ERROR:
        message = f"{tool} 出錯" if tool else "出錯"
    else:
        message = ""

    payload = {
        "session": session_id,
        "project": states.project_name(data),
        "character": states.character_for(session_id),
        "state": state,
        "anim": states.STATE_ANIM.get(state, "idle"),
        "tool": tool,
        "message": message,
        "event": event,
        "ts": time.time(),
        "transcript": data.get("transcript_path", ""),  # 地圖端拿它的 mtime 當心跳偵測中斷
    }
    states.write_state(session_id, payload)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
