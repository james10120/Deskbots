"""擷取／聚焦終端視窗 + 鍵盤注入（Win32，純 ctypes，無第三方依賴）。

- import 用：terminal_hwnd() → 回傳目前行程所屬終端的視窗 handle（int）。
    獨立 PowerShell：GetConsoleWindow 直接拿到視窗。
    VS Code/WT（ConPTY，無可見 console）：往上找父行程的可見主視窗。
- CLI 用：
    python winfocus.py <hwnd>                → 把該視窗叫到最前。
    python winfocus.py <hwnd> --send <文字>  → 聚焦後把文字打進去 + Enter。
      （地圖對話卡用：對 Claude Code session 送訊息或 /clear 等斜線指令。）
鐵則：絕不拋例外（hook 會 import 它）。
"""
from __future__ import annotations

import ctypes
import os
import sys
from ctypes import wintypes

try:
    _u32 = ctypes.windll.user32
    _k32 = ctypes.windll.kernel32
except Exception:
    _u32 = _k32 = None


def _is_top_visible(hwnd: int) -> bool:
    return bool(_u32.IsWindowVisible(hwnd)) and _u32.GetWindow(hwnd, 4) == 0  # GW_OWNER=4


def _main_window_of_pid(pid: int) -> int:
    found = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    def _cb(hwnd, _lparam):
        p = wintypes.DWORD()
        _u32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid and _is_top_visible(hwnd):
            found.append(hwnd)
            return False
        return True

    _u32.EnumWindows(_cb, 0)
    return int(found[0]) if found else 0


class _PE(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD),
        ("th32ProcessID", wintypes.DWORD), ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
        ("th32ModuleID", wintypes.DWORD), ("cntThreads", wintypes.DWORD),
        ("th32ParentProcessID", wintypes.DWORD), ("pcPriClassBase", ctypes.c_long),
        ("dwFlags", wintypes.DWORD), ("szExeFile", ctypes.c_char * 260),
    ]


def _parent_pid(pid: int) -> int:
    snap = _k32.CreateToolhelp32Snapshot(0x2, 0)   # TH32CS_SNAPPROCESS
    if snap == -1:
        return 0
    e = _PE()
    e.dwSize = ctypes.sizeof(_PE)
    ppid = 0
    try:
        if _k32.Process32First(snap, ctypes.byref(e)):
            while True:
                if e.th32ProcessID == pid:
                    ppid = int(e.th32ParentProcessID)
                    break
                if not _k32.Process32Next(snap, ctypes.byref(e)):
                    break
    finally:
        _k32.CloseHandle(snap)
    return ppid


def terminal_hwnd() -> int:
    if _u32 is None:
        return 0
    try:
        h = _k32.GetConsoleWindow()
        if h and _u32.IsWindowVisible(h):
            return int(h)
        pid = os.getpid()
        for _ in range(12):           # 往上找父行程的可見主視窗（VS Code/WT）
            pid = _parent_pid(pid)
            if not pid:
                break
            hw = _main_window_of_pid(pid)
            if hw:
                return hw
        return 0
    except Exception:
        return 0


def focus(hwnd) -> None:
    if _u32 is None:
        return
    try:
        hwnd = int(hwnd)
        if hwnd == 0:
            return
        if _u32.IsIconic(hwnd):
            _u32.ShowWindow(hwnd, 9)            # SW_RESTORE
        _u32.keybd_event(0x12, 0, 0, 0)         # 按下 Alt：繞過 SetForegroundWindow 限制
        _u32.SetForegroundWindow(hwnd)
        _u32.keybd_event(0x12, 0, 2, 0)         # 放開 Alt
        _u32.BringWindowToTop(hwnd)
    except Exception:
        pass


# ── 鍵盤注入（SendInput + KEYEVENTF_UNICODE）─────────────────────
KEYEVENTF_UNICODE = 0x0004
KEYEVENTF_KEYUP = 0x0002
INPUT_KEYBOARD = 1
VK_RETURN = 0x0D
VK_ESCAPE = 0x1B


class _KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD), ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(wintypes.ULONG)),
    ]


class _INPUT(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [("ki", _KEYBDINPUT),
                    ("pad", ctypes.c_byte * 32)]   # MOUSEINPUT 較大，墊滿避免結構過小
    _anonymous_ = ("u",)
    _fields_ = [("type", wintypes.DWORD), ("u", _U)]


def _key_inputs(text: str) -> list:
    """文字 → SendInput 事件序列（UTF-16 code unit 逐個 down+up，含 emoji/CJK）。"""
    seq = []
    for ch in text:
        # 以 UTF-16 code unit 送（BMP 外的字會拆成代理對）
        for unit in [int.from_bytes(ch.encode("utf-16-le")[i:i + 2], "little")
                     for i in range(0, len(ch.encode("utf-16-le")), 2)]:
            for flags in (KEYEVENTF_UNICODE, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP):
                inp = _INPUT()
                inp.type = INPUT_KEYBOARD
                inp.ki = _KEYBDINPUT(0, unit, flags, 0, None)
                seq.append(inp)
    return seq


def _press_vk(vk: int) -> None:
    for flags in (0, KEYEVENTF_KEYUP):
        inp = _INPUT()
        inp.type = INPUT_KEYBOARD
        inp.ki = _KEYBDINPUT(vk, 0, flags, 0, None)
        _u32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(_INPUT))


def send_text(hwnd, text: str) -> None:
    """聚焦該終端視窗，把文字打進去並送 Enter（給 Claude Code 下訊息/斜線指令）。

    特例：text=="<ESC>" → 只送一個 Escape 鍵（中斷 Claude 當前動作），不送 Enter。
    """
    if _u32 is None or not text:
        return
    try:
        import time
        focus(hwnd)
        # 等視窗真的到最前（聚焦是非同步的；沒到就不打字，避免打進別的視窗）
        target = int(hwnd)
        for _ in range(20):
            if _u32.GetForegroundWindow() == target:
                break
            time.sleep(0.05)
        if _u32.GetForegroundWindow() != target:
            return
        if text == "<ESC>":
            _press_vk(VK_ESCAPE)
            return
        seq = _key_inputs(text)
        if seq:
            arr = (_INPUT * len(seq))(*seq)
            _u32.SendInput(len(seq), arr, ctypes.sizeof(_INPUT))
        time.sleep(0.15)        # 給 TUI 一拍處理輸入（斜線指令選單）
        _press_vk(VK_RETURN)
    except Exception:
        pass


if __name__ == "__main__":
    if len(sys.argv) > 1:
        if len(sys.argv) > 3 and sys.argv[2] == "--send":
            send_text(sys.argv[1], " ".join(sys.argv[3:]))
        else:
            focus(sys.argv[1])
