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
REHIRE_FILE = states.RUNTIME_DIR / "rehire.json"   # 人才庫：可重新雇用的歷史專案
LOCK_FILE = states.RUNTIME_DIR / "usage.lock"
PROJECTS_DIR = Path.home() / ".claude" / "projects"
REHIRE_MAX = 8          # 人才庫最多列幾個專案

_lock_handle = None   # 全域持有，鎖才不會在函式返回後被釋放

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
    out: dict[str, dict] = {}
    seen: set[str] = set()
    active_cwds: set[str] = set()
    for f in (sessions_dir.glob("*.json") if sessions_dir.exists() else []):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        sid = str(d.get("session") or "")
        if not sid:
            continue
        seen.add(sid)
        cwd = str(d.get("cwd", "")).strip()
        if cwd:
            active_cwds.add(_norm_cwd(cwd))
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
    _write_json(USAGE_FILE, out)
    _scan_rehire(active_cwds)


def _norm_cwd(p: str) -> str:
    return p.replace("/", "\\").rstrip("\\").lower()


def _project_cwd(proj_dir: Path):
    """從某專案資料夾最新的 transcript 抓真實 cwd + 最後活動時間。"""
    files = sorted(proj_dir.glob("*.jsonl"), key=lambda f: f.stat().st_mtime, reverse=True)
    if not files:
        return None
    latest = files[0]
    cwd = ""
    try:
        with latest.open(encoding="utf-8") as fh:
            for _ in range(40):                 # cwd 通常在開頭幾行
                line = fh.readline()
                if not line:
                    break
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if o.get("cwd"):
                    cwd = str(o["cwd"])
                    break
    except OSError:
        return None
    if not cwd:
        return None
    return {"cwd": cwd, "mtime": latest.stat().st_mtime}


def _scan_rehire(active_cwds: set) -> None:
    """掃 ~/.claude/projects，列出「最近用過但目前沒在跑」的專案 → 人才庫。"""
    if not PROJECTS_DIR.exists():
        return
    cands = []
    for proj in PROJECTS_DIR.glob("*"):
        if not proj.is_dir():
            continue
        info = _project_cwd(proj)
        if info is None:
            continue
        if _norm_cwd(info["cwd"]) in active_cwds:   # 正在上工的不列
            continue
        cands.append(info)
    cands.sort(key=lambda c: c["mtime"], reverse=True)
    now = time.time()
    rows = []
    for c in cands[:REHIRE_MAX]:
        cwd = c["cwd"]
        name = cwd.replace("/", "\\").rstrip("\\").split("\\")[-1] or cwd
        rows.append({"project": name, "cwd": cwd, "ago": _ago(now - c["mtime"])})
    _write_json(REHIRE_FILE, rows)


def _ago(sec: float) -> str:
    if sec < 3600:
        return "%d 分鐘前" % max(1, int(sec / 60))
    if sec < 86400:
        return "%d 小時前" % int(sec / 3600)
    return "%d 天前" % int(sec / 86400)


def _write_json(path, data) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    try:
        states.RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
        tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        import os
        os.replace(tmp, path)
    except OSError:
        pass


def _acquire_singleton() -> bool:
    """確保同時只有一支 usage_poll 在跑。拿不到鎖回 False（→ 該退出）。

    用 OS 層的檔案鎖（行程結束會自動釋放，免清殘留 pid 檔）。
    開不了鎖檔或平台不支援 → 放行，絕不因為上鎖失敗而擋掉功能。
    """
    global _lock_handle
    try:
        states.RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
        fh = open(LOCK_FILE, "a+")
    except OSError:
        return True
    fh.seek(0)   # 各實例都鎖同一個位元組（位置 0），互斥才成立
    try:
        import msvcrt
        msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        fh.close()
        return False        # 另一支實例握著鎖
    except Exception:
        try:                # 非 Windows 退回 fcntl
            import fcntl
            fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            fh.close()
            return False
        except Exception:
            pass            # 兩者都沒有 → 放行
    _lock_handle = fh
    return True


def main() -> None:
    if not _acquire_singleton():
        return   # 已有一支 usage_poll 在跑，直接退出
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
