"""Deskbots 遠端代理：在 SSH 伺服器上跑，把該機的 Claude session 串流給本地 bridge。

部署（remote_install.py 會做）：放在遠端 <root>/app/ 與 states.py 同層，
hooks 由同層的 apply_settings.py 裝進遠端 ~/.claude/settings.json。
本地 ssh_bridge.py 以 `ssh <host> python3 <root>/app/remote_agent.py` 啟動本檔。

協定：stdout 每行一個 JSON——
  {"type":"hello", "v":1}                              開場
  {"type":"sync", "sessions":[...], "projects":[...]}  每 2s 一次完整快照
每個 session 物件 = emit.py 寫的 payload 原樣，外加：
  "age"     事件距今秒數（遠端時鐘算好，本地用 now-age 還原 ts → 免時鐘偏差）
  "tail"    transcript 尾段文字（只在有變動時附上，否則 null）
bridge 端把 tail 落地成本地檔、transcript 指過去 → Godot 的心跳/對話卡原樣生效。
projects = 這台「最近用過、目前沒在跑」的專案（掃遠端 ~/.claude/projects，
30s 一次），進本地看板的人才庫 → 點一下直接開 VS Code Remote 到該資料夾。

鐵則同 emit.py：絕不拋例外讓連線斷掉；bridge 收不到（管道斷）就安靜退出。
"""
from __future__ import annotations

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import states

INTERVAL = 2.0
TAIL_BYTES = 100_000   # transcript 尾段上限（最近一輪 Q&A 用，LAN 下 2s 一次無壓力）
PROJECTS_DIR = os.path.join(os.path.expanduser("~"), ".claude", "projects")
PROJECTS_SCAN_SEC = 30   # 多久重掃一次歷史專案（人才庫）
REHIRE_MAX = 8


def _ago(sec: float) -> str:
    if sec < 3600:
        return "%d 分鐘前" % max(1, int(sec / 60))
    if sec < 86400:
        return "%d 小時前" % int(sec / 3600)
    return "%d 天前" % int(sec / 86400)


def _project_cwd(proj_dir: str):
    """從某專案資料夾最新的 transcript 抓真實 cwd + 最後活動時間（同 usage_poll 規則）。"""
    try:
        files = sorted((os.path.join(proj_dir, f) for f in os.listdir(proj_dir)
                        if f.endswith(".jsonl")), key=os.path.getmtime, reverse=True)
    except OSError:
        return None
    if not files:
        return None
    cwd = ""
    try:
        with open(files[0], encoding="utf-8") as fh:
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
        if not cwd:
            return None
        return {"cwd": cwd, "mtime": os.path.getmtime(files[0])}
    except OSError:
        return None


def _scan_projects() -> list:
    """這台機器近期用過的專案（依最後活動排序；是否在跑/被移除由本地端過濾）。"""
    out = []
    try:
        for name in os.listdir(PROJECTS_DIR):
            proj = os.path.join(PROJECTS_DIR, name)
            if not os.path.isdir(proj):
                continue
            info = _project_cwd(proj)
            if info is not None:
                out.append(info)
    except OSError:
        return out
    out.sort(key=lambda c: c["mtime"], reverse=True)
    return out[: REHIRE_MAX * 2]   # 留餘裕給「正在跑」的排除


def _read_tail(path: str) -> str:
    """讀 transcript 尾段（位元組對齊到換行，避免切壞 UTF-8/JSON 行）。"""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            f.seek(max(0, size - TAIL_BYTES))
            raw = f.read()
        if size > TAIL_BYTES:
            nl = raw.find(b"\n")
            if nl >= 0:
                raw = raw[nl + 1:]
        return raw.decode("utf-8", errors="replace")
    except OSError:
        return ""


def _emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main() -> None:
    _emit({"type": "hello", "v": 1})
    sent_mtime: dict[str, float] = {}   # session id -> 已送出的 transcript mtime
    projects: list = []
    next_scan = 0.0
    while True:
        now = time.time()
        sessions = []
        try:
            if now >= next_scan:
                projects = _scan_projects()
                next_scan = now + PROJECTS_SCAN_SEC
            active = set()
            for d in states.read_all():   # 已套用遠端的時間衰減（transcript mtime 在這台才讀得到）
                sid = str(d.get("session", ""))
                if not sid:
                    continue
                d["age"] = max(0.0, now - float(d.get("ts", now)))
                tp = str(d.get("transcript", ""))
                tail = None
                if tp and os.path.exists(tp):
                    try:
                        mt = os.path.getmtime(tp)
                    except OSError:
                        mt = 0.0
                    if mt > sent_mtime.get(sid, -1.0):
                        tail = _read_tail(tp)
                        sent_mtime[sid] = mt
                d["tail"] = tail
                d["hwnd"] = 0
                active.add(str(d.get("cwd", "")).rstrip("/").lower())
                sessions.append(d)
            rows = []
            for c in projects:   # 排除正在跑的，補 ago / 專案名
                if c["cwd"].rstrip("/").lower() in active:
                    continue
                rows.append({"project": os.path.basename(c["cwd"].rstrip("/")) or c["cwd"],
                             "cwd": c["cwd"], "mtime": c["mtime"], "ago": _ago(now - c["mtime"])})
                if len(rows) >= REHIRE_MAX:
                    break
            _emit({"type": "sync", "sessions": sessions, "projects": rows})
        except (BrokenPipeError, OSError):
            return   # bridge 端收走了連線，安靜退出
        except Exception:
            pass     # 單輪失敗不斷線，下一輪再試
        time.sleep(INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
    sys.exit(0)
