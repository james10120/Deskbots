"""背景常駐：算每個 Claude Code session 的 token 使用量，寫 runtime/usage.json。

為什麼獨立一支而不放進 emit.py：
    emit.py 是 hook，鐵則是不可阻塞。解析整份 transcript（可能上百 KB）會拖慢
    每次工具呼叫，所以把這份重活搬到常駐輪詢，跟 Godot/statusline 一樣靠檔案溝通。

作法：
    每 POLL_SEC 秒掃 runtime/sessions/*.json 取得在場 session 與其 transcript 路徑，
    對每份 transcript 做「增量解析」——記住上次讀到的 byte offset 與累計值，
    append-only 的 JSONL 只讀新增的行，幾乎零成本。

輸出 runtime/usage.json：
    { session_id: {"in", "out", "cache", "total", "turns", "context_now", "model"} }

鐵則同 emit：不拋例外、讀不到就略過，永遠別干擾真正的 Claude Code。
"""
from __future__ import annotations

import json
import time
from pathlib import Path

try:
    import states  # 沿用 SESSIONS_DIR / RUNTIME_DIR
except Exception:
    import sys
    sys.exit(0)

POLL_SEC = 2.0
USAGE_FILE = states.RUNTIME_DIR / "usage.json"

# session_id -> 累計狀態（常駐記憶體，重啟才從頭算）
_acc: dict[str, dict] = {}


def _blank() -> dict:
    return {
        "path": "",        # 對應的 transcript 路徑（換檔就重算）
        "offset": 0,       # 已解析到的 byte 位置
        "in": 0, "out": 0, "cache": 0,
        "turns": 0,
        "context_now": 0,  # 最後一筆 assistant 的 input+cache（≈ 目前 context 佔用）
        "model": "",
    }


def _is_user_prompt(msg: dict) -> bool:
    """type==user 同時涵蓋使用者提問與 tool_result 回填；只算真正的提問。"""
    content = msg.get("content")
    if isinstance(content, str):
        return content.strip() != ""
    if isinstance(content, list):
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text" and str(b.get("text", "")).strip():
                return True
    return False


def _process_line(st: dict, line: str) -> None:
    line = line.strip()
    if not line or not line.startswith("{"):
        return
    try:
        d = json.loads(line)
    except Exception:
        return
    t = d.get("type")
    msg = d.get("message")
    if not isinstance(msg, dict):
        return
    if t == "user":
        if _is_user_prompt(msg):
            st["turns"] += 1
    elif t == "assistant":
        u = msg.get("usage")
        if not isinstance(u, dict):
            return
        i = int(u.get("input_tokens", 0) or 0)
        o = int(u.get("output_tokens", 0) or 0)
        cr = int(u.get("cache_read_input_tokens", 0) or 0)
        cc = int(u.get("cache_creation_input_tokens", 0) or 0)
        st["in"] += i
        st["out"] += o
        st["cache"] += cr + cc
        st["context_now"] = i + cr + cc   # 最後一筆覆蓋 → 即為當前 context 佔用
        m = msg.get("model")
        if m:
            st["model"] = str(m)


def _update_session(sid: str, transcript: str) -> dict | None:
    st = _acc.get(sid)
    if st is None or st["path"] != transcript:
        st = _blank()
        st["path"] = transcript
        _acc[sid] = st
    if not transcript:
        return st
    p = Path(transcript)
    try:
        size = p.stat().st_size
    except OSError:
        return st
    if size < st["offset"]:      # 檔案被截短/重建 → 從頭重算
        for k in ("offset", "in", "out", "cache", "turns", "context_now"):
            st[k] = 0
    if size <= st["offset"]:
        return st
    try:
        with p.open("rb") as fh:
            fh.seek(st["offset"])
            data = fh.read()
    except OSError:
        return st
    last_nl = data.rfind(b"\n")
    if last_nl == -1:            # 還沒有完整的一行，等下次
        return st
    complete = data[: last_nl + 1]
    st["offset"] += len(complete)
    for ln in complete.decode("utf-8", "ignore").split("\n"):
        _process_line(st, ln)
    return st


def _scan_once() -> None:
    sessions_dir = states.SESSIONS_DIR
    if not sessions_dir.exists():
        return
    out: dict[str, dict] = {}
    seen: set[str] = set()
    for f in sessions_dir.glob("*.json"):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        sid = str(d.get("session") or "")
        if not sid:
            continue
        seen.add(sid)
        st = _update_session(sid, str(d.get("transcript", "")))
        if st is None:
            continue
        out[sid] = {
            "in": st["in"], "out": st["out"], "cache": st["cache"],
            "total": st["in"] + st["out"] + st["cache"],
            "turns": st["turns"],
            "context_now": st["context_now"],
            "model": st["model"],
        }
    # 清掉已離場 session 的累計狀態，避免記憶體無限長
    for sid in list(_acc.keys()):
        if sid not in seen:
            _acc.pop(sid, None)
    tmp = USAGE_FILE.with_suffix(".json.tmp")
    try:
        states.RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
        tmp.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
        import os
        os.replace(tmp, USAGE_FILE)
    except OSError:
        pass


def main() -> None:
    while True:
        try:
            _scan_once()
        except Exception:
            pass
        time.sleep(POLL_SEC)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
