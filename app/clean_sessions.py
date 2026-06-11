"""清除殭屍 session 檔（崩潰或未正常結束、超過 1 小時沒更新的）。

地圖啟動器會先跑這個，確保不殘留鬼影機器人。
"""
from __future__ import annotations

import json
import time

import states

STALE_SEC = 3600  # 超過 1 小時沒更新就視為死掉

def main() -> None:
    if not states.SESSIONS_DIR.exists():
        return
    now = time.time()
    removed = 0
    for f in states.SESSIONS_DIR.glob("*.json"):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
            stale = now - float(d.get("ts", 0)) > STALE_SEC
        except Exception:
            stale = True  # 壞檔也清掉
        if stale:
            try:
                f.unlink()
                removed += 1
            except OSError:
                pass
    print(f"清除殭屍 session：{removed} 個")


if __name__ == "__main__":
    main()
