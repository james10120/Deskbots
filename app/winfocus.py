"""擷取／聚焦終端視窗（Win32，純 ctypes，無第三方依賴）。

- import 用：terminal_hwnd() → 回傳目前行程所屬終端的視窗 handle（int）。
    獨立 PowerShell：GetConsoleWindow 直接拿到視窗。
    VS Code/WT（ConPTY，無可見 console）：往上找父行程的可見主視窗。
- CLI 用：python winfocus.py <hwnd> → 把該視窗叫到最前。
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


if __name__ == "__main__":
    if len(sys.argv) > 1:
        focus(sys.argv[1])
