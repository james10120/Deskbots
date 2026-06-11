"""把 statusLine + 輕量 hooks 併入／移出使用者全域 ~/.claude/settings.json。

由使用者自己執行（Claude 的工具被安全機制擋住修改該檔）：
    py D:\\Work\\Deskbots\\app\\apply_settings.py            # 套用
    py D:\\Work\\Deskbots\\app\\apply_settings.py --remove   # 移除（乾淨卸載）

兩個方向都是 idempotent 且**非破壞性**：
  - 套用：只補上 FunAI 的 statusLine 與這幾個事件的 emit hook，保留你原有的其他 hook。
  - 移除：只拿掉 FunAI 自己的那幾筆（命令含 emit.py），事件清空才刪 key。
執行前都會先備份成 settings.json.bak。
"""
from __future__ import annotations

import json
import os
import re
import shutil
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")   # 否則 cp950 印不出 emoji
except Exception:
    pass

SETTINGS = Path.home() / ".claude" / "settings.json"

# hook 指令要寫絕對路徑（Claude 從任意 cwd 觸發），但路徑由「本檔所在位置」動態算出，
# 不寫死 → 整包可裝在任何電腦的任何路徑。含空白的路徑用引號包起來。
# 啟動器：Windows 用 py launcher；POSIX（SSH 遠端伺服器）用 python3。
_APP = Path(__file__).resolve().parent
_PY = "py" if os.name == "nt" else "python3"
def _cmd(script: str) -> str:
    p = str(_APP / script).replace("\\", "/")
    return f'{_PY} "{p}"' if " " in p else f"{_PY} {p}"
EMIT = _cmd("emit.py")
STATUSLINE = _cmd("statusline.py")

# PreToolUse 讓「用工具的回合」狀態完全準（emit.py 對它走精簡路徑，每次 ~37ms）
EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"]


def _is_ours_cmd(cmd, script_name: str) -> bool:
    """本工具的指令——不限安裝位置：形如 `py <path>/app/<script_name> ...`。
    設定裡只該有「目前安裝位置」的條目；其他位置（改名/搬移/複製留下的）一律視為
    自己的舊條目，套用與移除時都要清掉，否則 hook 會重複執行或指到死路徑。"""
    if not isinstance(cmd, str):
        return False
    return bool(re.match(r'^(?:py|python3?)\s+"?[^"]*[/\\]app[/\\]' + re.escape(script_name) + r'"?(\s|$)', cmd))


def _is_funai_cmd(cmd) -> bool:
    return _is_ours_cmd(cmd, "emit.py")


def _strip_funai_groups(arr) -> list:
    """從某事件的 hook 群組陣列中濾掉 FunAI 自己的條目，保留其他人的。"""
    if not isinstance(arr, list):
        return []
    out = []
    for grp in arr:
        if not isinstance(grp, dict):
            out.append(grp)
            continue
        inner = grp.get("hooks")
        if isinstance(inner, list):
            kept = [h for h in inner if not (isinstance(h, dict) and _is_funai_cmd(h.get("command")))]
            if not kept:
                continue          # 整組都是 FunAI → 丟掉
            grp = dict(grp)
            grp["hooks"] = kept
        out.append(grp)
    return out


def _load(backup: bool) -> dict | None:
    if not SETTINGS.exists():
        return {}
    if backup:
        shutil.copyfile(SETTINGS, SETTINGS.with_suffix(".json.bak"))
    try:
        return json.loads(SETTINGS.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError as e:
        print(f"!! 無法解析現有 settings.json：{e}\n   請先手動檢查，未做變更。")
        return None


def _save(data: dict) -> None:
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    SETTINGS.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def apply() -> None:
    data = _load(backup=True)
    if data is None:
        return
    # statusLine 是單一值，會蓋掉既有的 → 先把非 FunAI 的原值記下，移除時還原
    # （任何安裝位置的舊 statusline.py 都是我們自己的，不記、也順手清掉記錄鍵）
    prev_sl = data.get("statusLine")
    if (isinstance(prev_sl, dict) and prev_sl.get("command") != STATUSLINE
            and not _is_ours_cmd(prev_sl.get("command"), "statusline.py")):
        data["_funaiPrevStatusLine"] = prev_sl
    data["statusLine"] = {"type": "command", "command": STATUSLINE}
    rec = data.get("_funaiPrevStatusLine")
    if isinstance(rec, dict) and _is_ours_cmd(rec.get("command"), "statusline.py"):
        data.pop("_funaiPrevStatusLine", None)
    hooks = data.setdefault("hooks", {})
    for ev in EVENTS:
        arr = _strip_funai_groups(hooks.get(ev, []))   # 先去掉舊的 FunAI 條目（避免重複/更新）
        arr.append({"hooks": [{"type": "command", "command": f"{EMIT} {ev}"}]})
        hooks[ev] = arr
    _save(data)
    print(f"✅ 已更新 {SETTINGS}")
    print(f"   statusLine + hooks: {', '.join(EVENTS)}")
    print("   備份在 settings.json.bak。重開一個 Claude Code session 即可看到狀態列機器人。")


def remove() -> None:
    if not SETTINGS.exists():
        print("（settings.json 不存在，無事可做）")
        return
    data = _load(backup=True)
    if data is None:
        return
    # statusLine：只在它確實指向 FunAI 時處理；有記下的原值就還原
    sl = data.get("statusLine")
    if isinstance(sl, dict) and sl.get("command") == STATUSLINE:
        prev = data.pop("_funaiPrevStatusLine", None)
        if prev is not None:
            data["statusLine"] = prev      # 還原使用者原本的 statusLine
        else:
            data.pop("statusLine", None)
    else:
        data.pop("_funaiPrevStatusLine", None)   # 清掉殘留的記錄鍵
    # hooks：濾掉 FunAI 條目，事件清空就刪 key
    hooks = data.get("hooks")
    if isinstance(hooks, dict):
        for ev in EVENTS:
            if ev not in hooks:
                continue
            arr = _strip_funai_groups(hooks.get(ev, []))
            if arr:
                hooks[ev] = arr
            else:
                hooks.pop(ev, None)
        if not hooks:
            data.pop("hooks", None)
    _save(data)
    print(f"✅ 已從 {SETTINGS} 移除 FunAI 的 statusLine 與 hooks")
    print("   你原有的其他設定都保留；備份在 settings.json.bak。")


def main() -> None:
    if "--remove" in sys.argv[1:] or "-r" in sys.argv[1:]:
        remove()
    else:
        apply()


if __name__ == "__main__":
    main()
