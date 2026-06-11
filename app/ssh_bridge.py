"""Deskbots SSH 橋接：把遠端伺服器的 Claude session 鏡像進本地 runtime/sessions/。

設定檔 config/servers.json（陣列，一台一項）：
    [{"host": "myserver"}]                              # ~/.ssh/config 的別名或 user@ip
    可選欄位：
      "label"  地圖上顯示的機器名（預設=host）
      "root"   遠端安裝位置（預設 ~/deskbots，remote_install.py 的預設一致）
      "cmd"    覆寫啟動指令（測試用，例如本機跑 agent 模擬遠端）

每台一條長連線（ssh 必須免密碼金鑰認證）：
  ssh <host> python3 <root>/app/remote_agent.py
收 NDJSON 快照 → 寫 runtime/sessions/<label>__<sid>.json（session id 加 label 前綴、
專案名加 @label）；transcript 尾段落地到 runtime/transcripts/，路徑指過去 →
Godot 的心跳偵測與對話卡 Q&A 原樣生效。斷線清掉該台的鏡像檔（機器人離場）、
退避重連。整個程式結束時清掉所有鏡像。

由 run_deskbots.ps1 與 usage_poll 一起啟動。servers.json **熱載入**（每 3s 檢查）：
遊戲設定卡新增/移除伺服器不用重開；連線狀態寫 runtime/bridge.json 給設定卡顯示。
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import states

SERVERS_FILE = states.ROOT / "config" / "servers.json"
STATUS_FILE = states.RUNTIME_DIR / "bridge.json"
REHIRE_REMOTE_FILE = states.RUNTIME_DIR / "rehire_remote.json"   # 遠端人才庫（看板合併顯示）
TRANSCRIPTS_DIR = states.RUNTIME_DIR / "transcripts"
RETRY_MIN, RETRY_MAX = 5, 60
RELOAD_SEC = 3


def _safe(s: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "_", s) or "x"


def _log(label: str, msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {label}: {msg}", flush=True)


class Server:
    def __init__(self, conf: dict):
        self.host = str(conf["host"])
        self.label = str(conf.get("label") or self.host)
        root = str(conf.get("root") or "~/deskbots")
        self.cmd = conf.get("cmd") or [
            "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3",
            self.host, "python3", f"{root}/app/remote_agent.py",
        ]
        self.prefix = _safe(self.label) + "__"
        self.mirrored: set[str] = set()   # 目前鏡像中的本地檔名
        self.projects: list = []          # 這台的人才庫（agent 掃遠端 ~/.claude/projects）
        self.connected = False
        self.stop_ev = threading.Event()
        self.proc: subprocess.Popen | None = None
        self.thread: threading.Thread | None = None

    # ── 鏡像 ──────────────────────────────────────────────────
    def _apply_sync(self, sessions: list) -> None:
        now = time.time()
        alive: set[str] = set()
        for d in sessions:
            if not isinstance(d, dict):
                continue
            sid = str(d.get("session", ""))
            if not sid:
                continue
            fname = self.prefix + _safe(sid) + ".json"
            alive.add(fname)
            tail = d.pop("tail", None)
            tpath = TRANSCRIPTS_DIR / (self.prefix + _safe(sid) + ".jsonl")
            if isinstance(tail, str) and tail:
                TRANSCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
                tmp = tpath.with_suffix(".tmp")
                tmp.write_text(tail, encoding="utf-8")
                os.replace(tmp, tpath)   # mtime 只在遠端 transcript 有變時更新 = 心跳
            d["session"] = f"{self.label}:{sid}"
            d["project"] = f"{d.get('project', '?')}@{self.label}"
            d["host"] = self.host
            d["hwnd"] = 0
            d["transcript"] = str(tpath) if tpath.exists() else ""
            d["ts"] = now - float(d.pop("age", 0.0))   # 用遠端算好的 age 還原，免時鐘偏差
            states.SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
            target = states.SESSIONS_DIR / fname
            tmp = target.with_suffix(".json.tmp")
            tmp.write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
            os.replace(tmp, target)
        for gone in self.mirrored - alive:   # 遠端 SessionEnd → 本地離場
            (states.SESSIONS_DIR / gone).unlink(missing_ok=True)
        self.mirrored = alive

    def set_projects(self, rows: list) -> None:
        out = []
        for r in rows:
            if not isinstance(r, dict) or not r.get("cwd"):
                continue
            out.append({**r, "project": f"{r.get('project', '?')}@{self.label}",
                        "host": self.host, "label": self.label})
        self.projects = out

    def cleanup(self) -> None:
        for f in list(self.mirrored):
            (states.SESSIONS_DIR / f).unlink(missing_ok=True)
        self.mirrored = set()
        self.projects = []

    # ── 連線迴圈 ──────────────────────────────────────────────
    def run(self) -> None:
        backoff = RETRY_MIN
        while not self.stop_ev.is_set():
            try:
                self.proc = subprocess.Popen(
                    self.cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                    stdin=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace")
                for line in self.proc.stdout:
                    if self.stop_ev.is_set():
                        break
                    try:
                        msg = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    t = msg.get("type")
                    if t == "hello":
                        backoff = RETRY_MIN
                        self.connected = True
                        _log(self.label, "已連線")
                    elif t == "sync":
                        self._apply_sync(msg.get("sessions", []))
                        self.set_projects(msg.get("projects", []))
            except Exception as e:
                _log(self.label, f"連線錯誤：{e}")
            finally:
                self.connected = False
                if self.proc is not None:
                    try:
                        self.proc.kill()
                    except OSError:
                        pass
                self.cleanup()
            if self.stop_ev.is_set():
                return
            _log(self.label, f"斷線，{backoff}s 後重連")
            self.stop_ev.wait(backoff)
            backoff = min(backoff * 2, RETRY_MAX)

    def start(self) -> None:
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def stop(self) -> None:
        self.stop_ev.set()
        if self.proc is not None:
            try:
                self.proc.kill()   # 讓卡在 readline 的執行緒立刻收工
            except OSError:
                pass
        self.connected = False
        self.cleanup()


def _load_servers() -> list[dict]:
    try:
        servers = json.loads(SERVERS_FILE.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError):
        return []
    if not isinstance(servers, list):
        return []
    return [s for s in servers if isinstance(s, dict) and s.get("host")]


def _atomic_write(path, text: str) -> None:
    states.RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def _write_status(active: dict, last: str) -> str:
    """連線狀態 → runtime/bridge.json（設定卡的綠點/在場數）；沒變不重寫。"""
    status = {o.label: {"host": o.host, "connected": o.connected,
                        "sessions": len(o.mirrored)} for o in active.values()}
    s = json.dumps(status, ensure_ascii=False, sort_keys=True)
    if s != last:
        _atomic_write(STATUS_FILE, s)
    return s


def _write_rehire(active: dict, last: str) -> str:
    """各台的遠端人才庫合併 → runtime/rehire_remote.json（看板與本地的合併顯示）。"""
    rows = [r for o in active.values() for r in o.projects]
    rows.sort(key=lambda r: float(r.get("mtime", 0)), reverse=True)
    s = json.dumps(rows, ensure_ascii=False)
    if s != last:
        _atomic_write(REHIRE_REMOTE_FILE, s)
    return s


def main() -> None:
    print(f"SSH 橋接啟動：監看 {SERVERS_FILE}（熱載入，可在遊戲設定卡新增/移除；Ctrl+C 結束）")
    active: dict[str, Server] = {}   # host -> Server
    last_status = ""
    last_rehire = ""
    try:
        while True:
            desired = {str(c["host"]): c for c in _load_servers()}
            for h, conf in desired.items():
                if h not in active:
                    active[h] = Server(conf)
                    active[h].start()
                    _log(active[h].label, "加入監看")
            for h in list(active):
                if h not in desired:
                    s = active.pop(h)
                    s.stop()
                    _log(s.label, "已移除")
            last_status = _write_status(active, last_status)
            last_rehire = _write_rehire(active, last_rehire)
            time.sleep(RELOAD_SEC)
    except KeyboardInterrupt:
        pass
    finally:
        for s in active.values():
            s.stop()
        STATUS_FILE.unlink(missing_ok=True)
        REHIRE_REMOTE_FILE.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
